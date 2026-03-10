--[[
    Manhunt - Client Lobby
    Pre-game lobby display (30 second lobby with GTA-style countdown)
]]

Manhunt.Lobby = {
    active = false,
    startTime = 0,
}

-- Trigger lobby when phase changes to countdown
hook.Add("Manhunt_PhaseChanged", "Manhunt_LobbyPhase", function(phase)
    if phase == Manhunt.PHASE_COUNTDOWN then
        Manhunt.Lobby.active = true
        Manhunt.Lobby.startTime = CurTime()
    elseif phase == Manhunt.PHASE_ACTIVE then
        Manhunt.Lobby.active = false
    elseif phase == Manhunt.PHASE_IDLE then
        Manhunt.Lobby.active = false
    end
end)

-- Draw lobby/countdown overlay
hook.Add("HUDPaint", "Manhunt_LobbyHUD", function()
    if not Manhunt.Lobby.active then return end
    if Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then
        Manhunt.Lobby.active = false
        return
    end

    -- Don't draw lobby while tutorial or cinematic is active
    if Manhunt.Tutorial and (Manhunt.Tutorial.PendingThisRound or Manhunt.Tutorial.State.active) then return end
    if Manhunt.CinematicIntro and Manhunt.CinematicIntro.active then return end

    local sw, sh = ScrW(), ScrH()
    local remaining = math.max(0, Manhunt.CountdownEnd - CurTime())

    -- Full screen darkened overlay
    surface.SetDrawColor(0, 0, 0, 200)
    surface.DrawRect(0, 0, sw, sh)

    -- GTA-style "MANHUNT BEGINS IN..." text
    local titleY = sh * 0.25

    -- Animated title
    local titleAlpha = math.min(255, (CurTime() - Manhunt.Lobby.startTime) * 500)
    draw.SimpleText("M A N H U N T", "Manhunt_HUD_Title", sw / 2, titleY, Color(255, 255, 255, titleAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Subtitle
    draw.SimpleText("BEGINS IN", "Manhunt_HUD_Large", sw / 2, titleY + 60, Color(200, 200, 200, titleAlpha * 0.7), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Big countdown number
    local countNum = math.ceil(remaining)

    draw.SimpleText(tostring(countNum), "Manhunt_HUD_Countdown", sw / 2, sh * 0.5, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Player role display
    local team = Manhunt.GetPlayerTeam(LocalPlayer())
    local teamName = string.upper(Manhunt.GetTeamName(team))
    local teamColor = Manhunt.GetTeamColor(team)

    draw.SimpleText("YOUR ROLE", "Manhunt_HUD_Small", sw / 2, sh * 0.65, Color(180, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(teamName, "Manhunt_HUD_Title", sw / 2, sh * 0.65 + 40, teamColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Role description
    local desc = ""
    if Manhunt.TestMode then
        desc = "Solo testing mode. All weapons & items available. Death = respawn."
    elseif team == Manhunt.TEAM_FUGITIVE then
        desc = "Survive until time runs out. Your vehicle is spawning..."
    elseif team == Manhunt.TEAM_HUNTER then
        desc = "You will be frozen for the first interval. Hunt the Fugitive!"
    end
    draw.SimpleText(desc, "Manhunt_HUD_Medium", sw / 2, sh * 0.75, Color(200, 200, 200, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Game settings display
    local settingsY = sh * 0.82
    local intervalStr = Manhunt.Config.Interval % 1 == 0 and tostring(Manhunt.Config.Interval) or string.format("%.1f", Manhunt.Config.Interval)
    draw.SimpleText("Game Time: " .. Manhunt.Config.GameTime .. " min  |  Interval: " .. intervalStr .. " min", "Manhunt_HUD_Small", sw / 2, settingsY, Color(150, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Player list
    local listY = settingsY + 30
    local fugitive = Manhunt.GetFugitive()
    local hunters = Manhunt.GetHunters()

    if IsValid(fugitive) then
        draw.SimpleText("Fugitive: " .. fugitive:Nick(), "Manhunt_HUD_Small", sw / 2, listY, Color(50, 150, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        listY = listY + 20
    end

    local hunterNames = {}
    for _, h in ipairs(hunters) do
        if IsValid(h) then table.insert(hunterNames, h:Nick()) end
    end
    if #hunterNames > 0 then
        draw.SimpleText("Hunters: " .. table.concat(hunterNames, ", "), "Manhunt_HUD_Small", sw / 2, listY, Color(255, 50, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Cinematic bars (top and bottom black bars)
    local barHeight = sh * 0.08
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, sw, barHeight)
    surface.DrawRect(0, sh - barHeight, sw, barHeight)
end)
