--[[
    Manhunt - Server Zone System
    Shrinking play area during endgame phase
    Detects map bounds automatically, starts covering full map then shrinks
    Grace period before shrink so players can see the wall and run
    Players outside the zone take increasing damage
]]

Manhunt.Zone = Manhunt.Zone or {}

Manhunt.Zone.Active = false
Manhunt.Zone.Center = Vector(0, 0, 0)
Manhunt.Zone.StartRadius = 0
Manhunt.Zone.EndRadius = 0
Manhunt.Zone.StartTime = 0
Manhunt.Zone.GraceTime = 15      -- seconds before shrinking starts (zone visible but full size)
Manhunt.Zone.ShrinkDuration = 120 -- seconds to shrink from full to end
Manhunt.Zone.DamageTickRate = 1  -- damage every N seconds
Manhunt.Zone.BaseDamage = 5     -- damage per tick when just outside
Manhunt.Zone.MaxDamage = 20     -- max damage per tick (far outside)

-- Calculate map radius from world bounds
function Manhunt.Zone.GetMapRadius()
    local world = game.GetWorld()
    if not IsValid(world) then return 8000 end
    
    local mins, maxs = world:GetModelBounds()
    if not mins or not maxs then return 8000 end
    
    -- Use the XY plane diagonal as the radius (ignore Z)
    local sizeX = maxs.x - mins.x
    local sizeY = maxs.y - mins.y
    local diagonal = math.sqrt(sizeX * sizeX + sizeY * sizeY)
    
    return diagonal / 2
end

-- Calculate max distance from a center point to any corner of the map
-- This guarantees the zone circle covers the ENTIRE map from any center
function Manhunt.Zone.GetFullCoverageRadius(center)
    local world = game.GetWorld()
    if not IsValid(world) then return 12000 end
    
    local mins, maxs = world:GetModelBounds()
    if not mins or not maxs then return 12000 end
    
    -- Check distance to all 4 corners (XY plane)
    local cx, cy = center.x, center.y
    local corners = {
        Vector(mins.x, mins.y, 0),
        Vector(mins.x, maxs.y, 0),
        Vector(maxs.x, mins.y, 0),
        Vector(maxs.x, maxs.y, 0),
    }
    
    local maxDist = 0
    local centerFlat = Vector(cx, cy, 0)
    for _, corner in ipairs(corners) do
        local dist = centerFlat:Distance(corner)
        if dist > maxDist then
            maxDist = dist
        end
    end
    
    return maxDist + 500 -- small padding to ensure full coverage
end

-- Get the current zone radius based on elapsed time
-- Grace period: zone stays at full size, then starts shrinking
function Manhunt.Zone.GetCurrentRadius()
    if not Manhunt.Zone.Active then return Manhunt.Zone.StartRadius end
    
    local elapsed = CurTime() - Manhunt.Zone.StartTime
    
    -- Grace period: zone visible at full size
    if elapsed < Manhunt.Zone.GraceTime then
        return Manhunt.Zone.StartRadius
    end
    
    -- Shrink phase: lerp from start to end
    local shrinkElapsed = elapsed - Manhunt.Zone.GraceTime
    local frac = math.Clamp(shrinkElapsed / Manhunt.Zone.ShrinkDuration, 0, 1)
    
    return Lerp(frac, Manhunt.Zone.StartRadius, Manhunt.Zone.EndRadius)
end

