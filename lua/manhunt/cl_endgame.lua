--[[
    Manhunt - Client End Game Stats Screen
    Shows win/loss, damage dealt, closest distance, km moved
]]

Manhunt.EndGameData = {
    winner = nil,
    fugitiveDistKM = 0,
    closestDistM = 0,
    hunters = {},
    showTime = 0,
    statsReceived = false,
}

-- Receive end game event
hook.Add("Manhunt_GameEnded", "Manhunt_EndGameScreen", function(winner)
    Manhunt.EndGameData.winner = winner
    Manhunt.EndGameData.showTime = CurTime()
    Manhunt.EndGameData.statsReceived = false
end)

-- Receive stats
net.Receive("Manhunt_Stats", function()
    Manhunt.EndGameData.fugitiveDistKM = net.ReadFloat()
    Manhunt.EndGameData.closestDistM = net.ReadFloat()

    local hunterCount = net.ReadUInt(4)
    Manhunt.EndGameData.hunters = {}
    for i = 1, hunterCount do
        table.insert(Manhunt.EndGameData.hunters, {
            name = net.ReadString(),
            damage = net.ReadFloat(),
            distKM = net.ReadFloat(),
        })
    end

    Manhunt.EndGameData.statsReceived = true
end)

-- Smooth number animation
local function AnimateNumber(target, startTime, delay, duration)
    local elapsed = CurTime() - startTime - delay
    if elapsed < 0 then return 0 end
    local progress = math.Clamp(elapsed / duration, 0, 1)
    -- Ease out
    progress = 1 - (1 - progress) ^ 3
    return target * progress
end

