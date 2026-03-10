--[[
    Manhunt - Client Ping System
    3D world pings/markers that appear during scans (last 10% and hunter scanner)
]]

Manhunt.Pings = {}

local PING_DURATION = 5 -- seconds
local PING_FADE_TIME = 2 -- seconds to fade out

-- Receive ping from server
net.Receive("Manhunt_PingPos", function()
    local pos = net.ReadVector()
    local isFugitive = net.ReadBool()

    table.insert(Manhunt.Pings, {
        pos = pos,
        startTime = CurTime(),
        isFugitive = isFugitive,
        alpha = 255,
    })

    -- Audio
    surface.PlaySound("buttons/blip2.wav")
end)

-- Draw 3D pings in the world
hook.Add("PostDrawTranslucentRenderables", "Manhunt_DrawPings3D", function()
    if #Manhunt.Pings == 0 then return end

    for i = #Manhunt.Pings, 1, -1 do
        local ping = Manhunt.Pings[i]
        local elapsed = CurTime() - ping.startTime

        if elapsed > PING_DURATION then
            table.remove(Manhunt.Pings, i)
            continue
        end

        -- Calculate alpha (fade out in last PING_FADE_TIME seconds)
        local alpha = 255
        if elapsed > PING_DURATION - PING_FADE_TIME then
            alpha = Lerp((elapsed - (PING_DURATION - PING_FADE_TIME)) / PING_FADE_TIME, 255, 0)
        end

        local pos = ping.pos
        local color = ping.isFugitive and Color(50, 150, 255, alpha) or Color(255, 50, 50, alpha)

        -- Draw vertical beam
        local beamHeight = 2000
        render.SetColorMaterial()

        local ply = LocalPlayer()
        if not IsValid(ply) then return end
        local ringSize = 50 + math.sin(CurTime() * 4) * 20
        local eyeAng = ply:EyeAngles()

        cam.Start3D2D(pos + Vector(0, 0, 5), Angle(0, eyeAng.y - 90, 90), 1)
            -- Outer ring
            draw.NoTexture()
            surface.SetDrawColor(color.r, color.g, color.b, alpha * 0.5)

            local segments = 32
            for seg = 0, segments - 1 do
                local a1 = (seg / segments) * math.pi * 2
                local a2 = ((seg + 1) / segments) * math.pi * 2
                surface.DrawPoly({
                    {x = math.cos(a1) * ringSize, y = math.sin(a1) * ringSize},
                    {x = math.cos(a2) * ringSize, y = math.sin(a2) * ringSize},
                    {x = math.cos(a2) * (ringSize - 5), y = math.sin(a2) * (ringSize - 5)},
                    {x = math.cos(a1) * (ringSize - 5), y = math.sin(a1) * (ringSize - 5)},
                })
            end
        cam.End3D2D()

        -- Draw vertical line (beam)
        render.SetColorMaterial()
        render.DrawLine(pos, pos + Vector(0, 0, beamHeight), Color(color.r, color.g, color.b, alpha * 0.3), false)

        -- Draw diamond marker at top
        local markerPos = pos + Vector(0, 0, 200 + math.sin(CurTime() * 2) * 20)
        cam.Start3D2D(markerPos, Angle(0, eyeAng.y - 90, 90), 1)
            surface.SetDrawColor(color.r, color.g, color.b, alpha)
            -- Diamond shape
            local sz = 15
            surface.DrawPoly({
                {x = 0, y = -sz},
                {x = sz, y = 0},
                {x = 0, y = sz},
                {x = -sz, y = 0},
            })
        cam.End3D2D()
    end
end)

-- Draw 2D ping indicators on HUD (screen-space direction arrows for off-screen pings)
hook.Add("HUDPaint", "Manhunt_DrawPings2D", function()
    if #Manhunt.Pings == 0 then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local sw, sh = ScrW(), ScrH()

    for _, ping in ipairs(Manhunt.Pings) do
        local elapsed = CurTime() - ping.startTime
        if elapsed > PING_DURATION then continue end

        local alpha = 255
        if elapsed > PING_DURATION - PING_FADE_TIME then
            alpha = Lerp((elapsed - (PING_DURATION - PING_FADE_TIME)) / PING_FADE_TIME, 255, 0)
        end

        local screenPos = ping.pos:ToScreen()
        local color = ping.isFugitive and Color(50, 150, 255, alpha) or Color(255, 50, 50, alpha)

        -- If on screen, draw distance
        if screenPos.visible then
            local dist = math.Round(ply:GetPos():Distance(ping.pos) * 0.01905) -- to meters
            draw.SimpleText(dist .. "m", "Manhunt_HUD_Small", screenPos.x, screenPos.y - 30, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            -- Off-screen: draw directional arrow on screen edge
            local dir = (ping.pos - ply:GetPos()):GetNormalized()
            local eyeDir = ply:EyeAngles():Forward()

            -- Project direction to screen
            local dot = eyeDir:Dot(dir)
            local right = ply:EyeAngles():Right()
            local rightDot = right:Dot(dir)

            local edgeX = sw / 2 + rightDot * (sw / 2 - 40)
            local edgeY = sh / 2

            if dot < 0 then
                -- Behind the player
                edgeX = sw / 2 + (rightDot > 0 and 1 or -1) * (sw / 2 - 40)
            end

            edgeX = math.Clamp(edgeX, 40, sw - 40)
            edgeY = math.Clamp(edgeY, 40, sh - 40)

            -- Arrow
            local pulse = math.abs(math.sin(CurTime() * 4))
            draw.SimpleText("◆", "Manhunt_HUD_Large", edgeX, edgeY, Color(color.r, color.g, color.b, alpha * (0.5 + pulse * 0.5)), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            local dist = math.Round(ply:GetPos():Distance(ping.pos) * 0.01905)
            draw.SimpleText(dist .. "m", "Manhunt_HUD_Small", edgeX, edgeY + 25, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end)
