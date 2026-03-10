--[[
    Manhunt - Client Vehicle Beacon
    Shows a pulsing marker on the ground with countdown when vehicle beacon is thrown
]]

Manhunt.VehicleBeacon = {
    active = false,
    pos = Vector(0, 0, 0),
    startTime = 0,
    countdown = 3,
}

-- Receive beacon placement from server
net.Receive("Manhunt_VehicleBeacon", function()
    Manhunt.VehicleBeacon.pos = net.ReadVector()
    Manhunt.VehicleBeacon.countdown = net.ReadFloat()
    Manhunt.VehicleBeacon.startTime = CurTime()
    Manhunt.VehicleBeacon.active = true

    surface.PlaySound("ambient/machines/thumper_startup1.wav")
end)

-- Draw the 3D beacon marker in the world
hook.Add("PostDrawTranslucentRenderables", "Manhunt_VehicleBeaconDraw", function()
    if not Manhunt.VehicleBeacon.active then return end

    local elapsed = CurTime() - Manhunt.VehicleBeacon.startTime
    local countdown = Manhunt.VehicleBeacon.countdown

    if elapsed >= countdown + 1 then
        Manhunt.VehicleBeacon.active = false
        return
    end

    local pos = Manhunt.VehicleBeacon.pos
    local remaining = math.max(0, countdown - elapsed)
    local pulse = math.abs(math.sin(CurTime() * 4))

    -- Pulsing ring on the ground
    local ringRadius = 80 + pulse * 20
    local alpha = elapsed < countdown and 200 or math.max(0, 200 - (elapsed - countdown) * 400)
    local color = Color(50, 150, 255, alpha)

    -- Draw ring using cam.Start3D2D
    local ang = Angle(0, 0, 0)
    cam.Start3D2D(pos + Vector(0, 0, 2), ang, 1)
        -- Outer ring
        local segments = 48
        for i = 1, segments do
            local a1 = math.rad((i - 1) / segments * 360)
            local a2 = math.rad(i / segments * 360)

            local x1, y1 = math.cos(a1) * ringRadius, math.sin(a1) * ringRadius
            local x2, y2 = math.cos(a2) * ringRadius, math.sin(a2) * ringRadius

            surface.SetDrawColor(color)
            surface.DrawLine(x1, y1, x2, y2)

            -- Inner ring (smaller, brighter)
            local innerR = ringRadius * 0.5
            local ix1, iy1 = math.cos(a1) * innerR, math.sin(a1) * innerR
            local ix2, iy2 = math.cos(a2) * innerR, math.sin(a2) * innerR
            surface.SetDrawColor(50, 200, 255, alpha * 0.7)
            surface.DrawLine(ix1, iy1, ix2, iy2)
        end

        -- Center cross
        local crossSize = 15
        surface.SetDrawColor(255, 255, 255, alpha)
        surface.DrawLine(-crossSize, 0, crossSize, 0)
        surface.DrawLine(0, -crossSize, 0, crossSize)

        -- Countdown number
        if remaining > 0 then
            local countText = tostring(math.ceil(remaining))
            draw.SimpleText(countText, "Manhunt_HUD_Countdown", 0, -150, Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            draw.SimpleText("!", "Manhunt_HUD_Title", 0, -100, Color(50, 255, 50, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    cam.End3D2D()

    -- Vertical beam of light
    local beamHeight = 500
    local beamAlpha = alpha * 0.3
    render.SetColorMaterial()

    local topPos = pos + Vector(0, 0, beamHeight)
    render.DrawBeam(pos + Vector(0, 0, 5), topPos, 8, 0, 1, Color(50, 150, 255, beamAlpha))
    render.DrawBeam(pos + Vector(0, 0, 5), topPos, 20, 0, 1, Color(50, 150, 255, beamAlpha * 0.3))
end)

-- HUD indicator showing beacon location
hook.Add("HUDPaint", "Manhunt_VehicleBeaconHUD", function()
    if not Manhunt.VehicleBeacon.active then return end

    local elapsed = CurTime() - Manhunt.VehicleBeacon.startTime
    local countdown = Manhunt.VehicleBeacon.countdown
    local remaining = math.max(0, countdown - elapsed)

    if elapsed >= countdown + 1 then
        Manhunt.VehicleBeacon.active = false
        return
    end

    local sw, sh = ScrW(), ScrH()

    -- Top center notification
    if remaining > 0 then
        local pulse = math.abs(math.sin(CurTime() * 4))
        draw.RoundedBox(6, sw / 2 - 150, 70, 300, 40, Color(20, 40, 60, 200))
        draw.SimpleText("VEHICLE INCOMING: " .. math.ceil(remaining) .. "s", "Manhunt_HUD_Medium", sw / 2, 90, Color(50 + pulse * 100, 150 + pulse * 50, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        draw.RoundedBox(6, sw / 2 - 120, 70, 240, 40, Color(20, 50, 20, 200))
        draw.SimpleText("VEHICLE SPAWNED!", "Manhunt_HUD_Medium", sw / 2, 90, Color(50, 255, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)
