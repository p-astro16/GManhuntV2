--[[
    Manhunt - Server Vehicles
    Vehicle spawning with Glide mod compatibility
]]

Manhunt.SpawnedVehicle = nil
Manhunt.SpawnedVehicles = {} -- per-player vehicles: {steamid = entity}

-- Spawn the Infernus at a specific position (used by vehicle beacon)
function Manhunt.SpawnFugitiveVehicleAt(pos, owner)
    if not pos then return end

    local sid = IsValid(owner) and owner:SteamID() or "unknown"

    -- Remove this player's old vehicle if exists (not other players')
    if IsValid(Manhunt.SpawnedVehicles[sid]) then
        Manhunt.SpawnedVehicles[sid]:Remove()
    end

    local ang = Angle(0, 0, 0)
    if IsValid(owner) then
        ang = owner:GetAngles()
        ang.p = 0
        ang.r = 0
    end

    -- Try to spawn as Glide vehicle first
    local vehicle = ents.Create("gtav_infernus")

    if not IsValid(vehicle) then
        -- Fallback: try as simfphys
        vehicle = ents.Create("gmod_sent_vehicle_fphysics_base")
        if IsValid(vehicle) then
            vehicle.VehicleTable = list.Get("simfphys_vehicles")["gtav_infernus"]
        end
    end

    if not IsValid(vehicle) then
        print("[Manhunt] WARNING: Could not spawn gtav_infernus!")
        if IsValid(owner) then
            owner:ChatPrint("[Manhunt] Could not spawn vehicle! Make sure the Glide car mod is installed.")
        end
        return nil
    end

    vehicle:SetPos(pos + Vector(0, 0, 20))
    vehicle:SetAngles(ang)
    vehicle:Spawn()
    vehicle:Activate()

    vehicle.ManhuntVehicle = true
    vehicle.ManhuntOwner = owner

    Manhunt.SpawnedVehicles[sid] = vehicle
    -- Keep SpawnedVehicle pointing to the fugitive's vehicle for endgame logic
    if IsValid(owner) and Manhunt.GetPlayerTeam(owner) == Manhunt.TEAM_FUGITIVE then
        Manhunt.SpawnedVehicle = vehicle
    end

    if IsValid(owner) then
        owner:ChatPrint("[Manhunt] Your vehicle has arrived!")
    end

    return vehicle
end

-- Spawn the Infernus next to the fugitive (legacy fallback)
function Manhunt.SpawnFugitiveVehicle(ply)
    if not IsValid(ply) then return end

    local sid = ply:SteamID()

    -- Remove this player's old vehicle if exists
    if IsValid(Manhunt.SpawnedVehicles[sid]) then
        Manhunt.SpawnedVehicles[sid]:Remove()
    end

    local pos = ply:GetPos() + ply:GetRight() * 100 + Vector(0, 0, 20)
    local ang = ply:GetAngles()
    ang.p = 0
    ang.r = 0

    -- Try to spawn as Glide vehicle first
    local vehicle = ents.Create("gtav_infernus")

    if not IsValid(vehicle) then
        -- Fallback: try as simfphys
        vehicle = ents.Create("gmod_sent_vehicle_fphysics_base")
        if IsValid(vehicle) then
            vehicle.VehicleTable = list.Get("simfphys_vehicles")["gtav_infernus"]
        end
    end

    if not IsValid(vehicle) then
        print("[Manhunt] WARNING: Could not spawn gtav_infernus! Make sure Glide car mod is installed.")
        ply:ChatPrint("[Manhunt] Could not spawn vehicle! Make sure the Glide car mod is installed.")
        return nil
    end

    vehicle:SetPos(pos)
    vehicle:SetAngles(ang)
    vehicle:Spawn()
    vehicle:Activate()

    vehicle.ManhuntVehicle = true
    vehicle.ManhuntOwner = ply

    Manhunt.SpawnedVehicles[sid] = vehicle
    Manhunt.SpawnedVehicle = vehicle

    return vehicle
end

-- Clean up vehicles when game ends
function Manhunt.CleanupVehicles()
    if IsValid(Manhunt.SpawnedVehicle) then
        Manhunt.SpawnedVehicle:Remove()
        Manhunt.SpawnedVehicle = nil
    end
    for sid, veh in pairs(Manhunt.SpawnedVehicles) do
        if IsValid(veh) then veh:Remove() end
    end
    Manhunt.SpawnedVehicles = {}
end

-- Check if a player is in a vehicle (supports Glide)
function Manhunt.IsPlayerInVehicle(ply)
    if not IsValid(ply) then return false end

    -- Standard GMod vehicle check
    if ply:InVehicle() then return true end

    -- Glide vehicle check
    local glideVeh = ply:GetNWEntity("GlideVehicle")
    if IsValid(glideVeh) then return true end

    return false
end

-- Get the vehicle a player is in (supports Glide)
function Manhunt.GetPlayerVehicle(ply)
    if not IsValid(ply) then return nil end

    -- Standard GMod vehicle
    if ply:InVehicle() then
        return ply:GetVehicle()
    end

    -- Glide vehicle
    local glideVeh = ply:GetNWEntity("GlideVehicle")
    if IsValid(glideVeh) then return glideVeh end

    return nil
end

-- Get vehicle speed in km/h (supports Glide)
function Manhunt.GetVehicleSpeed(ply)
    local veh = Manhunt.GetPlayerVehicle(ply)
    if not IsValid(veh) then return 0 end

    -- Glide vehicles: GetSpeed() returns km/h directly
    if veh.GetSpeed then
        return veh:GetSpeed() or 0
    end

    -- Fallback to physics velocity (Source units/s → km/h)
    -- 1 Source unit = 0.01905m, so units/s * 0.01905 * 3.6 = km/h
    local phys = veh:GetPhysicsObject()
    if IsValid(phys) then
        return phys:GetVelocity():Length() * 0.06858
    end

    return 0
end
