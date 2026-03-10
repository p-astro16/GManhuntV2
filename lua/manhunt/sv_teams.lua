--[[
    Manhunt - Server Teams
    Team assignment and management
]]

Manhunt.ServerTeams = Manhunt.ServerTeams or {}

-- Set a player's team
function Manhunt.SetPlayerTeam(ply, team)
    if not IsValid(ply) then return end
    ply:SetNWInt("ManhuntTeam", team)
    Manhunt.TeamAssignments[ply:SteamID()] = team
    Manhunt.SyncTeams()
end

-- Sync all team assignments to clients
function Manhunt.SyncTeams()
    net.Start("Manhunt_TeamAssign")
    local count = table.Count(Manhunt.TeamAssignments)
    net.WriteUInt(count, 8)
    for sid, team in pairs(Manhunt.TeamAssignments) do
        net.WriteString(sid)
        net.WriteUInt(team, 4)
    end
    net.Broadcast()
end

-- Sync config to all clients
function Manhunt.SyncConfig()
    net.Start("Manhunt_SyncConfig")
    net.WriteUInt(Manhunt.Config.GameTime, 8)
    net.WriteUInt(Manhunt.Config.Interval * 2, 8) -- send as half-minutes
    net.WriteUInt(Manhunt.Config.Rounds or 1, 8)
    net.WriteBool(Manhunt.Config.TutorialEnabled ~= false)
    net.WriteBool(Manhunt.Config.ZoneEnabled ~= false)
    net.Broadcast()
end

-- Sync game phase
function Manhunt.SyncPhase()
    net.Start("Manhunt_GamePhase")
    net.WriteUInt(Manhunt.Phase, 4)
    net.WriteFloat(Manhunt.StartTime)
    net.WriteFloat(Manhunt.EndTime)
    net.WriteFloat(Manhunt.CountdownEnd)
    net.Broadcast()
end

-- Handle team set request from client
net.Receive("Manhunt_SetTeam", function(len, ply)
    if not ply:IsListenServerHost() then return end
    if Manhunt.Phase == Manhunt.PHASE_ACTIVE then return end

    local targetSID = net.ReadString()
    local team = net.ReadUInt(4)

    -- If setting as fugitive, remove current fugitive
    if team == Manhunt.TEAM_FUGITIVE then
        for sid, t in pairs(Manhunt.TeamAssignments) do
            if t == Manhunt.TEAM_FUGITIVE then
                Manhunt.TeamAssignments[sid] = Manhunt.TEAM_NONE
                local p = player.GetBySteamID(sid)
                if IsValid(p) then
                    p:SetNWInt("ManhuntTeam", Manhunt.TEAM_NONE)
                end
            end
        end
    end

    Manhunt.TeamAssignments[targetSID] = team
    local targetPly = player.GetBySteamID(targetSID)
    if IsValid(targetPly) then
        targetPly:SetNWInt("ManhuntTeam", team)
    end

    Manhunt.SyncTeams()
end)

-- Handle config update from client
net.Receive("Manhunt_UpdateConfig", function(len, ply)
    if not ply:IsListenServerHost() then return end
    if Manhunt.Phase == Manhunt.PHASE_ACTIVE then return end

    local key = net.ReadString()
    local value = net.ReadUInt(8)

    if key == "GameTime" then
        Manhunt.Config.GameTime = math.Clamp(value, 1, 120)
    elseif key == "Interval" then
        Manhunt.Config.Interval = math.Clamp(value / 2, 0.5, 10) -- value comes as half-minutes
    elseif key == "Rounds" then
        Manhunt.Config.Rounds = math.Clamp(value, 1, 10)
    elseif key == "TutorialEnabled" then
        Manhunt.Config.TutorialEnabled = value == 1
    elseif key == "ZoneEnabled" then
        Manhunt.Config.ZoneEnabled = value == 1
    end

    Manhunt.SyncConfig()
end)

-- Chat command to open menu
hook.Add("PlayerSay", "Manhunt_ChatCommand", function(ply, text)
    print("[Manhunt] [SV] PlayerSay fired: '" .. text .. "' by " .. ply:Nick())
    if string.lower(text) == "!manhunt" then
        print("[Manhunt] [SV] !manhunt detected")
        print("[Manhunt] [SV] IsListenServerHost: " .. tostring(ply:IsListenServerHost()))
        print("[Manhunt] [SV] IsValid: " .. tostring(IsValid(ply)))
        if ply:IsListenServerHost() then
            print("[Manhunt] [SV] Sending Manhunt_OpenMenu to " .. ply:Nick())
            net.Start("Manhunt_OpenMenu")
            net.Send(ply)
            Manhunt.SyncConfig()
            Manhunt.SyncTeams()
            print("[Manhunt] [SV] Menu net message sent + config/teams synced")
        else
            print("[Manhunt] [SV] BLOCKED: Player is NOT listen server host!")
        end
        return ""
    end
end)

-- Console command backup
concommand.Add("manhunt_menu", function(ply)
    print("[Manhunt] [SV] Console command 'manhunt_menu' executed")
    if not IsValid(ply) then
        print("[Manhunt] [SV] BLOCKED: Player not valid")
        return
    end
    print("[Manhunt] [SV] Player: " .. ply:Nick() .. " IsListenServerHost: " .. tostring(ply:IsListenServerHost()))
    if not ply:IsListenServerHost() then
        print("[Manhunt] [SV] BLOCKED: Player is NOT listen server host!")
        return
    end
    print("[Manhunt] [SV] Sending Manhunt_OpenMenu via console command")
    net.Start("Manhunt_OpenMenu")
    net.Send(ply)
    Manhunt.SyncConfig()
    Manhunt.SyncTeams()
    print("[Manhunt] [SV] Menu net message sent + config/teams synced")
end)

print("[Manhunt] sv_teams.lua loaded - chat command and concommand registered")

-- Handle player disconnect during game
hook.Add("PlayerDisconnected", "Manhunt_Disconnect", function(ply)
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end

    -- In test mode, just stop the game
    if Manhunt.TestMode then
        Manhunt.StopGame()
        return
    end

    if Manhunt.GetPlayerTeam(ply) == Manhunt.TEAM_FUGITIVE then
        -- Fugitive left, hunter wins
        Manhunt.EndGame("hunter")
    else
        -- Check if any hunters remain
        local hunters = Manhunt.GetHunters()
        local remaining = 0
        for _, h in ipairs(hunters) do
            if h ~= ply then remaining = remaining + 1 end
        end
        if remaining == 0 then
            Manhunt.EndGame("fugitive")
        end
    end
end)
