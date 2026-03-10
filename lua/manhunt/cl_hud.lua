--[[
    Manhunt - Client HUD
    Timer bar, charges indicator, team display, spawn protection, freeze indicator
]]

Manhunt.SpawnProtected = false
Manhunt.LocalFrozen = false

-- Fonts
surface.CreateFont("Manhunt_HUD_Large", {
    font = "Roboto",
    size = 36,
    weight = 700,
    antialias = true,
})

surface.CreateFont("Manhunt_HUD_Medium", {
    font = "Roboto",
    size = 24,
    weight = 600,
    antialias = true,
})

surface.CreateFont("Manhunt_HUD_Small", {
    font = "Roboto",
    size = 18,
    weight = 500,
    antialias = true,
})

surface.CreateFont("Manhunt_HUD_Title", {
    font = "Roboto",
    size = 48,
    weight = 800,
    antialias = true,
})

surface.CreateFont("Manhunt_HUD_Countdown", {
    font = "Roboto",
    size = 120,
    weight = 900,
    antialias = true,
})

local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", mins, secs)
end

hook.Add("HUDPaint", "Manhunt_HUD", function()
    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local team = Manhunt.GetPlayerTeam(ply)
    if team == Manhunt.TEAM_NONE and not Manhunt.TestMode and Manhunt.Phase ~= Manhunt.PHASE_ENDGAME then return end

    local sw, sh = ScrW(), ScrH()

    -- Countdown phase is handled by cl_lobby.lua

    -- Active game HUD
    if Manhunt.Phase == Manhunt.PHASE_ACTIVE then
        Manhunt.DrawTimerBar(sw, sh)
        Manhunt.DrawTeamIndicator(sw, sh, team)
        Manhunt.DrawChargesIndicator(sw, sh, ply)
        Manhunt.DrawFreezeOverlay(sw, sh)
        Manhunt.DrawSpawnProtection(sw, sh)
        Manhunt.DrawLastTenPercent(sw, sh)

        -- Test mode indicator
        if Manhunt.TestMode then
            local pulse = math.abs(math.sin(CurTime() * 2))
            draw.SimpleText("TEST MODE", "Manhunt_HUD_Medium", sw / 2, 55, Color(100, 150, 255, 155 + pulse * 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        end
    end
end)

-- Draw timer bar at top of screen
function Manhunt.DrawTimerBar(sw, sh)
    local barW = sw * 0.4
    local barH = 30
    local barX = (sw - barW) / 2
    local barY = 15

    local remaining = Manhunt.GetRemainingTime()
    local total = Manhunt.GetTotalGameTime()
    local fraction = total > 0 and (remaining / total) or 0

    -- Background
    draw.RoundedBox(6, barX - 2, barY - 2, barW + 4, barH + 4, Color(0, 0, 0, 200))

    -- Bar fill
    local barColor = Color(50, 200, 50)
    if fraction < 0.25 then
        barColor = Color(255, 50, 50)
    elseif fraction < 0.5 then
        barColor = Color(255, 200, 50)
    end

    if Manhunt.IsLastTenPercent() then
        -- Pulsing red in last 10%
        local pulse = math.abs(math.sin(CurTime() * 4))
        barColor = Color(255, 50 * pulse, 50 * pulse)
    elseif Manhunt.EndgameActive then
        -- Orange pulsing during endgame
        local pulse = math.abs(math.sin(CurTime() * 3))
        barColor = Color(255, 150 + pulse * 50, 50)
    end

    draw.RoundedBox(4, barX, barY, barW * fraction, barH, barColor)

    -- Time text
    draw.SimpleText(FormatTime(remaining), "Manhunt_HUD_Medium", sw / 2, barY + barH / 2, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Last 10% warning / Endgame indicator
    if Manhunt.IsLastTenPercent() then
        local pulse = math.abs(math.sin(CurTime() * 3))
        draw.SimpleText("FINAL PHASE", "Manhunt_HUD_Small", sw / 2, barY + barH + 8, Color(255, 50, 50, 155 + pulse * 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    elseif Manhunt.EndgameActive then
        local pulse = math.abs(math.sin(CurTime() * 2))
        draw.SimpleText("ENDGAME", "Manhunt_HUD_Small", sw / 2, barY + barH + 8, Color(255, 180, 50, 155 + pulse * 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end

    -- Next scan countdown
    if Manhunt.NextScanTime and Manhunt.NextScanTime > 0 then
        local nextScanIn = math.max(0, math.ceil(Manhunt.NextScanTime - CurTime()))
        local scanY = barY + barH + ((Manhunt.IsLastTenPercent() or Manhunt.EndgameActive) and 28 or 8)
        local scanText = "Next Scan: " .. FormatTime(nextScanIn)
        local scanAlpha = 180
        if nextScanIn <= 10 then
            local pulse = math.abs(math.sin(CurTime() * 4))
            scanAlpha = 180 + pulse * 75
        end
        draw.SimpleText(scanText, "Manhunt_HUD_Small", sw / 2, scanY, Color(50, 200, 255, scanAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end

-- Draw team indicator
function Manhunt.DrawTeamIndicator(sw, sh, team)
    local teamName = Manhunt.GetTeamName(team)
    local teamColor = Manhunt.GetTeamColor(team)

    local x = sw - 20
    local y = 20

    draw.SimpleText(teamName, "Manhunt_HUD_Medium", x, y, teamColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
end

-- Draw charges indicator for scanner weapon
function Manhunt.DrawChargesIndicator(sw, sh, ply)
    if not IsValid(ply) then return end

    local scannerCharges = 0
    local carbombCharges = 0
    local decoyAvailable = not ply:GetNWBool("ManhuntDecoyUsed", false)

    -- Get scanner charges
    local scanner = ply:GetWeapon("weapon_manhunt_scanner")
    if IsValid(scanner) then
        scannerCharges = scanner:GetNWInt("ManhuntCharges", 0)
    end

    -- Get carbomb charges (fugitive only)
    local carbomb = ply:GetWeapon("weapon_manhunt_carbomb")
    if IsValid(carbomb) then
        carbombCharges = carbomb:GetNWInt("ManhuntCharges", 0)
    end

    local x = sw - 20
    local y = 50
    local team = Manhunt.GetPlayerTeam(ply)

    -- Scanner charges
    local scanColor = scannerCharges > 0 and Color(100, 200, 255) or Color(100, 100, 100)
    draw.SimpleText("Scanner: " .. scannerCharges, "Manhunt_HUD_Small", x, y, scanColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    y = y + 22

    -- Fugitive-specific items (always show in test mode)
    if team == Manhunt.TEAM_FUGITIVE or Manhunt.TestMode then
        local bombColor = carbombCharges > 0 and Color(255, 100, 50) or Color(100, 100, 100)
        draw.SimpleText("Car Bomb: " .. carbombCharges, "Manhunt_HUD_Small", x, y, bombColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
        y = y + 22

        local decoyColor = decoyAvailable and Color(200, 200, 50) or Color(100, 100, 100)
        draw.SimpleText("Decoy: " .. (decoyAvailable and "1" or "0"), "Manhunt_HUD_Small", x, y, decoyColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
    end
end

-- Draw freeze overlay for hunters
function Manhunt.DrawFreezeOverlay(sw, sh)
    if not Manhunt.LocalFrozen then return end

    -- Vignette / frozen effect
    surface.SetDrawColor(100, 150, 255, 30)
    surface.DrawRect(0, 0, sw, sh)

    -- Border effect
    local borderSize = 4
    surface.SetDrawColor(100, 150, 255, 150)
    surface.DrawRect(0, 0, sw, borderSize)
    surface.DrawRect(0, sh - borderSize, sw, borderSize)
    surface.DrawRect(0, 0, borderSize, sh)
    surface.DrawRect(sw - borderSize, 0, borderSize, sh)

    draw.SimpleText("FROZEN - Waiting for interval...", "Manhunt_HUD_Large", sw / 2, sh / 2, Color(100, 200, 255, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Draw spawn protection indicator
function Manhunt.DrawSpawnProtection(sw, sh)
    if not Manhunt.SpawnProtected then return end

    local pulse = math.abs(math.sin(CurTime() * 5))
    surface.SetDrawColor(50, 255, 50, 20 + pulse * 30)
    surface.DrawRect(0, 0, sw, sh)

    draw.SimpleText("SPAWN PROTECTION", "Manhunt_HUD_Medium", sw / 2, sh - 80, Color(50, 255, 50, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Draw last 10% warning flash / endgame edge pulse
function Manhunt.DrawLastTenPercent(sw, sh)
    if Manhunt.IsLastTenPercent() then
        -- Red screen edge pulse in last 10%
        local pulse = math.abs(math.sin(CurTime() * 2)) * 0.3
        surface.SetDrawColor(255, 0, 0, pulse * 30)
        surface.DrawRect(0, 0, sw, 3)
        surface.DrawRect(0, sh - 3, sw, 3)
    elseif Manhunt.EndgameActive then
        -- Orange screen edge pulse during endgame
        local pulse = math.abs(math.sin(CurTime() * 1.5)) * 0.2
        surface.SetDrawColor(255, 150, 0, pulse * 20)
        surface.DrawRect(0, 0, sw, 2)
        surface.DrawRect(0, sh - 2, sw, 2)
    end
end

-- Audio cue handler
-- Track looping sounds so we can stop them
Manhunt.ActiveLoopSounds = Manhunt.ActiveLoopSounds or {}

-- Stop all active looping sounds
function Manhunt.StopAllLoopSounds()
    for _, sndObj in ipairs(Manhunt.ActiveLoopSounds) do
        if sndObj and sndObj:IsPlaying() then
            sndObj:Stop()
        end
    end
    Manhunt.ActiveLoopSounds = {}
end

-- Sounds that are looping and need to be stoppable
local loopingSounds = {
    fugitive_wins = true,
}

hook.Add("Manhunt_AudioCue", "Manhunt_PlayAudio", function(cueType)
    -- Use GMod built-in sounds
    local sounds = {
        countdown = "buttons/button17.wav",
        game_start = "ambient/alarms/warningbell1.wav",
        hunters_released = "ambient/alarms/klaxon1.wav",
        scan = "buttons/blip1.wav",
        scan_urgent = "ambient/alarms/apc_alarm2.wav",
        fugitive_wins = "ambient/levels/citadel/field_loop1.wav",
        hunter_wins = "ambient/levels/labs/electric_explosion5.wav",
        decoy_placed = "buttons/button9.wav",
        bomb_placed = "buttons/button14.wav",
        bomb_explode = "ambient/explosions/explode_4.wav",
    }

    local snd = sounds[cueType]
    if snd then
        if loopingSounds[cueType] then
            -- Use CreateSound so we can stop it later
            local lp = LocalPlayer()
            if IsValid(lp) then
                local sndObj = CreateSound(lp, snd)
                if sndObj then
                    sndObj:Play()
                    table.insert(Manhunt.ActiveLoopSounds, sndObj)
                end
            end
        else
            surface.PlaySound(snd)
        end
    end
end)

-- Airstrike target marker with countdown
local airstrikeMarker = nil

net.Receive("Manhunt_AirstrikeMarker", function()
    local pos = net.ReadVector()
    local countdown = net.ReadFloat()
    airstrikeMarker = { pos = pos, time = CurTime(), countdown = countdown, duration = countdown + 2 }

    -- Play local alarm sound
    surface.PlaySound("ambient/alarms/klaxon1.wav")
end)

hook.Add("HUDPaint", "Manhunt_AirstrikeMarker", function()
    if not airstrikeMarker then return end
    local elapsed = CurTime() - airstrikeMarker.time
    if elapsed > airstrikeMarker.duration then
        airstrikeMarker = nil
        return
    end

    local remaining = math.max(0, airstrikeMarker.countdown - elapsed)
    local exploded = elapsed >= airstrikeMarker.countdown

    local screenPos = airstrikeMarker.pos:ToScreen()
    if not screenPos.visible then
        -- Still show warning text at top of screen even if marker not visible
        if not exploded then
            local pulse = math.abs(math.sin(CurTime() * 6))
            local sw = ScrW()
            draw.RoundedBox(6, sw / 2 - 160, 70, 320, 45, Color(150, 20, 20, 200))
            draw.SimpleText("AIRSTRIKE INCOMING: " .. string.format("%.1f", remaining) .. "s", "Manhunt_HUD_Large", sw / 2, 92, Color(255, 50 + pulse * 150, 50, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
        return
    end

    local x, y = screenPos.x, screenPos.y

    if exploded then
        -- Flash effect after explosion
        local postTime = elapsed - airstrikeMarker.countdown
        local alpha = math.max(0, 255 * (1 - postTime / 2))
        surface.SetDrawColor(255, 200, 50, alpha * 0.3)
        surface.DrawRect(0, 0, ScrW(), ScrH())
        return
    end

    -- Pulsing danger zone circle
    local pulse = math.abs(math.sin(CurTime() * 6))
    local size = 35 + pulse * 15
    local alpha = 200 + pulse * 55

    -- Outer danger ring
    surface.SetDrawColor(255, 30, 30, alpha)
    for i = 0, 360, 5 do
        local r1, r2 = math.rad(i), math.rad(i + 5)
        surface.DrawLine(x + math.cos(r1) * size, y + math.sin(r1) * size, x + math.cos(r2) * size, y + math.sin(r2) * size)
    end

    -- Inner ring
    local s2 = size * 0.5
    for i = 0, 360, 5 do
        local r1, r2 = math.rad(i), math.rad(i + 5)
        surface.DrawLine(x + math.cos(r1) * s2, y + math.sin(r1) * s2, x + math.cos(r2) * s2, y + math.sin(r2) * s2)
    end

    -- Cross
    surface.DrawLine(x - size, y, x + size, y)
    surface.DrawLine(x, y - size, x, y + size)

    -- Countdown number at the marker
    draw.SimpleText(string.format("%.1f", remaining), "Manhunt_HUD_Title", x, y - size - 15, Color(255, 50, 50, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    draw.SimpleText("AIRSTRIKE", "Manhunt_HUD_Small", x, y + size + 5, Color(255, 50, 50, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    -- Warning banner at top of screen
    local sw = ScrW()
    local urgency = 1 - (remaining / airstrikeMarker.countdown)
    local bannerR = math.floor(150 + urgency * 105)
    draw.RoundedBox(6, sw / 2 - 160, 70, 320, 45, Color(bannerR, 20, 20, 200))
    draw.SimpleText("AIRSTRIKE INCOMING: " .. string.format("%.1f", remaining) .. "s", "Manhunt_HUD_Large", sw / 2, 92, Color(255, 50 + pulse * 150, 50, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

-- ============================================================
-- ENDGAME PHASE HUD
-- ============================================================

-- Endgame announcement
local endgameFlashTime = nil

net.Receive("Manhunt_EndgameTrigger", function()
    Manhunt.EndgameActive = true
    endgameFlashTime = CurTime()
    surface.PlaySound("ambient/alarms/klaxon1.wav")
end)

-- Endgame announcement overlay (flashes when triggered)
hook.Add("HUDPaint", "Manhunt_EndgameAnnouncement", function()
    if not endgameFlashTime then return end

    local elapsed = CurTime() - endgameFlashTime
    if elapsed > 5 then
        endgameFlashTime = nil
        return
    end

    local sw, sh = ScrW(), ScrH()
    local alpha = math.max(0, 255 * (1 - elapsed / 5))

    -- Red screen flash
    if elapsed < 0.5 then
        local flashAlpha = math.max(0, 80 * (1 - elapsed / 0.5))
        surface.SetDrawColor(255, 0, 0, flashAlpha)
        surface.DrawRect(0, 0, sw, sh)
    end

    -- Big "ENDGAME" text
    local pulse = math.abs(math.sin(CurTime() * 4))
    local textAlpha = alpha * (0.7 + pulse * 0.3)
    draw.SimpleText("ENDGAME", "Manhunt_HUD_Countdown", sw / 2, sh * 0.35, Color(255, 50, 50, textAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText("Intervals halved  •  Car destroyed  •  Scans recharged", "Manhunt_HUD_Medium", sw / 2, sh * 0.35 + 70, Color(255, 200, 200, textAlpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end)

-- Persistent endgame indicator (subtle, replaces "FINAL PHASE" text)
-- This is handled in DrawTimerBar already by checking IsEndgamePhase

-- Vehicle countdown (car about to explode)
local vehicleCountdown = nil

net.Receive("Manhunt_VehicleCountdown", function()
    local pos = net.ReadVector()
    local countdown = net.ReadFloat()
    vehicleCountdown = { pos = pos, time = CurTime(), countdown = countdown }
    surface.PlaySound("ambient/alarms/apc_alarm2.wav")
end)

hook.Add("HUDPaint", "Manhunt_VehicleCountdown", function()
    if not vehicleCountdown then return end

    local elapsed = CurTime() - vehicleCountdown.time
    if elapsed > vehicleCountdown.countdown + 2 then
        vehicleCountdown = nil
        return
    end

    local remaining = math.max(0, vehicleCountdown.countdown - elapsed)
    local exploded = elapsed >= vehicleCountdown.countdown

    local screenPos = vehicleCountdown.pos:ToScreen()

    if exploded then
        -- Brief flash after explosion
        local postTime = elapsed - vehicleCountdown.countdown
        local alpha = math.max(0, 200 * (1 - postTime / 2))
        surface.SetDrawColor(255, 150, 0, alpha * 0.2)
        surface.DrawRect(0, 0, ScrW(), ScrH())
        return
    end

    -- Warning banner
    local sw = ScrW()
    local pulse = math.abs(math.sin(CurTime() * 8))
    draw.RoundedBox(6, sw / 2 - 180, 120, 360, 40, Color(200, 100, 0, 220))
    draw.SimpleText("CAR EXPLODING: " .. string.format("%.1f", remaining) .. "s", "Manhunt_HUD_Large", sw / 2, 140, Color(255, 200 + pulse * 55, 50, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Marker on the vehicle
    if screenPos.visible then
        local x, y = screenPos.x, screenPos.y
        local size = 25 + pulse * 10
        surface.SetDrawColor(255, 150, 0, 200 + pulse * 55)
        for i = 0, 360, 5 do
            local r1, r2 = math.rad(i), math.rad(i + 5)
            surface.DrawLine(x + math.cos(r1) * size, y + math.sin(r1) * size, x + math.cos(r2) * size, y + math.sin(r2) * size)
        end
        draw.SimpleText(string.format("%.1f", remaining), "Manhunt_HUD_Title", x, y, Color(255, 200, 50, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)

-- Vehicle respawn marker (visible to ALL players)
local vehicleMarker = nil

net.Receive("Manhunt_VehicleMarker", function()
    local pos = net.ReadVector()
    local active = net.ReadBool()

    if active then
        vehicleMarker = { pos = pos, time = CurTime() }
    else
        vehicleMarker = nil
    end
end)

hook.Add("HUDPaint", "Manhunt_VehicleMarker", function()
    if not vehicleMarker then return end
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then
        vehicleMarker = nil
        return
    end

    local screenPos = vehicleMarker.pos:ToScreen()
    if not screenPos.visible then
        -- Show directional indicator at screen edge
        local sw, sh = ScrW(), ScrH()
        local ply = LocalPlayer()
        if not IsValid(ply) then return end

        local dir = (vehicleMarker.pos - ply:EyePos()):GetNormalized()
        local ang = ply:EyeAngles()
        local forward = ang:Forward()
        local right = ang:Right()

        local dotRight = dir:Dot(right)
        local dotForward = dir:Dot(forward)

        local edgeX = sw / 2 + dotRight * sw / 2
        local edgeY = sh / 2 - dotForward * sh / 2
        edgeX = math.Clamp(edgeX, 40, sw - 40)
        edgeY = math.Clamp(edgeY, 40, sh - 40)

        local pulse = math.abs(math.sin(CurTime() * 3))
        draw.SimpleText("▶ VEHICLE", "Manhunt_HUD_Small", edgeX, edgeY, Color(50, 200, 255, 180 + pulse * 75), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Distance
        local dist = ply:GetPos():Distance(vehicleMarker.pos)
        draw.SimpleText(math.floor(dist / 52.49) .. "m", "Manhunt_HUD_Small", edgeX, edgeY + 20, Color(200, 200, 200, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    local x, y = screenPos.x, screenPos.y
    local pulse = math.abs(math.sin(CurTime() * 2))
    local time = CurTime() - vehicleMarker.time

    -- Light beam going up
    local beamHeight = 150
    surface.SetDrawColor(50, 200, 255, 100 + pulse * 50)
    for i = -2, 2 do
        surface.DrawLine(x + i, y, x + i, y - beamHeight)
    end

    -- Pulsing circle at base
    local size = 20 + pulse * 8
    surface.SetDrawColor(50, 200, 255, 180 + pulse * 75)
    for i = 0, 360, 5 do
        local r1, r2 = math.rad(i), math.rad(i + 5)
        surface.DrawLine(x + math.cos(r1) * size, y + math.sin(r1) * size, x + math.cos(r2) * size, y + math.sin(r2) * size)
    end

    -- Expanding ring animation
    local ringPhase = (time * 0.8) % 1
    local ringSize = size + ringPhase * 30
    local ringAlpha = (1 - ringPhase) * 150
    surface.SetDrawColor(50, 200, 255, ringAlpha)
    for i = 0, 360, 5 do
        local r1, r2 = math.rad(i), math.rad(i + 5)
        surface.DrawLine(x + math.cos(r1) * ringSize, y + math.sin(r1) * ringSize, x + math.cos(r2) * ringSize, y + math.sin(r2) * ringSize)
    end

    -- Diamond icon
    local d = 8
    surface.SetDrawColor(50, 200, 255, 255)
    surface.DrawLine(x, y - d, x + d, y)
    surface.DrawLine(x + d, y, x, y + d)
    surface.DrawLine(x, y + d, x - d, y)
    surface.DrawLine(x - d, y, x, y - d)

    -- Label
    draw.SimpleText("VEHICLE", "Manhunt_HUD_Small", x, y - beamHeight - 5, Color(50, 200, 255, 200 + pulse * 55), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

    -- Distance
    local ply = LocalPlayer()
    if IsValid(ply) then
        local dist = ply:GetPos():Distance(vehicleMarker.pos)
        draw.SimpleText(math.floor(dist / 52.49) .. "m", "Manhunt_HUD_Small", x, y + size + 5, Color(200, 200, 200, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end)