-- Pick a random point within the playable map area
-- Validates: must be on navmesh, not in water, not in empty/void areas
function Manhunt.Zone.GetRandomCenter()
    local world = game.GetWorld()
    if not IsValid(world) then return Vector(0, 0, 0) end
    
    local mins, maxs = world:GetModelBounds()
    if not mins or not maxs then return Vector(0, 0, 0) end
    
    -- Try navmesh-based random point (guarantees walkable, non-water area)
    for i = 1, 50 do
        local testPos = Vector(
            math.Rand(mins.x * 0.5, maxs.x * 0.5),
            math.Rand(mins.y * 0.5, maxs.y * 0.5),
            0
        )
        
        local navArea = navmesh.GetNavArea(testPos, 5000)
        if navArea and not navArea:IsUnderwater() then
            local center = navArea:GetCenter()
            
            -- Extra check: trace down from sky to make sure there's solid ground
            local tr = util.TraceLine({
                start = Vector(center.x, center.y, center.z + 5000),
                endpos = Vector(center.x, center.y, center.z - 5000),
                mask = MASK_SOLID_BRUSHONLY,
            })
            
            if tr.Hit then
                -- Check water at ground level
                local groundZ = tr.HitPos.z
                if not util.IsInWorld(Vector(center.x, center.y, groundZ)) then continue end
                if bit.band(util.PointContents(Vector(center.x, center.y, groundZ + 10)), CONTENTS_WATER) ~= 0 then continue end
                
                -- Make sure there are enough nearby nav areas (not isolated)
                local nearbyAreas = navmesh.Find(center, 2000, 50, 50)
                if #nearbyAreas >= 5 then
                    print("[Manhunt] Zone center validated: " .. tostring(center) .. " (" .. #nearbyAreas .. " nearby nav areas)")
                    return Vector(center.x, center.y, 0)
                end
            end
        end
    end
    
    -- Fallback: use a random player's position (guaranteed to be playable)
    local players = player.GetAll()
    if #players > 0 then
        local ply = players[math.random(#players)]
        if IsValid(ply) then
            local pos = ply:GetPos()
            print("[Manhunt] Zone center fallback: using player position " .. tostring(pos))
            return Vector(pos.x, pos.y, 0)
        end
    end
    
    return Vector(0, 0, 0)
end

-- Get compass direction string from one point to another
function Manhunt.Zone.GetCompassDirection(fromPos, toPos)
    local dx = toPos.x - fromPos.x
    local dy = toPos.y - fromPos.y
    local angle = math.deg(math.atan2(dy, dx))
    
    -- GMod: +X is east, +Y is north
    -- Normalize to 0-360
    if angle < 0 then angle = angle + 360 end
    
    if angle >= 337.5 or angle < 22.5 then return "EAST" end
    if angle >= 22.5 and angle < 67.5 then return "NORTHEAST" end
    if angle >= 67.5 and angle < 112.5 then return "NORTH" end
    if angle >= 112.5 and angle < 157.5 then return "NORTHWEST" end
    if angle >= 157.5 and angle < 202.5 then return "WEST" end
    if angle >= 202.5 and angle < 247.5 then return "SOUTHWEST" end
    if angle >= 247.5 and angle < 292.5 then return "SOUTH" end
    if angle >= 292.5 and angle < 337.5 then return "SOUTHEAST" end
    return "UNKNOWN"
end

-- Pre-pick the zone center and announce to all players (called 1 min before zone starts)
function Manhunt.Zone.PreAnnounce()
    if Manhunt.Config.ZoneEnabled == false then return end
    
    -- Pick the zone center early
    Manhunt.Zone.PendingCenter = Manhunt.Zone.GetRandomCenter()
    
    print("[Manhunt] Zone pre-announced! Center will be: " .. tostring(Manhunt.Zone.PendingCenter))
    
    -- Send announcement to all players with the zone center position
    -- Each client calculates compass direction relative to their own position
    net.Start("Manhunt_ZoneAnnounce")
    net.WriteVector(Manhunt.Zone.PendingCenter)
    net.Broadcast()
end

-- Start the shrinking zone
function Manhunt.Zone.Start()
    if Manhunt.Config.ZoneEnabled == false then return end
    if Manhunt.Zone.Active then return end
    
    -- Use pre-announced center if available, otherwise pick fresh
    if Manhunt.Zone.PendingCenter then
        Manhunt.Zone.Center = Manhunt.Zone.PendingCenter
        Manhunt.Zone.PendingCenter = nil
    else
        Manhunt.Zone.Center = Manhunt.Zone.GetRandomCenter()
    end
    
    local mapRadius = Manhunt.Zone.GetMapRadius()
    local fullRadius = Manhunt.Zone.GetFullCoverageRadius(Manhunt.Zone.Center)
    Manhunt.Zone.StartRadius = fullRadius -- covers the ENTIRE map from center point
    Manhunt.Zone.EndRadius = mapRadius * 0.65 -- shrink to 65% of map radius
    Manhunt.Zone.StartTime = CurTime()
    Manhunt.Zone.Active = true
    
    -- Track last alert time per player for Siege-style pings
    Manhunt.Zone.LastAlertTime = {}
    
    print("[Manhunt] Zone started! Center: " .. tostring(Manhunt.Zone.Center) .. " Full coverage radius: " .. math.floor(fullRadius) .. " -> End radius: " .. math.floor(mapRadius * 0.65) .. " (Grace: " .. Manhunt.Zone.GraceTime .. "s, Shrink: " .. Manhunt.Zone.ShrinkDuration .. "s)")
    
    -- Sync to clients
    Manhunt.Zone.Sync()
    
    -- Start damage ticker
    timer.Create("Manhunt_ZoneDamage", Manhunt.Zone.DamageTickRate, 0, function()
        if not Manhunt.Zone.Active then
            timer.Remove("Manhunt_ZoneDamage")
            return
        end
        Manhunt.Zone.DamageTick()
    end)
end

-- Stop the zone
function Manhunt.Zone.Stop()
    Manhunt.Zone.Active = false
    timer.Remove("Manhunt_ZoneDamage")
    
    -- Notify clients to stop
    net.Start("Manhunt_ZoneSync")
    net.WriteBool(false) -- not active
    net.Broadcast()
end

-- Sync zone state to all clients
function Manhunt.Zone.Sync()
    net.Start("Manhunt_ZoneSync")
    net.WriteBool(true) -- active
    net.WriteVector(Manhunt.Zone.Center)
    net.WriteFloat(Manhunt.Zone.StartRadius)
    net.WriteFloat(Manhunt.Zone.EndRadius)
    net.WriteFloat(Manhunt.Zone.StartTime)
    net.WriteFloat(Manhunt.Zone.ShrinkDuration)
    net.WriteFloat(Manhunt.Zone.GraceTime)
    net.Broadcast()
end

-- Apply damage to players outside the zone
function Manhunt.Zone.DamageTick()
    if not Manhunt.Zone.Active then return end
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
    
    local radius = Manhunt.Zone.GetCurrentRadius()
    local center = Manhunt.Zone.Center
    
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            local plyPos = Vector(ply:GetPos().x, ply:GetPos().y, 0)
            local centerFlat = Vector(center.x, center.y, 0)
            local dist = plyPos:Distance(centerFlat)
            
            if dist > radius then
                -- How far outside (0 = edge, 1 = very far)
                local overFrac = math.Clamp((dist - radius) / (radius * 0.5), 0, 1)
                local dmg = Lerp(overFrac, Manhunt.Zone.BaseDamage, Manhunt.Zone.MaxDamage)
                
                local dmgInfo = DamageInfo()
                dmgInfo:SetDamage(dmg)
                dmgInfo:SetDamageType(DMG_POISON)
                dmgInfo:SetAttacker(game.GetWorld())
                dmgInfo:SetInflictor(game.GetWorld())
                ply:TakeDamageInfo(dmgInfo)
                
                -- Warning sound
                ply:EmitSound("player/pl_pain5.wav", 50, 100 + overFrac * 40)
                
                -- Siege-style alert: ping this player's exact location to the enemy team every 3 seconds
                local sid = ply:SteamID()
                Manhunt.Zone.LastAlertTime = Manhunt.Zone.LastAlertTime or {}
                local lastAlert = Manhunt.Zone.LastAlertTime[sid] or 0
                if CurTime() - lastAlert >= 3 then
                    Manhunt.Zone.LastAlertTime[sid] = CurTime()
                    Manhunt.Zone.SendAlert(ply)
                end
            end
        end
    end
end

-- Send a zone alert (Siege-style ping) to the opposing team
function Manhunt.Zone.SendAlert(outsidePly)
    if not IsValid(outsidePly) then return end
    
    local pos = outsidePly:GetPos()
    local isFugitive = Manhunt.GetPlayerTeam(outsidePly) == Manhunt.TEAM_FUGITIVE
    
    -- Determine recipients (opposing team)
    local recipients = {}
    if Manhunt.TestMode then
        -- In test mode, send to self for testing
        recipients = player.GetAll()
    elseif isFugitive then
        recipients = Manhunt.GetHunters()
    else
        local fug = Manhunt.GetFugitive()
        if IsValid(fug) then recipients = {fug} end
    end
    
    for _, target in ipairs(recipients) do
        if IsValid(target) then
            net.Start("Manhunt_ZoneAlert")
            net.WriteVector(pos)
            net.WriteString(outsidePly:Nick())
            net.Send(target)
        end
    end
end

print("[Manhunt] sv_zone.lua loaded")
