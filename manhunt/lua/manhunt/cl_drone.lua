--[[
    Manhunt - Client Drone Camera
    Bird's eye view camera controlled with WASD
    Hunters use this to scout for the fugitive from above
    Includes thermal vision to highlight players
]]

Manhunt.Drone = Manhunt.Drone or {
    active = false,
    startTime = 0,
    duration = 15,
    deployPos = Vector(0, 0, 0),
    camPos = Vector(0, 0, 0),     -- Current XY position of drone
    camHeight = 1500,             -- Current height (adjustable)
    maxRange = 4000,
    speed = 1600,
    fov = 90,
    thermalOn = true,             -- Thermal vision toggle
}

local DRONE_HEIGHT_DEFAULT = 1500
local DRONE_HEIGHT_MIN = 200
local DRONE_HEIGHT_MAX = 3000
local DRONE_SPEED = 1600
local DRONE_VERTICAL_SPEED = 800
local DRONE_MAX_RANGE = 4000

-- Receive drone activation from server
net.Receive("Manhunt_DroneActivate", function()
    local deployPos = net.ReadVector()
    local duration = net.ReadFloat()

    Manhunt.Drone.active = true
    Manhunt.Drone.startTime = CurTime()
    Manhunt.Drone.duration = duration
    Manhunt.Drone.deployPos = deployPos
    Manhunt.Drone.camPos = Vector(deployPos.x, deployPos.y, 0)
    Manhunt.Drone.camHeight = DRONE_HEIGHT_DEFAULT

    surface.PlaySound("buttons/blip2.wav")
end)

net.Receive("Manhunt_DroneDeactivate", function()
    Manhunt.Drone.active = false
end)

-- Override camera to drone view
hook.Add("CalcView", "Manhunt_DroneView", function(ply, pos, angles, fov)
    if not Manhunt.Drone.active then return end

    local elapsed = CurTime() - Manhunt.Drone.startTime
    if elapsed > Manhunt.Drone.duration then
        Manhunt.Drone.active = false
        return
    end

    -- Move drone camera with WASD (client-side prediction)
    local moveSpeed = DRONE_SPEED * FrameTime()
    local vertSpeed = DRONE_VERTICAL_SPEED * FrameTime()
    
    -- Use yaw for horizontal movement direction
    local forward = Angle(0, angles.y, 0):Forward()
    local right = Angle(0, angles.y, 0):Right()

    if input.IsKeyDown(KEY_W) then
        Manhunt.Drone.camPos = Manhunt.Drone.camPos + Vector(forward.x, forward.y, 0) * moveSpeed
    end
    if input.IsKeyDown(KEY_S) then
        Manhunt.Drone.camPos = Manhunt.Drone.camPos - Vector(forward.x, forward.y, 0) * moveSpeed
    end
    if input.IsKeyDown(KEY_D) then
        Manhunt.Drone.camPos = Manhunt.Drone.camPos + Vector(right.x, right.y, 0) * moveSpeed
    end
    if input.IsKeyDown(KEY_A) then
        Manhunt.Drone.camPos = Manhunt.Drone.camPos - Vector(right.x, right.y, 0) * moveSpeed
    end
    
    -- Vertical movement: Space = up, Ctrl = down
    if input.IsKeyDown(KEY_SPACE) then
        Manhunt.Drone.camHeight = Manhunt.Drone.camHeight + vertSpeed
    end
    if input.IsKeyDown(KEY_LCONTROL) then
        Manhunt.Drone.camHeight = Manhunt.Drone.camHeight - vertSpeed
    end
    
    -- Clamp height
    Manhunt.Drone.camHeight = math.Clamp(Manhunt.Drone.camHeight, DRONE_HEIGHT_MIN, DRONE_HEIGHT_MAX)

    -- Clamp to max range from deploy position
    local offset = Manhunt.Drone.camPos - Vector(Manhunt.Drone.deployPos.x, Manhunt.Drone.deployPos.y, 0)
    if offset:Length() > DRONE_MAX_RANGE then
        offset = offset:GetNormalized() * DRONE_MAX_RANGE
        Manhunt.Drone.camPos = Vector(Manhunt.Drone.deployPos.x, Manhunt.Drone.deployPos.y, 0) + offset
    end

    -- Calculate world position
    local droneWorldPos = Vector(Manhunt.Drone.camPos.x, Manhunt.Drone.camPos.y, Manhunt.Drone.deployPos.z + Manhunt.Drone.camHeight)

    -- Slight sway for realism
    local swayX = math.sin(CurTime() * 0.8) * 3
    local swayY = math.cos(CurTime() * 1.1) * 2

    return {
        origin = droneWorldPos + Vector(swayX, swayY, 0),
        angles = Angle(angles.p, angles.y, 0),  -- Free mouse look (pitch + yaw)
        fov = 90,
        drawviewer = true,
    }
end)

