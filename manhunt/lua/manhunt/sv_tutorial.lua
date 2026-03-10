--[[
    Manhunt - Server Tutorial System
    Spawns demo entities for the interactive tutorial
    Each step spawns props/vehicles/effects at a stage position
    Per-player: each player gets their own demo entities hidden from others
]]

Manhunt.Tutorial = Manhunt.Tutorial or {}
Manhunt.Tutorial.ActivePlayers = {} -- track which players are in tutorial
Manhunt.Tutorial.PlayerData = {}    -- per-player: {entities = {}, sounds = {}}

-- Get or create per-player data
local function GetPlayerData(ply)
    local sid = ply:SteamID()
    if not Manhunt.Tutorial.PlayerData[sid] then
        Manhunt.Tutorial.PlayerData[sid] = { entities = {}, sounds = {} }
    end
    return Manhunt.Tutorial.PlayerData[sid]
end

-- Clean up a specific player's demo entities + sounds
function Manhunt.Tutorial.CleanupPlayer(ply)
    local sid = IsValid(ply) and ply:SteamID() or nil
    if not sid then return end
    
    local data = Manhunt.Tutorial.PlayerData[sid]
    if not data then return end
    
    for _, ent in ipairs(data.entities) do
        if IsValid(ent) then ent:Remove() end
    end
    data.entities = {}
    
    for _, snd in ipairs(data.sounds) do
        if snd then snd:Stop() end
    end
    data.sounds = {}
end

-- Clean up ALL players (used on game end etc.)
function Manhunt.Tutorial.Cleanup()
    for sid, data in pairs(Manhunt.Tutorial.PlayerData) do
        for _, ent in ipairs(data.entities) do
            if IsValid(ent) then ent:Remove() end
        end
        for _, snd in ipairs(data.sounds) do
            if snd then snd:Stop() end
        end
    end
    Manhunt.Tutorial.PlayerData = {}
end

-- Helper: spawn a demo entity, track it per-player, hide from other players
local function SpawnDemo(ply, class, pos, ang, model, scale, color)
    local ent
    if class == "prop_physics" then
        ent = ents.Create("prop_physics")
        if not IsValid(ent) then return nil end
        ent:SetModel(model or "models/props_junk/wood_crate001a.mdl")
        ent:SetPos(pos)
        ent:SetAngles(ang or Angle(0, 0, 0))
        ent:Spawn()
        ent:Activate()
        if scale then ent:SetModelScale(scale) end
        if color then ent:SetColor(color) end
        local phys = ent:GetPhysicsObject()
        if IsValid(phys) then
            phys:EnableMotion(false)
        end
    elseif class == "prop_dynamic" then
        ent = ents.Create("prop_dynamic")
        if not IsValid(ent) then return nil end
        ent:SetModel(model or "models/props_junk/wood_crate001a.mdl")
        ent:SetPos(pos)
        ent:SetAngles(ang or Angle(0, 0, 0))
        ent:Spawn()
        ent:Activate()
        if scale then ent:SetModelScale(scale) end
        if color then ent:SetColor(color) end
    end
    
    if IsValid(ent) then
        -- Hide this entity from all other players
        for _, other in ipairs(player.GetAll()) do
            if other ~= ply then
                ent:SetPreventTransmit(other, true)
            end
        end
        
        -- Track per-player
        local data = GetPlayerData(ply)
        table.insert(data.entities, ent)
    end
    return ent
end

-- Get a stage position in front of the player
function Manhunt.Tutorial.GetStagePos(ply)
    local forward = ply:GetForward()
    return ply:GetPos() + forward * 400 + Vector(0, 0, 0)
end

-- ============================================================
-- DEMO SEQUENCES
-- Each returns the "look at" position for the camera
-- ============================================================

