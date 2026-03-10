--[[
    Manhunt - Server Game Logic
    Main game controller: start, stop, phases, intervals, win conditions
]]

Manhunt.HunterDeaths = Manhunt.HunterDeaths or {}
Manhunt.IntervalCount = 0
Manhunt.DecoyActive = false
Manhunt.DecoyPos = nil

-- Car bomb state
Manhunt.CarBomb = {
    placed = false,
    entity = nil,   -- The bomb entity (visual)
    target = nil,    -- The vehicle it's attached to
}

-- Start the game (normal mode)
function Manhunt.StartGame()
    if Manhunt.TestMode then
        return Manhunt.StartTestMode()
    end

    local fugitive = Manhunt.GetFugitive()
    local hunters = Manhunt.GetHunters()

    if not IsValid(fugitive) then
        print("[Manhunt] Cannot start: No fugitive assigned!")
        return false
    end

    if #hunters == 0 then
        print("[Manhunt] Cannot start: No hunters assigned!")
        return false
    end

    print("[Manhunt] Starting game!")

    -- Reset state
    Manhunt.HunterDeaths = {}
    Manhunt.IntervalCount = 0
    Manhunt.CarBomb = { placed = false, entity = nil, target = nil }
    Manhunt.DecoyActive = false
    Manhunt.DecoyPos = nil
    Manhunt.NextIntervalTime = 0
    Manhunt.EndgameActive = false
    Manhunt.EndgameTriggered = false
    Manhunt.ZoneAnnounced = false

    for _, hunter in ipairs(hunters) do
        Manhunt.HunterDeaths[hunter:SteamID()] = 0
    end

    -- Reset per-player state
    for _, ply in ipairs(player.GetAll()) do
        ply.ManhuntDecoyUsed = false
        ply:SetNWBool("ManhuntDecoyUsed", false)
        ply.NextSpawnTime = nil
    end

    -- Phase: Countdown
    Manhunt.Phase = Manhunt.PHASE_COUNTDOWN
    Manhunt.CountdownEnd = CurTime() + 10
    Manhunt.SyncPhase()

    -- Prepare fugitive
    Manhunt.GiveFugitiveLoadout(fugitive)

    -- Freeze all hunters (and make them immune)
    for _, hunter in ipairs(hunters) do
        Manhunt.FreezePlayer(hunter, true)
        hunter:GodEnable()
        Manhunt.GiveHunterLoadout(hunter)
    end

    -- Play countdown audio
    Manhunt.PlayAudioCue("countdown")

    -- After 10 second countdown
    timer.Create("Manhunt_Countdown", 10, 1, function()
        if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end

        -- Phase: Active
        Manhunt.Phase = Manhunt.PHASE_ACTIVE
        local gameTimeSec = Manhunt.Config.GameTime * 60
        Manhunt.StartTime = CurTime()
        Manhunt.EndTime = CurTime() + gameTimeSec
        Manhunt.SyncPhase()

        -- Fugitive spawns their own vehicle via Vehicle Beacon SWEP
        -- Give spawn protection (5 seconds)
        local fug = Manhunt.GetFugitive()
        if IsValid(fug) then
            Manhunt.ApplySpawnProtection(fug, 5)
        end

        -- Play game start audio
        Manhunt.PlayAudioCue("game_start")

        -- Start tracking
        Manhunt.InitTracking()
        Manhunt.StartTracking()
        Manhunt.StartViewpointRecording()
        
        -- Start pickup system (weapon + ammo spawns)
        if Manhunt.Pickups and Manhunt.Pickups.Start then
            Manhunt.Pickups.Start()
        end

        -- Unfreeze hunters after first interval
        local firstInterval = Manhunt.Config.Interval * 60
        timer.Create("Manhunt_UnfreezeHunters", firstInterval, 1, function()
            for _, hunter in ipairs(Manhunt.GetHunters()) do
                if IsValid(hunter) then
                    Manhunt.FreezePlayer(hunter, false)
                    hunter:GodDisable()
                end
            end
            Manhunt.PlayAudioCue("hunters_released")

            -- Trigger first camera scan
            Manhunt.TriggerIntervalScan()
        end)

        -- Start interval timer for camera scans (after first interval + subsequent)
        timer.Create("Manhunt_IntervalCheck", 1, 0, function()
            Manhunt.CheckInterval()
        end)

        -- Game end timer
        timer.Create("Manhunt_GameEnd", gameTimeSec, 1, function()
            if Manhunt.Phase == Manhunt.PHASE_ACTIVE then
                Manhunt.EndGame("fugitive")
            end
        end)
    end)

    return true
end

