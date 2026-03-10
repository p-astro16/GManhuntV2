--[[
    Manhunt - High Speed Chase Pickups (Server)
    Road pickup spawning, collection, ability grants
]]

Manhunt.Chase = Manhunt.Chase or {}
Manhunt.Chase.Pickups = Manhunt.Chase.Pickups or {}

Manhunt.Chase.Pickups.ActivePickups = {}  -- {idx = {pos, abilityId, entity}}
Manhunt.Chase.Pickups.NextSpawnTime = 0
Manhunt.Chase.Pickups.PickupCounter = 0

-- Start the pickup system
function Manhunt.Chase.Pickups.Start()
    Manhunt.Chase.Pickups.ActivePickups = {}
    Manhunt.Chase.Pickups.PickupCounter = 0
    Manhunt.Chase.Pickups.NextSpawnTime = CurTime() + 10 -- first spawn after 10s

    timer.Create("Manhunt_ChasePickupThink", 2, 0, function()
        if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE or not Manhunt.IsChaseMode() then
            timer.Remove("Manhunt_ChasePickupThink")
            return
        end
        Manhunt.Chase.Pickups.Think()
    end)

    print("[Manhunt] [Chase] Pickup system started!")
end

-- Stop the pickup system
function Manhunt.Chase.Pickups.Stop()
    timer.Remove("Manhunt_ChasePickupThink")

    -- Remove all pickup entities
    for idx, pickup in pairs(Manhunt.Chase.Pickups.ActivePickups) do
        if IsValid(pickup.entity) then
            pickup.entity:Remove()
        end
    end
    Manhunt.Chase.Pickups.ActivePickups = {}
    Manhunt.Chase.Pickups.PickupCounter = 0
end

-- Think: spawn pickups and check collection
function Manhunt.Chase.Pickups.Think()
    local now = CurTime()
    local config = Manhunt.Chase.PickupConfig

    -- Spawn new pickups
    if now >= Manhunt.Chase.Pickups.NextSpawnTime then
        local activeCount = table.Count(Manhunt.Chase.Pickups.ActivePickups)
        if activeCount < config.MaxPickups then
            Manhunt.Chase.Pickups.SpawnPickup()
        end
        Manhunt.Chase.Pickups.NextSpawnTime = now + config.SpawnInterval
    end

    -- Check for drive-through collection
    Manhunt.Chase.Pickups.CheckCollection()
end