function Manhunt.Tutorial.Demo_VehicleBeacon(stagePos, ply)
    Manhunt.Tutorial.CleanupPlayer(ply)
    
    -- Spawn a grenade prop falling down
    local grenadePos = stagePos + Vector(0, 0, 50)
    local grenade = SpawnDemo(ply, "prop_dynamic", grenadePos, nil, "models/weapons/w_grenade.mdl", 1.5, Color(50, 150, 255))
    
    -- After 1.5s, remove grenade and spawn car
    timer.Simple(1.5, function()
        if IsValid(grenade) then
            grenade:Remove()
        end
        
        -- Spawn effect
        local effectData = EffectData()
        effectData:SetOrigin(stagePos)
        effectData:SetScale(2)
        util.Effect("ThumperDust", effectData)
        sound.Play("ambient/machines/thumper_startup1.wav", stagePos, 80, 100)
        
        -- Spawn demo car (use standard HL2 vehicle model)
        local car = SpawnDemo(ply, "prop_dynamic", stagePos + Vector(0, 0, 20), Angle(0, 45, 0), "models/buggy.mdl", 1)
        if IsValid(car) then
            car:SetColor(Color(30, 120, 255))
        end
    end)
    
    return stagePos + Vector(0, 0, 50)
end

function Manhunt.Tutorial.Demo_CarBomb(stagePos, ply)
    Manhunt.Tutorial.CleanupPlayer(ply)
    
    -- Spawn a car (use standard HL2 vehicle model)
    local car = SpawnDemo(ply, "prop_dynamic", stagePos, Angle(0, 30, 0), "models/buggy.mdl", 1)
    if IsValid(car) then
        car:SetColor(Color(180, 50, 50))
    end
    
    -- Flashing light on the car (bomb indicator)
    local light = SpawnDemo(ply, "prop_dynamic", stagePos + Vector(0, 0, 60), nil, "models/hunter/plates/plate.mdl", 0.5, Color(255, 0, 0))
    
    -- After 3s, explode the car
    timer.Simple(3, function()
        if IsValid(car) then
            local explode = ents.Create("env_explosion")
            if IsValid(explode) then
                explode:SetPos(car:GetPos())
                explode:Spawn()
                explode:SetKeyValue("iMagnitude", "200")
                explode:Fire("Explode", "", 0)
            end
            util.ScreenShake(car:GetPos(), 15, 5, 2, 2000)
            car:Remove()
        end
        if IsValid(light) then light:Remove() end
    end)
    
    return stagePos + Vector(0, 0, 60)
end

function Manhunt.Tutorial.Demo_Scanner(stagePos, ply)
    Manhunt.Tutorial.CleanupPlayer(ply)
    
    -- Spawn a scanner device prop
    local scanner = SpawnDemo(ply, "prop_dynamic", stagePos + Vector(0, 0, 30), Angle(-20, 0, 0), "models/weapons/w_slam.mdl", 2, Color(0, 200, 255))
    
    -- Create a pulsing plate on the ground (radar effect)
    local radar = SpawnDemo(ply, "prop_dynamic", stagePos, Angle(0, 0, 0), "models/hunter/plates/plate.mdl", 3, Color(0, 200, 255, 100))
    if IsValid(radar) then
        radar:SetMaterial("models/debug/debugwhite")
        radar:SetRenderMode(RENDERMODE_TRANSALPHA)
    end
    
    -- Play scan sound
    sound.Play("buttons/blip1.wav", stagePos, 80, 100)
    
    -- Pulse effect
    timer.Simple(1, function()
        sound.Play("ambient/machines/combine_terminal_idle4.wav", stagePos, 70, 150)
    end)
    
    return stagePos + Vector(0, 0, 40)
end

function Manhunt.Tutorial.Demo_Decoy(stagePos, ply)
    Manhunt.Tutorial.CleanupPlayer(ply)
    
    -- Spawn a grenade being thrown
    local startPos = stagePos + Vector(-100, 0, 80)
    local endPos = stagePos + Vector(100, 50, 0)
    
    local grenade = SpawnDemo(ply, "prop_dynamic", startPos, nil, "models/weapons/w_grenade.mdl", 1.2, Color(255, 200, 50))
    
    -- Animate the grenade "throw" using timers
    timer.Simple(0.5, function()
        if IsValid(grenade) then
            grenade:SetPos(LerpVector(0.5, startPos, endPos))
        end
    end)
    
    timer.Simple(1.0, function()
        if IsValid(grenade) then
            grenade:SetPos(endPos)
            sound.Play("physics/metal/metal_canister_impact_soft1.wav", endPos, 70, 100)
        end
    end)
    
    -- Show the fake blip marker
    timer.Simple(1.5, function()
        if IsValid(grenade) then grenade:Remove() end
        
        local marker = SpawnDemo(ply, "prop_dynamic", endPos + Vector(0, 0, 2), nil, "models/hunter/plates/plate.mdl", 2, Color(255, 200, 50, 200))
        if IsValid(marker) then
            marker:SetMaterial("models/debug/debugwhite")
            marker:SetRenderMode(RENDERMODE_TRANSALPHA)
        end
        
        sound.Play("buttons/blip2.wav", endPos, 80, 120)
    end)
    
    return stagePos + Vector(0, 25, 40)