-- Start test mode (solo play)
function Manhunt.StartTestMode()
    local ply = player.GetAll()[1]
    if not IsValid(ply) then
        print("[Manhunt] Cannot start test mode: No player found!")
        return false
    end

    print("[Manhunt] Starting TEST MODE!")

    -- Set test mode flag and sync to client
    Manhunt.TestMode = true
    net.Start("Manhunt_TestMode")
    net.WriteBool(true)
    net.Broadcast()

    -- Assign player as fugitive
    Manhunt.SetPlayerTeam(ply, Manhunt.TEAM_FUGITIVE)

    -- Reset state
    Manhunt.HunterDeaths = {}
    Manhunt.IntervalCount = 0
    Manhunt.CarBomb = { placed = false, entity = nil, target = nil }
    Manhunt.DecoyActive = false
    Manhunt.DecoyPos = nil
    Manhunt.NextIntervalTime = 0
    Manhunt.EndgameActive = false
    Manhunt.EndgameTriggered = false
    Manhunt.ZoneAnnounced = false

    ply.ManhuntDecoyUsed = false
    ply:SetNWBool("ManhuntDecoyUsed", false)
    ply.NextSpawnTime = nil

    -- Short countdown (3s instead of 10s for test mode)
    Manhunt.Phase = Manhunt.PHASE_COUNTDOWN
    Manhunt.CountdownEnd = CurTime() + 3
    Manhunt.SyncPhase()

    -- Give combined loadout (both fugitive + hunter items)
    Manhunt.GiveTestModeLoadout(ply)

    Manhunt.PlayAudioCue("countdown")

    timer.Create("Manhunt_Countdown", 3, 1, function()
        if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end

        Manhunt.Phase = Manhunt.PHASE_ACTIVE
        local gameTimeSec = Manhunt.Config.GameTime * 60
        Manhunt.StartTime = CurTime()
        Manhunt.EndTime = CurTime() + gameTimeSec
        Manhunt.SyncPhase()

        -- Fugitive spawns their own vehicle via Vehicle Beacon SWEP
        if IsValid(ply) then
            Manhunt.ApplySpawnProtection(ply, 5)
        end

        Manhunt.PlayAudioCue("game_start")

        -- Start tracking
        Manhunt.InitTracking()
        Manhunt.StartTracking()
        Manhunt.StartViewpointRecording()
        
        -- Start pickup system in test mode too
        if Manhunt.Pickups and Manhunt.Pickups.Start then
            Manhunt.Pickups.Start()
        end

        -- In test mode: no hunter freeze, just start scans immediately
        -- First scan after one interval
        timer.Create("Manhunt_IntervalCheck", 1, 0, function()
            Manhunt.CheckInterval()
        end)

        -- Initialize first interval time
        Manhunt.NextIntervalTime = CurTime() + Manhunt.GetCurrentInterval()

        timer.Create("Manhunt_GameEnd", gameTimeSec, 1, function()
            if Manhunt.Phase == Manhunt.PHASE_ACTIVE then
                Manhunt.EndGame("fugitive")
            end
        end)
    end)

    return true
end

-- Interval check (runs every second)
Manhunt.NextIntervalTime = 0
function Manhunt.CheckInterval()
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then
        timer.Remove("Manhunt_IntervalCheck")
        return
    end

    local now = CurTime()

    -- Initialize next interval time after hunters are unfrozen (normal mode only)
    if Manhunt.NextIntervalTime == 0 and not Manhunt.TestMode then
        local firstInterval = Manhunt.Config.Interval * 60
        Manhunt.NextIntervalTime = Manhunt.StartTime + firstInterval + Manhunt.GetCurrentInterval()
    end

    -- Safety: if still 0 in test mode, set it now
    if Manhunt.NextIntervalTime == 0 then
        Manhunt.NextIntervalTime = now + Manhunt.GetCurrentInterval()
    end

    if now >= Manhunt.NextIntervalTime then
        Manhunt.TriggerIntervalScan()
        Manhunt.NextIntervalTime = now + Manhunt.GetCurrentInterval()
    end

    -- Check for endgame trigger at 80% game time
    if not Manhunt.EndgameTriggered then
        local remaining = Manhunt.GetRemainingTime()
        local total = Manhunt.GetTotalGameTime()
        if total > 0 and remaining <= total * 0.2 then
            Manhunt.TriggerEndgameMechanic()
        end
        
        -- Announce zone 1 minute before endgame (pre-pick center + compass direction)
        if not Manhunt.ZoneAnnounced and total > 0 then
            local endgameThreshold = total * 0.2
            if remaining <= endgameThreshold + 60 then
                Manhunt.ZoneAnnounced = true
                if Manhunt.Zone and Manhunt.Zone.PreAnnounce then
                    Manhunt.Zone.PreAnnounce()
                end
            end
        end
    end
    
    -- Check for weapon spawn at 50% game time
    if Manhunt.Pickups and not Manhunt.Pickups.WeaponSpawned then
        local remaining = Manhunt.GetRemainingTime()
        local total = Manhunt.GetTotalGameTime()
        if total > 0 and remaining <= total * 0.5 then
            print("[Manhunt] 50% game time reached - spawning weapon! (remaining: " .. math.floor(remaining) .. "s / total: " .. math.floor(total) .. "s)")
            Manhunt.Pickups.SpawnWeapon()
        end
    end

    -- Sync the next scan time to clients so HUD can show countdown
    if not Manhunt._lastIntervalSync or now - Manhunt._lastIntervalSync >= 1 then
        Manhunt._lastIntervalSync = now
        net.Start("Manhunt_NextScan")
        net.WriteFloat(Manhunt.NextIntervalTime)
        net.Broadcast()
    end