-- Find a road position for a pickup
function Manhunt.Chase.Pickups.FindSpawnPos()
    local navAreas = navmesh.GetAllNavAreas()
    if not navAreas or #navAreas == 0 then return nil end

    local config = Manhunt.Chase.PickupConfig

    for attempt = 1, 30 do
        local area = navAreas[math.random(#navAreas)]
        if not area then continue end

        local pos = area:GetCenter()
        local sizeX = area:GetSizeX()
        local sizeY = area:GetSizeY()

        -- Prefer wider areas (roads)
        if sizeX < 150 or sizeY < 150 then continue end

        -- Not underwater
        if bit.band(util.PointContents(pos), CONTENTS_WATER) ~= 0 then continue end

        -- Above ground
        local skyTr = util.TraceLine({
            start = pos + Vector(0, 0, 50),
            endpos = pos + Vector(0, 0, 30000),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if not skyTr.HitSky and skyTr.Hit then continue end

        -- Check distance from existing pickups
        local tooClose = false
        for _, existing in pairs(Manhunt.Chase.Pickups.ActivePickups) do
            if pos:Distance(existing.pos) < config.MinDistance then
                tooClose = true
                break
            end
        end
        if tooClose then continue end

        -- Trace to ground
        local tr = util.TraceLine({
            start = pos + Vector(0, 0, 200),
            endpos = pos - Vector(0, 0, 200),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if tr.Hit then
            return tr.HitPos + Vector(0, 0, 30) -- float slightly above ground
        end
    end

    return nil
end

-- Spawn a pickup
function Manhunt.Chase.Pickups.SpawnPickup()
    local pos = Manhunt.Chase.Pickups.FindSpawnPos()
    if not pos then return end

    -- Pick a random ability for this pickup
    local abilityId = Manhunt.Chase.PickupAbilities[math.random(#Manhunt.Chase.PickupAbilities)]
    local abilityDef = Manhunt.Chase.Abilities[abilityId]
    if not abilityDef then return end

    Manhunt.Chase.Pickups.PickupCounter = Manhunt.Chase.Pickups.PickupCounter + 1
    local idx = Manhunt.Chase.Pickups.PickupCounter

    -- Create a visible entity (spinning prop)
    local ent = ents.Create("prop_physics")
    if not IsValid(ent) then return end
    ent:SetModel("models/items/item_item_crate.mdl")
    ent:SetPos(pos)
    ent:Spawn()
    ent:SetMoveType(MOVETYPE_NONE)
    ent:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    ent:SetColor(abilityDef.color)
    ent:SetRenderMode(RENDERMODE_TRANSCOLOR)
    ent:SetModelScale(0.6)

    local phys = ent:GetPhysicsObject()
    if IsValid(phys) then
        phys:EnableMotion(false)
    end

    ent.ManhuntChasePickup = true
    ent.ManhuntPickupIdx = idx

    Manhunt.Chase.Pickups.ActivePickups[idx] = {
        pos = pos,
        abilityId = abilityId,
        entity = ent,
    }

    -- Notify clients about pickup spawn
    net.Start("Manhunt_ChasePickupSpawn")
    net.WriteUInt(idx, 8)
    net.WriteUInt(abilityId, 8)
    net.WriteVector(pos)
    net.Broadcast()

    print("[Manhunt] [Chase] Pickup spawned: " .. abilityDef.name .. " at " .. tostring(pos))
end

-- Check if any player is close enough to collect a pickup
function Manhunt.Chase.Pickups.CheckCollection()
    local collectRadius = Manhunt.Chase.PickupConfig.CollectRadius

    for idx, pickup in pairs(Manhunt.Chase.Pickups.ActivePickups) do
        if not IsValid(pickup.entity) then
            Manhunt.Chase.Pickups.ActivePickups[idx] = nil
            continue
        end

        for _, ply in ipairs(player.GetAll()) do
            if not IsValid(ply) or not ply:Alive() then continue end
            if not Manhunt.IsPlayerInVehicle(ply) then continue end

            local team = Manhunt.GetPlayerTeam(ply)
            if team == Manhunt.TEAM_NONE and not Manhunt.TestMode then continue end

            -- Check if this team can use this ability
            if not Manhunt.Chase.CanTeamUse(pickup.abilityId, team) and not Manhunt.TestMode then
                continue
            end

            local dist = ply:GetPos():Distance(pickup.pos)
            if dist < collectRadius then
                Manhunt.Chase.Pickups.DoCollect(ply, idx)
                break
            end
        end
    end
end

-- Collect a pickup
function Manhunt.Chase.Pickups.Collect(ply, pickupIdx)
    -- Server-side proxy, actual collection handled by CheckCollection
end

function Manhunt.Chase.Pickups.DoCollect(ply, idx)
    local pickup = Manhunt.Chase.Pickups.ActivePickups[idx]
    if not pickup then return end

    local sid = ply:SteamID()
    local abilityId = pickup.abilityId
    local abilityDef = Manhunt.Chase.Abilities[abilityId]

    -- Grant the ability charge
    if not Manhunt.Chase.PlayerAbilities[sid] then
        Manhunt.Chase.PlayerAbilities[sid] = {}
    end
    Manhunt.Chase.PlayerAbilities[sid][abilityId] = (Manhunt.Chase.PlayerAbilities[sid][abilityId] or 0) + 1

    -- Initialize cooldown if not set
    if not Manhunt.Chase.Cooldowns[sid] then
        Manhunt.Chase.Cooldowns[sid] = {}
    end
    if not Manhunt.Chase.Cooldowns[sid][abilityId] then
        Manhunt.Chase.Cooldowns[sid][abilityId] = 0
    end

    -- Sync abilities to player
    Manhunt.Chase.SyncAbilities(ply)

    -- Remove pickup entity
    if IsValid(pickup.entity) then
        pickup.entity:Remove()
    end
    Manhunt.Chase.Pickups.ActivePickups[idx] = nil

    -- Notify all clients
    net.Start("Manhunt_ChasePickupCollect")
    net.WriteUInt(idx, 8)
    net.WriteEntity(ply)
    net.WriteUInt(abilityId, 8)
    net.Broadcast()

    ply:ChatPrint("[Manhunt] Picked up: " .. (abilityDef and abilityDef.name or "Unknown") .. "!")
    print("[Manhunt] [Chase] " .. ply:Nick() .. " collected " .. (abilityDef and abilityDef.name or "?"))
end

print("[Manhunt] [SV] sv_chase_pickups.lua loaded!")
