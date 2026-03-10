--[[
    Manhunt - High Speed Chase (Server)
    Main game logic: spawn, countdown, abilities, win conditions
]]

Manhunt.Chase = Manhunt.Chase or {}
Manhunt.Chase.Active = false
Manhunt.Chase.PlayerAbilities = {}    -- {steamid = {abilityId = charges}}
Manhunt.Chase.Cooldowns = {}          -- {steamid = {abilityId = endTime}}
Manhunt.Chase.StationaryTime = {}     -- {steamid = startTime}
Manhunt.Chase.ExitTime = {}           -- {steamid = exitTime}
Manhunt.Chase.ShieldActive = {}       -- {steamid = true}
Manhunt.Chase.GhostActive = {}        -- {steamid = true}
Manhunt.Chase.TrackerTarget = nil     -- entity being tracked
Manhunt.Chase.TrackerEnd = 0          -- when tracking expires
Manhunt.Chase.VehicleHealth = {}      -- {steamid = health}

-- Find a good open spawn area for the chase (road/open area)
function Manhunt.Chase.FindSpawnArea()
    local navAreas = navmesh.GetAllNavAreas()
    if not navAreas or #navAreas == 0 then
        -- Fallback to player spawns
        local spawns = ents.FindByClass("info_player_start")
        table.Add(spawns, ents.FindByClass("info_player_deathmatch"))
        table.Add(spawns, ents.FindByClass("info_player_terrorist"))
        table.Add(spawns, ents.FindByClass("info_player_counterterrorist"))
        if #spawns > 0 then
            return spawns[math.random(#spawns)]:GetPos()
        end
        -- Last resort: find any valid ground position near world center
        local tr = util.TraceLine({
            start = Vector(0, 0, 5000),
            endpos = Vector(0, 0, -5000),
            mask = MASK_SOLID_BRUSHONLY,
        })
        return tr.Hit and (tr.HitPos + Vector(0, 0, 10)) or Vector(0, 0, 100)
    end

    -- Find large, flat, open areas (good for roads/plazas)
    local candidates = {}
    for _, area in ipairs(navAreas) do
        local sizeX = area:GetSizeX()
        local sizeY = area:GetSizeY()
        -- Need a big enough area for cars
        if sizeX > 400 and sizeY > 400 then
            local center = area:GetCenter()
            -- Not underwater
            if bit.band(util.PointContents(center), CONTENTS_WATER) == 0 then
                -- Above ground (can see sky)
                local tr = util.TraceLine({
                    start = center + Vector(0, 0, 50),
                    endpos = center + Vector(0, 0, 50000),
                    mask = MASK_SOLID_BRUSHONLY,
                })
                if tr.HitSky or not tr.Hit then
                    -- Enough overhead clearance
                    local upTr = util.TraceLine({
                        start = center + Vector(0, 0, 10),
                        endpos = center + Vector(0, 0, 400),
                        mask = MASK_SOLID_BRUSHONLY,
                    })
                    if not upTr.Hit then
                        table.insert(candidates, {
                            pos = center,
                            score = sizeX * sizeY, -- bigger = better
                        })
                    end
                end
            end
        end
    end

    if #candidates == 0 then
        -- Fallback: any nav area that's above ground
        for i = 1, math.min(50, #navAreas) do
            local area = navAreas[math.random(#navAreas)]
            local center = area:GetCenter()
            if bit.band(util.PointContents(center), CONTENTS_WATER) == 0 then
                return center
            end
        end
        return navAreas[1]:GetCenter()
    end

    -- Sort by size (biggest first) and pick randomly from top 5
    table.sort(candidates, function(a, b) return a.score > b.score end)
    local pick = candidates[math.random(math.min(5, #candidates))]
    return pick.pos
end

-- Spawn a vehicle next to a player position
function Manhunt.Chase.SpawnVehicleAt(pos, owner, offset)
    offset = offset or Vector(0, 0, 0)
    local spawnPos = pos + offset + Vector(0, 0, 30)

    local ang = Angle(0, math.random(0, 360), 0)

    local vehicle = ents.Create("gtav_infernus")
    if not IsValid(vehicle) then
        vehicle = ents.Create("gmod_sent_vehicle_fphysics_base")
        if IsValid(vehicle) then
            vehicle.VehicleTable = list.Get("simfphys_vehicles")["gtav_infernus"]
        end
    end

    if not IsValid(vehicle) then
        if IsValid(owner) then
            owner:ChatPrint("[Manhunt] Could not spawn vehicle! Make sure the Glide car mod is installed.")
        end
        return nil
    end

    vehicle:SetPos(spawnPos)
    vehicle:SetAngles(ang)
    vehicle:Spawn()
    vehicle:Activate()

    vehicle.ManhuntVehicle = true
    vehicle.ManhuntChaseVehicle = true
    vehicle.ManhuntOwner = owner

    if IsValid(owner) then
        local sid = owner:SteamID()
        if IsValid(Manhunt.SpawnedVehicles[sid]) then
            Manhunt.SpawnedVehicles[sid]:Remove()
        end
        Manhunt.SpawnedVehicles[sid] = vehicle
        Manhunt.Chase.VehicleHealth[sid] = Manhunt.Chase.MaxVehicleHealth
    end

    return vehicle
end

-- Start the High Speed Chase gamemode
function Manhunt.Chase.StartGame()
    local fugitive = Manhunt.GetFugitive()
    local hunters = Manhunt.GetHunters()

    if not IsValid(fugitive) and not Manhunt.TestMode then
        print("[Manhunt] [Chase] Cannot start: No fugitive assigned!")
        return false
    end

    if #hunters == 0 and not Manhunt.TestMode then
        print("[Manhunt] [Chase] Cannot start: No hunters assigned!")
        return false
    end

    print("[Manhunt] [Chase] Starting High Speed Chase!")

    -- In test mode, assign the solo player as fugitive
    if Manhunt.TestMode then
        local ply = player.GetAll()[1]
        if IsValid(ply) then
            Manhunt.SetPlayerTeam(ply, Manhunt.TEAM_FUGITIVE)
        end
    end

    -- Reset state
    Manhunt.Chase.Active = true
    Manhunt.Chase.PlayerAbilities = {}
    Manhunt.Chase.Cooldowns = {}
    Manhunt.Chase.StationaryTime = {}
    Manhunt.Chase.ExitTime = {}
    Manhunt.Chase.ShieldActive = {}
    Manhunt.Chase.GhostActive = {}
    Manhunt.Chase.TrackerTarget = nil
    Manhunt.Chase.TrackerEnd = 0
    Manhunt.Chase.VehicleHealth = {}
    Manhunt.Chase.GraceEnd = 0  -- grace period: no exit/stationary checks
    Manhunt.HunterDeaths = {}
    Manhunt.EndgameActive = false
    Manhunt.EndgameTriggered = false

    -- Find spawn area
    local spawnCenter = Manhunt.Chase.FindSpawnArea()
    print("[Manhunt] [Chase] Spawn area: " .. tostring(spawnCenter))

    -- Teleport all players to spawn area and spawn their cars
    local allPlayers = {}
    if Manhunt.TestMode then
        allPlayers = { player.GetAll()[1] }
    else
        table.insert(allPlayers, fugitive)
        for _, h in ipairs(hunters) do table.insert(allPlayers, h) end
    end

    -- Calculate spawn positions in a circle
    local numPlayers = #allPlayers
    for i, ply in ipairs(allPlayers) do
        if not IsValid(ply) then continue end
        local angle = (i - 1) * (360 / numPlayers)
        local rad = math.rad(angle)
        local offset = Vector(math.cos(rad) * 300, math.sin(rad) * 300, 0)
        local playerPos = spawnCenter + offset

        -- Trace down to ground
        local tr = util.TraceLine({
            start = playerPos + Vector(0, 0, 500),
            endpos = playerPos - Vector(0, 0, 500),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then
            playerPos = tr.HitPos + Vector(0, 0, 10)
        end

        ply:SetPos(playerPos)
        ply:SetEyeAngles(Angle(0, angle + 180, 0)) -- face center initially

        -- Spawn vehicle next to player
        local carOffset = Vector(math.cos(rad) * 150, math.sin(rad) * 150, 0)
        local veh = Manhunt.Chase.SpawnVehicleAt(playerPos, ply, carOffset)

        -- Make sure car faces outward
        if IsValid(veh) then
            veh:SetAngles(Angle(0, angle, 0))
        end

        -- Give abilities
        Manhunt.Chase.GiveAbilities(ply)

        -- Freeze player during countdown
        Manhunt.FreezePlayer(ply, true)
        ply:GodEnable()
    end

    -- Phase: Countdown
    Manhunt.Phase = Manhunt.PHASE_COUNTDOWN
    Manhunt.CountdownEnd = CurTime() + Manhunt.Chase.COUNTDOWN_TIME
    Manhunt.SyncPhase()

    -- Sync chase mode to clients
    net.Start("Manhunt_ChaseGamemode")
    net.WriteBool(true)
    net.Broadcast()

    Manhunt.PlayAudioCue("countdown")

    -- After countdown: unfreeze, start game
    timer.Create("Manhunt_ChaseCountdown", Manhunt.Chase.COUNTDOWN_TIME, 1, function()
        if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end

        Manhunt.Phase = Manhunt.PHASE_ACTIVE
        local gameTimeSec = Manhunt.Config.GameTime * 60
        Manhunt.StartTime = CurTime()
        Manhunt.EndTime = CurTime() + gameTimeSec
        Manhunt.SyncPhase()

        -- Unfreeze all players
        for _, ply in ipairs(allPlayers) do
            if IsValid(ply) then
                Manhunt.FreezePlayer(ply, false)
                ply:GodDisable()
            end
        end

        Manhunt.PlayAudioCue("game_start")

        -- Grace period: 15 seconds to get in the car and start driving
        Manhunt.Chase.GraceEnd = CurTime() + 15
        print("[Manhunt] [Chase] Grace period active for 15s (get in your car!)")

        -- Chase mode: prevent player death from ending the game
        -- If a player somehow dies (crash, fall), respawn them in their car
        -- Store original spawn positions for each player
        Manhunt.Chase.SpawnPositions = Manhunt.Chase.SpawnPositions or {}
        for i, ply in ipairs(allPlayers) do
            if IsValid(ply) then
                Manhunt.Chase.SpawnPositions[ply:SteamID()] = ply:GetPos()
            end
        end

        -- Prevent player death while in vehicle — redirect damage to vehicle health
        hook.Add("EntityTakeDamage", "Manhunt_ChaseVehicleDamage", function(target, dmgInfo)
            if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
            if not Manhunt.IsChaseMode() then return end
            if not target:IsPlayer() then return end
            if not Manhunt.IsPlayerInVehicle(target) then return end
            
            local sid = target:SteamID()
            local dmg = dmgInfo:GetDamage()
            
            -- Shield blocks damage
            if Manhunt.Chase.ShieldActive[sid] then
                dmgInfo:SetDamage(0)
                return
            end
            
            -- Redirect damage to vehicle health pool instead of player
            Manhunt.Chase.VehicleHealth[sid] = (Manhunt.Chase.VehicleHealth[sid] or Manhunt.Chase.MaxVehicleHealth) - dmg
            
            -- Keep the player alive — cap health at minimum 1
            if target:Health() - dmg <= 0 then
                dmgInfo:SetDamage(0)
                target:SetHealth(math.max(target:Health(), 1))
            end
        end)

        hook.Add("PlayerDeath", "Manhunt_ChasePlayerDeath", function(victim, inflictor, attacker)
            if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
            if not Manhunt.IsChaseMode() then return end
            print("[Manhunt] [Chase] Player died: " .. victim:Nick() .. " - respawning in 1s")
            timer.Simple(1, function()
                if not IsValid(victim) then return end
                if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
                victim:Spawn()
                local sid = victim:SteamID()
                local veh = Manhunt.SpawnedVehicles and Manhunt.SpawnedVehicles[sid]
                if IsValid(veh) then
                    -- Put them back near their vehicle
                    timer.Simple(0, function()
                        if IsValid(victim) and IsValid(veh) then
                            victim:SetPos(veh:GetPos() + Vector(0, 0, 50))
                        end
                    end)
                else
                    local fallback = Manhunt.Chase.SpawnPositions and Manhunt.Chase.SpawnPositions[sid]
                    if fallback then
                        timer.Simple(0, function()
                            if IsValid(victim) then
                                victim:SetPos(fallback)
                            end
                        end)
                    end
                end
            end)
        end)

        -- Re-sync abilities to all players now that game is active
        for _, p in ipairs(allPlayers) do
            if IsValid(p) then
                Manhunt.Chase.SyncAbilities(p)
            end
        end

        -- Start chase think loop
        timer.Create("Manhunt_ChaseThink", 0.5, 0, function()
            Manhunt.Chase.Think()
        end)

        -- Start pickup system
        if Manhunt.Chase.Pickups and Manhunt.Chase.Pickups.Start then
            Manhunt.Chase.Pickups.Start()
        end

        -- Game end timer
        timer.Create("Manhunt_ChaseGameEnd", gameTimeSec, 1, function()
            if Manhunt.Phase == Manhunt.PHASE_ACTIVE and Manhunt.IsChaseMode() then
                Manhunt.Chase.EndGame("fugitive")
            end
        end)

        -- Sync vehicle health periodically
        timer.Create("Manhunt_ChaseHealthSync", 2, 0, function()
            if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then
                timer.Remove("Manhunt_ChaseHealthSync")
                return
            end
            Manhunt.Chase.SyncVehicleHealth()
        end)
    end)

    return true
end

-- Give a player their chase abilities
function Manhunt.Chase.GiveAbilities(ply)
    if not IsValid(ply) then return end
    local sid = ply:SteamID()
    local team = Manhunt.GetPlayerTeam(ply)

    Manhunt.Chase.PlayerAbilities[sid] = {}
    Manhunt.Chase.Cooldowns[sid] = {}

    -- Determine which abilities this player gets
    local abilityList
    if team == Manhunt.TEAM_FUGITIVE or Manhunt.TestMode then
        abilityList = Manhunt.Chase.FugitiveAbilities
    else
        abilityList = Manhunt.Chase.HunterAbilities
    end

    for _, abilityId in ipairs(abilityList) do
        Manhunt.Chase.PlayerAbilities[sid][abilityId] = 1 -- 1 charge each
        Manhunt.Chase.Cooldowns[sid][abilityId] = 0
    end

    -- Sync to client
    Manhunt.Chase.SyncAbilities(ply)
end

-- Sync abilities to a player
function Manhunt.Chase.SyncAbilities(ply)
    if not IsValid(ply) then return end
    local sid = ply:SteamID()
    local abilities = Manhunt.Chase.PlayerAbilities[sid] or {}
    local cooldowns = Manhunt.Chase.Cooldowns[sid] or {}

    net.Start("Manhunt_ChaseAbilityGrant")
    local count = table.Count(abilities)
    net.WriteUInt(count, 8)
    for abilityId, charges in pairs(abilities) do
        net.WriteUInt(abilityId, 8)
        net.WriteUInt(charges, 8)
        net.WriteFloat(cooldowns[abilityId] or 0)
    end
    net.Send(ply)
end

-- Sync vehicle health to all players
function Manhunt.Chase.SyncVehicleHealth()
    net.Start("Manhunt_ChaseVehicleHealth")
    local count = table.Count(Manhunt.Chase.VehicleHealth)
    net.WriteUInt(count, 8)
    for sid, health in pairs(Manhunt.Chase.VehicleHealth) do
        net.WriteString(sid)
        net.WriteFloat(health)
    end
    net.Broadcast()
end

-- Main think loop (runs every 0.5s)
function Manhunt.Chase.Think()
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then
        timer.Remove("Manhunt_ChaseThink")
        return
    end

    local now = CurTime()

    -- Get all active players
    local allPlayers = {}
    if Manhunt.TestMode then
        allPlayers = { player.GetAll()[1] }
    else
        local fug = Manhunt.GetFugitive()
        if IsValid(fug) then table.insert(allPlayers, fug) end
        for _, h in ipairs(Manhunt.GetHunters()) do
            if IsValid(h) then table.insert(allPlayers, h) end
        end
    end

    for _, ply in ipairs(allPlayers) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local sid = ply:SteamID()
        local team = Manhunt.GetPlayerTeam(ply)
        local inVehicle = Manhunt.IsPlayerInVehicle(ply)

        -- === Skip checks during grace period (first 15s to get in car) ===
        local graceActive = now < (Manhunt.Chase.GraceEnd or 0)

        -- === Exit Vehicle Detection (skip during grace) ===
        if not graceActive and not inVehicle then
            if not Manhunt.Chase.ExitTime[sid] then
                Manhunt.Chase.ExitTime[sid] = now
                print("[Manhunt] [Chase] " .. ply:Nick() .. " exited vehicle! 5s warning.")
                -- Warn client
                net.Start("Manhunt_ChaseExitWarning")
                net.WriteBool(true)
                net.WriteFloat(Manhunt.Chase.EXIT_VEHICLE_TIME)
                net.Send(ply)
            else
                local elapsed = now - Manhunt.Chase.ExitTime[sid]
                if elapsed >= Manhunt.Chase.EXIT_VEHICLE_TIME then
                    -- Player was out too long - they lose
                    print("[Manhunt] [Chase] " .. ply:Nick() .. " was out of vehicle too long!")
                    if team == Manhunt.TEAM_FUGITIVE or Manhunt.TestMode then
                        Manhunt.Chase.EndGame("hunter")
                    else
                        -- Hunter out of car: just kill them
                        ply:Kill()
                    end
                end
            end
        else
            if Manhunt.Chase.ExitTime[sid] then
                Manhunt.Chase.ExitTime[sid] = nil
                net.Start("Manhunt_ChaseExitWarning")
                net.WriteBool(false)
                net.WriteFloat(0)
                net.Send(ply)
            end
        end

        -- === Stationary Detection (Fugitive only, skip during grace) ===
        if not graceActive and (team == Manhunt.TEAM_FUGITIVE or Manhunt.TestMode) and inVehicle then
            local speed = Manhunt.GetVehicleSpeed(ply)
            if speed < Manhunt.Chase.STATIONARY_SPEED then
                if not Manhunt.Chase.StationaryTime[sid] then
                    Manhunt.Chase.StationaryTime[sid] = now
                end
                local stationaryElapsed = now - Manhunt.Chase.StationaryTime[sid]

                -- Warn after 2 seconds
                if stationaryElapsed >= 2 then
                    net.Start("Manhunt_ChaseStationaryWarn")
                    net.WriteFloat(Manhunt.Chase.STATIONARY_THRESHOLD - stationaryElapsed)
                    net.Send(ply)
                end

                if stationaryElapsed >= Manhunt.Chase.STATIONARY_THRESHOLD then
                    print("[Manhunt] [Chase] Fugitive stationary too long! Speed: " .. speed)
                    Manhunt.Chase.EndGame("hunter")
                end
            else
                Manhunt.Chase.StationaryTime[sid] = nil
            end
        elseif graceActive then
            Manhunt.Chase.StationaryTime[sid] = nil
        end

        -- === Vehicle damage tracking (from collisions/entities) ===
        if inVehicle then
            local veh = Manhunt.GetPlayerVehicle(ply)
            if IsValid(veh) then
                -- Sync Glide engine health into our custom health pool
                if veh.GetEngineHealth then
                    local engineHP = veh:GetEngineHealth()
                    local maxEngineHP = veh.GetMaxEngineHealth and veh:GetMaxEngineHealth() or 100
                    -- Map Glide engine health to our VehicleHealth (proportional)
                    if maxEngineHP > 0 then
                        local fraction = math.Clamp(engineHP / maxEngineHP, 0, 1)
                        Manhunt.Chase.VehicleHealth[sid] = math.max(Manhunt.Chase.VehicleHealth[sid] or Manhunt.Chase.MaxVehicleHealth, 0)
                        -- Only apply if Glide health is lower than our tracked health (collision damage)
                        local mappedHP = fraction * Manhunt.Chase.MaxVehicleHealth
                        if mappedHP < (Manhunt.Chase.VehicleHealth[sid] or Manhunt.Chase.MaxVehicleHealth) then
                            Manhunt.Chase.VehicleHealth[sid] = mappedHP
                        end
                    end
                end

                -- Check custom vehicle health for destruction
                if (Manhunt.Chase.VehicleHealth[sid] or Manhunt.Chase.MaxVehicleHealth) <= 0 and not Manhunt.Chase.ShieldActive[sid] then
                    print("[Manhunt] [Chase] " .. ply:Nick() .. " vehicle destroyed! Health: " .. tostring(Manhunt.Chase.VehicleHealth[sid]))
                    if team == Manhunt.TEAM_FUGITIVE or Manhunt.TestMode then
                        Manhunt.Chase.EndGame("hunter")
                    end
                end
            end
        end
    end

    -- === Tracker dart logic ===
    if Manhunt.Chase.TrackerTarget and now < Manhunt.Chase.TrackerEnd then
        local target = Manhunt.Chase.TrackerTarget
        if IsValid(target) then
            -- Send tracked position to all hunters
            local targetPos = target:GetPos()
            for _, h in ipairs(Manhunt.GetHunters()) do
                if IsValid(h) then
                    net.Start("Manhunt_ChaseTracker")
                    net.WriteVector(targetPos)
                    net.WriteBool(true)
                    net.Send(h)
                end
            end
        end
    elseif Manhunt.Chase.TrackerEnd > 0 and now >= Manhunt.Chase.TrackerEnd then
        Manhunt.Chase.TrackerEnd = 0
        Manhunt.Chase.TrackerTarget = nil
    end

    -- === Ghost mode expiry ===
    for sid, _ in pairs(Manhunt.Chase.GhostActive) do
        local ply2 = player.GetBySteamID(sid)
        if IsValid(ply2) then
            local veh = Manhunt.GetPlayerVehicle(ply2)
            if IsValid(veh) then
                -- Ghost is managed by timer in UseAbility, just keep collision disabled
                veh:SetCollisionGroup(COLLISION_GROUP_WEAPON)
            end
        end
    end
end

-- Use an ability
function Manhunt.Chase.UseAbility(ply, abilityId)
    if not IsValid(ply) then return false end
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return false end

    local sid = ply:SteamID()
    local team = Manhunt.GetPlayerTeam(ply)
    local now = CurTime()

    -- Check if player has this ability
    local abilities = Manhunt.Chase.PlayerAbilities[sid]
    if not abilities or not abilities[abilityId] or abilities[abilityId] <= 0 then
        return false
    end

    -- Check cooldown
    local cooldowns = Manhunt.Chase.Cooldowns[sid]
    if cooldowns and cooldowns[abilityId] and now < cooldowns[abilityId] then
        return false
    end

    -- Check team restriction
    if not Manhunt.Chase.CanTeamUse(abilityId, team) and not Manhunt.TestMode then
        return false
    end

    -- Must be in a vehicle for most abilities
    if not Manhunt.IsPlayerInVehicle(ply) then return false end

    local veh = Manhunt.GetPlayerVehicle(ply)
    if not IsValid(veh) then return false end

    local abilityDef = Manhunt.Chase.Abilities[abilityId]
    if not abilityDef then return false end

    -- Execute the ability
    local success = false

    if abilityId == Manhunt.Chase.ABILITY_OIL_SLICK then
        success = Manhunt.Chase.DoOilSlick(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_SMOKE_SCREEN then
        success = Manhunt.Chase.DoSmokeScreen(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_EMP_BLAST then
        success = Manhunt.Chase.DoEMPBlast(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_NITRO_BOOST then
        success = Manhunt.Chase.DoNitroBoost(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_SHIELD then
        success = Manhunt.Chase.DoShield(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_GHOST_MODE then
        success = Manhunt.Chase.DoGhostMode(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_SHOCKWAVE then
        success = Manhunt.Chase.DoShockwave(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_ROADBLOCK then
        success = Manhunt.Chase.DoRoadblock(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_MISSILE then
        success = Manhunt.Chase.DoMissile(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_TRACKER_DART then
        success = Manhunt.Chase.DoTrackerDart(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_REPAIR_KIT then
        success = Manhunt.Chase.DoRepairKit(ply, veh)
    elseif abilityId == Manhunt.Chase.ABILITY_SPEED_TRAP then
        success = Manhunt.Chase.DoSpeedTrap(ply, veh)
    end

    if success then
        -- Consume charge (repair kit / speed trap are single-use, remove entirely)
        abilities[abilityId] = abilities[abilityId] - 1
        if abilities[abilityId] <= 0 then
            abilities[abilityId] = nil
        end

        -- Set cooldown (only if they still have charges for rechargeable abilities)
        if abilityDef.cooldown and abilityDef.cooldown > 0 then
            cooldowns[abilityId] = now + abilityDef.cooldown
            -- Recharge: give back 1 charge after cooldown
            timer.Simple(abilityDef.cooldown, function()
                if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
                if not Manhunt.IsChaseMode() then return end
                local ab = Manhunt.Chase.PlayerAbilities[sid]
                if ab then
                    ab[abilityId] = (ab[abilityId] or 0) + 1
                    if IsValid(ply) then
                        Manhunt.Chase.SyncAbilities(ply)
                    end
                end
            end)
        end

        -- Sync abilities
        Manhunt.Chase.SyncAbilities(ply)

        -- Broadcast effect to all clients
        net.Start("Manhunt_ChaseEffect")
        net.WriteUInt(abilityId, 8)
        net.WriteVector(veh:GetPos())
        net.WriteAngle(veh:GetAngles())
        net.WriteEntity(ply)
        net.Broadcast()

        print("[Manhunt] [Chase] " .. ply:Nick() .. " used " .. abilityDef.name)
    end

    return success
end

-- ==========================================
-- ABILITY IMPLEMENTATIONS
-- ==========================================

-- Oil Slick: drop oil behind car
function Manhunt.Chase.DoOilSlick(ply, veh)
    local pos = veh:GetPos() - veh:GetForward() * 200
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 100),
        endpos = pos - Vector(0, 0, 200),
        mask = MASK_SOLID_BRUSHONLY,
    })
    if tr.Hit then pos = tr.HitPos + Vector(0, 0, 2) end

    -- Create oil trigger zone
    local oil = ents.Create("prop_physics")
    if not IsValid(oil) then return false end
    oil:SetModel("models/hunter/plates/plate4x4.mdl")
    oil:SetPos(pos)
    oil:SetAngles(Angle(0, 0, 0))
    oil:Spawn()
    oil:SetColor(Color(20, 20, 20, 200))
    oil:SetRenderMode(RENDERMODE_TRANSCOLOR)
    oil:SetMoveType(MOVETYPE_NONE)
    oil:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    oil:GetPhysicsObject():EnableMotion(false)
    oil.ManhuntOilSlick = true
    oil.ManhuntOwner = ply

    -- Oil effect: check for vehicles driving over it
    local duration = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_OIL_SLICK].duration
    timer.Create("Manhunt_Oil_" .. oil:EntIndex(), 0.3, math.ceil(duration / 0.3), function()
        if not IsValid(oil) then return end
        local oilPos = oil:GetPos()
        for _, ent in ipairs(ents.FindInSphere(oilPos, 250)) do
            if ent.ManhuntChaseVehicle and ent.ManhuntOwner ~= ply then
                -- Apply spin force
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    phys:ApplyTorqueCenter(Vector(0, 0, math.random(-500000, 500000)))
                    phys:ApplyForceCenter(VectorRand() * 200000)
                end
            end
        end
    end)

    -- Remove after duration
    timer.Simple(duration, function()
        if IsValid(oil) then oil:Remove() end
    end)

    return true
end

-- Smoke Screen: deploy smoke behind vehicle
function Manhunt.Chase.DoSmokeScreen(ply, veh)
    local pos = veh:GetPos() - veh:GetForward() * 150

    -- Spawn multiple smoke effects
    for i = 1, 5 do
        local smokePos = pos + VectorRand() * 100
        local smoke = ents.Create("env_smokestack")
        if IsValid(smoke) then
            smoke:SetPos(smokePos)
            smoke:SetKeyValue("InitialState", "1")
            smoke:SetKeyValue("BaseSpread", "100")
            smoke:SetKeyValue("SpreadSpeed", "50")
            smoke:SetKeyValue("Speed", "30")
            smoke:SetKeyValue("StartSize", "200")
            smoke:SetKeyValue("EndSize", "400")
            smoke:SetKeyValue("Rate", "50")
            smoke:SetKeyValue("JetLength", "300")
            smoke:SetKeyValue("twist", "10")
            smoke:SetKeyValue("rendercolor", "80 80 80")
            smoke:SetKeyValue("renderamt", "200")
            smoke:Spawn()
            smoke:Activate()

            local duration = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_SMOKE_SCREEN].duration
            timer.Simple(duration, function()
                if IsValid(smoke) then smoke:Remove() end
            end)
        end
    end

    return true
end

-- EMP Blast: disable nearby hunter vehicles
function Manhunt.Chase.DoEMPBlast(ply, veh)
    local pos = veh:GetPos()
    local radius = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_EMP_BLAST].radius
    local stunDur = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_EMP_BLAST].stunDuration

    for _, ent in ipairs(ents.FindInSphere(pos, radius)) do
        if ent.ManhuntChaseVehicle and ent.ManhuntOwner ~= ply then
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                -- Kill velocity and freeze briefly
                local savedVel = phys:GetVelocity()
                phys:SetVelocity(savedVel * 0.2)
                phys:EnableMotion(false)

                timer.Simple(stunDur, function()
                    if IsValid(ent) and IsValid(phys) then
                        phys:EnableMotion(true)
                    end
                end)
            end

            -- Notify the stunned player
            if IsValid(ent.ManhuntOwner) then
                ent.ManhuntOwner:ChatPrint("[Manhunt] Your vehicle was hit by an EMP!")
            end
        end
    end

    return true
end

-- Nitro Boost: massive forward boost
function Manhunt.Chase.DoNitroBoost(ply, veh)
    local phys = veh:GetPhysicsObject()
    if not IsValid(phys) then return false end

    local forward = veh:GetForward()
    local force = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_NITRO_BOOST].boostForce
    phys:ApplyForceCenter(forward * force)

    return true
end

-- Shield: temporary invulnerability
function Manhunt.Chase.DoShield(ply, veh)
    local sid = ply:SteamID()
    Manhunt.Chase.ShieldActive[sid] = true

    local duration = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_SHIELD].duration

    -- Make vehicle take no damage
    ply:GodEnable()

    timer.Create("Manhunt_Shield_" .. sid, duration, 1, function()
        Manhunt.Chase.ShieldActive[sid] = nil
        if IsValid(ply) then
            ply:GodDisable()
        end
    end)

    return true
end

-- Ghost Mode: invisible + pass through vehicles
function Manhunt.Chase.DoGhostMode(ply, veh)
    local sid = ply:SteamID()
    Manhunt.Chase.GhostActive[sid] = true

    local duration = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_GHOST_MODE].duration

    -- Make vehicle non-solid and invisible-ish (handled client-side for rendering)
    veh:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    veh:SetRenderMode(RENDERMODE_TRANSCOLOR)
    veh:SetColor(Color(255, 255, 255, 50))

    timer.Create("Manhunt_Ghost_" .. sid, duration, 1, function()
        Manhunt.Chase.GhostActive[sid] = nil
        if IsValid(veh) then
            veh:SetCollisionGroup(COLLISION_GROUP_NONE)
            veh:SetRenderMode(RENDERMODE_NORMAL)
            veh:SetColor(Color(255, 255, 255, 255))
        end
    end)

    return true
end

-- Shockwave: push nearby vehicles away
function Manhunt.Chase.DoShockwave(ply, veh)
    local pos = veh:GetPos()
    local radius = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_SHOCKWAVE].radius
    local force = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_SHOCKWAVE].knockForce

    for _, ent in ipairs(ents.FindInSphere(pos, radius)) do
        if ent.ManhuntChaseVehicle and ent ~= veh then
            local phys = ent:GetPhysicsObject()
            if IsValid(phys) then
                local dir = (ent:GetPos() - pos):GetNormalized()
                dir.z = 0.3 -- slight upward push
                phys:ApplyForceCenter(dir * force)
            end
        end
    end

    return true
end

-- Roadblock: spawn barriers ahead on the road
function Manhunt.Chase.DoRoadblock(ply, veh)
    local forward = veh:GetForward()
    local pos = veh:GetPos() + forward * 800 -- spawn ahead

    -- Trace down to ground
    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 200),
        endpos = pos - Vector(0, 0, 500),
        mask = MASK_SOLID_BRUSHONLY,
    })
    if tr.Hit then pos = tr.HitPos + Vector(0, 0, 5) end

    local duration = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_ROADBLOCK].duration
    local barricades = {}

    -- Spawn 3 barriers in a line perpendicular to driving direction
    local right = veh:GetRight()
    for i = -1, 1 do
        local barrierPos = pos + right * (i * 180)
        local barrier = ents.Create("prop_physics")
        if IsValid(barrier) then
            barrier:SetModel("models/props_c17/concrete_barrier001a.mdl")
            barrier:SetPos(barrierPos)
            barrier:SetAngles(Angle(0, veh:GetAngles().y + 90, 0))
            barrier:Spawn()
            barrier:Activate()
            barrier:GetPhysicsObject():SetMass(5000)
            barrier.ManhuntRoadblock = true
            table.insert(barricades, barrier)
        end
    end

    -- Remove after duration
    timer.Simple(duration, function()
        for _, b in ipairs(barricades) do
            if IsValid(b) then b:Remove() end
        end
    end)

    return true
end

-- Missile: fire a homing missile at the fugitive
function Manhunt.Chase.DoMissile(ply, veh)
    local target = nil
    if Manhunt.TestMode then
        -- In test mode, fire forward (no target)
        target = nil
    else
        local team = Manhunt.GetPlayerTeam(ply)
        if team == Manhunt.TEAM_HUNTER then
            target = Manhunt.GetFugitive()
        else
            -- Fugitive fires at nearest hunter
            local nearest, nearDist = nil, math.huge
            for _, h in ipairs(Manhunt.GetHunters()) do
                if IsValid(h) then
                    local d = h:GetPos():Distance(ply:GetPos())
                    if d < nearDist then
                        nearest = h
                        nearDist = d
                    end
                end
            end
            target = nearest
        end
    end

    local missilePos = veh:GetPos() + veh:GetForward() * 100 + Vector(0, 0, 50)
    local missileDir = veh:GetForward()

    local missile = ents.Create("prop_physics")
    if not IsValid(missile) then return false end
    missile:SetModel("models/weapons/w_missile_launch.mdl")
    missile:SetPos(missilePos)
    missile:SetAngles(missileDir:Angle())
    missile:Spawn()
    missile:SetCollisionGroup(COLLISION_GROUP_WEAPON)
    missile:SetMoveType(MOVETYPE_FLY)

    local missileSpeed = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_MISSILE].speed
    local missileDmg = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_MISSILE].damage
    missile.ManhuntMissile = true
    missile.ManhuntOwner = ply

    local lifeTime = 0
    timer.Create("Manhunt_Missile_" .. missile:EntIndex(), 0.05, 200, function()
        if not IsValid(missile) then return end
        lifeTime = lifeTime + 0.05

        -- Homing toward target
        local vel = missileDir * missileSpeed
        if IsValid(target) then
            local targetPos = target:GetPos() + Vector(0, 0, 30)
            local toTarget = (targetPos - missile:GetPos()):GetNormalized()
            -- Gradually turn toward target
            missileDir = (missileDir + toTarget * 0.05):GetNormalized()
            vel = missileDir * missileSpeed
        end

        missile:SetAngles(missileDir:Angle())
        missile:SetVelocity(vel)

        -- Check for hit
        for _, ent in ipairs(ents.FindInSphere(missile:GetPos(), 100)) do
            if ent.ManhuntChaseVehicle and ent.ManhuntOwner ~= ply then
                -- Don't damage shielded vehicles
                local ownerSid = IsValid(ent.ManhuntOwner) and ent.ManhuntOwner:SteamID() or ""
                if Manhunt.Chase.ShieldActive[ownerSid] then continue end

                -- Explode!
                local effectData = EffectData()
                effectData:SetOrigin(missile:GetPos())
                effectData:SetMagnitude(50)
                effectData:SetScale(100)
                util.Effect("Explosion", effectData)

                -- Damage vehicle health
                if Manhunt.Chase.VehicleHealth[ownerSid] then
                    Manhunt.Chase.VehicleHealth[ownerSid] = Manhunt.Chase.VehicleHealth[ownerSid] - missileDmg
                    if Manhunt.Chase.VehicleHealth[ownerSid] <= 0 then
                        local victimTeam = IsValid(ent.ManhuntOwner) and Manhunt.GetPlayerTeam(ent.ManhuntOwner) or 0
                        if victimTeam == Manhunt.TEAM_FUGITIVE then
                            Manhunt.Chase.EndGame("hunter")
                        end
                    end
                end

                -- Push vehicle
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    phys:ApplyForceCenter((ent:GetPos() - missile:GetPos()):GetNormalized() * 300000)
                end

                missile:Remove()
                return
            end
        end

        -- Timeout after 5 seconds
        if lifeTime > 5 then
            local effectData = EffectData()
            effectData:SetOrigin(missile:GetPos())
            effectData:SetMagnitude(20)
            util.Effect("Explosion", effectData)
            missile:Remove()
        end
    end)

    return true
end

-- Tracker Dart: tag the fugitive
function Manhunt.Chase.DoTrackerDart(ply, veh)
    local fugitive = Manhunt.GetFugitive()
    if Manhunt.TestMode then
        fugitive = ply -- track self in test mode
    end
    if not IsValid(fugitive) then return false end

    local trackDur = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_TRACKER_DART].trackDuration
    Manhunt.Chase.TrackerTarget = fugitive
    Manhunt.Chase.TrackerEnd = CurTime() + trackDur

    -- Notify fugitive
    if IsValid(fugitive) and fugitive ~= ply then
        fugitive:ChatPrint("[Manhunt] You've been tagged! Hunters can see your position for " .. trackDur .. "s!")
    end

    return true
end

-- Repair Kit: heal vehicle
function Manhunt.Chase.DoRepairKit(ply, veh)
    local sid = ply:SteamID()
    local healAmount = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_REPAIR_KIT].healAmount

    Manhunt.Chase.VehicleHealth[sid] = math.min(
        Manhunt.Chase.MaxVehicleHealth,
        (Manhunt.Chase.VehicleHealth[sid] or Manhunt.Chase.MaxVehicleHealth) + healAmount
    )

    -- Also try to repair Glide vehicle engine
    if veh.SetEngineHealth then
        veh:SetEngineHealth(math.min(veh:GetMaxEngineHealth(), veh:GetEngineHealth() + healAmount))
    end

    ply:ChatPrint("[Manhunt] Vehicle repaired! +" .. healAmount .. " HP")
    return true