end

function Manhunt.Tutorial.Demo_Drone(stagePos, ply)
    Manhunt.Tutorial.CleanupPlayer(ply)
    
    -- Spawn a drone-like prop floating above
    local dronePos = stagePos + Vector(0, 0, 200)
    local drone = SpawnDemo(ply, "prop_dynamic", dronePos, Angle(0, 0, 0), "models/hunter/plates/plate.mdl", 1.5, Color(0, 180, 255))
    if IsValid(drone) then
        drone:SetMaterial("models/debug/debugwhite")
    end
    
    -- Spawn a "target" player model on the ground
    local target = SpawnDemo(ply, "prop_dynamic", stagePos, Angle(0, 180, 0), "models/player/kleiner.mdl", 1, Color(255, 60, 20))
    
    sound.Play("buttons/blip2.wav", dronePos, 80, 80)
    
    -- Simulate drone scanning sound
    timer.Simple(1, function()
        sound.Play("ambient/machines/combine_terminal_idle4.wav", dronePos, 70, 120)
    end)
    
    return stagePos + Vector(0, 0, 80)
end

function Manhunt.Tutorial.Demo_Airstrike(stagePos, ply)
    Manhunt.Tutorial.CleanupPlayer(ply)
    
    -- Spawn a target marker on the ground
    local marker = SpawnDemo(ply, "prop_dynamic", stagePos, Angle(0, 0, 0), "models/hunter/plates/plate.mdl", 4, Color(255, 0, 0, 200))
    if IsValid(marker) then
        marker:SetMaterial("models/debug/debugwhite")
        marker:SetRenderMode(RENDERMODE_TRANSALPHA)
    end
    
    -- Play alarm sound (tracked per-player so CleanupPlayer can stop it)
    local alarmEnt = ents.Create("prop_dynamic")
    if IsValid(alarmEnt) then
        alarmEnt:SetPos(stagePos)
        alarmEnt:SetModel("models/hunter/plates/plate.mdl")
        alarmEnt:SetNoDraw(true)
        alarmEnt:Spawn()
        -- Hide from other players
        for _, other in ipairs(player.GetAll()) do
            if other ~= ply then
                alarmEnt:SetPreventTransmit(other, true)
            end
        end
        local data = GetPlayerData(ply)
        table.insert(data.entities, alarmEnt)
        
        local alarmSound = CreateSound(alarmEnt, "ambient/alarms/alarm_citizen_loop1.wav")
        if alarmSound then
            alarmSound:Play()
            table.insert(data.sounds, alarmSound)
        end
    end
    
    -- After 3s, big explosion
    timer.Simple(3, function()
        if IsValid(marker) then marker:Remove() end
        
        -- Main explosion
        local explode = ents.Create("env_explosion")
        if IsValid(explode) then
            explode:SetPos(stagePos)
            explode:Spawn()
            explode:SetKeyValue("iMagnitude", "400")
            explode:Fire("Explode", "", 0)
        end
        
        -- Ring of secondary explosions
        for i = 1, 6 do
            local angle = math.rad((i / 6) * 360)
            local offset = Vector(math.cos(angle) * 400, math.sin(angle) * 400, 0)
            timer.Simple(0.1 * i, function()
                local exp = ents.Create("env_explosion")
                if IsValid(exp) then
                    exp:SetPos(stagePos + offset)
                    exp:Spawn()
                    exp:SetKeyValue("iMagnitude", "200")
                    exp:Fire("Explode", "", 0)
                end
            end)
        end
        
        util.ScreenShake(stagePos, 25, 5, 3, 3000)
        
        -- Dust effect
        local effectData = EffectData()
        effectData:SetOrigin(stagePos)
        effectData:SetScale(3)
        util.Effect("ThumperDust", effectData)
    end)
    
    return stagePos + Vector(0, 0, 30)
