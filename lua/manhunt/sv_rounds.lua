--[[
    Manhunt - Server Round System
    Manages multiple rounds with rotating fugitive, tracks scores across rounds
    Configurable number of rounds (1-10) from menu
]]

Manhunt.Rounds = {
    enabled = false,
    totalRounds = 1,
    currentRound = 0,
    scores = {},          -- {steamid = wins}
    roundHistory = {},    -- {round, winner, fugitiveSID, fugitiveName}
    fugitiveOrder = {},   -- Ordered list of SteamIDs for who becomes fugitive
    delayBetweenRounds = 12, -- seconds (time for endgame screen + stats)
}

-- Initialize the round system for a new match
function Manhunt.InitRounds(totalRounds)
    Manhunt.Rounds.enabled = totalRounds > 1
    Manhunt.Rounds.totalRounds = totalRounds
    Manhunt.Rounds.currentRound = 0
    Manhunt.Rounds.scores = {}
    Manhunt.Rounds.roundHistory = {}

    -- Initialize scores for all players
    for _, ply in ipairs(player.GetAll()) do
        Manhunt.Rounds.scores[ply:SteamID()] = 0
    end

    -- Build fugitive rotation order
    Manhunt.BuildFugitiveOrder()
end

-- Build the order of who becomes fugitive each round
function Manhunt.BuildFugitiveOrder()
    local players = player.GetAll()
    Manhunt.Rounds.fugitiveOrder = {}

    -- Shuffle player order  
    local shuffled = {}
    for _, ply in ipairs(players) do
        table.insert(shuffled, ply:SteamID())
    end

    -- Fisher-Yates shuffle
    for i = #shuffled, 2, -1 do
        local j = math.random(1, i)
        shuffled[i], shuffled[j] = shuffled[j], shuffled[i]
    end

    -- Fill fugitive order (cycle through players if more rounds than players)
    for i = 1, Manhunt.Rounds.totalRounds do
        local idx = ((i - 1) % #shuffled) + 1
        table.insert(Manhunt.Rounds.fugitiveOrder, shuffled[idx])
    end

    print("[Manhunt] Fugitive order: " .. table.concat(Manhunt.Rounds.fugitiveOrder, ", "))
end

-- Start the next round
function Manhunt.StartNextRound()
    Manhunt.Rounds.currentRound = Manhunt.Rounds.currentRound + 1
    local round = Manhunt.Rounds.currentRound

    print("[Manhunt] Starting Round " .. round .. " of " .. Manhunt.Rounds.totalRounds)

    -- Get the fugitive for this round
    local fugitiveSID = Manhunt.Rounds.fugitiveOrder[round]
    if not fugitiveSID then
        print("[Manhunt] No fugitive assigned for round " .. round .. "! Ending match.")
        Manhunt.EndMatch()
        return
    end
    
    -- Check if the assigned fugitive is still connected
    local fugitivePlayer = player.GetBySteamID(fugitiveSID)
    if not IsValid(fugitivePlayer) then
        print("[Manhunt] Fugitive " .. fugitiveSID .. " disconnected! Skipping to next round.")
        -- Skip this round and try the next one
        if round < Manhunt.Rounds.totalRounds then
            Manhunt.StartNextRound()
        else
            Manhunt.EndMatch()
        end
        return
    end

    -- Assign teams: fugitive + everyone else as hunter
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID() == fugitiveSID then
            Manhunt.SetPlayerTeam(ply, Manhunt.TEAM_FUGITIVE)
        else
            Manhunt.SetPlayerTeam(ply, Manhunt.TEAM_HUNTER)
        end
    end

    Manhunt.SyncTeams()

    -- Sync round info to clients
    net.Start("Manhunt_RoundInfo")
    net.WriteUInt(round, 8)
    net.WriteUInt(Manhunt.Rounds.totalRounds, 8)
    net.WriteString(fugitiveSID)
    net.Broadcast()

    -- Respawn everyone
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            ply:Spawn()
        elseif IsValid(ply) then
            ply:Spawn()
        end
    end

    -- Start the game (normal flow handles the rest)
    timer.Simple(1, function()
        Manhunt.StartGame()
    end)
end

-- Called when a round ends (hook into EndGame)
function Manhunt.OnRoundEnd(winner)
    if not Manhunt.Rounds.enabled then return end

    local round = Manhunt.Rounds.currentRound
    local fugitiveSID = Manhunt.Rounds.fugitiveOrder[round]

    -- Record round result
    local fugitiveName = "Unknown"
    for _, ply in ipairs(player.GetAll()) do
        if ply:SteamID() == fugitiveSID then
            fugitiveName = ply:Nick()
            break
        end
    end

    table.insert(Manhunt.Rounds.roundHistory, {
        round = round,
        winner = winner,
        fugitiveSID = fugitiveSID,
        fugitiveName = fugitiveName,
    })

    -- Award score
    if winner == "fugitive" then
        -- Fugitive gets a point
        Manhunt.Rounds.scores[fugitiveSID] = (Manhunt.Rounds.scores[fugitiveSID] or 0) + 1
    else
        -- All hunters get a point
        for _, ply in ipairs(player.GetAll()) do
            local sid = ply:SteamID()
            if sid ~= fugitiveSID then
                Manhunt.Rounds.scores[sid] = (Manhunt.Rounds.scores[sid] or 0) + 1
            end
        end
    end

    -- Sync scores to clients
    Manhunt.SyncRoundScores()

    -- Check if match is over
    if round >= Manhunt.Rounds.totalRounds then
        -- All rounds done — show final results after delay
        timer.Simple(Manhunt.Rounds.delayBetweenRounds, function()
            Manhunt.EndMatch()
        end)
    else
        -- More rounds to go — start next round after delay
        timer.Simple(Manhunt.Rounds.delayBetweenRounds, function()
            Manhunt.StartNextRound()
        end)
    end
end

-- End the entire match (all rounds complete)
function Manhunt.EndMatch()
    print("[Manhunt] Match complete! All " .. Manhunt.Rounds.totalRounds .. " rounds finished.")

    -- Determine overall winner (most points)
    local bestSID = nil
    local bestScore = -1
    for sid, score in pairs(Manhunt.Rounds.scores) do
        if score > bestScore then
            bestScore = score
            bestSID = sid
        end
    end

    -- Send final match results to clients
    net.Start("Manhunt_MatchEnd")
    net.WriteUInt(Manhunt.Rounds.totalRounds, 8)

    -- Send all scores
    local scoreCount = table.Count(Manhunt.Rounds.scores)
    net.WriteUInt(scoreCount, 8)
    for sid, score in pairs(Manhunt.Rounds.scores) do
        local plyName = sid
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID() == sid then
                plyName = ply:Nick()
                break
            end
        end
        net.WriteString(plyName)
        net.WriteString(sid)
        net.WriteUInt(score, 8)
    end

    -- Send round history
    net.WriteUInt(#Manhunt.Rounds.roundHistory, 8)
    for _, r in ipairs(Manhunt.Rounds.roundHistory) do
        net.WriteUInt(r.round, 8)
        net.WriteString(r.winner)
        net.WriteString(r.fugitiveName)
    end

    net.Broadcast()

    -- Reset round system
    Manhunt.Rounds.enabled = false
    Manhunt.Rounds.currentRound = 0

    -- Reset game to idle
    timer.Simple(1, function()
        Manhunt.Phase = Manhunt.PHASE_IDLE
        Manhunt.SyncPhase()
    end)
end

-- Sync round scores to all clients
function Manhunt.SyncRoundScores()
    net.Start("Manhunt_RoundScores")
    local count = table.Count(Manhunt.Rounds.scores)
    net.WriteUInt(count, 8)
    for sid, score in pairs(Manhunt.Rounds.scores) do
        local plyName = sid
        for _, ply in ipairs(player.GetAll()) do
            if ply:SteamID() == sid then
                plyName = ply:Nick()
                break
            end
        end
        net.WriteString(plyName)
        net.WriteUInt(score, 8)
    end
    net.Broadcast()
end