end

-- Speed Trap: place a trap on the road
function Manhunt.Chase.DoSpeedTrap(ply, veh)
    local pos = veh:GetPos() - veh:GetForward() * 100

    local tr = util.TraceLine({
        start = pos + Vector(0, 0, 100),
        endpos = pos - Vector(0, 0, 200),
        mask = MASK_SOLID_BRUSHONLY,
    })
    if tr.Hit then pos = tr.HitPos + Vector(0, 0, 2) end

    local trap = ents.Create("prop_physics")
    if not IsValid(trap) then return false end
    trap:SetModel("models/props_junk/PopCan01a.mdl") -- small model
    trap:SetPos(pos)
    trap:Spawn()
    trap:SetColor(Color(255, 255, 0, 200))
    trap:SetRenderMode(RENDERMODE_TRANSCOLOR)
    trap:SetMoveType(MOVETYPE_NONE)
    trap:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    trap:GetPhysicsObject():EnableMotion(false)
    trap:SetModelScale(3)
    trap.ManhuntSpeedTrap = true
    trap.ManhuntOwner = ply

    local slowDur = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_SPEED_TRAP].slowDuration
    local slowFactor = Manhunt.Chase.Abilities[Manhunt.Chase.ABILITY_SPEED_TRAP].slowFactor

    -- Check for vehicles
    timer.Create("Manhunt_Trap_" .. trap:EntIndex(), 0.3, 100, function()
        if not IsValid(trap) then return end
        for _, ent in ipairs(ents.FindInSphere(trap:GetPos(), 200)) do
            if ent.ManhuntChaseVehicle and ent.ManhuntOwner ~= ply then
                -- Slow the vehicle
                local phys = ent:GetPhysicsObject()
                if IsValid(phys) then
                    phys:SetVelocity(phys:GetVelocity() * slowFactor)
                end
                if IsValid(ent.ManhuntOwner) then
                    ent.ManhuntOwner:ChatPrint("[Manhunt] You hit a Speed Trap!")
                end
                trap:Remove()
                return
            end
        end
    end)

    -- Remove after 30 seconds if not triggered
    timer.Simple(30, function()
        if IsValid(trap) then trap:Remove() end
    end)

    return true
