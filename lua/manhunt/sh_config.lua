--[[
    Manhunt - Shared Config
    Network strings, team enums, default configuration
]]

-- Team enums
Manhunt.TEAM_NONE = 0
Manhunt.TEAM_FUGITIVE = 1
Manhunt.TEAM_HUNTER = 2

-- Phase enums
Manhunt.PHASE_IDLE = 0
Manhunt.PHASE_LOBBY = 1
Manhunt.PHASE_COUNTDOWN = 2
Manhunt.PHASE_ACTIVE = 3
Manhunt.PHASE_ENDGAME = 4

-- Default config
Manhunt.DefaultConfig = {
    GameTime = 30,          -- minutes (0-120)
    Interval = 3,           -- minutes (1-10)
    Rounds = 1,             -- number of rounds (1-10)
    TutorialEnabled = true, -- show tutorial at game start
    ZoneEnabled = true,     -- shrinking zone during endgame
}

-- Shared state (synced via net messages)
Manhunt.Config = table.Copy(Manhunt.DefaultConfig)
Manhunt.Phase = Manhunt.PHASE_IDLE
Manhunt.StartTime = 0
Manhunt.EndTime = 0
Manhunt.CountdownEnd = 0
Manhunt.Winner = nil
Manhunt.TestMode = false -- Solo test mode
Manhunt.EndgameActive = false -- True when 80% of game time has passed

-- Player team assignments {SteamID = team}
Manhunt.TeamAssignments = {}

-- Register network strings
if SERVER then
    print("[Manhunt] [SV] Registering network strings...")
    util.AddNetworkString("Manhunt_SyncConfig")
    util.AddNetworkString("Manhunt_UpdateConfig")
    util.AddNetworkString("Manhunt_RequestStart")
    util.AddNetworkString("Manhunt_RequestStop")
    util.AddNetworkString("Manhunt_GamePhase")
    util.AddNetworkString("Manhunt_TeamAssign")
    util.AddNetworkString("Manhunt_SetTeam")
    util.AddNetworkString("Manhunt_CameraView")
    util.AddNetworkString("Manhunt_PingPos")
    util.AddNetworkString("Manhunt_ScanRequest")
    util.AddNetworkString("Manhunt_DecoyPlace")
    util.AddNetworkString("Manhunt_DecoySync")
    util.AddNetworkString("Manhunt_CarBombPlace")
    util.AddNetworkString("Manhunt_CarBombDetonate")
    util.AddNetworkString("Manhunt_CarBombSync")
    util.AddNetworkString("Manhunt_EndGame")
    util.AddNetworkString("Manhunt_Stats")
    util.AddNetworkString("Manhunt_ReplayData")
    util.AddNetworkString("Manhunt_Freeze")
    util.AddNetworkString("Manhunt_OpenMenu")
    util.AddNetworkString("Manhunt_TimerSync")
    util.AddNetworkString("Manhunt_SpawnProtect")
    util.AddNetworkString("Manhunt_AudioCue")
    util.AddNetworkString("Manhunt_VehicleInfo")
    util.AddNetworkString("Manhunt_LobbySync")
    util.AddNetworkString("Manhunt_TestMode")
    util.AddNetworkString("Manhunt_NextScan")
    util.AddNetworkString("Manhunt_KillCam")
    util.AddNetworkString("Manhunt_RoundInfo")
    util.AddNetworkString("Manhunt_RoundScores")
    util.AddNetworkString("Manhunt_MatchEnd")
    util.AddNetworkString("Manhunt_VehicleBeacon")
    util.AddNetworkString("Manhunt_AirstrikeMarker")
    util.AddNetworkString("Manhunt_EndgameTrigger")
    util.AddNetworkString("Manhunt_VehicleMarker")
    util.AddNetworkString("Manhunt_VehicleCountdown")
    util.AddNetworkString("Manhunt_HunterKillPiP")
    util.AddNetworkString("Manhunt_DroneActivate")
    util.AddNetworkString("Manhunt_DroneDeactivate")
    util.AddNetworkString("Manhunt_TutorialStart")
    util.AddNetworkString("Manhunt_TutorialEnd")
    util.AddNetworkString("Manhunt_TutorialSkip")
    util.AddNetworkString("Manhunt_TutorialDemo")
    util.AddNetworkString("Manhunt_TutorialLookAt")
    util.AddNetworkString("Manhunt_ZoneSync")
    util.AddNetworkString("Manhunt_ZoneAlert")
    util.AddNetworkString("Manhunt_ZoneAnnounce")
    util.AddNetworkString("Manhunt_WeaponSpawn")
    util.AddNetworkString("Manhunt_AmmoSpawn")
    util.AddNetworkString("Manhunt_PickupCollected")
    print("[Manhunt] [SV] All network strings registered!")