-- Draw end game screen
hook.Add("HUDPaint", "Manhunt_EndGameHUD", function()
    if Manhunt.Phase ~= Manhunt.PHASE_ENDGAME then return end
    if not Manhunt.EndGameData.winner then return end

    local sw, sh = ScrW(), ScrH()
    local elapsed = CurTime() - Manhunt.EndGameData.showTime

    -- Phase 1 (0-2s): Winner announcement (big text with dramatic fade-in)
    -- Phase 2 (2-8s): Stats appear one by one
    -- Phase 3 (8s+): Full stats visible, waiting for replay or dismiss

    -- Darken background
    local bgAlpha = math.min(220, elapsed * 200)
    surface.SetDrawColor(0, 0, 0, bgAlpha)
    surface.DrawRect(0, 0, sw, sh)

    -- Cinematic bars
    local barH = sh * 0.06
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, sw, barH)
    surface.DrawRect(0, sh - barH, sw, barH)

    -- Winner announcement
    local winner = Manhunt.EndGameData.winner
    local winnerText, winnerColor, subText

    local myTeam = Manhunt.GetPlayerTeam(LocalPlayer())

    if winner == "fugitive" then
        winnerText = "FUGITIVE SURVIVED"
        winnerColor = Color(50, 150, 255)
        subText = myTeam == Manhunt.TEAM_FUGITIVE and "YOU WON!" or "YOU LOST!"
    else
        winnerText = "FUGITIVE ELIMINATED"
        winnerColor = Color(255, 50, 50)
        subText = myTeam == Manhunt.TEAM_HUNTER and "YOU WON!" or "YOU LOST!"
    end

    -- Animate winner text
    if elapsed < 3 then
        local textAlpha = math.min(255, elapsed * 300)
        local scale = 1 + math.max(0, 1 - elapsed) * 0.5

        draw.SimpleText(winnerText, "Manhunt_HUD_Title", sw / 2, sh * 0.3, Color(winnerColor.r, winnerColor.g, winnerColor.b, textAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local subColor = (myTeam == Manhunt.TEAM_FUGITIVE and winner == "fugitive") or (myTeam == Manhunt.TEAM_HUNTER and winner == "hunter")
        local subClr = subColor and Color(50, 255, 50, textAlpha) or Color(255, 50, 50, textAlpha)
        draw.SimpleText(subText, "Manhunt_HUD_Large", sw / 2, sh * 0.3 + 55, subClr, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        draw.SimpleText(winnerText, "Manhunt_HUD_Title", sw / 2, sh * 0.15, winnerColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        local subColor = (myTeam == Manhunt.TEAM_FUGITIVE and winner == "fugitive") or (myTeam == Manhunt.TEAM_HUNTER and winner == "hunter")
        local subClr = subColor and Color(50, 255, 50) or Color(255, 50, 50)
        draw.SimpleText(subText, "Manhunt_HUD_Large", sw / 2, sh * 0.15 + 55, subClr, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Stats (appear after 2 seconds)
    if elapsed > 2 and Manhunt.EndGameData.statsReceived then
        local startTime = Manhunt.EndGameData.showTime
        local statsY = sh * 0.35
        local statSpacing = 60
        local centerX = sw / 2
        local boxW = sw * 0.5
        local boxX = centerX - boxW / 2

        -- Stats box background
        local boxAlpha = math.min(180, (elapsed - 2) * 200)
        draw.RoundedBox(8, boxX, statsY - 20, boxW, 300, Color(20, 20, 20, boxAlpha))

        -- Title
        draw.SimpleText("GAME STATISTICS", "Manhunt_HUD_Medium", centerX, statsY, Color(255, 255, 255, boxAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        statsY = statsY + 40

        -- Divider
        surface.SetDrawColor(100, 100, 100, boxAlpha)
        surface.DrawRect(boxX + 20, statsY, boxW - 40, 1)
        statsY = statsY + 15

        -- Closest distance
        local closestDist = AnimateNumber(Manhunt.EndGameData.closestDistM, startTime, 2.5, 1)
        draw.SimpleText("Closest Distance:", "Manhunt_HUD_Small", boxX + 30, statsY, Color(180, 180, 180, boxAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(string.format("%.1f m", closestDist), "Manhunt_HUD_Medium", boxX + boxW - 30, statsY, Color(255, 200, 50, boxAlpha), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        statsY = statsY + 35

        -- Fugitive distance
        local fugDist = AnimateNumber(Manhunt.EndGameData.fugitiveDistKM, startTime, 3, 1)
        draw.SimpleText("Fugitive Distance:", "Manhunt_HUD_Small", boxX + 30, statsY, Color(180, 180, 180, boxAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
        draw.SimpleText(string.format("%.2f km", fugDist), "Manhunt_HUD_Medium", boxX + boxW - 30, statsY, Color(50, 150, 255, boxAlpha), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        statsY = statsY + 35

        -- Divider
        surface.SetDrawColor(100, 100, 100, boxAlpha)
        surface.DrawRect(boxX + 20, statsY, boxW - 40, 1)
        statsY = statsY + 15

        -- Hunter stats
        for i, hunter in ipairs(Manhunt.EndGameData.hunters) do
            local delay = 3.5 + (i - 1) * 0.5

            draw.SimpleText(hunter.name, "Manhunt_HUD_Small", boxX + 30, statsY, Color(255, 80, 80, boxAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            statsY = statsY + 22

            local dmg = AnimateNumber(hunter.damage, startTime, delay, 0.8)
            draw.SimpleText("  Damage Dealt:", "Manhunt_HUD_Small", boxX + 40, statsY, Color(150, 150, 150, boxAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(string.format("%.0f HP", dmg), "Manhunt_HUD_Small", boxX + boxW - 30, statsY, Color(255, 100, 100, boxAlpha), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            statsY = statsY + 22

            local dist = AnimateNumber(hunter.distKM, startTime, delay + 0.3, 0.8)
            draw.SimpleText("  Distance Moved:", "Manhunt_HUD_Small", boxX + 40, statsY, Color(150, 150, 150, boxAlpha), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
            draw.SimpleText(string.format("%.2f km", dist), "Manhunt_HUD_Small", boxX + boxW - 30, statsY, Color(255, 150, 50, boxAlpha), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
            statsY = statsY + 30
        end

        -- Dismiss hint
        if elapsed > 6 then
            local pulse = math.abs(math.sin(CurTime() * 2))
            draw.SimpleText("Press [SPACE] to view replay  |  Press [ESC] or [BACKSPACE] to close", "Manhunt_HUD_Small", sw / 2, sh - barH - 20, Color(200, 200, 200, 100 + pulse * 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
        end
    end
end)

-- Handle dismiss / replay trigger
local endgameEscCooldown = 0

hook.Add("Think", "Manhunt_EndGameInput", function()
    if Manhunt.Phase ~= Manhunt.PHASE_ENDGAME then return end
    if not Manhunt.EndGameData.winner then return end

    -- Debounce
    if CurTime() < endgameEscCooldown then return end

    if input.IsKeyDown(KEY_SPACE) then
        endgameEscCooldown = CurTime() + 0.5
        Manhunt.StopAllLoopSounds()
        hook.Run("Manhunt_ShowReplay")
    elseif input.IsKeyDown(KEY_ESCAPE) or input.IsKeyDown(KEY_BACKSPACE) then
        endgameEscCooldown = CurTime() + 0.5
        Manhunt.StopAllLoopSounds()
        Manhunt.EndGameData.winner = nil
        -- Don't override Manhunt.Phase — let the server control game state
    end
end)
