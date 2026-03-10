--[[
    Manhunt - Shared Game State
    Game state synchronization between server and client
]]

-- Sync game phase to all clients
if CLIENT then
    print("[Manhunt] [CL] sh_gamestate.lua registering net receivers...")

    net.Receive("Manhunt_GamePhase", function()
        Manhunt.Phase = net.ReadUInt(4)
        Manhunt.StartTime = net.ReadFloat()
        Manhunt.EndTime = net.ReadFloat()
        Manhunt.CountdownEnd = net.ReadFloat()
        print("[Manhunt] [CL] Received GamePhase: " .. tostring(Manhunt.Phase))

        -- Stop any looping sounds when a new game phase starts (e.g. new round)
        if Manhunt.Phase == Manhunt.PHASE_COUNTDOWN or Manhunt.Phase == Manhunt.PHASE_IDLE then
            Manhunt.EndgameActive = false
            if Manhunt.StopAllLoopSounds then
                Manhunt.StopAllLoopSounds()
            end
        end

        hook.Run("Manhunt_PhaseChanged", Manhunt.Phase)
    end)

    net.Receive("Manhunt_SyncConfig", function()
        Manhunt.Config.GameTime = net.ReadUInt(8)
        Manhunt.Config.Interval = net.ReadUInt(8) / 2 -- stored as half-minutes
        Manhunt.Config.Rounds = net.ReadUInt(8)
        Manhunt.Config.TutorialEnabled = net.ReadBool()
        Manhunt.Config.ZoneEnabled = net.ReadBool()
        Manhunt.Gamemode = net.ReadUInt(8)
        print("[Manhunt] [CL] Received SyncConfig: GameTime=" .. Manhunt.Config.GameTime .. " Interval=" .. Manhunt.Config.Interval .. " Rounds=" .. (Manhunt.Config.Rounds or 1) .. " Tutorial=" .. tostring(Manhunt.Config.TutorialEnabled) .. " Zone=" .. tostring(Manhunt.Config.ZoneEnabled) .. " Gamemode=" .. tostring(Manhunt.Gamemode))
    end)

    net.Receive("Manhunt_TeamAssign", function()
        local count = net.ReadUInt(8)
        Manhunt.TeamAssignments = {}
        for i = 1, count do
            local sid = net.ReadString()
            local team = net.ReadUInt(4)
            Manhunt.TeamAssignments[sid] = team
        end
        print("[Manhunt] [CL] Received TeamAssign: " .. count .. " assignments")
    end)

    net.Receive("Manhunt_EndGame", function()
        Manhunt.Winner = net.ReadString()
        Manhunt.Phase = Manhunt.PHASE_ENDGAME
        Manhunt.EndgameActive = false
        hook.Run("Manhunt_GameEnded", Manhunt.Winner)
    end)

    net.Receive("Manhunt_TimerSync", function()
        Manhunt.StartTime = net.ReadFloat()
        Manhunt.EndTime = net.ReadFloat()
    end)

    net.Receive("Manhunt_Freeze", function()
        local frozen = net.ReadBool()
        Manhunt.LocalFrozen = frozen
    end)

    net.Receive("Manhunt_SpawnProtect", function()
        local active = net.ReadBool()
        Manhunt.SpawnProtected = active
    end)

    net.Receive("Manhunt_AudioCue", function()
        local cueType = net.ReadString()
        hook.Run("Manhunt_AudioCue", cueType)
    end)

    net.Receive("Manhunt_TestMode", function()
        Manhunt.TestMode = net.ReadBool()
        print("[Manhunt] [CL] Received TestMode: " .. tostring(Manhunt.TestMode))
    end)

    -- Receive next scan time for HUD countdown
    Manhunt.NextScanTime = 0
    net.Receive("Manhunt_NextScan", function()
        Manhunt.NextScanTime = net.ReadFloat()
    end)

    print("[Manhunt] [CL] sh_gamestate.lua all net receivers registered!")

    -- Freeze movement hook
    hook.Add("CreateMove", "Manhunt_FreezeMovement", function(cmd)
        if Manhunt.LocalFrozen then
            cmd:ClearMovement()
            cmd:RemoveKey(IN_JUMP)
            cmd:RemoveKey(IN_DUCK)
        end
    end)
end

--[[
    Manhunt - End Game Screen
    Displays winner and stats at the end of the game phase
]]  


