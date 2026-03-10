--[[
    Manhunt - Client Tutorial System
    Interactive in-game tutorial with demo scenes
    Camera orbits demo entities while text explains each item/mechanic
    Press SPACE to advance, BACKSPACE to skip
    Triggered via manhunt_tutorial or auto on first game
    In test mode: shows a team picker (Fugitive / Hunter) first
]]

Manhunt.Tutorial = Manhunt.Tutorial or {}

Manhunt.Tutorial.State = {
    active = false,
    stepIndex = 0,
    stepStartTime = 0,
    stagePos = Vector(0, 0, 0),
    lookAt = Vector(0, 0, 0),
    camAngle = 0,          -- orbit angle
    fadeAlpha = 0,          -- transition fade
    transitioning = false,
    skipping = false,
    teamFilter = "all",    -- "all", "fugitive", or "hunter"
    showPicker = false,     -- team picker popup active
    filteredSteps = {},     -- steps after filtering
}

-- Flag: tutorial will show this round (suppresses cinematic/lobby until tutorial done)
Manhunt.Tutorial.PendingThisRound = false
-- Flag: tutorial already completed/skipped this round (prevents re-trigger)
Manhunt.Tutorial.CompletedThisRound = false
-- Flag: waiting for other players to finish their tutorial
Manhunt.Tutorial.WaitingForOthers = false

-- Check if tutorial should show for the current round
function Manhunt.Tutorial.ShouldShowThisRound()
    -- Disabled in menu settings
    if Manhunt.Config.TutorialEnabled == false then return false end
    -- Already done this round
    if Manhunt.Tutorial.CompletedThisRound then return false end
    -- In multi-round games, tutorial only on round 1
    local rd = Manhunt.RoundData
    if rd and rd.currentRound > 1 then return false end
    return true
end

-- ============================================================
-- TUTORIAL STEPS DEFINITION
-- ============================================================
-- team: "both" = shown in all tutorials, "fugitive" or "hunter" = team-specific
-- ============================================================

local ALL_STEPS = {
    {
        title = "WELCOME TO MANHUNT",
        lines = {
            "A deadly game of cat and mouse.",
            "One fugitive must survive. The hunters must eliminate them.",
            "Press [SPACE] to continue or [ESC] to skip the tutorial.",
        },
        duration = 8,
        demo = nil,
        camType = "overview",
        team = "both",
    },
    {
        title = "YOUR GOAL - FUGITIVE",
        lines = {
            "As the FUGITIVE, you must SURVIVE until the timer runs out.",
            "Use vehicles, weapons, and the city to stay hidden.",
            "You have a scanner, car bomb, decoy, vehicle beacon, and medkit.",
        },
        duration = 8,
        demo = nil,
        camType = "player",
        teamColor = Color(255, 80, 80),
        team = "fugitive",
    },
    {
        title = "YOUR GOAL - HUNTER",
        lines = {
            "As a HUNTER, work together to FIND and ELIMINATE the fugitive.",
            "You have a scanner, recon drone, airstrike, and vehicle beacon.",
            "Scanners periodically reveal the fugitive's approximate location.",
        },
        duration = 8,
        demo = nil,
        camType = "player",
        teamColor = Color(80, 150, 255),
        team = "hunter",
    },
    {
        title = "VEHICLE BEACON",
        lines = {
            "Throw the beacon to SPAWN A VEHICLE at the landing spot.",
            "Use vehicles to travel fast across the map.",
            "Both teams have this tool - essential for mobility!",
        },
        duration = 9,
        demo = "vbeacon",
        camType = "demo",
        icon = "veh",
        team = "both",
    },
    {
        title = "CAR BOMB",
        lines = {
            "Enter a vehicle and LEFT CLICK to arm the bomb.",
            "When a hunter approaches the vehicle, it EXPLODES!",
            "Set a trap and lure hunters in - one use per game.",
        },
        duration = 9,
        demo = "carbomb",
        camType = "demo",
        icon = "bomb",
        team = "fugitive",
    },
    {
        title = "SCANNER",
        lines = {
            "Use the scanner to reveal the other team's location.",
            "Shows their approximate position for a few seconds on the radar.",
            "Limited charges - use them wisely!",
        },
        duration = 8,
        demo = "scanner",
        camType = "demo",
        icon = "scan",
        team = "both",
    },
    {
        title = "DECOY GRENADE",
        lines = {
            "Throw to place a FAKE BLIP on the hunters' scanner.",
            "The decoy stays active for 30 seconds across multiple scans.",
            "Confuse the hunters with false information!",
        },
        duration = 8,
        demo = "decoy",
        camType = "demo",
        icon = "decoy",
        team = "fugitive",
    },
    {
        title = "RECON DRONE",
        lines = {
            "Deploy the drone for a BIRD'S EYE VIEW of the area.",
            "WASD to fly around, press [R] for THERMAL VISION.",
            "15 second duration - use it to scout large areas!",
        },
        duration = 9,
        demo = "drone",
        camType = "demo",
        icon = "drone",
        team = "hunter",
    },
    {
        title = "AIRSTRIKE",
        lines = {
            "Available after 80% of the game timer has elapsed.",
            "Click a location to call in a MASSIVE airstrike.",
            "10 second countdown gives the fugitive time to run!",
        },
        duration = 10,
        demo = "airstrike",
        camType = "demo",
        icon = "strike",
        team = "hunter",
    },
    {
        title = "MEDKIT",
        lines = {
            "Heals you when you're injured.",
            "Essential for surviving encounters.",
            "Don't forget to heal after taking damage!",
        },
        duration = 7,
        demo = "medkit",
        camType = "demo",
        icon = "med",
        team = "both",
    },
    {
        title = "THE HUNT BEGINS",
        lines = {
            "You now know all the tools at your disposal.",
            "Pay attention to your surroundings.",
            "Good luck. You'll need it.",
        },
        duration = 5,
        demo = nil,
        camType = "overview",
        team = "both",
    },
}

