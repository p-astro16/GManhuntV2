--[[
    Manhunt - Server Pickup System
    Spawns a weapon (arc9_eft_usp) at 50% game time for the fugitive to fight back
    Spawns ammo at random intervals on the map
]]

Manhunt.Pickups = Manhunt.Pickups or {}
Manhunt.Pickups.WeaponSpawned = false
Manhunt.Pickups.Entities = {}

local WEAPON_CLASS = "arc9_eft_fn57"
local AMMO_TYPE = "57x28mm"
local AMMO_AMOUNT = 20           -- Ammo per pickup (1 magazine worth)
local AMMO_INTERVAL_MIN = 45     -- Min seconds between ammo spawns
local AMMO_INTERVAL_MAX = 90     -- Max seconds between ammo spawns

-- Find a safe, accessible spawn position on the map
function Manhunt.Pickups.FindSpawnPos()
    local navAreas = navmesh.GetAllNavAreas()
    if not navAreas or #navAreas == 0 then return nil end
    
    -- Helper: check above ground
    local function IsAboveGround(pos)
        local tr = util.TraceLine({
            start = pos + Vector(0, 0, 50),
            endpos = pos + Vector(0, 0, 50000),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if tr.HitSky then return true end
        if tr.HitPos.z - pos.z > 5000 then return true end
        if not tr.Hit then return true end
        return false
    end
    
    -- Helper: check inside zone
    local function IsInsideZone(pos)
        if not Manhunt.Zone or not Manhunt.Zone.Active then return true end
        local center = Manhunt.Zone.Center
        local radius = Manhunt.Zone.GetCurrentRadius()
        local flatPos = Vector(pos.x, pos.y, 0)
        local flatCenter = Vector(center.x, center.y, 0)
        return flatPos:Distance(flatCenter) < radius * 0.85
    end
    
    for attempt = 1, 30 do
        local area = navAreas[math.random(#navAreas)]
        if not area then continue end
        
        local pos = area:GetCenter()
        local sizeX = area:GetSizeX()
        local sizeY = area:GetSizeY()
        
        -- Need a reasonably sized area (accessible by foot)
        if sizeX < 80 or sizeY < 80 then continue end
        if not IsAboveGround(pos) then continue end
        if not IsInsideZone(pos) then continue end
        
        -- Not in water
        if bit.band(util.PointContents(pos), CONTENTS_WATER) ~= 0 then continue end
        
        -- Trace to ground
        local tr = util.TraceLine({
            start = pos + Vector(0, 0, 100),
            endpos = pos - Vector(0, 0, 100),
            mask = MASK_SOLID_BRUSHONLY,
        })
        
        if tr.Hit then
            return tr.HitPos + Vector(0, 0, 10)
        end
    end
    
    -- Fallback: player spawn points
    local spawns = ents.FindByClass("info_player_start")
    table.Add(spawns, ents.FindByClass("info_player_deathmatch"))
    if #spawns > 0 then
        local spawn = spawns[math.random(#spawns)]
        if IsValid(spawn) then
            return spawn:GetPos() + Vector(0, 0, 10)
        end
    end
    
    return nil
end

-- Spawn the USP weapon at 50% game time
function Manhunt.Pickups.SpawnWeapon()
    if Manhunt.Pickups.WeaponSpawned then return end
    Manhunt.Pickups.WeaponSpawned = true
    
    print("[Manhunt] SpawnWeapon() called - giving USP directly to fugitive!")
    
    -- Give the weapon directly to the fugitive (and in test mode, to the player)
    local recipients = {}
    if Manhunt.TestMode then
        local ply = player.GetAll()[1]
        if IsValid(ply) then table.insert(recipients, ply) end
    else
        local fugitive = Manhunt.GetFugitive()
        if IsValid(fugitive) then table.insert(recipients, fugitive) end
    end
    
    for _, ply in ipairs(recipients) do
        if IsValid(ply) and ply:Alive() then
            ply:Give(WEAPON_CLASS)
            ply:GiveAmmo(AMMO_AMOUNT * 2, AMMO_TYPE, true) -- 2 mags worth of starting ammo
            ply:ChatPrint("[Manhunt] You received a USP! Fight back!")
            ply:EmitSound("items/suitchargeok1.wav")
        end
    end
    
    -- Notify all clients
    net.Start("Manhunt_WeaponSpawn")
    net.WriteVector(Vector(0, 0, 0))
    net.WriteString(WEAPON_CLASS)
    net.Broadcast()
    
    -- Chat notification for everyone
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            ply:ChatPrint("[Manhunt] The fugitive has received a weapon!")
        end
    end
end

-- Spawn an ammo pickup at a random location
function Manhunt.Pickups.SpawnAmmo()
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
    
    local pos = Manhunt.Pickups.FindSpawnPos()
    if not pos then return end
    
    -- Create a visible ammo box prop with pickup logic
    local ammoBox = ents.Create("prop_physics")
    if not IsValid(ammoBox) then return end
    
    ammoBox:SetModel("models/items/boxsrounds.mdl")
    ammoBox:SetPos(pos + Vector(0, 0, 10))
    ammoBox:SetAngles(Angle(0, math.random(360), 0))
    ammoBox:Spawn()
    ammoBox:Activate()
    
    -- Make it frozen in place (don't want it rolling away)
    local phys = ammoBox:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
    end
    
    -- Custom flag
    ammoBox:SetNWBool("ManhuntAmmo", true)
    ammoBox.ManhuntAmmoAmount = AMMO_AMOUNT
    
    -- Track for cleanup
    table.insert(Manhunt.Pickups.Entities, ammoBox)
    
    print("[Manhunt] Ammo spawned at " .. tostring(pos))
    
    -- Notify clients
    net.Start("Manhunt_AmmoSpawn")
    net.WriteVector(pos)
    net.Broadcast()
    
    -- Auto-remove after 120 seconds if not picked up
    timer.Simple(120, function()
        if IsValid(ammoBox) then
            ammoBox:Remove()
            
            -- Notify clients to remove marker
            net.Start("Manhunt_PickupCollected")
            net.WriteVector(pos)
            net.Broadcast()
        end
    end)
end

-- Check for players near ammo pickups (touch trigger)
hook.Add("Think", "Manhunt_AmmoPickupCheck", function()
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
    
    -- Only check every 0.3 seconds for performance
    if not Manhunt.Pickups._lastCheck or CurTime() - Manhunt.Pickups._lastCheck >= 0.3 then
        Manhunt.Pickups._lastCheck = CurTime()
    else
        return
    end
    
    for i = #Manhunt.Pickups.Entities, 1, -1 do
        local ent = Manhunt.Pickups.Entities[i]
        if not IsValid(ent) then
            table.remove(Manhunt.Pickups.Entities, i)
            continue
        end
        
        -- Only check ammo boxes (weapons are picked up by GMod automatically)
        if not ent:GetNWBool("ManhuntAmmo", false) then continue end
        
        local entPos = ent:GetPos()
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() and ply:GetPos():Distance(entPos) < 80 then
                -- Give ammo
                ply:GiveAmmo(ent.ManhuntAmmoAmount or AMMO_AMOUNT, AMMO_TYPE, true)
                ply:EmitSound("items/ammo_pickup.wav")
                ply:ChatPrint("[Manhunt] Picked up pistol ammo!")
                
                -- Notify clients to remove marker
                net.Start("Manhunt_PickupCollected")
                net.WriteVector(entPos)
                net.Broadcast()
                
                ent:Remove()
                table.remove(Manhunt.Pickups.Entities, i)
                break
            end
        end
    end
end)

-- Start the pickup system (called from game start)
function Manhunt.Pickups.Start()
    Manhunt.Pickups.WeaponSpawned = false
    Manhunt.Pickups.Entities = {}
    Manhunt.Pickups._weaponCheckStarted = false
    
    -- Start ammo spawn timer (random intervals once weapon is available)
    timer.Create("Manhunt_AmmoSpawnTimer", AMMO_INTERVAL_MIN, 0, function()
        if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then
            timer.Remove("Manhunt_AmmoSpawnTimer")
            return
        end
        
        -- Only spawn ammo after the weapon has been spawned
        if not Manhunt.Pickups.WeaponSpawned then return end
        
        Manhunt.Pickups.SpawnAmmo()
        
        -- Randomize next interval
        local nextInterval = math.random(AMMO_INTERVAL_MIN, AMMO_INTERVAL_MAX)
        timer.Adjust("Manhunt_AmmoSpawnTimer", nextInterval, 0)
    end)
end

-- Stop and clean up pickups
function Manhunt.Pickups.Stop()
    timer.Remove("Manhunt_AmmoSpawnTimer")
    
    -- Remove all pickup entities
    for _, ent in ipairs(Manhunt.Pickups.Entities) do
        if IsValid(ent) then
            ent:Remove()
        end
    end
    Manhunt.Pickups.Entities = {}
    Manhunt.Pickups.WeaponSpawned = false
end

print("[Manhunt] sv_pickups.lua loaded")