end

-- End the chase game
function Manhunt.Chase.EndGame(winner)
    if Manhunt.Phase == Manhunt.PHASE_ENDGAME then return end

    print("[Manhunt] [Chase] Game over! Winner: " .. winner)

    Manhunt.Chase.Active = false
    Manhunt.Phase = Manhunt.PHASE_ENDGAME
    Manhunt.Winner = winner

    if Manhunt.TestMode then
        Manhunt.TestMode = false
        net.Start("Manhunt_TestMode")
        net.WriteBool(false)
        net.Broadcast()
    end

    -- Stop all chase timers
    timer.Remove("Manhunt_ChaseCountdown")
    timer.Remove("Manhunt_ChaseThink")
    timer.Remove("Manhunt_ChaseGameEnd")
    timer.Remove("Manhunt_ChaseHealthSync")

    -- Remove ability-related timers
    for _, ply in ipairs(player.GetAll()) do
        local sid = ply:SteamID()
        timer.Remove("Manhunt_Shield_" .. sid)
        timer.Remove("Manhunt_Ghost_" .. sid)
    end

    -- Clean up chase entities
    for _, ent in ipairs(ents.GetAll()) do
        if ent.ManhuntOilSlick or ent.ManhuntRoadblock or ent.ManhuntSpeedTrap or ent.ManhuntMissile then
            ent:Remove()
        end
    end

    -- Remove oil/trap timers
    for _, tmr in ipairs(timer.GetTimers and timer.GetTimers() or {}) do
        -- timer.GetTimers doesn't exist in GMod, so we'll just let them expire
    end

    -- Unfreeze everyone
    for _, ply in ipairs(player.GetAll()) do
        Manhunt.FreezePlayer(ply, false)
        ply:GodDisable()
        -- Restore ghost vehicles
        local sid = ply:SteamID()
        local veh = Manhunt.SpawnedVehicles[sid]
        if IsValid(veh) then
            veh:SetCollisionGroup(COLLISION_GROUP_NONE)
            veh:SetRenderMode(RENDERMODE_NORMAL)
            veh:SetColor(Color(255, 255, 255, 255))
        end
    end

    Manhunt.Chase.ShieldActive = {}
    Manhunt.Chase.GhostActive = {}

    -- Send end game
    net.Start("Manhunt_EndGame")
    net.WriteString(winner)
    net.Broadcast()

    Manhunt.PlayAudioCue(winner == "fugitive" and "fugitive_wins" or "hunter_wins")

    -- Handle rounds
    if Manhunt.Rounds and Manhunt.Rounds.enabled then
        Manhunt.OnRoundEnd(winner)
    end

    hook.Remove("PlayerDeath", "Manhunt_ChasePlayerDeath")
    hook.Remove("EntityTakeDamage", "Manhunt_ChaseVehicleDamage")

    -- Clean up vehicles after delay
    timer.Simple(15, function()
        Manhunt.CleanupVehicles()
    end)