end

function Manhunt.Tutorial.Demo_Medkit(stagePos, ply)
    Manhunt.Tutorial.CleanupPlayer(ply)
    
    -- Spawn a medkit model (standard HL2 model)
    local medkit = SpawnDemo(ply, "prop_dynamic", stagePos + Vector(0, 0, 30), Angle(0, 0, 0), "models/items/healthkit.mdl", 2)
    
    -- Green healing particles
    local heal = SpawnDemo(ply, "prop_dynamic", stagePos, nil, "models/hunter/plates/plate.mdl", 2, Color(50, 255, 50, 100))
    if IsValid(heal) then
        heal:SetMaterial("models/debug/debugwhite")
        heal:SetRenderMode(RENDERMODE_TRANSALPHA)
    end
    
    sound.Play("items/medshot4.wav", stagePos, 80, 100)
    
    return stagePos + Vector(0, 0, 40)
end

-- ============================================================
-- TUTORIAL FLOW
-- ============================================================

-- Handle tutorial demo request from client
net.Receive("Manhunt_TutorialDemo", function(len, ply)
    if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end
    if not Manhunt.Tutorial.ActivePlayers[ply:SteamID()] then return end
    local demoName = net.ReadString()
    local stagePos = Manhunt.Tutorial.GetStagePos(ply)
    local lookAt = stagePos
    
    -- Run the requested demo
    if demoName == "vbeacon" then
        lookAt = Manhunt.Tutorial.Demo_VehicleBeacon(stagePos, ply)
    elseif demoName == "carbomb" then
        lookAt = Manhunt.Tutorial.Demo_CarBomb(stagePos, ply)
    elseif demoName == "scanner" then
        lookAt = Manhunt.Tutorial.Demo_Scanner(stagePos, ply)
    elseif demoName == "decoy" then
        lookAt = Manhunt.Tutorial.Demo_Decoy(stagePos, ply)
    elseif demoName == "drone" then
        lookAt = Manhunt.Tutorial.Demo_Drone(stagePos, ply)
    elseif demoName == "airstrike" then
        lookAt = Manhunt.Tutorial.Demo_Airstrike(stagePos, ply)
    elseif demoName == "medkit" then
        lookAt = Manhunt.Tutorial.Demo_Medkit(stagePos, ply)
    elseif demoName == "cleanup" then
        Manhunt.Tutorial.CleanupPlayer(ply)
        return
    end
    
    -- Send lookAt position back to client
    net.Start("Manhunt_TutorialLookAt")
    net.WriteVector(lookAt)
    net.WriteVector(stagePos)
    net.Send(ply)
end)

-- Handle tutorial skip
net.Receive("Manhunt_TutorialSkip", function(len, ply)
    if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end
    Manhunt.Tutorial.CleanupPlayer(ply)
    if IsValid(ply) then
        ply:Freeze(false)
        ply:GodDisable()
        Manhunt.Tutorial.ActivePlayers[ply:SteamID()] = nil
    end
    -- Resume countdown only when ALL players are done
    if table.Count(Manhunt.Tutorial.ActivePlayers) == 0 then
        Manhunt.Tutorial.ResumeCountdown()
    end
end)

-- Handle tutorial start request
net.Receive("Manhunt_TutorialStart", function(len, ply)
    if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end
    if IsValid(ply) then
        ply:Freeze(true)
        ply:GodEnable()
        Manhunt.Tutorial.ActivePlayers[ply:SteamID()] = true
    end
    -- Pause the game countdown (only does it once)
    Manhunt.Tutorial.PauseCountdown()
end)

-- Handle tutorial end
net.Receive("Manhunt_TutorialEnd", function(len, ply)
    if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end
    Manhunt.Tutorial.CleanupPlayer(ply)
    if IsValid(ply) then
        ply:Freeze(false)
        ply:GodDisable()
        Manhunt.Tutorial.ActivePlayers[ply:SteamID()] = nil
    end
    -- Resume countdown only when ALL players are done
    if table.Count(Manhunt.Tutorial.ActivePlayers) == 0 then
        Manhunt.Tutorial.ResumeCountdown()
    end
end)

-- ============================================================
-- COUNTDOWN PAUSE/RESUME
-- ============================================================