-- Filter steps based on selected team
local function BuildFilteredSteps(teamFilter)
    local result = {}
    for _, step in ipairs(ALL_STEPS) do
        if step.team == "both" or step.team == teamFilter or teamFilter == "all" then
            table.insert(result, step)
        end
    end
    return result
end

-- ============================================================
-- TEAM PICKER POPUP (for test mode)
-- ============================================================

function Manhunt.Tutorial.ShowTeamPicker()
    local state = Manhunt.Tutorial.State
    state.showPicker = true
    
    -- Register with server immediately so we're tracked
    net.Start("Manhunt_TutorialStart")
    net.SendToServer()
    
    -- Remove existing frame if any
    if IsValid(Manhunt.Tutorial.PickerFrame) then
        Manhunt.Tutorial.PickerFrame:Remove()
    end
    
    local sw, sh = ScrW(), ScrH()
    
    local frame = vgui.Create("DFrame")
    frame:SetSize(460, 340)
    frame:Center()
    frame:SetTitle("")
    frame:SetDraggable(false)
    frame:ShowCloseButton(false)
    frame:MakePopup()
    frame.Paint = function(self, w, h)
        -- Dark background
        draw.RoundedBox(12, 0, 0, w, h, Color(15, 15, 20, 245))
        -- Border
        surface.SetDrawColor(60, 80, 120, 200)
        surface.DrawOutlinedRect(0, 0, w, h, 2)
        -- Inner glow line
        surface.SetDrawColor(40, 60, 100, 80)
        surface.DrawOutlinedRect(4, 4, w - 8, h - 8, 1)
        
        -- Title
        draw.SimpleText("MANHUNT TUTORIAL", "Manhunt_HUD_Large", w / 2, 30, Color(255, 255, 255, 240), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Choose which tutorial to view:", "Manhunt_HUD_Small", w / 2, 62, Color(180, 180, 180, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    
    Manhunt.Tutorial.PickerFrame = frame
    
    -- Fugitive button
    local btnFugitive = vgui.Create("DButton", frame)
    btnFugitive:SetSize(400, 65)
    btnFugitive:SetPos(30, 90)
    btnFugitive:SetText("")
    btnFugitive.Paint = function(self, w, h)
        local hovered = self:IsHovered()
        local bgColor = hovered and Color(180, 50, 50, 200) or Color(120, 30, 30, 150)
        draw.RoundedBox(8, 0, 0, w, h, bgColor)
        if hovered then
            surface.SetDrawColor(255, 80, 80, 100)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
        end
        draw.SimpleText("FUGITIVE TUTORIAL", "Manhunt_HUD_Medium", w / 2, 18, Color(255, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Scanner, Car Bomb, Decoy, Vehicle Beacon, Medkit", "Manhunt_HUD_Small", w / 2, 44, Color(200, 200, 200, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnFugitive.DoClick = function()
        surface.PlaySound("buttons/button9.wav")
        frame:Remove()
        state.showPicker = false
        Manhunt.Tutorial.StartWithTeam("fugitive")
    end
    
    -- Hunter button
    local btnHunter = vgui.Create("DButton", frame)
    btnHunter:SetSize(400, 65)
    btnHunter:SetPos(30, 165)
    btnHunter:SetText("")
    btnHunter.Paint = function(self, w, h)
        local hovered = self:IsHovered()
        local bgColor = hovered and Color(40, 80, 200, 200) or Color(25, 50, 130, 150)
        draw.RoundedBox(8, 0, 0, w, h, bgColor)
        if hovered then
            surface.SetDrawColor(80, 130, 255, 100)
            surface.DrawOutlinedRect(0, 0, w, h, 2)
        end
        draw.SimpleText("HUNTER TUTORIAL", "Manhunt_HUD_Medium", w / 2, 18, Color(80, 150, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("Scanner, Recon Drone, Airstrike, Vehicle Beacon, Medkit", "Manhunt_HUD_Small", w / 2, 44, Color(200, 200, 200, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnHunter.DoClick = function()
        surface.PlaySound("buttons/button9.wav")
        frame:Remove()
        state.showPicker = false
        Manhunt.Tutorial.StartWithTeam("hunter")
    end
    
    -- Skip button
    local btnSkip = vgui.Create("DButton", frame)
    btnSkip:SetSize(400, 40)
    btnSkip:SetPos(30, 245)
    btnSkip:SetText("")
    btnSkip.Paint = function(self, w, h)
        local hovered = self:IsHovered()
        local bgColor = hovered and Color(60, 60, 60, 180) or Color(40, 40, 40, 120)
        draw.RoundedBox(6, 0, 0, w, h, bgColor)
        draw.SimpleText("SKIP TUTORIAL", "Manhunt_HUD_Small", w / 2, h / 2, Color(150, 150, 150, hovered and 255 or 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    btnSkip.DoClick = function()
        surface.PlaySound("buttons/button15.wav")
        frame:Remove()
        state.showPicker = false
        Manhunt.Tutorial.PendingThisRound = false
        Manhunt.Tutorial.CompletedThisRound = true
        -- Tell server we're skipping
        net.Start("Manhunt_TutorialSkip")
        net.SendToServer()
        -- Wait for all players to finish
        Manhunt.Tutorial.WaitingForOthers = true
    end
end

-- ============================================================
-- TUTORIAL CONTROL
-- ============================================================

-- Start with a specific team filter
function Manhunt.Tutorial.StartWithTeam(teamFilter)
    local state = Manhunt.Tutorial.State
    state.active = true
    state.stepIndex = 0
    state.skipping = false
    state.fadeAlpha = 255
    state.transitioning = false
    state.teamFilter = teamFilter or "all"
    state.filteredSteps = BuildFilteredSteps(state.teamFilter)
    
    -- Tell server to freeze us
    net.Start("Manhunt_TutorialStart")
    net.SendToServer()
    
    -- Start first step
    Manhunt.Tutorial.NextStep()
    
    surface.PlaySound("ambient/atmosphere/city_skypass1.wav")
end

-- Legacy start (shows all steps)
function Manhunt.Tutorial.Start()
    if Manhunt.TestMode then
        -- In test mode, show the team picker
        Manhunt.Tutorial.ShowTeamPicker()
    else
        -- In a real game, auto-detect team
        local myTeam = Manhunt.GetPlayerTeam(LocalPlayer())
        if myTeam == Manhunt.TEAM_FUGITIVE then
            Manhunt.Tutorial.StartWithTeam("fugitive")
        elseif myTeam == Manhunt.TEAM_HUNTER then
            Manhunt.Tutorial.StartWithTeam("hunter")
        else
            Manhunt.Tutorial.ShowTeamPicker()
        end
    end
end

function Manhunt.Tutorial.Stop()
    local state = Manhunt.Tutorial.State
    state.active = false
    state.stepIndex = 0
    state.filteredSteps = {}
    Manhunt.Tutorial.PendingThisRound = false
    Manhunt.Tutorial.CompletedThisRound = true
    
    -- Tell server to unfreeze and cleanup
    net.Start("Manhunt_TutorialEnd")
    net.SendToServer()
    
    -- Wait for all players to finish before starting cinematic
    Manhunt.Tutorial.WaitingForOthers = true
end

function Manhunt.Tutorial.Skip()
    local state = Manhunt.Tutorial.State
    if not state.active then return end
    state.skipping = true
    
    -- Quick fade out then stop (Stop sends TutorialEnd to server)
    timer.Simple(0.5, function()
        Manhunt.Tutorial.Stop()
    end)
end

function Manhunt.Tutorial.NextStep()
    local state = Manhunt.Tutorial.State
    state.stepIndex = state.stepIndex + 1
    
    local steps = state.filteredSteps
    if not steps or #steps == 0 then
        Manhunt.Tutorial.Stop()
        return
    end
    
    if state.stepIndex > #steps then
        Manhunt.Tutorial.Stop()
        return
    end
    
    local step = steps[state.stepIndex]
    state.stepStartTime = CurTime()
    state.transitioning = false
    state.fadeAlpha = 255  -- Start faded, then fade in
    
    -- Request demo spawn from server
    if step.demo then
        net.Start("Manhunt_TutorialDemo")
        net.WriteString(step.demo)
        net.SendToServer()
    else
        -- Cleanup previous demo
        net.Start("Manhunt_TutorialDemo")
        net.WriteString("cleanup")
        net.SendToServer()
    end
end

function Manhunt.Tutorial.GetCurrentStep()
    local state = Manhunt.Tutorial.State
    if not state.filteredSteps or state.stepIndex < 1 then return nil end
    return state.filteredSteps[state.stepIndex]
end

-- Receive lookAt position from server after demo spawn
net.Receive("Manhunt_TutorialLookAt", function()
    local lookAt = net.ReadVector()
    local stagePos = net.ReadVector()
    Manhunt.Tutorial.State.lookAt = lookAt
    Manhunt.Tutorial.State.stagePos = stagePos
end)

-- ============================================================
-- CAMERA
-- ============================================================

hook.Add("CalcView", "Manhunt_TutorialView", function(ply, pos, angles, fov)
    if not Manhunt.Tutorial.State.active then return end
    
    local state = Manhunt.Tutorial.State
    local step = Manhunt.Tutorial.GetCurrentStep()
    if not step then return end
    
    local elapsed = CurTime() - state.stepStartTime
    state.camAngle = state.camAngle + FrameTime() * 15 -- slow orbit
    
    local camPos, camAng
    
    if step.camType == "overview" then
        -- High above, slowly orbiting the player
        local center = ply:GetPos()
        local radius = 800
        local height = 600
        local orbitRad = math.rad(state.camAngle)
        
        camPos = center + Vector(math.cos(orbitRad) * radius, math.sin(orbitRad) * radius, height)
        camAng = (center + Vector(0, 0, 50) - camPos):Angle()
        
    elseif step.camType == "player" then
        -- Orbit around the player at medium distance
        local center = ply:GetPos() + Vector(0, 0, 40)
        local radius = 200
        local height = 80
        local orbitRad = math.rad(state.camAngle)
        
        camPos = center + Vector(math.cos(orbitRad) * radius, math.sin(orbitRad) * radius, height)
        camAng = (center - camPos):Angle()
        
    elseif step.camType == "demo" then
        -- Orbit around the demo stage
        local center = state.lookAt
        if center == Vector(0, 0, 0) then
            center = ply:GetPos() + ply:GetForward() * 400 + Vector(0, 0, 50)
        end
        
        local radius = 300
        local height = 120
        local orbitRad = math.rad(state.camAngle)
        
        camPos = center + Vector(math.cos(orbitRad) * radius, math.sin(orbitRad) * radius, height)
        camAng = (center - camPos):Angle()
    end
    
    if not camPos then return end
    
    return {
        origin = camPos,
        angles = camAng,
        fov = 80,
        drawviewer = true,
    }
end)

-- ============================================================
-- INPUT BLOCKING
-- ============================================================

hook.Add("CreateMove", "Manhunt_TutorialBlock", function(cmd)
    if not Manhunt.Tutorial.State.active then return end
    cmd:ClearMovement()
    cmd:ClearButtons()
end)

-- Key handling: SPACE to advance, BACKSPACE to skip
hook.Add("PlayerButtonDown", "Manhunt_TutorialInput", function(ply, button)
    if not Manhunt.Tutorial.State.active then return end
    
    if button == KEY_SPACE or button == KEY_ENTER or button == MOUSE_LEFT then
        Manhunt.Tutorial.NextStep()
        surface.PlaySound("buttons/button9.wav")
    elseif button == KEY_BACKSPACE then
        Manhunt.Tutorial.Skip()
    end
end)

-- ============================================================
-- HUD RENDERING
-- ============================================================

hook.Add("HUDPaint", "Manhunt_TutorialHUD", function()
    if not Manhunt.Tutorial.State.active then return end
    
    local state = Manhunt.Tutorial.State
    local step = Manhunt.Tutorial.GetCurrentStep()
    if not step then return end
    
    local sw, sh = ScrW(), ScrH()
    local elapsed = CurTime() - state.stepStartTime
    
    -- Fade in/out
    local fadeIn = math.Clamp(elapsed / 0.5, 0, 1)
    local autoAdvanceTime = step.duration - 1
    local fadeOut = elapsed > autoAdvanceTime and math.Clamp((elapsed - autoAdvanceTime) / 1, 0, 1) or 0
    
    -- Auto advance when step duration expires
    if elapsed >= step.duration then
        Manhunt.Tutorial.NextStep()
        return
    end
    
    -- Skip fade
    if state.skipping then
        fadeOut = math.Clamp(fadeOut + FrameTime() * 4, 0, 1)
    end
    
    local alpha = (fadeIn * (1 - fadeOut)) * 255
    
    -- Cinematic bars
    local barH = sh * 0.12
    surface.SetDrawColor(0, 0, 0, 240)
    surface.DrawRect(0, 0, sw, barH)
    surface.DrawRect(0, sh - barH, sw, barH)
    
    -- Subtle dark overlay on sides
    surface.SetDrawColor(0, 0, 0, 30)
    surface.DrawRect(0, barH, sw * 0.05, sh - barH * 2)
    surface.DrawRect(sw * 0.95, barH, sw * 0.05, sh - barH * 2)
    
    -- Step counter (top right in bar)
    local totalSteps = state.filteredSteps and #state.filteredSteps or 0
    local stepText = "STEP " .. state.stepIndex .. " / " .. totalSteps
    draw.SimpleText(stepText, "Manhunt_HUD_Small", sw - 30, barH / 2, Color(150, 150, 150, alpha), TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    
    -- Team indicator in top bar
    local teamLabel = state.teamFilter == "fugitive" and "FUGITIVE" or (state.teamFilter == "hunter" and "HUNTER" or "ALL")
    local teamCol = state.teamFilter == "fugitive" and Color(255, 80, 80, alpha) or (state.teamFilter == "hunter" and Color(80, 150, 255, alpha) or Color(200, 200, 200, alpha))
    draw.SimpleText(teamLabel .. " TUTORIAL", "Manhunt_HUD_Small", 30, barH / 2, teamCol, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    
    -- Title
    local titleColor = step.teamColor or Color(255, 255, 255)
    local titleAlpha = math.min(alpha, fadeIn * 255)
    
    -- Title shadow
    draw.SimpleText(step.title, "Manhunt_HUD_Title", sw / 2 + 2, barH / 2 + 2, Color(0, 0, 0, titleAlpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    -- Title main
    draw.SimpleText(step.title, "Manhunt_HUD_Title", sw / 2, barH / 2, Color(titleColor.r, titleColor.g, titleColor.b, titleAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    
    -- Description text (bottom bar area)
    local textY = sh - barH + 15
    local lineSpacing = 22
    
    for i, line in ipairs(step.lines) do
        -- Stagger appearance of each line
        local lineDelay = 0.3 + (i - 1) * 0.4
        local lineAlpha = math.Clamp((elapsed - lineDelay) / 0.3, 0, 1) * alpha
        
        if lineAlpha > 0 then
            -- Shadow
            draw.SimpleText(line, "Manhunt_HUD_Small", sw / 2 + 1, textY + (i - 1) * lineSpacing + 1, Color(0, 0, 0, lineAlpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            -- Main
            draw.SimpleText(line, "Manhunt_HUD_Small", sw / 2, textY + (i - 1) * lineSpacing, Color(220, 220, 220, lineAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
    
    -- Progress bar at very bottom
    local progBarH = 3
    local progBarW = sw * 0.6
    local progBarX = (sw - progBarW) / 2
    local progBarY = sh - 8
    local progFrac = elapsed / step.duration
    
    draw.RoundedBox(1, progBarX, progBarY, progBarW, progBarH, Color(50, 50, 50, 150))
    draw.RoundedBox(1, progBarX, progBarY, progBarW * progFrac, progBarH, Color(200, 200, 200, 180))
    
    -- Controls hint (bottom middle, above bar)
    local hintAlpha = math.min(alpha, 140)
    draw.SimpleText("[SPACE] Next  |  [BACKSPACE] Skip Tutorial", "Manhunt_HUD_Small", sw / 2, sh - barH - 10, Color(150, 150, 150, hintAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    
    -- Demo icon/label (if applicable) 
    if step.demo and step.icon then
        local iconPulse = math.abs(math.sin(CurTime() * 2)) * 30
        
        -- Demo label box (top-left area)
        local boxW = 200
        local boxH = 35
        local boxX = 30
        local boxY = barH + 20
        
        draw.RoundedBox(6, boxX, boxY, boxW, boxH, Color(0, 0, 0, alpha * 0.7))
        draw.RoundedBox(4, boxX + 2, boxY + 2, boxW - 4, boxH - 4, Color(50, 80, 120, alpha * 0.3))
        draw.SimpleText("LIVE DEMO", "Manhunt_HUD_Small", boxX + boxW / 2, boxY + boxH / 2, Color(100 + iconPulse, 200 + iconPulse * 0.5, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        
        -- Blinking recording dot
        local dotPulse = math.abs(math.sin(CurTime() * 3))
        draw.RoundedBox(6, boxX + 10, boxY + boxH / 2 - 4, 8, 8, Color(255, 50, 50, alpha * dotPulse))
    end
    
    -- Transition fade overlay
    local transAlpha = (1 - fadeIn) * 255
    if transAlpha > 0 then
        surface.SetDrawColor(0, 0, 0, transAlpha)
        surface.DrawRect(0, 0, sw, sh)
    end
    
    -- Skip fade overlay
    if state.skipping then
        surface.SetDrawColor(0, 0, 0, fadeOut * 255)
        surface.DrawRect(0, 0, sw, sh)
    end
end)

-- ============================================================
-- HIDE DEFAULT HUD DURING TUTORIAL
-- ============================================================

hook.Add("HUDShouldDraw", "Manhunt_TutorialHideHUD", function(name)
    if not Manhunt.Tutorial.State.active then return end
    if name == "CHudHealth" or name == "CHudBattery" or name == "CHudAmmo" or name == "CHudSecondaryAmmo" or name == "CHudCrosshair" then
        return false
    end
end)

-- ============================================================
-- CONSOLE COMMAND
-- ============================================================

concommand.Add("manhunt_tutorial", function()
    if Manhunt.Tutorial.State.active then
        Manhunt.Tutorial.Skip()
    else
        -- Always show team picker when manually triggered
        Manhunt.Tutorial.ShowTeamPicker()
    end
end)

-- ============================================================
-- AUTO-TRIGGER EVERY GAME (skip rounds 2+ in multi-round)
-- ============================================================

hook.Add("Manhunt_PhaseChanged", "Manhunt_TutorialAutoTrigger", function(phase)
    -- Reset completed flag when a new game starts (lobby phase)
    if phase == Manhunt.PHASE_LOBBY then
        Manhunt.Tutorial.CompletedThisRound = false
        Manhunt.Tutorial.PendingThisRound = false
        return
    end

    if phase == Manhunt.PHASE_COUNTDOWN then
        if not Manhunt.Tutorial.ShouldShowThisRound() then return end
        -- Already active or pending - don't re-trigger
        if Manhunt.Tutorial.State.active then return end
        if Manhunt.Tutorial.PendingThisRound then return end

        -- Set flag immediately so cinematic/lobby know to wait
        Manhunt.Tutorial.PendingThisRound = true

        timer.Simple(0.5, function()
            if Manhunt.TestMode then
                -- Test mode: show picker (no real team assigned)
                Manhunt.Tutorial.ShowTeamPicker()
            else
                -- Real game: auto-detect team and start the right tutorial
                local myTeam = Manhunt.GetPlayerTeam(LocalPlayer())
                if myTeam == Manhunt.TEAM_FUGITIVE then
                    Manhunt.Tutorial.StartWithTeam("fugitive")
                elseif myTeam == Manhunt.TEAM_HUNTER then
                    Manhunt.Tutorial.StartWithTeam("hunter")
                else
                    -- Fallback: show picker if team unknown
                    Manhunt.Tutorial.ShowTeamPicker()
                end
            end
        end)
    end
end)

-- Also trigger when test mode is detected
hook.Add("Manhunt_TestModeStarted", "Manhunt_TutorialTestMode", function()
    Manhunt.Tutorial.PendingThisRound = true
    timer.Simple(1, function()
        Manhunt.Tutorial.ShowTeamPicker()
    end)
end)

-- ============================================================
-- ALL PLAYERS DONE - SERVER SAYS GO
-- ============================================================

net.Receive("Manhunt_TutorialAllDone", function()
    if Manhunt.Tutorial.WaitingForOthers then
        Manhunt.Tutorial.WaitingForOthers = false
        if Manhunt.StartCinematicIntro then
            Manhunt.StartCinematicIntro()
        end
    end
end)

-- ============================================================
-- WAITING FOR OTHER PLAYERS HUD
-- ============================================================

hook.Add("HUDPaint", "Manhunt_TutorialWaitingHUD", function()
    if not Manhunt.Tutorial.WaitingForOthers then return end
    
    local sw, sh = ScrW(), ScrH()
    
    -- Dark overlay
    surface.SetDrawColor(0, 0, 0, 200)
    surface.DrawRect(0, 0, sw, sh)
    
    -- Animated dots
    local dotCount = math.floor(CurTime() * 2) % 4
    local dots = string.rep(".", dotCount)
    
    -- Main text
    draw.SimpleText("WAITING FOR OTHER PLAYERS" .. dots, "Manhunt_HUD_Title", sw / 2, sh / 2 - 30, Color(255, 255, 255, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("TO FINISH TUTORIAL", "Manhunt_HUD_Medium", sw / 2, sh / 2 + 15, Color(180, 180, 180, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    
    -- Subtle pulsing ring
    local pulse = 0.5 + math.sin(CurTime() * 2) * 0.3
    local ringSize = 80 + pulse * 20
    surface.SetDrawColor(80, 150, 255, 60 * pulse)
    local cx, cy = sw / 2, sh / 2 + 60
    for i = 0, 360, 2 do
        local rad = math.rad(i)
        surface.DrawRect(cx + math.cos(rad) * ringSize, cy + math.sin(rad) * ringSize, 2, 2)
    end
    
    -- Hint
    draw.SimpleText("The game will begin once everyone is ready.", "Manhunt_HUD_Small", sw / 2, sh / 2 + 100, Color(120, 120, 120, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

-- Reset waiting state on game end / phase change to idle
hook.Add("Manhunt_PhaseChanged", "Manhunt_TutorialWaitingReset", function(phase)
    if phase == Manhunt.PHASE_IDLE or phase == Manhunt.PHASE_LOBBY then
        Manhunt.Tutorial.WaitingForOthers = false
    end
end)

print("[Manhunt] cl_tutorial.lua loaded")