end

-- Stop chase (force stop)
function Manhunt.Chase.StopGame()
    Manhunt.Chase.Active = false
    hook.Remove("PlayerDeath", "Manhunt_ChasePlayerDeath")
    hook.Remove("EntityTakeDamage", "Manhunt_ChaseVehicleDamage")

    timer.Remove("Manhunt_ChaseCountdown")
    timer.Remove("Manhunt_ChaseThink")
    timer.Remove("Manhunt_ChaseGameEnd")
    timer.Remove("Manhunt_ChaseHealthSync")

    -- Stop pickup system
    if Manhunt.Chase.Pickups and Manhunt.Chase.Pickups.Stop then
        Manhunt.Chase.Pickups.Stop()
    end

    -- Clean up entities
    for _, ent in ipairs(ents.GetAll()) do
        if ent.ManhuntOilSlick or ent.ManhuntRoadblock or ent.ManhuntSpeedTrap or ent.ManhuntMissile then
            ent:Remove()
        end
    end

    for _, ply in ipairs(player.GetAll()) do
        local sid = ply:SteamID()
        timer.Remove("Manhunt_Shield_" .. sid)
        timer.Remove("Manhunt_Ghost_" .. sid)
        Manhunt.FreezePlayer(ply, false)
        ply:GodDisable()
    end

    Manhunt.Chase.ShieldActive = {}
    Manhunt.Chase.GhostActive = {}
end

-- Receive ability use from client
net.Receive("Manhunt_ChaseAbilityUse", function(len, ply)
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
    if not Manhunt.IsChaseMode() then return end
    local team = Manhunt.GetPlayerTeam(ply)
    if team ~= Manhunt.TEAM_FUGITIVE and team ~= Manhunt.TEAM_HUNTER then return end

    local abilityId = net.ReadUInt(8)
    Manhunt.Chase.UseAbility(ply, abilityId)
end)

-- Handle pickup collect from client proximity
net.Receive("Manhunt_ChasePickupCollect", function(len, ply)
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
    if not Manhunt.IsChaseMode() then return end

    local pickupIdx = net.ReadUInt(8)
    if Manhunt.Chase.Pickups and Manhunt.Chase.Pickups.Collect then
        Manhunt.Chase.Pickups.Collect(ply, pickupIdx)
    end
end)

print("[Manhunt] [SV] sv_chase.lua loaded!")
