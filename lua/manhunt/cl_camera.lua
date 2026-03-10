--[[
    Manhunt - Client Camera System
    GTA V-style surveillance camera (bird's eye → 360° pan)
    Renders in top-left corner for hunters during interval scans
]]

Manhunt.Camera = {
    active = false,
    startTime = 0,
    duration = 5, -- seconds
    targetPos = Vector(0, 0, 0),
    inVehicle = false,
    vehicleDir = Vector(0, 0, 0),
    vehicleSpeed = 0,
    isUrgent = false,
    showDecoy = false,
    decoyPos = Vector(0, 0, 0),
    rendering = false,
}

local CAMERA_SIZE = 420 -- pixels (bigger PIP window)
local CAMERA_MARGIN = 20
local CAMERA_HEIGHT_START = 2000
local CAMERA_HEIGHT_END = 64 -- Eye level
local CAMERA_DURATION = 5

-- Render target for the surveillance cam (higher res)
local cameraRT = GetRenderTarget("ManhuntSurveillanceCam", 1024, 1024)
local cameraMat = CreateMaterial("ManhuntCameraMat", "UnlitGeneric", {
    ["$basetexture"] = cameraRT:GetName(),
    ["$nolod"] = 1,
})

-- Receive camera view from server
net.Receive("Manhunt_CameraView", function()
    local pos = net.ReadVector()
    local inVehicle = net.ReadBool()
    local vehDir = net.ReadVector()
    local vehSpeed = net.ReadFloat()
    local isUrgent = net.ReadBool()
    local showDecoy = net.ReadBool()
    local decoyPos = net.ReadVector()

    Manhunt.ActivateCamera(pos, inVehicle, vehDir, vehSpeed, isUrgent, showDecoy, decoyPos)
end)

-- Activate the surveillance camera
function Manhunt.ActivateCamera(pos, inVehicle, vehDir, vehSpeed, isUrgent, showDecoy, decoyPos)
    Manhunt.Camera.active = true
    Manhunt.Camera.startTime = CurTime()
    Manhunt.Camera.targetPos = pos
    Manhunt.Camera.inVehicle = inVehicle
    Manhunt.Camera.vehicleDir = vehDir
    Manhunt.Camera.vehicleSpeed = vehSpeed
    Manhunt.Camera.isUrgent = isUrgent
    Manhunt.Camera.showDecoy = showDecoy
    Manhunt.Camera.decoyPos = decoyPos

    -- Audio feedback
    surface.PlaySound("buttons/blip1.wav")
end

-- Calculate camera position and angle based on animation progress
local function GetCameraTransform(progress, targetPos)
    -- Phase 1 (0-0.85): Descend from bird's eye to eye level while doing a full 360°
    -- Phase 2 (0.85-1.0): Hold at eye level, fade out

    local height, yaw, dist

    if progress < 0.85 then
        -- Full descent + 360° spin
        local t = progress / 0.85
        t = t * t * (3 - 2 * t) -- Smooth ease-in-out
        height = Lerp(t, CAMERA_HEIGHT_START, CAMERA_HEIGHT_END)
        dist = Lerp(t, 600, 120) -- Wide at top, close at eye level
        yaw = t * 360
    else
        -- Hold final position during fade
        height = CAMERA_HEIGHT_END
        dist = 120
        yaw = 360
    end

    local rad = math.rad(yaw)
    local camPos = targetPos + Vector(math.cos(rad) * dist, math.sin(rad) * dist, height)
    local lookAt = targetPos + Vector(0, 0, 64) -- Look at head level
    local camAng = (lookAt - camPos):Angle()

    return camPos, camAng
end

-- Render the surveillance camera to RT
hook.Add("RenderScene", "Manhunt_CameraRender", function()
    if not Manhunt.Camera.active then return end
    if Manhunt.Camera.rendering then return end

    local progress = (CurTime() - Manhunt.Camera.startTime) / CAMERA_DURATION
    if progress >= 1 then
        Manhunt.Camera.active = false
        return
    end

    Manhunt.Camera.rendering = true

    local camPos, camAng = GetCameraTransform(progress, Manhunt.Camera.targetPos)

    render.PushRenderTarget(cameraRT)
    render.Clear(0, 0, 0, 255)
    render.RenderView({
        origin = camPos,
        angles = camAng,
        x = 0,
        y = 0,
        w = 1024,
        h = 1024,
        fov = 100, -- Wide FOV to show more environment
        drawviewmodel = false,
        drawhud = false,
    })
    render.PopRenderTarget()

    Manhunt.Camera.rendering = false
end)

-- Draw the camera feed on screen
hook.Add("HUDPaint", "Manhunt_CameraDraw", function()
    if not Manhunt.Camera.active then return end

    local progress = (CurTime() - Manhunt.Camera.startTime) / CAMERA_DURATION
    if progress >= 1 then
        Manhunt.Camera.active = false
        return
    end

    -- Calculate alpha (fade in and out)
    local alpha = 255
    if progress < 0.05 then
        alpha = Lerp(progress / 0.05, 0, 255)
    elseif progress > 0.9 then
        alpha = Lerp((progress - 0.9) / 0.1, 255, 0)
    end

    local x = CAMERA_MARGIN
    local y = CAMERA_MARGIN
    local size = CAMERA_SIZE

    -- Background + border
    local borderColor = Manhunt.Camera.isUrgent and Color(255, 50, 50, alpha) or Color(50, 200, 255, alpha)
    draw.RoundedBox(4, x - 3, y - 3, size + 6, size + 6, borderColor)
    draw.RoundedBox(2, x, y, size, size, Color(0, 0, 0, alpha))

    -- Camera feed
    surface.SetDrawColor(255, 255, 255, alpha)
    surface.SetMaterial(cameraMat)
    surface.DrawTexturedRect(x, y, size, size)

    -- Scanline effect
    local scanlineY = y + (CurTime() * 200 % size)
    surface.SetDrawColor(255, 255, 255, 20)
    surface.DrawRect(x, scanlineY, size, 2)

    -- GTA-style "SURVEILLANCE" text
    draw.SimpleText("SURVEILLANCE", "Manhunt_HUD_Small", x + 5, y + 5, Color(255, 255, 255, alpha * 0.8))

    -- Timestamp
    draw.SimpleText(os.date("%H:%M:%S"), "Manhunt_HUD_Small", x + size - 5, y + 5, Color(255, 255, 255, alpha * 0.6), TEXT_ALIGN_RIGHT)

    -- Vehicle info
    if Manhunt.Camera.inVehicle then
        local speedKMH = math.Round(Manhunt.Camera.vehicleSpeed) -- Already in km/h from server
        draw.SimpleText("IN VEHICLE", "Manhunt_HUD_Medium", x + 10, y + size - 60, Color(255, 200, 50, alpha))
        draw.SimpleText(speedKMH .. " km/h", "Manhunt_HUD_Large", x + 10, y + size - 35, Color(255, 200, 50, alpha))

        -- Direction compass
        local dir = Manhunt.Camera.vehicleDir
        if dir:Length() > 0.1 then
            local ang = math.deg(math.atan2(dir.y, dir.x))
            if ang < 0 then ang = ang + 360 end

            local compass = "E"
            if ang >= 337.5 or ang < 22.5 then compass = "E"
            elseif ang < 67.5 then compass = "NE"
            elseif ang < 112.5 then compass = "N"
            elseif ang < 157.5 then compass = "NW"
            elseif ang < 202.5 then compass = "W"
            elseif ang < 247.5 then compass = "SW"
            elseif ang < 292.5 then compass = "S"
            else compass = "SE" end

            draw.SimpleText("HEADING: " .. compass, "Manhunt_HUD_Medium", x + size - 10, y + size - 35, Color(255, 200, 50, alpha), TEXT_ALIGN_RIGHT)
        end
    else
        draw.SimpleText("ON FOOT", "Manhunt_HUD_Medium", x + 10, y + size - 35, Color(180, 180, 180, alpha * 0.7))
    end

    -- Urgent mode indicator
    if Manhunt.Camera.isUrgent then
        local pulse = math.abs(math.sin(CurTime() * 6))
        draw.SimpleText("! FINAL PHASE !", "Manhunt_HUD_Small", x + size / 2, y + size + 5, Color(255, 50, 50, pulse * 255), TEXT_ALIGN_CENTER)
    end

    -- Decoy indicator (show two blips if decoy active)
    if Manhunt.Camera.showDecoy then
        draw.SimpleText("MULTIPLE SIGNALS DETECTED", "Manhunt_HUD_Small", x + size / 2, y + size + 22, Color(255, 255, 50, alpha), TEXT_ALIGN_CENTER)
    end
end)