end

-- Trigger a surveillance camera scan for all hunters
function Manhunt.TriggerIntervalScan()
    Manhunt.IntervalCount = Manhunt.IntervalCount + 1
    local fugitive = Manhunt.GetFugitive()
    if not IsValid(fugitive) then return end

    local targetPos = fugitive:GetPos()
    local inVehicle = Manhunt.IsPlayerInVehicle(fugitive)
    local vehicleSpeed = inVehicle and Manhunt.GetVehicleSpeed(fugitive) or 0
    local vehicleDir = Vector(0, 0, 0)
    if inVehicle then
        vehicleDir = fugitive:GetVelocity():GetNormalized()
    end

    -- Check for decoy
    local showDecoy = Manhunt.DecoyActive
    local decoyPos = Manhunt.DecoyPos or Vector(0, 0, 0)

    -- In test mode, send the camera view to the solo player (themselves)
    if Manhunt.TestMode then
        local ply = player.GetAll()[1]
        if IsValid(ply) then
            net.Start("Manhunt_CameraView")
            net.WriteVector(targetPos)
            net.WriteBool(inVehicle)
            net.WriteVector(vehicleDir)
            net.WriteFloat(vehicleSpeed)
            net.WriteBool(Manhunt.IsLastTenPercent())
            net.WriteBool(showDecoy)
            net.WriteVector(decoyPos)
            net.Send(ply)

            if Manhunt.IsLastTenPercent() then
                net.Start("Manhunt_PingPos")
                net.WriteVector(targetPos)
                net.WriteBool(true)
                net.Send(ply)
            end
        end
    else
        -- Send camera view to all hunters
        for _, hunter in ipairs(Manhunt.GetHunters()) do
            if IsValid(hunter) then
                net.Start("Manhunt_CameraView")
                net.WriteVector(targetPos)
                net.WriteBool(inVehicle)
                net.WriteVector(vehicleDir)
                net.WriteFloat(vehicleSpeed)
                net.WriteBool(Manhunt.IsLastTenPercent())
                net.WriteBool(showDecoy)
                net.WriteVector(decoyPos)
                net.Send(hunter)

                -- In last 10%, also send a ping
                if Manhunt.IsLastTenPercent() then
                    net.Start("Manhunt_PingPos")
                    net.WriteVector(targetPos)
                    net.WriteBool(true) -- is fugitive ping
                    net.Send(hunter)
                end
            end
        end
    end

    -- Play scan audio cue
    Manhunt.PlayAudioCue(Manhunt.IsLastTenPercent() and "scan_urgent" or "scan")

    -- Decoy lifetime is now managed by weapon_manhunt_decoy SWEP (30s timer)
end

