--[[
    Manhunt - Client Cinematic Intro
    Map flyover camera with dramatic music before the countdown begins
    Triggered during PHASE_COUNTDOWN, plays before the regular countdown
]]

Manhunt.CinematicIntro = {
    active = false,
    startTime = 0,
    duration = 6, -- seconds for the flyover
    waypoints = {},
    completed = false,
}

-- Generate flyover waypoints based on map geometry
function Manhunt.GenerateFlyoverWaypoints()
    local waypoints = {}

    -- Get map bounds by sampling navmesh or using known positions
    local mapCenter = Vector(0, 0, 0)
    local playerCount = 0

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) then
            mapCenter = mapCenter + ply:GetPos()
            playerCount = playerCount + 1
        end
    end

    if playerCount > 0 then
        mapCenter = mapCenter / playerCount
    end

    -- Create a dramatic flyover path
    -- Start high and far, sweep across the map, end near the center
    local radius = 3000
    local height = 1500

    -- Waypoint 1: High above, looking down
    table.insert(waypoints, {
        pos = mapCenter + Vector(radius, 0, height + 500),
        lookAt = mapCenter + Vector(0, 0, 0),
        time = 0,
    })

    -- Waypoint 2: Sweeping across
    table.insert(waypoints, {
        pos = mapCenter + Vector(0, radius, height),
        lookAt = mapCenter + Vector(0, 0, 200),
        time = 0.35,
    })

    -- Waypoint 3: Lower, coming towards center
    table.insert(waypoints, {
        pos = mapCenter + Vector(-radius * 0.5, -radius * 0.3, height * 0.5),
        lookAt = mapCenter + Vector(0, 0, 100),
        time = 0.65,
    })

    -- Waypoint 4: End near ground level, dramatic angle
    table.insert(waypoints, {
        pos = mapCenter + Vector(-200, 100, 300),
        lookAt = mapCenter + Vector(0, 0, 50),
        time = 1.0,
    })

    return waypoints
end