end

print("[Manhunt] sh_config.lua executed (" .. (SERVER and "SERVER" or "CLIENT") .. ")")

-- Helper: Get a player's Manhunt team
function Manhunt.GetPlayerTeam(ply)
    if not IsValid(ply) then return Manhunt.TEAM_NONE end
    -- In test mode, player counts as both teams
    if Manhunt.TestMode then return Manhunt.TEAM_FUGITIVE end
    return ply:GetNWInt("ManhuntTeam", Manhunt.TEAM_NONE)
end

-- Helper: Is test mode active?
function Manhunt.IsTestMode()
    return Manhunt.TestMode == true
end

-- Helper: Is the game active?
function Manhunt.IsActive()
    return Manhunt.Phase == Manhunt.PHASE_ACTIVE
end

-- Helper: Is in countdown?
function Manhunt.IsCountdown()
    return Manhunt.Phase == Manhunt.PHASE_COUNTDOWN
end

-- Helper: Get fugitive player
function Manhunt.GetFugitive()
    -- In test mode, return the solo player
    if Manhunt.TestMode then
        return player.GetAll()[1]
    end
    for _, ply in ipairs(player.GetAll()) do
        if Manhunt.GetPlayerTeam(ply) == Manhunt.TEAM_FUGITIVE then
            return ply
        end
    end
    return nil
end

-- Helper: Get all hunters
function Manhunt.GetHunters()
    -- In test mode, return the solo player as a "hunter" too
    if Manhunt.TestMode then
        return { player.GetAll()[1] }
    end
    local hunters = {}
    for _, ply in ipairs(player.GetAll()) do
        if Manhunt.GetPlayerTeam(ply) == Manhunt.TEAM_HUNTER then
            table.insert(hunters, ply)
        end
    end
    return hunters
end

-- Helper: Get remaining time in seconds
function Manhunt.GetRemainingTime()
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return 0 end
    return math.max(0, Manhunt.EndTime - CurTime())
end

-- Helper: Get total game time in seconds
function Manhunt.GetTotalGameTime()
    return Manhunt.Config.GameTime * 60
end

-- Helper: Get current interval in seconds (halved during endgame phase at 80%)
function Manhunt.GetCurrentInterval()
    local baseInterval = Manhunt.Config.Interval * 60

    if Manhunt.EndgameActive then
        return baseInterval / 2
    end

    return baseInterval
end

-- Helper: Are we in the endgame phase? (last 20% of game time)
function Manhunt.IsEndgamePhase()
    return Manhunt.EndgameActive == true
end

-- Helper: Are we in the last 10%?
function Manhunt.IsLastTenPercent()
    local remaining = Manhunt.GetRemainingTime()
    local total = Manhunt.GetTotalGameTime()
    return total > 0 and remaining <= total * 0.1
end

-- Team name helper
function Manhunt.GetTeamName(team)
    if Manhunt.TestMode then return "Test Mode" end
    if team == Manhunt.TEAM_FUGITIVE then return "Fugitive"
    elseif team == Manhunt.TEAM_HUNTER then return "Hunter"
    else return "Unassigned" end
end

-- Team color helper
function Manhunt.GetTeamColor(team)
    if team == Manhunt.TEAM_FUGITIVE then return Color(50, 150, 255)
    elseif team == Manhunt.TEAM_HUNTER then return Color(255, 50, 50)
    else return Color(180, 180, 180) end
end