-- Trigger endgame mechanic at 80% game time
function Manhunt.TriggerEndgameMechanic()
    if Manhunt.EndgameTriggered then return end
    Manhunt.EndgameTriggered = true
    Manhunt.EndgameActive = true

    print("[Manhunt] ENDGAME PHASE TRIGGERED - 80% of game time elapsed!")

    -- 1. Halve the intervals: already handled by GetCurrentInterval() checking EndgameActive
    -- Immediately adjust the next interval to use the halved time
    local now = CurTime()
    local remaining = Manhunt.NextIntervalTime - now
    if remaining > Manhunt.GetCurrentInterval() then
        Manhunt.NextIntervalTime = now + Manhunt.GetCurrentInterval()
    end

    -- 2. Notify all clients about endgame phase
    net.Start("Manhunt_EndgameTrigger")
    net.Broadcast()

    -- Play endgame audio cue
    Manhunt.PlayAudioCue("hunters_released") -- Use alarm sound for endgame

    -- 3. Start shrinking zone (if enabled)
    if Manhunt.Zone and Manhunt.Zone.Start then
        Manhunt.Zone.Start()
    end

    -- 3b. Force-spawn weapon if not already spawned (endgame = 80%, weapon should be at 50%)
    if Manhunt.Pickups and not Manhunt.Pickups.WeaponSpawned then
        print("[Manhunt] Endgame triggered - forcing weapon spawn!")
        Manhunt.Pickups.SpawnWeapon()
    end

    -- 4. Hunter scan refill: 2 scans if they had 0, keep if > 2
    local function RefillHunterScans()
        local hunters = Manhunt.GetHunters()
        for _, hunter in ipairs(hunters) do
            if IsValid(hunter) then
                local scanner = hunter:GetWeapon("weapon_manhunt_scanner")
                if IsValid(scanner) then
                    local charges = scanner:GetNWInt("ManhuntCharges", 0)
                    if charges < 2 then
                        scanner:SetNWInt("ManhuntCharges", 2)
                        hunter:ChatPrint("[Manhunt] ENDGAME: Scanner recharged to 2!")
                    end
                end
            end
        end

        -- In test mode, also refill own scanner
        if Manhunt.TestMode then
            local ply = player.GetAll()[1]
            if IsValid(ply) then
                local scanner = ply:GetWeapon("weapon_manhunt_scanner")
                if IsValid(scanner) then
                    local charges = scanner:GetNWInt("ManhuntCharges", 0)
                    if charges < 2 then
                        scanner:SetNWInt("ManhuntCharges", 2)
                        ply:ChatPrint("[Manhunt] ENDGAME: Scanner recharged to 2!")
                    end
                end
            end
        end
    end
    RefillHunterScans()

    -- 4. Explode the fugitive's car with 3 second countdown
    local fugitive = Manhunt.GetFugitive()
    local vehicle = Manhunt.SpawnedVehicle

    if IsValid(vehicle) then
        -- Notify all clients about the car countdown
        net.Start("Manhunt_VehicleCountdown")
        net.WriteVector(vehicle:GetPos())
        net.WriteFloat(3) -- 3 second countdown
        net.Broadcast()

        -- If fugitive is in the vehicle, eject them
        timer.Simple(1.5, function()
            if not IsValid(vehicle) then return end
            if IsValid(fugitive) and Manhunt.IsPlayerInVehicle(fugitive) then
                -- Eject from Glide vehicle
                local glideVeh = fugitive:GetNWEntity("GlideVehicle")
                if IsValid(glideVeh) and glideVeh.EjectDriver then
                    glideVeh:EjectDriver()
                elseif fugitive:InVehicle() then
                    fugitive:ExitVehicle()
                end
                if IsValid(fugitive) then
                    fugitive:ChatPrint("[Manhunt] ENDGAME: Get out! Your car is about to explode!")
                end
            end
        end)

        -- Explode after 3 seconds
        timer.Simple(3, function()
            if not IsValid(vehicle) then return end

            local explodePos = vehicle:GetPos()

            -- Create explosion effect
            local effectData = EffectData()
            effectData:SetOrigin(explodePos)
            effectData:SetMagnitude(100)
            effectData:SetScale(200)
            util.Effect("Explosion", effectData)

            -- Damage near the vehicle (but don't instakill)
            util.BlastDamage(vehicle, vehicle, explodePos, 300, 50)

            -- Fire effects
            for i = 1, 3 do
                local firePos = explodePos + VectorRand() * 100
                local fire = ents.Create("env_fire")
                if IsValid(fire) then
                    fire:SetPos(firePos)
                    fire:SetKeyValue("health", "5")
                    fire:SetKeyValue("firesize", "80")
                    fire:SetKeyValue("fireattack", "1")
                    fire:SetKeyValue("damagescale", "0")
                    fire:Spawn()
                    fire:Activate()
                    fire:Fire("StartFire", "", 0)
                    timer.Simple(6, function()
                        if IsValid(fire) then fire:Remove() end
                    end)
                end
            end

            -- Remove the vehicle
            vehicle:Remove()
            Manhunt.SpawnedVehicle = nil

            -- 5. Spawn a new vehicle at a random location after a delay
            timer.Create("Manhunt_EndgameCarRespawn", 10, 1, function()
                if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end

                local spawnPos = Manhunt.FindRandomVehicleSpawnPos()
                if not spawnPos then
                    print("[Manhunt] Could not find random spawn position for endgame vehicle!")
                    -- Fallback: spawn near fugitive
                    local fug = Manhunt.GetFugitive()
                    if IsValid(fug) then
                        spawnPos = fug:GetPos() + Vector(math.random(-500, 500), math.random(-500, 500), 50)
                    end
                end

                if spawnPos then
                    -- Spawn the new vehicle
                    local newVehicle = Manhunt.SpawnFugitiveVehicleAt(spawnPos, Manhunt.GetFugitive())

                    -- Send vehicle marker to ALL players (both teams can see it)
                    net.Start("Manhunt_VehicleMarker")
                    net.WriteVector(spawnPos)
                    net.WriteBool(true) -- marker active
                    net.Broadcast()

                    if IsValid(Manhunt.GetFugitive()) then
                        Manhunt.GetFugitive():ChatPrint("[Manhunt] ENDGAME: A new vehicle has spawned! Look for the marker!")
                    end

                    -- Check if fugitive enters the vehicle to remove the marker
                    timer.Create("Manhunt_EndgameVehicleMarkerCheck", 1, 0, function()
                        if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then
                            timer.Remove("Manhunt_EndgameVehicleMarkerCheck")
                            return
                        end

                        local fug = Manhunt.GetFugitive()
                        if not IsValid(fug) then return end

                        if Manhunt.IsPlayerInVehicle(fug) then
                            -- Fugitive entered the vehicle, remove marker
                            net.Start("Manhunt_VehicleMarker")
                            net.WriteVector(Vector(0, 0, 0))
                            net.WriteBool(false) -- marker inactive
                            net.Broadcast()
                            timer.Remove("Manhunt_EndgameVehicleMarkerCheck")
                        end
                    end)
                end
            end)
        end)
    else
        -- No vehicle existed, just spawn one at a random location after a short delay
        timer.Create("Manhunt_EndgameCarRespawn", 5, 1, function()
            if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end

            local spawnPos = Manhunt.FindRandomVehicleSpawnPos()
            if not spawnPos then
                local fug = Manhunt.GetFugitive()
                if IsValid(fug) then
                    spawnPos = fug:GetPos() + Vector(math.random(-500, 500), math.random(-500, 500), 50)
                end
            end

            if spawnPos then
                Manhunt.SpawnFugitiveVehicleAt(spawnPos, Manhunt.GetFugitive())

                net.Start("Manhunt_VehicleMarker")
                net.WriteVector(spawnPos)
                net.WriteBool(true)
                net.Broadcast()

                if IsValid(Manhunt.GetFugitive()) then
                    Manhunt.GetFugitive():ChatPrint("[Manhunt] ENDGAME: A vehicle has spawned! Look for the marker!")
                end

                timer.Create("Manhunt_EndgameVehicleMarkerCheck", 1, 0, function()
                    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then
                        timer.Remove("Manhunt_EndgameVehicleMarkerCheck")
                        return
                    end

                    local fug = Manhunt.GetFugitive()
                    if not IsValid(fug) then return end

                    if Manhunt.IsPlayerInVehicle(fug) then
                        net.Start("Manhunt_VehicleMarker")
                        net.WriteVector(Vector(0, 0, 0))
                        net.WriteBool(false)
                        net.Broadcast()
                        timer.Remove("Manhunt_EndgameVehicleMarkerCheck")
                    end
                end)
            end
        end)
    end
end

-- Find a random valid spawn position on the map for a vehicle
function Manhunt.FindRandomVehicleSpawnPos()
    -- Helper: check if a position is above ground (can see the sky)
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

    -- Helper: check if position is inside the shrinking zone (if active)
    local function IsInsideZone(pos)
        if not Manhunt.Zone or not Manhunt.Zone.Active then return true end
        local center = Manhunt.Zone.Center
        local radius = Manhunt.Zone.GetCurrentRadius()
        local flatPos = Vector(pos.x, pos.y, 0)
        local flatCenter = Vector(center.x, center.y, 0)
        -- Must be well inside the zone (80% of radius) so it stays valid as zone shrinks
        return flatPos:Distance(flatCenter) < radius * 0.8
    end

    -- Helper: check if position is safe for vehicle placement
    local function IsSafeSpawn(pos)
        -- Not in water
        if bit.band(util.PointContents(pos), CONTENTS_WATER) ~= 0 then return false end
        if bit.band(util.PointContents(pos + Vector(0, 0, 30)), CONTENTS_WATER) ~= 0 then return false end

        -- Ground is relatively flat (trace 4 corners of vehicle footprint)
        local checkDist = 120 -- half vehicle width
        local baseZ = pos.z
        for _, offset in ipairs({Vector(checkDist, 0, 0), Vector(-checkDist, 0, 0), Vector(0, checkDist, 0), Vector(0, -checkDist, 0)}) do
            local tr = util.TraceLine({
                start = pos + offset + Vector(0, 0, 200),
                endpos = pos + offset - Vector(0, 0, 200),
                mask = MASK_SOLID_BRUSHONLY,
            })
            if not tr.Hit then return false end
            if math.abs(tr.HitPos.z - baseZ) > 80 then return false end -- Too steep
        end

        -- Enough overhead clearance (not under a bridge/roof)
        local upTrace = util.TraceLine({
            start = pos + Vector(0, 0, 10),
            endpos = pos + Vector(0, 0, 300),
            mask = MASK_SOLID_BRUSHONLY,
        })
        if upTrace.Hit then return false end

        -- Not blocked by nearby props/walls
        local hullTrace = util.TraceHull({
            start = pos + Vector(0, 0, 30),
            endpos = pos + Vector(0, 0, 30),
            mins = Vector(-100, -50, 0),
            maxs = Vector(100, 50, 70),
            mask = MASK_SOLID,
        })
        if hullTrace.Hit then return false end

        return true
    end

    -- Try navmesh first
    local navAreas = navmesh.GetAllNavAreas()
    if navAreas and #navAreas > 0 then
        -- Shuffle navmesh areas for better randomness
        local shuffled = {}
        for _, v in ipairs(navAreas) do shuffled[#shuffled + 1] = v end
        for i = #shuffled, 2, -1 do
            local j = math.random(i)
            shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
        end

        -- Try multiple times to find a good spot
        for attempt = 1, math.min(40, #shuffled) do
            local area = shuffled[attempt]
            if area then
                local pos = area:GetCenter()
                local sizeX = area:GetSizeX()
                local sizeY = area:GetSizeY()
                if sizeX > 200 and sizeY > 200 then
                    if not IsAboveGround(pos) then continue end
                    if not IsInsideZone(pos) then continue end

                    local fugitive = Manhunt.GetFugitive()
                    if IsValid(fugitive) then
                        local dist = pos:Distance(fugitive:GetPos())
                        if dist > 800 and dist < 8000 then
                            local tr = util.TraceLine({
                                start = pos + Vector(0, 0, 100),
                                endpos = pos - Vector(0, 0, 100),
                                mask = MASK_SOLID_BRUSHONLY
                            })
                            if tr.Hit then
                                local spawnPos = tr.HitPos + Vector(0, 0, 20)
                                if IsSafeSpawn(spawnPos) then
                                    return spawnPos
                                end
                            end
                        end
                    else
                        local spawnPos = pos + Vector(0, 0, 20)
                        if IsSafeSpawn(spawnPos) then
                            return spawnPos
                        end
                    end
                end
            end
        end
    end

    -- Fallback: try player spawn points
    local spawns = ents.FindByClass("info_player_start")
    table.Add(spawns, ents.FindByClass("info_player_deathmatch"))
    table.Add(spawns, ents.FindByClass("info_player_terrorist"))
    table.Add(spawns, ents.FindByClass("info_player_counterterrorist"))

    if #spawns > 0 then
        for attempt = 1, math.min(#spawns, 15) do
            local spawn = spawns[math.random(#spawns)]
            if IsValid(spawn) then
                local pos = spawn:GetPos()
                if not IsAboveGround(pos) then continue end
                if not IsInsideZone(pos) then continue end
                local fugitive = Manhunt.GetFugitive()
                if IsValid(fugitive) then
                    local dist = pos:Distance(fugitive:GetPos())
                    if dist > 500 then
                        return pos + Vector(0, 0, 20)
                    end
                else
                    return pos + Vector(0, 0, 20)
                end
            end
        end
        -- Last resort: return any valid spawn
        for _, spawn in ipairs(spawns) do
            if IsValid(spawn) then
                return spawn:GetPos() + Vector(0, 0, 20)
            end
        end
        return nil
    end

    return nil
end

-- End the game
function Manhunt.EndGame(winner)
    if Manhunt.Phase == Manhunt.PHASE_ENDGAME then return end

    print("[Manhunt] Game over! Winner: " .. winner)

    Manhunt.Phase = Manhunt.PHASE_ENDGAME
    Manhunt.Winner = winner

    -- Clear test mode
    if Manhunt.TestMode then
        Manhunt.TestMode = false
        net.Start("Manhunt_TestMode")
        net.WriteBool(false)
        net.Broadcast()
    end

    -- Stop all timers
    timer.Remove("Manhunt_Countdown")
    timer.Remove("Manhunt_UnfreezeHunters")
    timer.Remove("Manhunt_IntervalCheck")
    timer.Remove("Manhunt_GameEnd")
    timer.Remove("Manhunt_EndgameCarRespawn")
    timer.Remove("Manhunt_EndgameVehicleMarkerCheck")
    timer.Remove("Manhunt_ZoneDamage")
    Manhunt.StopTracking()

    -- Stop zone
    if Manhunt.Zone and Manhunt.Zone.Stop then
        Manhunt.Zone.Stop()
    end
    
    -- Stop pickups
    if Manhunt.Pickups and Manhunt.Pickups.Stop then
        Manhunt.Pickups.Stop()
    end

    -- Unfreeze everyone
    for _, ply in ipairs(player.GetAll()) do
        Manhunt.FreezePlayer(ply, false)
        ply:GodDisable()
        -- Remove spawn protection
        timer.Remove("Manhunt_SpawnProtection_" .. ply:SteamID())
        if ply.ManhuntSpawnProtected then
            ply.ManhuntSpawnProtected = false
        end
    end

    -- Reset endgame state
    Manhunt.EndgameActive = false
    Manhunt.EndgameTriggered = false
    Manhunt.ZoneAnnounced = false

    -- Send end game message
    net.Start("Manhunt_EndGame")
    net.WriteString(winner)
    net.Broadcast()

    -- Send stats
    timer.Simple(0.5, function()
        Manhunt.SendStats()
    end)

    -- Send replay data
    timer.Simple(1, function()
        Manhunt.SendReplayData()
    end)

    -- Play end game audio
    Manhunt.PlayAudioCue(winner == "fugitive" and "fugitive_wins" or "hunter_wins")

    -- Notify round system (if active)
    if Manhunt.Rounds and Manhunt.Rounds.enabled then
        Manhunt.OnRoundEnd(winner)
    end

    -- Clean up vehicles after a delay
    timer.Simple(15, function()
        Manhunt.CleanupVehicles()
    end)
end

-- Stop the game (force stop from menu)
function Manhunt.StopGame()
    if Manhunt.Phase == Manhunt.PHASE_IDLE then return end

    Manhunt.Phase = Manhunt.PHASE_IDLE
    Manhunt.Winner = nil

    -- Clear test mode
    if Manhunt.TestMode then
        Manhunt.TestMode = false
        net.Start("Manhunt_TestMode")
        net.WriteBool(false)
        net.Broadcast()
    end

    -- Stop all timers
    timer.Remove("Manhunt_Countdown")
    timer.Remove("Manhunt_UnfreezeHunters")
    timer.Remove("Manhunt_IntervalCheck")
    timer.Remove("Manhunt_GameEnd")
    timer.Remove("Manhunt_EndgameCarRespawn")
    timer.Remove("Manhunt_EndgameVehicleMarkerCheck")
    timer.Remove("Manhunt_ZoneDamage")
    Manhunt.StopTracking()

    -- Stop zone
    if Manhunt.Zone and Manhunt.Zone.Stop then
        Manhunt.Zone.Stop()
    end
    
    -- Stop pickups
    if Manhunt.Pickups and Manhunt.Pickups.Stop then
        Manhunt.Pickups.Stop()
    end

    -- Unfreeze everyone
    for _, ply in ipairs(player.GetAll()) do
        Manhunt.FreezePlayer(ply, false)
        ply:GodDisable()
        timer.Remove("Manhunt_SpawnProtection_" .. ply:SteamID())
        if ply.ManhuntSpawnProtected then
            ply.ManhuntSpawnProtected = false
        end
    end

    -- Reset endgame state
    Manhunt.EndgameActive = false
    Manhunt.EndgameTriggered = false
    Manhunt.ZoneAnnounced = false

    Manhunt.SyncPhase()
    Manhunt.CleanupVehicles()
end

-- Freeze/unfreeze a player
function Manhunt.FreezePlayer(ply, frozen)
    if not IsValid(ply) then return end

    net.Start("Manhunt_Freeze")
    net.WriteBool(frozen)
    net.Send(ply)
end

-- Fugitive death → Hunter wins (skip in test mode)
hook.Add("PlayerDeath", "Manhunt_PlayerDeath", function(victim, inflictor, attacker)
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end

    -- In test mode, death just respawns the player, no game over
    if Manhunt.TestMode then return end

    if Manhunt.GetPlayerTeam(victim) == Manhunt.TEAM_FUGITIVE then
        -- Send kill cam data to all players
        local attackerName = IsValid(attacker) and attacker:IsPlayer() and attacker:Nick() or "World"
        local weaponName = ""
        if IsValid(attacker) and attacker:IsPlayer() then
            local wep = attacker:GetActiveWeapon()
            if IsValid(wep) then
                weaponName = wep:GetPrintName() or wep:GetClass()
            end
        end

        -- Get viewpoint replay buffer from the attacker
        local vpBuffer = {}
        if IsValid(attacker) and attacker:IsPlayer() then
            vpBuffer = Manhunt.GetViewpointBuffer(attacker)
        end

        net.Start("Manhunt_KillCam")
        -- Write viewpoint buffer for replay
        net.WriteUInt(#vpBuffer, 8)
        for _, entry in ipairs(vpBuffer) do
            net.WriteVector(entry.pos)
            net.WriteAngle(entry.ang)
        end
        -- Write kill info
        net.WriteVector(victim:GetPos())
        net.WriteString(victim:Nick())
        net.WriteString(attackerName)
        net.WriteString(weaponName)
        net.Broadcast()

        -- Delay game end to allow kill cam to play (4 seconds)
        timer.Simple(4, function()
            Manhunt.EndGame("hunter")
        end)
    elseif Manhunt.GetPlayerTeam(victim) == Manhunt.TEAM_HUNTER then
        -- Hunter death: increment death counter for respawn penalty
        local sid = victim:SteamID()
        Manhunt.HunterDeaths[sid] = (Manhunt.HunterDeaths[sid] or 0) + 1

        -- Send kill PiP to the fugitive so they can see the hunter die
        local fugitive = Manhunt.GetFugitive()
        if IsValid(fugitive) then
            local killerName = ""
            local weaponName = ""

            if IsValid(attacker) and attacker:IsPlayer() then
                killerName = attacker:Nick()
                local wep = attacker:GetActiveWeapon()
                if IsValid(wep) then
                    weaponName = wep:GetPrintName() or wep:GetClass()
                end
            elseif IsValid(attacker) then
                killerName = attacker:GetClass()
            else
                killerName = "World"
            end

            net.Start("Manhunt_HunterKillPiP")
            net.WriteVector(victim:GetPos())
            net.WriteVector(IsValid(attacker) and attacker:IsPlayer() and attacker:EyePos() or victim:GetPos() + Vector(0, 0, 100))
            net.WriteAngle(IsValid(attacker) and attacker:IsPlayer() and attacker:EyeAngles() or Angle(20, 0, 0))
            net.WriteString(victim:Nick())
            net.WriteString(killerName)
            net.WriteString(weaponName)
            net.Send(fugitive)
        end
    end
end)

-- Hunter respawn with penalty
hook.Add("PlayerDeathThink", "Manhunt_HunterRespawn", function(ply)
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
    if Manhunt.GetPlayerTeam(ply) ~= Manhunt.TEAM_HUNTER then return end

    local sid = ply:SteamID()
    local deaths = Manhunt.HunterDeaths[sid] or 0
    local respawnDelay = math.min(5 + (deaths - 1) * 5, 20) -- 5s, 10s, 15s, 20s max

    if ply.NextSpawnTime == nil then
        ply.NextSpawnTime = CurTime() + respawnDelay
    end

    if CurTime() >= ply.NextSpawnTime then
        ply.NextSpawnTime = nil
        ply:Spawn()

        -- Re-give scanner
        timer.Simple(0.5, function()
            if IsValid(ply) then
                Manhunt.GiveHunterLoadout(ply)
            end
        end)
    end

    return true -- Block default respawn behavior
end)

-- Prevent fugitive from respawning (game ends on death) - skip in test mode
hook.Add("PlayerDeathThink", "Manhunt_FugitiveNoRespawn", function(ply)
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
    if Manhunt.TestMode then return end -- Allow respawn in test mode
    if Manhunt.GetPlayerTeam(ply) == Manhunt.TEAM_FUGITIVE then
        return true -- Block respawn
    end
end)

-- Handle game start request
net.Receive("Manhunt_RequestStart", function(len, ply)
    if not ply:IsListenServerHost() then return end

    -- Initialize round system if multiple rounds configured
    local rounds = Manhunt.Config.Rounds or 1
    if rounds > 1 then
        Manhunt.InitRounds(rounds)
        Manhunt.StartNextRound()
    else
        -- Single round, normal start
        Manhunt.Rounds.enabled = false
        Manhunt.StartGame()
    end
end)

-- Handle test mode start request
net.Receive("Manhunt_TestMode", function(len, ply)
    if not ply:IsListenServerHost() then return end
    local start = net.ReadBool()
    if start then
        Manhunt.TestMode = true
        Manhunt.StartGame()
    else
        Manhunt.StopGame()
    end
end)

-- Handle game stop request
net.Receive("Manhunt_RequestStop", function(len, ply)
    if not ply:IsListenServerHost() then return end
    Manhunt.StopGame()
end)

-- Note: Scan requests are handled directly by weapon_manhunt_scanner
-- Note: Car bomb logic is handled directly by weapon_manhunt_carbomb

-- Decoy placement is now handled by weapon_manhunt_decoy SWEP (throwable grenade)

-- Note: Car bomb placement is handled by weapon_manhunt_carbomb directly
-- The net receivers below are kept as backup for non-weapon triggers

-- Audio cue helper
function Manhunt.PlayAudioCue(cueType)
    net.Start("Manhunt_AudioCue")
    net.WriteString(cueType)
    net.Broadcast()
end

-- Lobby sync for pre-game
net.Receive("Manhunt_LobbySync", function(len, ply)
    -- Resync all data to requesting player
    Manhunt.SyncConfig()
    Manhunt.SyncTeams()
    Manhunt.SyncPhase()
end)

-- Console command to instantly trigger endgame phase
concommand.Add("manhunt_endgame", function(ply, cmd, args)
    -- Only allow listen server host
    if IsValid(ply) and not ply:IsListenServerHost() then
        ply:ChatPrint("[Manhunt] Only the host can trigger endgame.")
        return
    end

    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then
        if IsValid(ply) then
            ply:ChatPrint("[Manhunt] Game must be active to trigger endgame.")
        else
            print("[Manhunt] Game must be active to trigger endgame.")
        end
        return
    end

    if Manhunt.EndgameTriggered then
        if IsValid(ply) then
            ply:ChatPrint("[Manhunt] Endgame is already active!")
        else
            print("[Manhunt] Endgame is already active!")
        end
        return
    end

    print("[Manhunt] Endgame manually triggered by host!")
    
    -- Immediately unfreeze all hunters and remove god mode
    timer.Remove("Manhunt_UnfreezeHunters")
    for _, hunter in ipairs(Manhunt.GetHunters()) do
        if IsValid(hunter) then
            Manhunt.FreezePlayer(hunter, false)
            hunter:GodDisable()
        end
    end
    
    Manhunt.TriggerEndgameMechanic()
end)