function Manhunt.Tutorial.PauseCountdown()
    if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end
    -- Only pause once (check if already paused)
    if Manhunt.Tutorial._countdownPaused then return end
    Manhunt.Tutorial._countdownPaused = true
    
    -- Save remaining countdown time
    local remaining = math.max(0, Manhunt.CountdownEnd - CurTime())
    Manhunt.Tutorial._countdownRemaining = remaining
    
    -- Stop the countdown timer
    timer.Remove("Manhunt_Countdown")
    
    -- Push CountdownEnd far into the future so lobby timer freezes
    Manhunt.CountdownEnd = CurTime() + 99999
    Manhunt.SyncPhase()
end

function Manhunt.Tutorial.ResumeCountdown()
    if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end
    if not Manhunt.Tutorial._countdownPaused then return end
    Manhunt.Tutorial._countdownPaused = false
    
    -- Notify all clients that tutorials are done
    net.Start("Manhunt_TutorialAllDone")
    net.Broadcast()
    
    local remaining = Manhunt.Tutorial._countdownRemaining or (Manhunt.TestMode and 3 or 10)
    Manhunt.Tutorial._countdownRemaining = nil
    
    -- Reset countdown from now
    Manhunt.CountdownEnd = CurTime() + remaining
    Manhunt.SyncPhase()
    
    -- Recreate the countdown timer
    timer.Create("Manhunt_Countdown", remaining, 1, function()
        if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end
        
        Manhunt.Phase = Manhunt.PHASE_ACTIVE
        local gameTimeSec = Manhunt.Config.GameTime * 60
        Manhunt.StartTime = CurTime()
        Manhunt.EndTime = CurTime() + gameTimeSec
        Manhunt.SyncPhase()
        
        if Manhunt.TestMode then
            -- Test mode transition
            local ply = player.GetAll()[1]
            if IsValid(ply) then
                Manhunt.ApplySpawnProtection(ply, 5)
            end
            
            Manhunt.PlayAudioCue("game_start")
            Manhunt.InitTracking()
            Manhunt.StartTracking()
            Manhunt.StartViewpointRecording()
            
            if Manhunt.Pickups and Manhunt.Pickups.Start then
                Manhunt.Pickups.Start()
            end
            
            timer.Create("Manhunt_IntervalCheck", 1, 0, function()
                Manhunt.CheckInterval()
            end)
            
            Manhunt.NextIntervalTime = CurTime() + Manhunt.GetCurrentInterval()
            
            timer.Create("Manhunt_GameEnd", gameTimeSec, 1, function()
                if Manhunt.Phase == Manhunt.PHASE_ACTIVE then
                    Manhunt.EndGame("fugitive")
                end
            end)
        else
            -- Normal mode transition
            local fug = Manhunt.GetFugitive()
            if IsValid(fug) then
                Manhunt.ApplySpawnProtection(fug, 5)
            end
            
            Manhunt.PlayAudioCue("game_start")
            Manhunt.InitTracking()
            Manhunt.StartTracking()
            Manhunt.StartViewpointRecording()
            
            if Manhunt.Pickups and Manhunt.Pickups.Start then
                Manhunt.Pickups.Start()
            end
            
            local firstInterval = Manhunt.Config.Interval * 60
            timer.Create("Manhunt_UnfreezeHunters", firstInterval, 1, function()
                for _, hunter in ipairs(Manhunt.GetHunters()) do
                    if IsValid(hunter) then
                        Manhunt.FreezePlayer(hunter, false)
                        hunter:GodDisable()
                    end
                end
                Manhunt.PlayAudioCue("hunters_released")
                
                if Manhunt.TriggerIntervalScan then
                    Manhunt.TriggerIntervalScan()
                end
            end)
            
            Manhunt.NextIntervalTime = CurTime() + firstInterval
            timer.Create("Manhunt_IntervalCheck", 1, 0, function()
                Manhunt.CheckInterval()
            end)
            
            timer.Create("Manhunt_GameEnd", gameTimeSec, 1, function()
                if Manhunt.Phase == Manhunt.PHASE_ACTIVE then
                    Manhunt.EndGame("fugitive")
                end
            end)
        end
    end)
end

print("[Manhunt] sv_tutorial.lua loaded")
