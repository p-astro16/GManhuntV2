--[[
    Manhunt - Client Kill Cam
    Real replay-style kill cam showing the killer's perspective (viewpoint buffer)
    Also includes Hunter Kill PiP shown to the fugitive when a hunter dies
]]

-- ============================================================
-- MAIN KILL CAM (Fugitive death - shown to everyone)
-- Replays the killer's actual viewpoint from the last few seconds
-- ============================================================

Manhunt.KillCam = {
    active = false,
    startTime = 0,
    duration = 4,
    viewBuffer = {},    -- Array of {pos=Vector, ang=Angle} recorded at 10Hz
    victimPos = Vector(0, 0, 0),
    attackerName = "",
    victimName = "",
    weaponName = "",
}

-- Receive kill cam data from server (includes viewpoint replay buffer)
net.Receive("Manhunt_KillCam", function()
    -- Read viewpoint buffer
    local count = net.ReadUInt(8)
    local buffer = {}
    for i = 1, count do
        table.insert(buffer, {
            pos = net.ReadVector(),
            ang = net.ReadAngle(),
        })
    end

    Manhunt.KillCam.viewBuffer = buffer
    Manhunt.KillCam.victimPos = net.ReadVector()
    Manhunt.KillCam.victimName = net.ReadString()
    Manhunt.KillCam.attackerName = net.ReadString()
    Manhunt.KillCam.weaponName = net.ReadString()

    Manhunt.KillCam.active = true
    Manhunt.KillCam.startTime = CurTime()
    -- Duration matches the buffer length (recorded at 10Hz = 0.1s per entry)
    Manhunt.KillCam.duration = math.Clamp(#buffer * 0.1, 2, 6)

    surface.PlaySound("ambient/alarms/warningbell1.wav")
end)

-- Camera view: replay the killer's actual viewpoint
hook.Add("CalcView", "Manhunt_KillCamView", function(ply, pos, angles, fov)
    if not Manhunt.KillCam.active then return end

    local elapsed = CurTime() - Manhunt.KillCam.startTime
    local duration = Manhunt.KillCam.duration
    local progress = elapsed / duration

    if progress >= 1 then
        Manhunt.KillCam.active = false
        return
    end

    local buffer = Manhunt.KillCam.viewBuffer
    if not buffer or #buffer == 0 then
        -- Fallback: no buffer, just look at death pos from above
        local deathPos = Manhunt.KillCam.victimPos
        return {
            origin = deathPos + Vector(0, 0, 200),
            angles = Angle(60, 0, 0),
            fov = 70,
            drawviewer = true,
        }
    end

    -- Map progress to buffer index with smooth interpolation
    local exactIdx = 1 + progress * (#buffer - 1)
    local idx1 = math.Clamp(math.floor(exactIdx), 1, #buffer)
    local idx2 = math.Clamp(idx1 + 1, 1, #buffer)
    local frac = exactIdx - math.floor(exactIdx)

    -- Smooth interpolation
    local camPos = LerpVector(frac, buffer[idx1].pos, buffer[idx2].pos)
    local camAng = LerpAngle(frac, buffer[idx1].ang, buffer[idx2].ang)

    -- Slow-mo FOV effect (starts normal, slowly narrows for dramatic effect)
    local killFov = Lerp(progress, 75, 55)

    return {
        origin = camPos,
        angles = camAng,
        fov = killFov,
        drawviewer = true,
    }
end)

-- Draw kill cam overlay (cinematic bars, text, effects)
hook.Add("HUDPaint", "Manhunt_KillCamHUD", function()
    if not Manhunt.KillCam.active then return end

    local sw, sh = ScrW(), ScrH()
    local elapsed = CurTime() - Manhunt.KillCam.startTime
    local progress = elapsed / Manhunt.KillCam.duration

    if progress >= 1 then
        Manhunt.KillCam.active = false
        return
    end

    -- Cinematic bars (top and bottom)
    local barH = sh * 0.08
    local barAlpha = math.min(255, elapsed * 500)
    surface.SetDrawColor(0, 0, 0, barAlpha)
    surface.DrawRect(0, 0, sw, barH)
    surface.DrawRect(0, sh - barH, sw, barH)

    -- Vignette (dark edges)
    local vigAlpha = 100
    surface.SetDrawColor(0, 0, 0, vigAlpha)
    surface.DrawRect(0, 0, sw * 0.05, sh)
    surface.DrawRect(sw * 0.95, 0, sw * 0.05, sh)

    -- Flash effect at start
    if elapsed < 0.5 then
        local flashAlpha = (1 - elapsed / 0.5) * 200
        surface.SetDrawColor(255, 255, 255, flashAlpha)
        surface.DrawRect(0, 0, sw, sh)
    end

    -- Kill info text
    if elapsed > 0.5 then
        local fadeIn = math.min(255, (elapsed - 0.5) * 400)
        draw.SimpleText("FUGITIVE ELIMINATED", "Manhunt_HUD_Title", sw / 2, sh * 0.2, Color(255, 50, 50, fadeIn), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        if elapsed > 1.2 then
            local fadeIn2 = math.min(255, (elapsed - 1.2) * 400)
            draw.SimpleText(Manhunt.KillCam.victimName, "Manhunt_HUD_Large", sw / 2, sh * 0.2 + 55, Color(50, 150, 255, fadeIn2), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        if elapsed > 1.8 then
            local fadeIn3 = math.min(255, (elapsed - 1.8) * 400)
            draw.SimpleText("Killed by " .. Manhunt.KillCam.attackerName, "Manhunt_HUD_Medium", sw / 2, sh * 0.2 + 95, Color(255, 80, 80, fadeIn3), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            if Manhunt.KillCam.weaponName ~= "" then
                draw.SimpleText("with " .. Manhunt.KillCam.weaponName, "Manhunt_HUD_Small", sw / 2, sh * 0.2 + 125, Color(200, 200, 200, fadeIn3), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end
    end

    -- "KILL CAM" indicator
    local pulse = math.abs(math.sin(CurTime() * 4))
    draw.SimpleText("KILL CAM", "Manhunt_HUD_Small", sw / 2, sh - barH - 15, Color(255, 255, 255, 100 + pulse * 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

    -- Red scanline effect
    for i = 0, sh, 4 do
        surface.SetDrawColor(255, 0, 0, 3)
        surface.DrawLine(0, i, sw, i)
    end
end)

-- ============================================================
-- HUNTER KILL PiP (shown to the Fugitive when a hunter dies)
-- Uses PostRender for RT capture to avoid white screen bug
-- ============================================================

Manhunt.HunterKillPiP = {
    active = false,
    startTime = 0,
    duration = 4,
    deathPos = Vector(0, 0, 0),
    attackerEyePos = Vector(0, 0, 0),
    attackerEyeAng = Angle(0, 0, 0),
    hunterName = "",
    killerName = "",
    weaponName = "",
    rendering = false,
}

local KILL_PIP_SIZE = 340
local KILL_PIP_MARGIN = 20

-- Separate RT for the kill PiP (so it doesn't conflict with surveillance cam)
local killPipRT = GetRenderTarget("ManhuntHunterKillPiP", 1024, 1024)
local killPipMat = CreateMaterial("ManhuntKillPiPMat_" .. SysTime(), "UnlitGeneric", {
    ["$basetexture"] = killPipRT:GetName(),
    ["$nolod"] = 1,
})

-- Queue system: if multiple hunters die close together, queue them
Manhunt.HunterKillPiPQueue = Manhunt.HunterKillPiPQueue or {}

net.Receive("Manhunt_HunterKillPiP", function()
    local data = {
        deathPos = net.ReadVector(),
        attackerEyePos = net.ReadVector(),
        attackerEyeAng = net.ReadAngle(),
        hunterName = net.ReadString(),
        killerName = net.ReadString(),
        weaponName = net.ReadString(),
    }

    -- If PiP is already active, queue it
    if Manhunt.HunterKillPiP.active then
        table.insert(Manhunt.HunterKillPiPQueue, data)
    else
        Manhunt.StartHunterKillPiP(data)
    end
end)

function Manhunt.StartHunterKillPiP(data)
    Manhunt.HunterKillPiP.active = true
    Manhunt.HunterKillPiP.startTime = CurTime()
    Manhunt.HunterKillPiP.deathPos = data.deathPos
    Manhunt.HunterKillPiP.attackerEyePos = data.attackerEyePos
    Manhunt.HunterKillPiP.attackerEyeAng = data.attackerEyeAng
    Manhunt.HunterKillPiP.hunterName = data.hunterName
    Manhunt.HunterKillPiP.killerName = data.killerName
    Manhunt.HunterKillPiP.weaponName = data.weaponName

    surface.PlaySound("buttons/button17.wav")
end

-- Render the kill PiP camera to RT using RenderScene (same approach as surveillance cam)
hook.Add("RenderScene", "Manhunt_HunterKillPiPRender", function()
    if not Manhunt.HunterKillPiP.active then return end
    if Manhunt.HunterKillPiP.rendering then return end

    local pip = Manhunt.HunterKillPiP
    local elapsed = CurTime() - pip.startTime
    local progress = elapsed / pip.duration

    if progress >= 1 then
        pip.active = false
        -- Check queue
        if #Manhunt.HunterKillPiPQueue > 0 then
            Manhunt.StartHunterKillPiP(table.remove(Manhunt.HunterKillPiPQueue, 1))
        end
        return
    end

    pip.rendering = true

    -- Camera: start at killer's eye view, then slowly orbit the death position
    local t = progress * progress * (3 - 2 * progress) -- ease-in-out
    local startPos = pip.attackerEyePos
    local startAng = pip.attackerEyeAng
    local lookAt = pip.deathPos + Vector(0, 0, 40)

    -- Orbit parameters (target position)
    local orbitAngle = elapsed * 40 + startAng.y
    local rad = math.rad(orbitAngle)
    local orbitDist = Lerp(t, 60, 200)
    local orbitHeight = Lerp(t, 0, 150)
    local orbitPos = pip.deathPos + Vector(math.cos(rad) * orbitDist, math.sin(rad) * orbitDist, 64 + orbitHeight)
    local orbitAng = (lookAt - orbitPos):Angle()

    -- Blend from killer's view to orbit over the first 1/3 of duration
    local blendT = math.Clamp(progress * 3, 0, 1)
    blendT = blendT * blendT * (3 - 2 * blendT) -- smooth step

    local camPos = LerpVector(blendT, startPos, orbitPos)
    local camAng = LerpAngle(blendT, startAng, orbitAng)

    local oldW, oldH = ScrW(), ScrH()

    render.PushRenderTarget(killPipRT)
    render.SetViewPort(0, 0, 1024, 1024)
    render.Clear(0, 0, 0, 255, true, true)
    render.RenderView({
        origin = camPos,
        angles = camAng,
        x = 0, y = 0,
        w = 1024, h = 1024,
        fov = 80,
        drawviewmodel = false,
        drawhud = false,
        dopostprocess = false,
        bloomtone = false,
    })
    render.SetViewPort(0, 0, oldW, oldH)
    render.PopRenderTarget()

    pip.rendering = false
end)

-- Draw the hunter kill PiP on screen (bottom-left corner for fugitive)
hook.Add("HUDPaint", "Manhunt_HunterKillPiPDraw", function()
    if not Manhunt.HunterKillPiP.active then return end

    local pip = Manhunt.HunterKillPiP
    local elapsed = CurTime() - pip.startTime
    local progress = elapsed / pip.duration

    if progress >= 1 then
        pip.active = false
        if #Manhunt.HunterKillPiPQueue > 0 then
            Manhunt.StartHunterKillPiP(table.remove(Manhunt.HunterKillPiPQueue, 1))
        end
        return
    end

    -- Fade in/out
    local alpha = 255
    if progress < 0.08 then
        alpha = Lerp(progress / 0.08, 0, 255)
    elseif progress > 0.85 then
        alpha = Lerp((progress - 0.85) / 0.15, 255, 0)
    end

    local sw, sh = ScrW(), ScrH()
    local size = KILL_PIP_SIZE
    local y = sh - size - KILL_PIP_MARGIN - 30

    -- Slide in from the left
    local slideProgress = math.min(1, elapsed / 0.3)
    slideProgress = slideProgress * slideProgress * (3 - 2 * slideProgress)
    local x = Lerp(slideProgress, -size, KILL_PIP_MARGIN)

    -- Red border (hunter death = red theme)
    local pulse = math.abs(math.sin(CurTime() * 4))
    local borderAlpha = alpha * (0.7 + pulse * 0.3)
    draw.RoundedBox(4, x - 3, y - 3, size + 6, size + 6, Color(255, 50, 50, borderAlpha))
    draw.RoundedBox(2, x, y, size, size, Color(0, 0, 0, alpha))

    -- Camera feed
    surface.SetDrawColor(255, 255, 255, alpha)
    surface.SetMaterial(killPipMat)
    surface.DrawTexturedRect(x, y, size, size)

    -- Dark overlay for text readability
    surface.SetDrawColor(0, 0, 0, alpha * 0.3)
    surface.DrawRect(x, y, size, 28)
    surface.DrawRect(x, y + size - 55, size, 55)

    -- "HUNTER ELIMINATED" header
    draw.SimpleText("HUNTER ELIMINATED", "Manhunt_HUD_Small", x + 5, y + 5, Color(255, 80, 80, alpha))

    -- Scanline effect
    local scanY = y + (CurTime() * 150 % size)
    surface.SetDrawColor(255, 50, 50, 15)
    surface.DrawRect(x, scanY, size, 2)

    -- Hunter name
    if elapsed > 0.3 then
        local textAlpha = math.min(alpha, (elapsed - 0.3) * 600)
        draw.SimpleText(pip.hunterName, "Manhunt_HUD_Medium", x + size / 2, y + size - 48, Color(255, 100, 100, textAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        -- Kill info
        if pip.killerName ~= "" then
            local killText = pip.weaponName ~= "" and ("by " .. pip.killerName .. " (" .. pip.weaponName .. ")") or ("by " .. pip.killerName)
            draw.SimpleText(killText, "Manhunt_HUD_Small", x + size / 2, y + size - 22, Color(200, 200, 200, textAlpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end

    -- Red corner accents
    local accLen = 15
    surface.SetDrawColor(255, 50, 50, alpha * 0.6)
    -- Top-left
    surface.DrawRect(x, y, accLen, 2)
    surface.DrawRect(x, y, 2, accLen)
    -- Top-right
    surface.DrawRect(x + size - accLen, y, accLen, 2)
    surface.DrawRect(x + size - 2, y, 2, accLen)
    -- Bottom-left
    surface.DrawRect(x, y + size - 2, accLen, 2)
    surface.DrawRect(x, y + size - accLen, 2, accLen)
    -- Bottom-right
    surface.DrawRect(x + size - accLen, y + size - 2, accLen, 2)
    surface.DrawRect(x + size - 2, y + size - accLen, 2, accLen)
end)