-- Block movement during drone (but allow ATTACK2 for cancel)
hook.Add("CreateMove", "Manhunt_DroneBlockMove", function(cmd)
    if not Manhunt.Drone.active then return end
    cmd:ClearMovement()
    -- Keep ATTACK2 so SecondaryAttack (cancel) still works
    local buttons = cmd:GetButtons()
    cmd:ClearButtons()
    if bit.band(buttons, IN_ATTACK2) ~= 0 then
        cmd:SetButtons(IN_ATTACK2)
    end
end)

-- Toggle thermal vision with R key, cancel drone with Backspace
hook.Add("PlayerButtonDown", "Manhunt_DroneThermalToggle", function(ply, button)
    if not Manhunt.Drone.active then return end
    if button == KEY_R then
        Manhunt.Drone.thermalOn = not Manhunt.Drone.thermalOn
        surface.PlaySound(Manhunt.Drone.thermalOn and "buttons/blip1.wav" or "buttons/button15.wav")
    end
    if button == KEY_BACKSPACE then
        -- Force a secondary attack next frame to cancel the drone
        Manhunt.Drone._forceCancel = true
    end
end)

-- Inject ATTACK2 when Backspace cancel is requested
hook.Add("CreateMove", "Manhunt_DroneBackspaceCancel", function(cmd)
    if Manhunt.Drone._forceCancel then
        Manhunt.Drone._forceCancel = false
        cmd:SetButtons(bit.bor(cmd:GetButtons(), IN_ATTACK2))
    end
end)

-- Thermal vision: draw colored halos around players
hook.Add("PreDrawHalos", "Manhunt_DroneThermal", function()
    if not Manhunt.Drone.active then return end
    if not Manhunt.Drone.thermalOn then return end

    local me = LocalPlayer()
    local targets = {}
    local friendlies = {}

    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            if Manhunt.GetPlayerTeam and Manhunt.GetPlayerTeam(ply) == Manhunt.TEAM_FUGITIVE then
                table.insert(targets, ply)
            else
                table.insert(friendlies, ply)
            end
        end
    end

    -- Also add vehicles for thermal detection
    for _, veh in ipairs(ents.FindByClass("prop_vehicle_*")) do
        if IsValid(veh) and IsValid(veh:GetDriver()) then
            table.insert(targets, veh)
        end
    end

    -- Fugitive = bright red/orange thermal signature (big glow)
    if #targets > 0 then
        halo.Add(targets, Color(255, 60, 20), 6, 6, 3, true, true)
    end
    -- Hunters/friendlies = blue thermal signature
    if #friendlies > 0 then
        halo.Add(friendlies, Color(30, 120, 255), 4, 4, 2, true, true)
    end
end)

