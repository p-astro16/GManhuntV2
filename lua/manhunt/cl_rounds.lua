--[[
    Manhunt - Client Round System
    Displays round info, scores between rounds, and final match results
]]

Manhunt.RoundData = {
    currentRound = 0,
    totalRounds = 1,
    fugitiveSID = "",
    scores = {},      -- {name = score}
    matchEnded = false,
    matchData = nil,
}

-- Receive round info at start of each round
net.Receive("Manhunt_RoundInfo", function()
    Manhunt.RoundData.currentRound = net.ReadUInt(8)
    Manhunt.RoundData.totalRounds = net.ReadUInt(8)
    Manhunt.RoundData.fugitiveSID = net.ReadString()
    Manhunt.RoundData.matchEnded = false

    print("[Manhunt] Round " .. Manhunt.RoundData.currentRound .. " of " .. Manhunt.RoundData.totalRounds)
end)

-- Receive score updates
net.Receive("Manhunt_RoundScores", function()
    local count = net.ReadUInt(8)
    Manhunt.RoundData.scores = {}
    for i = 1, count do
        local name = net.ReadString()
        local score = net.ReadUInt(8)
        Manhunt.RoundData.scores[name] = score
    end
end)

-- Receive final match results
net.Receive("Manhunt_MatchEnd", function()
    local totalRounds = net.ReadUInt(8)
    local scoreCount = net.ReadUInt(8)

    local scores = {}
    for i = 1, scoreCount do
        local name = net.ReadString()
        local sid = net.ReadString()
        local score = net.ReadUInt(8)
        table.insert(scores, { name = name, sid = sid, score = score })
    end

    local historyCount = net.ReadUInt(8)
    local history = {}
    for i = 1, historyCount do
        local round = net.ReadUInt(8)
        local winner = net.ReadString()
        local fugName = net.ReadString()
        table.insert(history, { round = round, winner = winner, fugitiveName = fugName })
    end

    -- Sort scores by highest
    table.sort(scores, function(a, b) return a.score > b.score end)

    Manhunt.RoundData.matchEnded = true
    Manhunt.RoundData.matchData = {
        totalRounds = totalRounds,
        scores = scores,
        history = history,
        showTime = CurTime(),
    }
end)

-- Draw round indicator in HUD (top right during active game)
hook.Add("HUDPaint", "Manhunt_RoundHUD", function()
    if not Manhunt.RoundData or Manhunt.RoundData.totalRounds <= 1 then return end
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE and Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end

    local sw, sh = ScrW(), ScrH()

    -- Round indicator (top right)
    local text = "ROUND " .. Manhunt.RoundData.currentRound .. " / " .. Manhunt.RoundData.totalRounds
    draw.SimpleText(text, "Manhunt_HUD_Medium", sw - 20, 20, Color(255, 255, 255, 200), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

    -- Small score summary
    local y = 48
    for name, score in pairs(Manhunt.RoundData.scores) do
        draw.SimpleText(name .. ": " .. score, "Manhunt_HUD_Small", sw - 20, y, Color(200, 200, 200, 150), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        y = y + 20
    end
end)

-- Draw final match results screen
hook.Add("HUDPaint", "Manhunt_MatchEndHUD", function()
    if not Manhunt.RoundData.matchEnded then return end
    if not Manhunt.RoundData.matchData then return end

    local data = Manhunt.RoundData.matchData
    local elapsed = CurTime() - data.showTime
    local sw, sh = ScrW(), ScrH()

    -- Dark background
    local bgAlpha = math.min(235, elapsed * 300)
    surface.SetDrawColor(0, 0, 0, bgAlpha)
    surface.DrawRect(0, 0, sw, sh)

    -- Cinematic bars
    local barH = sh * 0.06
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, sw, barH)
    surface.DrawRect(0, sh - barH, sw, barH)

    local centerX = sw / 2

    -- Title
    if elapsed > 0.3 then
        local fadeIn = math.min(255, (elapsed - 0.3) * 300)
        draw.SimpleText("MATCH COMPLETE", "Manhunt_HUD_Title", centerX, sh * 0.1, Color(255, 255, 255, fadeIn), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText(data.totalRounds .. " Rounds Played", "Manhunt_HUD_Medium", centerX, sh * 0.1 + 50, Color(180, 180, 180, fadeIn), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Scoreboard
    if elapsed > 1 then
        local fadeIn = math.min(255, (elapsed - 1) * 300)
        local boxW = sw * 0.5
        local boxX = centerX - boxW / 2
        local y = sh * 0.22

        draw.RoundedBox(8, boxX, y - 10, boxW, 50 + #data.scores * 40, Color(20, 20, 25, fadeIn * 0.7))
        draw.SimpleText("FINAL STANDINGS", "Manhunt_HUD_Medium", centerX, y, Color(255, 200, 50, fadeIn), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        y = y + 40

        for i, entry in ipairs(data.scores) do
            local delay = 1.5 + (i - 1) * 0.3
            if elapsed > delay then
                local rowFade = math.min(255, (elapsed - delay) * 400)
                local isFirst = (i == 1)
                local nameColor = isFirst and Color(255, 215, 0, rowFade) or Color(220, 220, 220, rowFade)
                local scoreColor = isFirst and Color(255, 215, 0, rowFade) or Color(180, 180, 180, rowFade)

                local prefix = isFirst and ">> " or "   "
                local suffix = isFirst and " <<" or ""

                draw.SimpleText(prefix .. "#" .. i .. "  " .. entry.name .. suffix, "Manhunt_HUD_Medium", boxX + 30, y, nameColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
                draw.SimpleText(entry.score .. " wins", "Manhunt_HUD_Medium", boxX + boxW - 30, y, scoreColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
                y = y + 40
            end
        end
    end

    -- Round history
    if elapsed > 3 then
        local fadeIn = math.min(255, (elapsed - 3) * 300)
        local y = sh * 0.6
        local boxW = sw * 0.5
        local boxX = centerX - boxW / 2

        draw.RoundedBox(8, boxX, y - 10, boxW, 40 + #data.history * 28, Color(20, 20, 25, fadeIn * 0.7))
        draw.SimpleText("ROUND HISTORY", "Manhunt_HUD_Medium", centerX, y, Color(200, 200, 200, fadeIn), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        y = y + 35

        for _, r in ipairs(data.history) do
            local winColor = r.winner == "fugitive" and Color(50, 150, 255, fadeIn) or Color(255, 80, 80, fadeIn)
            local winText = r.winner == "fugitive" and "Fugitive survived" or "Hunter wins"
            draw.SimpleText("Round " .. r.round .. ": " .. r.fugitiveName .. " (Fugitive) — " .. winText, "Manhunt_HUD_Small", centerX, y, winColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            y = y + 28
        end
    end

    -- Dismiss hint
    if elapsed > 5 then
        local pulse = math.abs(math.sin(CurTime() * 2))
        draw.SimpleText("Press [ESC] or [BACKSPACE] to close", "Manhunt_HUD_Small", centerX, sh - barH - 15, Color(200, 200, 200, 100 + pulse * 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    end
end)

-- Dismiss match results
local matchEndCooldown = 0
hook.Add("Think", "Manhunt_MatchEndDismiss", function()
    if not Manhunt.RoundData.matchEnded then return end
    if CurTime() < matchEndCooldown then return end

    if input.IsKeyDown(KEY_ESCAPE) or input.IsKeyDown(KEY_BACKSPACE) then
        matchEndCooldown = CurTime() + 0.5
        Manhunt.RoundData.matchEnded = false
        Manhunt.RoundData.matchData = nil
    end
end)