-- Interpolate between waypoints
local function CatmullRom(t, p0, p1, p2, p3)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * (
        (2 * p1) +
        (-p0 + p2) * t +
        (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
        (-p0 + 3 * p1 - 3 * p2 + p3) * t3
    )
end

local function GetWaypointTransform(progress, waypoints)
    if #waypoints < 2 then
        return waypoints[1].pos, (waypoints[1].lookAt - waypoints[1].pos):Angle()
    end

    -- Find which segment we're in
    local segIdx = 1
    for i = 1, #waypoints - 1 do
        if progress >= waypoints[i].time and progress <= waypoints[i + 1].time then
            segIdx = i
            break
        end
    end

    local wp1 = waypoints[segIdx]
    local wp2 = waypoints[math.min(segIdx + 1, #waypoints)]
    local segLength = wp2.time - wp1.time
    local t = segLength > 0 and ((progress - wp1.time) / segLength) or 0

    -- Smooth interpolation
    t = t * t * (3 - 2 * t) -- ease-in-out

    local pos = LerpVector(t, wp1.pos, wp2.pos)
    local lookAt = LerpVector(t, wp1.lookAt, wp2.lookAt)

    local ang = (lookAt - pos):Angle()

    return pos, ang
end

-- Activate cinematic intro
function Manhunt.StartCinematicIntro()
    Manhunt.CinematicIntro.active = true
    Manhunt.CinematicIntro.startTime = CurTime()
    Manhunt.CinematicIntro.completed = false
    Manhunt.CinematicIntro.waypoints = Manhunt.GenerateFlyoverWaypoints()

    -- Play dramatic music
    surface.PlaySound("ambient/atmosphere/city_skypass1.wav")
end

-- End cinematic intro
function Manhunt.EndCinematicIntro()
    Manhunt.CinematicIntro.active = false
    Manhunt.CinematicIntro.completed = true
end

-- Override camera during cinematic intro
hook.Add("CalcView", "Manhunt_CinematicIntroView", function(ply, pos, angles, fov)
    if not Manhunt.CinematicIntro.active then return end

    local elapsed = CurTime() - Manhunt.CinematicIntro.startTime
    local progress = elapsed / Manhunt.CinematicIntro.duration

    if progress >= 1 then
        Manhunt.EndCinematicIntro()
        return
    end

    local waypoints = Manhunt.CinematicIntro.waypoints
    if #waypoints < 2 then return end

    local camPos, camAng = GetWaypointTransform(progress, waypoints)

    -- Cinematic wide FOV
    local cinematicFov = Lerp(progress, 95, 75)

    return {
        origin = camPos,
        angles = camAng,
        fov = cinematicFov,
        drawviewer = true,
    }
end)

-- Draw cinematic intro overlay
hook.Add("HUDPaint", "Manhunt_CinematicIntroHUD", function()
    if not Manhunt.CinematicIntro.active then return end

    local sw, sh = ScrW(), ScrH()
    local elapsed = CurTime() - Manhunt.CinematicIntro.startTime
    local progress = elapsed / Manhunt.CinematicIntro.duration

    -- Cinematic bars (top and bottom)
    local barH = sh * 0.1
    surface.SetDrawColor(0, 0, 0, 255)
    surface.DrawRect(0, 0, sw, barH)
    surface.DrawRect(0, sh - barH, sw, barH)

    -- Title text: "MANHUNT" appearing
    if elapsed > 0.5 then
        local titleAlpha = math.min(255, (elapsed - 0.5) * 200)

        -- Shadow
        draw.SimpleText("M A N H U N T", "Manhunt_HUD_Title", sw / 2 + 2, sh * 0.15 + 2, Color(0, 0, 0, titleAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        -- Main
        draw.SimpleText("M A N H U N T", "Manhunt_HUD_Title", sw / 2, sh * 0.15, Color(255, 255, 255, titleAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Map name
    if elapsed > 1.5 then
        local mapAlpha = math.min(255, (elapsed - 1.5) * 300)
        local mapName = string.upper(game.GetMap())
        draw.SimpleText(mapName, "Manhunt_HUD_Medium", sw / 2, sh * 0.15 + 55, Color(200, 50, 50, mapAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Round info (if round system active)
    if elapsed > 2.5 and Manhunt.RoundData and Manhunt.RoundData.totalRounds > 1 then
        local roundAlpha = math.min(255, (elapsed - 2.5) * 300)
        draw.SimpleText("ROUND " .. Manhunt.RoundData.currentRound .. " OF " .. Manhunt.RoundData.totalRounds, "Manhunt_HUD_Large", sw / 2, sh * 0.85, Color(255, 255, 255, roundAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- "Get Ready" text near the end
    if elapsed > 4 then
        local readyAlpha = math.min(255, (elapsed - 4) * 400)
        local pulse = math.abs(math.sin(CurTime() * 4))
        draw.SimpleText("GET READY", "Manhunt_HUD_Large", sw / 2, sh / 2, Color(255, 255, 255, readyAlpha * (0.5 + pulse * 0.5)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Fade to white at the very end (transition to countdown)
    if progress > 0.9 then
        local fadeAlpha = (progress - 0.9) / 0.1 * 255
        surface.SetDrawColor(255, 255, 255, fadeAlpha)
        surface.DrawRect(0, 0, sw, sh)
    end
end)

-- Block player input during cinematic
hook.Add("CreateMove", "Manhunt_CinematicIntroBlock", function(cmd)
    if Manhunt.CinematicIntro.active then
        cmd:ClearMovement()
        cmd:ClearButtons()
    end
end)

-- Trigger cinematic when countdown starts
hook.Add("Manhunt_PhaseChanged", "Manhunt_CinematicTrigger", function(phase)
    if phase == Manhunt.PHASE_COUNTDOWN then
        -- If tutorial will show this round, don't start cinematic now
        -- (the tutorial will trigger it when it ends)
        if Manhunt.Tutorial and Manhunt.Tutorial.ShouldShowThisRound and Manhunt.Tutorial.ShouldShowThisRound() then
            return
        end

        -- No tutorial: start cinematic immediately
        Manhunt.StartCinematicIntro()
    end
end)