-- Draw drone HUD overlay
hook.Add("HUDPaint", "Manhunt_DroneHUD", function()
    if not Manhunt.Drone.active then return end

    local sw, sh = ScrW(), ScrH()
    local elapsed = CurTime() - Manhunt.Drone.startTime
    local remaining = math.max(0, Manhunt.Drone.duration - elapsed)

    if remaining <= 0 then
        Manhunt.Drone.active = false
        return
    end

    -- Drone frame overlay
    -- Corner brackets
    local bracketLen = 60
    local bracketThick = 2
    local margin = 40
    local bracketColor = Color(0, 180, 255, 200)

    surface.SetDrawColor(bracketColor)
    -- Top-left
    surface.DrawRect(margin, margin, bracketLen, bracketThick)
    surface.DrawRect(margin, margin, bracketThick, bracketLen)
    -- Top-right
    surface.DrawRect(sw - margin - bracketLen, margin, bracketLen, bracketThick)
    surface.DrawRect(sw - margin - bracketThick, margin, bracketThick, bracketLen)
    -- Bottom-left
    surface.DrawRect(margin, sh - margin - bracketThick, bracketLen, bracketThick)
    surface.DrawRect(margin, sh - margin - bracketLen, bracketThick, bracketLen)
    -- Bottom-right
    surface.DrawRect(sw - margin - bracketLen, sh - margin - bracketThick, bracketLen, bracketThick)
    surface.DrawRect(sw - margin - bracketThick, sh - margin - bracketLen, bracketThick, bracketLen)

    -- Crosshair (center dot + thin lines)
    local cx, cy = sw / 2, sh / 2
    surface.SetDrawColor(0, 180, 255, 150)
    surface.DrawRect(cx - 15, cy, 12, 1)
    surface.DrawRect(cx + 4, cy, 12, 1)
    surface.DrawRect(cx, cy - 15, 1, 12)
    surface.DrawRect(cx, cy + 4, 1, 12)
    draw.RoundedBox(2, cx - 2, cy - 2, 4, 4, Color(0, 200, 255, 200))

    -- Grid overlay (subtle)
    surface.SetDrawColor(0, 150, 255, 10)
    for gx = margin, sw - margin, 80 do
        surface.DrawLine(gx, margin, gx, sh - margin)
    end
    for gy = margin, sh - margin, 80 do
        surface.DrawLine(margin, gy, sw - margin, gy)
    end

    -- Timer bar at top
    local barW = 300
    local barH = 6
    local barX = (sw - barW) / 2
    local barY = margin + 15

    local fraction = remaining / Manhunt.Drone.duration
    local timerColor = remaining < 1.5 and Color(255, 60, 60) or Color(0, 180, 255)

    draw.RoundedBox(3, barX - 1, barY - 1, barW + 2, barH + 2, Color(0, 0, 0, 180))
    draw.RoundedBox(2, barX, barY, barW * fraction, barH, timerColor)

    -- "RECON DRONE" header
    draw.SimpleText("RECON DRONE", "Manhunt_HUD_Medium", sw / 2, margin - 2, Color(0, 180, 255, 220), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

    -- Time remaining
    draw.SimpleText(string.format("%.1fs", remaining), "Manhunt_HUD_Small", sw / 2, barY + barH + 5, Color(200, 200, 200, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

    -- Range indicator
    local offset = Manhunt.Drone.camPos - Vector(Manhunt.Drone.deployPos.x, Manhunt.Drone.deployPos.y, 0)
    local rangeFrac = offset:Length() / DRONE_MAX_RANGE
    local rangeColor = rangeFrac > 0.8 and Color(255, 100, 50) or Color(0, 180, 255)
    draw.SimpleText("Range: " .. math.floor(rangeFrac * 100) .. "%", "Manhunt_HUD_Small", margin + 5, sh - margin - 5, rangeColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)

    -- Controls hint
    local thermalStatus = Manhunt.Drone.thermalOn and "ON" or "OFF"
    draw.SimpleText("[WASD] Move  |  [Space/Ctrl] Up/Down  |  [Mouse] Look  |  [R] Thermal: " .. thermalStatus .. "  |  [Right Click/Backspace] Cancel", "Manhunt_HUD_Small", sw / 2, sh - margin - 5, Color(150, 150, 150, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

    -- Altitude indicator (dynamic)
    draw.SimpleText("ALT: " .. math.floor(Manhunt.Drone.camHeight) .. "u", "Manhunt_HUD_Small", sw - margin - 5, sh - margin - 5, Color(0, 180, 255, 150), TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)

    -- Scanline effect (subtle)
    local scanY = margin + (CurTime() * 100 % (sh - margin * 2))
    surface.SetDrawColor(0, 180, 255, 8)
    surface.DrawRect(margin, margin + scanY, sw - margin * 2, 2)

    -- Thermal vision overlay tint
    if Manhunt.Drone.thermalOn then
        -- Subtle green/cyan tint like thermal imaging
        surface.SetDrawColor(0, 40, 30, 25)
        surface.DrawRect(margin, margin, sw - margin * 2, sh - margin * 2)

        -- Thermal indicator
        draw.SimpleText("THERMAL", "Manhunt_HUD_Small", sw - margin - 5, margin + 5, Color(0, 255, 100, 200), TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

        -- Draw player markers with distance labels on screen
        local me = LocalPlayer()
        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                local plyPos = ply:GetPos() + Vector(0, 0, 50)
                local screenPos = plyPos:ToScreen()
                if screenPos.visible then
                    local isFugitive = Manhunt.GetPlayerTeam and Manhunt.GetPlayerTeam(ply) == Manhunt.TEAM_FUGITIVE
                    local markerColor = isFugitive and Color(255, 60, 20, 220) or Color(30, 150, 255, 180)
                    local label = isFugitive and "TARGET" or "FRIENDLY"

                    -- Pulsing diamond marker
                    local pulse = math.abs(math.sin(CurTime() * 3)) * 4
                    local size = 8 + pulse

                    -- Draw diamond shape
                    local sx, sy = screenPos.x, screenPos.y
                    surface.SetDrawColor(markerColor)
                    for d = -size, size do
                        local w = size - math.abs(d)
                        surface.DrawRect(sx - w, sy + d, w * 2, 1)
                    end

                    -- Outline box
                    surface.SetDrawColor(markerColor.r, markerColor.g, markerColor.b, 100)
                    surface.DrawOutlinedRect(sx - 20, sy - 25, 40, 50, 1)

                    -- Label + distance
                    local dist = math.floor(me:GetPos():Distance(ply:GetPos()))
                    draw.SimpleText(label, "Manhunt_HUD_Small", sx, sy - 30, markerColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
                    draw.SimpleText(dist .. "u", "Manhunt_HUD_Small", sx, sy + 28, Color(200, 200, 200, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                end
            end
        end
    end

    -- Pulsing "low time" warning
    if remaining < 2 then
        local pulse = math.abs(math.sin(CurTime() * 6))
        surface.SetDrawColor(255, 50, 50, pulse * 40)
        surface.DrawRect(margin, margin, sw - margin * 2, sh - margin * 2)
    end

    -- Vignette effect
    surface.SetDrawColor(0, 0, 0, 60)
    surface.DrawRect(0, 0, sw * 0.03, sh)
    surface.DrawRect(sw * 0.97, 0, sw * 0.03, sh)
    surface.DrawRect(0, 0, sw, sh * 0.03)
    surface.DrawRect(0, sh * 0.97, sw, sh * 0.03)
end)
