--[[
    Manhunt - Client Replay System
    Post-game top-down map view with colored paths
    Camera placed high above the map looking straight down
    Paths drawn in 2D over the live 3D world using ToScreen()
    Blue = Fugitive, Red = Hunter(s)
    Smooth Catmull-Rom interpolated paths
]]

Manhunt.Replay = {
    active = false,
    data = {},
    startTime = 0,
    playbackTime = 0,
    playbackSpeed = 1,
    totalDuration = 0,
    mapBounds = {
        min = Vector(0, 0, 0),
        max = Vector(0, 0, 0),
    },
    paused = false,
    camHeight = 5000,
    camFov = 90,
    camCenter = Vector(0, 0, 5000),
}

-- Receive replay data from server
net.Receive("Manhunt_ReplayData", function()
    local len = net.ReadUInt(32)
    local data = net.ReadData(len)

    data = util.Decompress(data)
    if not data then return end

    local tbl = util.JSONToTable(data)
    if not tbl then return end

    Manhunt.Replay.data = tbl
    Manhunt.CalculateReplayBounds()

    print("[Manhunt] Replay data received: " .. #tbl .. " frames")
end)

-- Helper: convert replay position (table {x,y,z} or Vector) to Vector
local function ReplayToVector(pos)
    if isvector(pos) then return pos end
    if istable(pos) then
        return Vector(tonumber(pos[1]) or 0, tonumber(pos[2]) or 0, tonumber(pos[3]) or 0)
    end
    return Vector(0, 0, 0)
end

-- Calculate bounds and camera parameters for the map view
function Manhunt.CalculateReplayBounds()
    local minX, minY, minZ = math.huge, math.huge, math.huge
    local maxX, maxY, maxZ = -math.huge, -math.huge, -math.huge

    for _, frame in ipairs(Manhunt.Replay.data) do
        if frame.fugitive then
            local v = ReplayToVector(frame.fugitive)
            minX = math.min(minX, v.x); minY = math.min(minY, v.y); minZ = math.min(minZ, v.z)
            maxX = math.max(maxX, v.x); maxY = math.max(maxY, v.y); maxZ = math.max(maxZ, v.z)
        end
        if frame.hunters then
            for _, hPos in pairs(frame.hunters) do
                local v = ReplayToVector(hPos)
                minX = math.min(minX, v.x); minY = math.min(minY, v.y); minZ = math.min(minZ, v.z)
                maxX = math.max(maxX, v.x); maxY = math.max(maxY, v.y); maxZ = math.max(maxZ, v.z)
            end
        end
    end

    -- Add generous padding
    local padX = math.max((maxX - minX) * 0.2, 800)
    local padY = math.max((maxY - minY) * 0.2, 800)
    Manhunt.Replay.mapBounds.min = Vector(minX - padX, minY - padY, minZ)
    Manhunt.Replay.mapBounds.max = Vector(maxX + padX, maxY + padY, maxZ)

    if #Manhunt.Replay.data > 0 then
        Manhunt.Replay.totalDuration = Manhunt.Replay.data[#Manhunt.Replay.data].time or 0
    end

    -- Calculate camera to see entire play area from above
    local centerX = (minX + maxX) / 2
    local centerY = (minY + maxY) / 2
    local centerZ = (minZ + maxZ) / 2

    local mapW = (maxX + padX) - (minX - padX)
    local mapH = (maxY + padY) - (minY - padY)
    local maxSpan = math.max(mapW, mapH)

    -- Account for aspect ratio: use mapW/mapH to pick ideal FOV axis
    local sw, sh = ScrW(), ScrH()
    local aspect = sw / sh
    local fov = 90

    -- Height needed for horizontal FOV to cover mapW
    local hFovRad = math.rad(fov / 2)
    local heightForW = (mapW / 2) / math.tan(hFovRad)

    -- Height needed for vertical FOV to cover mapH
    local vFov = 2 * math.deg(math.atan(math.tan(hFovRad) / aspect))
    local vFovRad = math.rad(vFov / 2)
    local heightForH = (mapH / 2) / math.tan(vFovRad)

    local requiredHeight = math.max(heightForW, heightForH) * 1.1

    -- Trace up to find sky ceiling so we don't clip through it
    local tr = util.TraceLine({
        start = Vector(centerX, centerY, centerZ + 200),
        endpos = Vector(centerX, centerY, centerZ + 50000),
        mask = MASK_SOLID_BRUSHONLY,
    })
    local skyHeight = tr.HitPos.z - 100

    Manhunt.Replay.camHeight = math.max(skyHeight, centerZ + requiredHeight)
    Manhunt.Replay.camFov = fov
    Manhunt.Replay.camCenter = Vector(centerX, centerY, Manhunt.Replay.camHeight)

    print("[Manhunt] Replay camera: height=" .. math.floor(Manhunt.Replay.camHeight) .. " fov=" .. fov .. " span=" .. math.floor(maxSpan))
end

-- Catmull-Rom 1D interpolation for smooth paths
local function CatmullRom1D(t, p0, p1, p2, p3)
    local t2 = t * t
    local t3 = t2 * t
    return 0.5 * (
        (2 * p1) +
        (-p0 + p2) * t +
        (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
        (-p0 + 3 * p1 - 3 * p2 + p3) * t3
    )
end

-- Generate smooth world-space points using Catmull-Rom
local function SmoothWorldPath(rawVectors, subdivisions)
    if #rawVectors < 2 then return rawVectors end

    local smoothed = {}
    subdivisions = subdivisions or 8

    for i = 1, #rawVectors - 1 do
        local p0 = rawVectors[math.max(1, i - 1)]
        local p1 = rawVectors[i]
        local p2 = rawVectors[i + 1]
        local p3 = rawVectors[math.min(#rawVectors, i + 2)]

        for s = 0, subdivisions - 1 do
            local t = s / subdivisions
            table.insert(smoothed, Vector(
                CatmullRom1D(t, p0.x, p1.x, p2.x, p3.x),
                CatmullRom1D(t, p0.y, p1.y, p2.y, p3.y),
                CatmullRom1D(t, p0.z, p1.z, p2.z, p3.z)
            ))
        end
    end

    table.insert(smoothed, rawVectors[#rawVectors])
    return smoothed
end

-- Draw a thick line between two screen points
local function DrawThickLine(x1, y1, x2, y2, thickness, color)
    surface.SetDrawColor(color.r, color.g, color.b, color.a or 255)

    if thickness <= 1 then
        surface.DrawLine(x1, y1, x2, y2)
        return
    end

    local dx = x2 - x1
    local dy = y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len == 0 then return end

    local nx = -dy / len
    local ny = dx / len

    local halfT = thickness / 2
    local steps = math.ceil(thickness)
    for s = 0, steps do
        local offset = -halfT + (s / steps) * thickness
        surface.DrawLine(
            x1 + nx * offset, y1 + ny * offset,
            x2 + nx * offset, y2 + ny * offset
        )
    end
end

-- Convert world vectors to screen points and draw path
local function DrawWorldPath(worldPoints, color, thickness)
    if #worldPoints < 2 then return end

    local prevScreen = worldPoints[1]:ToScreen()
    for i = 2, #worldPoints do
        local curScreen = worldPoints[i]:ToScreen()
        if prevScreen.visible or curScreen.visible then
            DrawThickLine(prevScreen.x, prevScreen.y, curScreen.x, curScreen.y, thickness or 2, color)
        end
        prevScreen = curScreen
    end
end

-- Format time for display
local function FormatReplayTime(seconds)
    local mins = math.floor(seconds / 60)
    local secs = math.floor(seconds % 60)
    return string.format("%d:%02d", mins, secs)
end

-- Show replay (triggered after end game)
hook.Add("Manhunt_ShowReplay", "Manhunt_ActivateReplay", function()
    if #Manhunt.Replay.data == 0 then
        chat.AddText(Color(255, 100, 100), "[Manhunt] No replay data available!")
        return
    end

    Manhunt.Replay.active = true
    Manhunt.Replay.startTime = CurTime()
    Manhunt.Replay.playbackTime = 0
    Manhunt.Replay.paused = false
    Manhunt.Replay.playbackSpeed = 1

    -- Recalculate bounds (screen size might have changed)
    Manhunt.CalculateReplayBounds()

    -- Close end game screen
    Manhunt.EndGameData.winner = nil
end)

-- Override camera to top-down view during replay
hook.Add("CalcView", "Manhunt_ReplayView", function(ply, pos, angles, fov)
    if not Manhunt.Replay.active then return end

    return {
        origin = Manhunt.Replay.camCenter,
        angles = Angle(90, 0, 0),
        fov = Manhunt.Replay.camFov,
        drawviewer = false,
    }
end)

-- Draw replay overlay
hook.Add("HUDPaint", "Manhunt_ReplayDraw", function()
    if not Manhunt.Replay.active then return end

    local sw, sh = ScrW(), ScrH()
    local data = Manhunt.Replay.data
    local totalDuration = Manhunt.Replay.totalDuration

    -- Update playback time
    if not Manhunt.Replay.paused then
        Manhunt.Replay.playbackTime = Manhunt.Replay.playbackTime + FrameTime() * Manhunt.Replay.playbackSpeed

        if Manhunt.Replay.playbackTime >= totalDuration then
            Manhunt.Replay.playbackTime = totalDuration
            Manhunt.Replay.paused = true
        end
    end

    local currentTime = Manhunt.Replay.playbackTime

    -- Subtle dark overlay for contrast
    surface.SetDrawColor(0, 0, 10, 80)
    surface.DrawRect(0, 0, sw, sh)

    -- Collect world positions up to current time
    local fugRaw = {}
    local hunterRaw = {}

    for _, frame in ipairs(data) do
        if (frame.time or 0) > currentTime then break end

        if frame.fugitive then
            table.insert(fugRaw, ReplayToVector(frame.fugitive))
        end

        if frame.hunters then
            for sid, hPos in pairs(frame.hunters) do
                if not hunterRaw[sid] then hunterRaw[sid] = {} end
                table.insert(hunterRaw[sid], ReplayToVector(hPos))
            end
        end
    end

    -- Smooth paths in world space using Catmull-Rom
    local fugSmooth = SmoothWorldPath(fugRaw, 10)

    -- Draw hunter paths (red/orange tones)
    local hunterColors = {
        Color(255, 60, 60, 200),
        Color(255, 140, 40, 200),
        Color(255, 60, 160, 200),
        Color(255, 200, 40, 200),
    }
    local colorIdx = 1
    for sid, rawPts in pairs(hunterRaw) do
        local col = hunterColors[colorIdx] or Color(255, 60, 60, 200)
        colorIdx = colorIdx + 1

        local smoothPts = SmoothWorldPath(rawPts, 10)

        -- Glow (wider, transparent)
        DrawWorldPath(smoothPts, Color(col.r, col.g, col.b, 40), 6)
        -- Main path
        DrawWorldPath(smoothPts, col, 3)

        -- Current position marker
        if #smoothPts > 0 then
            local sp = smoothPts[#smoothPts]:ToScreen()
            if sp.visible then
                draw.RoundedBox(8, sp.x - 10, sp.y - 10, 20, 20, Color(col.r, col.g, col.b, 80))
                draw.RoundedBox(6, sp.x - 7, sp.y - 7, 14, 14, col)
                draw.SimpleText("H", "Manhunt_HUD_Small", sp.x, sp.y, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end

    -- Draw fugitive path (blue)
    local fugColor = Color(50, 150, 255, 220)
    DrawWorldPath(fugSmooth, Color(50, 150, 255, 40), 6)
    DrawWorldPath(fugSmooth, fugColor, 3)

    -- Fugitive current position
    if #fugSmooth > 0 then
        local sp = fugSmooth[#fugSmooth]:ToScreen()
        if sp.visible then
            draw.RoundedBox(8, sp.x - 10, sp.y - 10, 20, 20, Color(50, 150, 255, 80))
            draw.RoundedBox(6, sp.x - 7, sp.y - 7, 14, 14, Color(50, 150, 255))
            draw.SimpleText("F", "Manhunt_HUD_Small", sp.x, sp.y, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end

    -- =================== UI OVERLAY ===================

    -- Title bar
    draw.RoundedBox(0, 0, 0, sw, 55, Color(0, 0, 0, 180))
    draw.SimpleText("MANHUNT REPLAY", "Manhunt_HUD_Title", sw / 2, 8, Color(255, 255, 255, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    -- Timeline bar
    local barW = sw * 0.6
    local barH = 8
    local barX = (sw - barW) / 2
    local barY = sh - 55

    draw.RoundedBox(4, barX - 2, barY - 2, barW + 4, barH + 4, Color(0, 0, 0, 180))
    draw.RoundedBox(4, barX, barY, barW, barH, Color(40, 40, 40, 200))
    local progress = totalDuration > 0 and (currentTime / totalDuration) or 0
    draw.RoundedBox(4, barX, barY, barW * progress, barH, Color(50, 200, 255))

    -- Playhead
    local headX = barX + barW * progress
    draw.RoundedBox(6, headX - 5, barY - 3, 10, barH + 6, Color(255, 255, 255, 220))

    -- Time display
    draw.SimpleText(FormatReplayTime(currentTime) .. " / " .. FormatReplayTime(totalDuration), "Manhunt_HUD_Small", sw / 2, barY + 14, Color(200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    -- Speed display
    draw.SimpleText(Manhunt.Replay.playbackSpeed .. "x", "Manhunt_HUD_Small", barX + barW + 15, barY - 2, Color(200, 200, 200), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    -- Paused indicator
    if Manhunt.Replay.paused then
        local pulseAlpha = math.abs(math.sin(CurTime() * 2)) * 200 + 55
        draw.RoundedBox(8, sw / 2 - 60, sh / 2 - 20, 120, 40, Color(0, 0, 0, 150))
        draw.SimpleText("PAUSED", "Manhunt_HUD_Medium", sw / 2, sh / 2, Color(255, 255, 255, pulseAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    -- Legend
    local legendY = sh - 110
    draw.RoundedBox(6, 12, legendY - 5, 130, 55, Color(0, 0, 0, 150))
    draw.RoundedBox(4, 22, legendY + 2, 12, 12, Color(50, 150, 255))
    draw.SimpleText("Fugitive", "Manhunt_HUD_Small", 42, legendY, Color(50, 150, 255), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    draw.RoundedBox(4, 22, legendY + 25, 12, 12, Color(255, 60, 60))
    draw.SimpleText("Hunter", "Manhunt_HUD_Small", 42, legendY + 23, Color(255, 60, 60), TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

    -- Controls hint
    draw.RoundedBox(0, 0, sh - 25, sw, 25, Color(0, 0, 0, 150))
    draw.SimpleText("[SPACE] Pause/Play  |  [\xe2\x86\x90/\xe2\x86\x92] Speed  |  [ESC/BACKSPACE] Close", "Manhunt_HUD_Small", sw / 2, sh - 13, Color(150, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

-- Replay controls
local replayEscCooldown = 0

hook.Add("Think", "Manhunt_ReplayControls", function()
    if not Manhunt.Replay.active then return end

    if CurTime() < replayEscCooldown then return end

    if input.IsKeyDown(KEY_SPACE) then
        replayEscCooldown = CurTime() + 0.3
        Manhunt.Replay.paused = not Manhunt.Replay.paused
        if Manhunt.Replay.playbackTime >= Manhunt.Replay.totalDuration then
            Manhunt.Replay.playbackTime = 0
            Manhunt.Replay.paused = false
        end
    elseif input.IsKeyDown(KEY_RIGHT) then
        replayEscCooldown = CurTime() + 0.3
        Manhunt.Replay.playbackSpeed = math.min(8, Manhunt.Replay.playbackSpeed * 2)
    elseif input.IsKeyDown(KEY_LEFT) then
        replayEscCooldown = CurTime() + 0.3
        Manhunt.Replay.playbackSpeed = math.max(0.25, Manhunt.Replay.playbackSpeed / 2)
    elseif input.IsKeyDown(KEY_ESCAPE) or input.IsKeyDown(KEY_BACKSPACE) then
        replayEscCooldown = CurTime() + 0.5
        Manhunt.Replay.active = false
    end
end)

-- Block normal input during replay
hook.Add("CreateMove", "Manhunt_ReplayBlockInput", function(cmd)
    if Manhunt.Replay.active then
        cmd:ClearMovement()
        cmd:ClearButtons()
    end
end)
