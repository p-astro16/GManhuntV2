--[[
    Manhunt - Client Zone System
    Renders the shrinking zone circle on the ground
    Shows warning effects when player is outside the zone
]]

Manhunt.Zone = Manhunt.Zone or {}

Manhunt.Zone.Active = false
Manhunt.Zone.Center = Vector(0, 0, 0)
Manhunt.Zone.StartRadius = 0
Manhunt.Zone.EndRadius = 0
Manhunt.Zone.StartTime = 0
Manhunt.Zone.GraceTime = 15
Manhunt.Zone.ShrinkDuration = 120

-- Get current radius (client-side prediction)
function Manhunt.Zone.GetCurrentRadius()
    if not Manhunt.Zone.Active then return Manhunt.Zone.StartRadius end
    
    local elapsed = CurTime() - Manhunt.Zone.StartTime
    
    -- Grace period: zone visible at full size
    if elapsed < Manhunt.Zone.GraceTime then
        return Manhunt.Zone.StartRadius
    end
    
    -- Shrink phase
    local shrinkElapsed = elapsed - Manhunt.Zone.GraceTime
    local frac = math.Clamp(shrinkElapsed / Manhunt.Zone.ShrinkDuration, 0, 1)
    
    return Lerp(frac, Manhunt.Zone.StartRadius, Manhunt.Zone.EndRadius)
end

-- Is the local player outside the zone?
function Manhunt.Zone.IsOutside()
    if not Manhunt.Zone.Active then return false end
    
    local ply = LocalPlayer()
    if not IsValid(ply) then return false end
    
    local plyPos = Vector(ply:GetPos().x, ply:GetPos().y, 0)
    local center = Vector(Manhunt.Zone.Center.x, Manhunt.Zone.Center.y, 0)
    local dist = plyPos:Distance(center)
    
    return dist > Manhunt.Zone.GetCurrentRadius()
end

-- Receive zone sync from server
net.Receive("Manhunt_ZoneSync", function()
    local active = net.ReadBool()
    
    if not active then
        Manhunt.Zone.Active = false
        return
    end
    
    Manhunt.Zone.Active = true
    Manhunt.Zone.Center = net.ReadVector()
    Manhunt.Zone.StartRadius = net.ReadFloat()
    Manhunt.Zone.EndRadius = net.ReadFloat()
    Manhunt.Zone.StartTime = net.ReadFloat()
    Manhunt.Zone.ShrinkDuration = net.ReadFloat()
    Manhunt.Zone.GraceTime = net.ReadFloat()
end)

-- ============================================================
-- 3D ZONE RING
-- ============================================================

local CIRCLE_SEGMENTS = 128
local wallMat = Material("models/debug/debugwhite")

hook.Add("PostDrawTranslucentRenderables", "Manhunt_ZoneDraw", function()
    if not Manhunt.Zone.Active then return end
    
    local radius = Manhunt.Zone.GetCurrentRadius()
    local center = Manhunt.Zone.Center
    
    -- Only draw if close enough to see (performance)
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local distToCenter = ply:GetPos():Distance(center)
    if distToCenter > radius + 8000 then return end
    
    local wallHeight = 1500
    local time = CurTime()
    local pulse = math.abs(math.sin(time * 2)) * 0.3 + 0.7
    
    -- Bright red/orange wall color - very visible
    local wallAlpha = 120 * pulse
    local wallColor = Color(255, 40, 20, wallAlpha)
    local wallColorTop = Color(255, 80, 30, wallAlpha * 0.4)
    local groundColor = Color(255, 30, 20, 100 * pulse)
    
    -- Calculate circle points and cache ground Z
    local points = {}
    for i = 0, CIRCLE_SEGMENTS do
        local angle = (i / CIRCLE_SEGMENTS) * math.pi * 2
        local x = center.x + math.cos(angle) * radius
        local y = center.y + math.sin(angle) * radius
        
        local tr = util.TraceLine({
            start = Vector(x, y, center.z + 5000),
            endpos = Vector(x, y, center.z - 5000),
            mask = MASK_SOLID_BRUSHONLY,
        })
        
        local groundZ = tr.HitPos and tr.HitPos.z or center.z
        points[i] = { x = x, y = y, z = groundZ }
    end
    
    -- Draw thick glowing wall
    render.SetMaterial(wallMat)
    
    for i = 1, CIRCLE_SEGMENTS do
        local p1 = points[i - 1]
        local p2 = points[i]
        
        local bot1 = Vector(p1.x, p1.y, p1.z - 50)
        local bot2 = Vector(p2.x, p2.y, p2.z - 50)
        local mid1 = Vector(p1.x, p1.y, p1.z + wallHeight * 0.4)
        local mid2 = Vector(p2.x, p2.y, p2.z + wallHeight * 0.4)
        local top1 = Vector(p1.x, p1.y, p1.z + wallHeight)
        local top2 = Vector(p2.x, p2.y, p2.z + wallHeight)
        
        -- Bottom half (brighter)
        render.DrawQuad(bot1, bot2, mid2, mid1, wallColor)
        -- Top half (fades out)
        render.DrawQuad(mid1, mid2, top2, top1, wallColorTop)
    end
    
    -- Draw thick ground ring (inner + outer bands)
    for band = -2, 2 do
        local bandR = radius + band * 25
        if bandR <= 0 then continue end
        local innerR = bandR - 15
        local outerR = bandR + 15
        local bandAlpha = band == 0 and groundColor.a or (groundColor.a * 0.5)
        
        for i = 1, CIRCLE_SEGMENTS do
            local a1 = ((i - 1) / CIRCLE_SEGMENTS) * math.pi * 2
            local a2 = (i / CIRCLE_SEGMENTS) * math.pi * 2
            
            local z = points[i] and points[i].z + 5 or center.z + 5
            
            render.DrawQuad(
                Vector(center.x + math.cos(a1) * innerR, center.y + math.sin(a1) * innerR, z),
                Vector(center.x + math.cos(a1) * outerR, center.y + math.sin(a1) * outerR, z),
                Vector(center.x + math.cos(a2) * outerR, center.y + math.sin(a2) * outerR, z),
                Vector(center.x + math.cos(a2) * innerR, center.y + math.sin(a2) * innerR, z),
                Color(groundColor.r, groundColor.g, groundColor.b, bandAlpha)
            )
        end
    end
    
    -- Animated scan line going up the wall
    local scanY = (time % 3) / 3 -- 0 to 1 over 3 seconds
    local scanHeight = wallHeight * scanY
    local scanColor = Color(255, 255, 100, 180 * pulse)
    
    for i = 1, CIRCLE_SEGMENTS do
        local p1 = points[i - 1]
        local p2 = points[i]
        
        local s1 = Vector(p1.x, p1.y, p1.z + scanHeight)
        local s2 = Vector(p2.x, p2.y, p2.z + scanHeight)
        local s3 = Vector(p2.x, p2.y, p2.z + scanHeight + 40)
        local s4 = Vector(p1.x, p1.y, p1.z + scanHeight + 40)
        
        render.DrawQuad(s1, s2, s3, s4, scanColor)
    end
end)

-- ============================================================
-- HUD WARNING WHEN OUTSIDE ZONE
-- ============================================================

hook.Add("HUDPaint", "Manhunt_ZoneHUD", function()
    if not Manhunt.Zone.Active then return end
    
    local sw, sh = ScrW(), ScrH()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    
    local radius = Manhunt.Zone.GetCurrentRadius()
    local center = Manhunt.Zone.Center
    local plyPos = Vector(ply:GetPos().x, ply:GetPos().y, 0)
    local centerFlat = Vector(center.x, center.y, 0)
    local dist = plyPos:Distance(centerFlat)
    
    -- Shrinking indicator (always visible during zone)
    local elapsed = CurTime() - Manhunt.Zone.StartTime
    local graceTime = Manhunt.Zone.GraceTime or 15
    local shrinkDuration = Manhunt.Zone.ShrinkDuration or 120
    
    local inGrace = elapsed < graceTime
    local shrinkFrac = 0
    if not inGrace then
        shrinkFrac = math.Clamp((elapsed - graceTime) / shrinkDuration, 0, 1)
    end
    
    if inGrace then
        -- Grace period countdown: zone hasn't started shrinking yet
        local graceRemaining = math.ceil(graceTime - elapsed)
        local barW = 240
        local barH = 8
        local barX = sw / 2 - barW / 2
        local barY = 10
        local graceFrac = elapsed / graceTime
        local pulse = math.abs(math.sin(CurTime() * 3)) * 0.3 + 0.7
        
        draw.RoundedBox(3, barX - 1, barY - 1, barW + 2, barH + 2, Color(0, 0, 0, 150))
        draw.RoundedBox(2, barX, barY, barW, barH, Color(40, 40, 20, 180))
        draw.RoundedBox(2, barX, barY, barW * (1 - graceFrac), barH, Color(255, 200, 50, 200 * pulse))
        draw.SimpleText("ZONE CLOSING IN " .. graceRemaining .. "s", "Manhunt_HUD_Small", sw / 2, barY + barH + 4, Color(255, 200, 50, 200 * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    elseif shrinkFrac < 1 then
        -- Shrink phase progress bar (top center)
        local barW = 200
        local barH = 6
        local barX = sw / 2 - barW / 2
        local barY = 10
        
        draw.RoundedBox(3, barX - 1, barY - 1, barW + 2, barH + 2, Color(0, 0, 0, 150))
        draw.RoundedBox(2, barX, barY, barW, barH, Color(40, 20, 20, 180))
        draw.RoundedBox(2, barX, barY, barW * (1 - shrinkFrac), barH, Color(255, 60, 60, 200))
        draw.SimpleText("ZONE SHRINKING", "Manhunt_HUD_Small", sw / 2, barY + barH + 4, Color(255, 80, 80, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
    
    -- Outside zone warning
    if dist > radius then
        local overFrac = math.Clamp((dist - radius) / (radius * 0.5), 0, 1)
        local pulse = math.abs(math.sin(CurTime() * 4))
        local alpha = Lerp(overFrac, 80, 200) * pulse
        
        -- Red vignette
        surface.SetDrawColor(255, 0, 0, alpha * 0.4)
        surface.DrawRect(0, 0, sw, sh * 0.15)
        surface.DrawRect(0, sh * 0.85, sw, sh * 0.15)
        surface.DrawRect(0, 0, sw * 0.1, sh)
        surface.DrawRect(sw * 0.9, 0, sw * 0.1, sh)
        
        -- Warning text
        local warningAlpha = 150 + pulse * 105
        draw.SimpleText("⚠ OUTSIDE PLAY ZONE ⚠", "Manhunt_HUD_Large", sw / 2 + 2, sh * 0.2 + 2, Color(0, 0, 0, warningAlpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        draw.SimpleText("⚠ OUTSIDE PLAY ZONE ⚠", "Manhunt_HUD_Large", sw / 2, sh * 0.2, Color(255, 50, 50, warningAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        
        draw.SimpleText("Return to the zone or take damage!", "Manhunt_HUD_Small", sw / 2, sh * 0.2 + 35, Color(255, 150, 150, warningAlpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        
        -- Direction arrow toward zone center
        local toCenterDir = (centerFlat - plyPos):GetNormalized()
        local ang = math.deg(math.atan2(toCenterDir.y, toCenterDir.x))
        local eyeAng = ply:EyeAngles().y
        local relAngle = math.NormalizeAngle(ang - eyeAng)
        
        local arrowX = sw / 2 + math.sin(math.rad(relAngle)) * 120
        local arrowY = sh * 0.2 + 80 - math.cos(math.rad(relAngle)) * 40
        
        draw.SimpleText("▼", "Manhunt_HUD_Large", arrowX, arrowY, Color(255, 80, 80, warningAlpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end)

-- ============================================================
-- SIEGE-STYLE ZONE ALERT (ping enemy location when outside zone)
-- ============================================================

Manhunt.Zone.Alerts = Manhunt.Zone.Alerts or {}

net.Receive("Manhunt_ZoneAlert", function()
    local pos = net.ReadVector()
    local name = net.ReadString()
    
    table.insert(Manhunt.Zone.Alerts, {
        pos = pos,
        name = name,
        time = CurTime(),
        duration = 4, -- visible for 4 seconds
    })
    
    -- Alert sound
    surface.PlaySound("buttons/blip1.wav")
end)

-- Draw zone alert pings (3D markers visible through walls)
hook.Add("HUDPaint", "Manhunt_ZoneAlerts", function()
    local sw, sh = ScrW(), ScrH()
    local now = CurTime()
    
    -- Clean up expired alerts
    for i = #Manhunt.Zone.Alerts, 1, -1 do
        if now - Manhunt.Zone.Alerts[i].time > Manhunt.Zone.Alerts[i].duration then
            table.remove(Manhunt.Zone.Alerts, i)
        end
    end
    
    for _, alert in ipairs(Manhunt.Zone.Alerts) do
        local elapsed = now - alert.time
        local frac = elapsed / alert.duration
        local alpha = 255 * (1 - frac)
        local pulse = math.abs(math.sin(now * 5)) * 0.3 + 0.7
        
        local screenPos = alert.pos:ToScreen()
        
        if screenPos.visible then
            -- Red ping marker
            local size = 20 + math.sin(now * 4) * 5
            
            -- Outer glow ring (expanding)
            local ringSize = 15 + elapsed * 30
            local ringAlpha = alpha * 0.3
            surface.SetDrawColor(255, 40, 40, ringAlpha)
            for r = ringSize - 2, ringSize + 2 do
                local segments = 32
                for s = 0, segments - 1 do
                    local a1 = (s / segments) * math.pi * 2
                    local a2 = ((s + 1) / segments) * math.pi * 2
                    surface.DrawLine(
                        screenPos.x + math.cos(a1) * r, screenPos.y + math.sin(a1) * r,
                        screenPos.x + math.cos(a2) * r, screenPos.y + math.sin(a2) * r
                    )
                end
            end
            
            -- Diamond marker
            draw.NoTexture()
            surface.SetDrawColor(255, 40, 40, alpha * pulse)
            local sx, sy = screenPos.x, screenPos.y
            for d = -size, size do
                local w = size - math.abs(d)
                surface.DrawRect(sx - w, sy + d, w * 2, 1)
            end
            
            -- Inner dot
            draw.RoundedBox(4, sx - 4, sy - 4, 8, 8, Color(255, 255, 255, alpha))
            
            -- Name label
            draw.SimpleText(alert.name, "Manhunt_HUD_Small", sx, sy - size - 8, Color(255, 60, 60, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
            draw.SimpleText("OUTSIDE ZONE", "Manhunt_HUD_Small", sx, sy + size + 4, Color(255, 100, 100, alpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
        else
            -- Off-screen: draw edge indicator
            local ply = LocalPlayer()
            if not IsValid(ply) then continue end
            
            local toAlert = (alert.pos - ply:GetPos()):GetNormalized()
            local eyeAng = ply:EyeAngles().y
            local ang = math.deg(math.atan2(toAlert.y, toAlert.x))
            local relAngle = math.rad(math.NormalizeAngle(ang - eyeAng))
            
            local edgeX = sw / 2 + math.sin(relAngle) * (sw / 2 - 50)
            local edgeY = sh / 2 - math.cos(relAngle) * (sh / 2 - 50)
            edgeX = math.Clamp(edgeX, 30, sw - 30)
            edgeY = math.Clamp(edgeY, 30, sh - 30)
            
            -- Red arrow on edge of screen
            draw.RoundedBox(4, edgeX - 8, edgeY - 8, 16, 16, Color(255, 40, 40, alpha * pulse))
            draw.SimpleText("!", "Manhunt_HUD_Small", edgeX, edgeY, Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end)

-- ============================================================
-- ZONE PRE-ANNOUNCEMENT (1 min before zone spawns)
-- ============================================================

Manhunt.Zone.Announcement = nil

-- Get compass direction from player to a target position
local function GetCompassDir(fromPos, toPos)
    local dx = toPos.x - fromPos.x
    local dy = toPos.y - fromPos.y
    local angle = math.deg(math.atan2(dy, dx))
    if angle < 0 then angle = angle + 360 end
    
    if angle >= 337.5 or angle < 22.5 then return "EAST", "E" end
    if angle >= 22.5 and angle < 67.5 then return "NORTHEAST", "NE" end
    if angle >= 67.5 and angle < 112.5 then return "NORTH", "N" end
    if angle >= 112.5 and angle < 157.5 then return "NORTHWEST", "NW" end
    if angle >= 157.5 and angle < 202.5 then return "WEST", "W" end
    if angle >= 202.5 and angle < 247.5 then return "SOUTHWEST", "SW" end
    if angle >= 247.5 and angle < 292.5 then return "SOUTH", "S" end
    if angle >= 292.5 and angle < 337.5 then return "SOUTHEAST", "SE" end
    return "UNKNOWN", "?"
end

-- Compass arrow rotation table (angle from north, clockwise)
local compassAngles = {
    N = 0, NE = 45, E = 90, SE = 135,
    S = 180, SW = 225, W = 270, NW = 315,
}

net.Receive("Manhunt_ZoneAnnounce", function()
    local zoneCenter = net.ReadVector()
    
    Manhunt.Zone.Announcement = {
        center = zoneCenter,
        time = CurTime(),
        duration = 60, -- show for 60 seconds (until zone actually spawns)
    }
    
    -- Play announcement sound
    surface.PlaySound("buttons/button17.wav")
    
    -- Also play a warning beep after a short delay
    timer.Simple(0.3, function()
        surface.PlaySound("ambient/alarms/warningbell1.wav")
    end)
end)

-- Draw zone announcement HUD
hook.Add("HUDPaint", "Manhunt_ZoneAnnouncement", function()
    local ann = Manhunt.Zone.Announcement
    if not ann then return end
    
    local elapsed = CurTime() - ann.time
    if elapsed > ann.duration then
        Manhunt.Zone.Announcement = nil
        return
    end
    
    -- Cancel once zone is actually active
    if Manhunt.Zone.Active then
        Manhunt.Zone.Announcement = nil
        return
    end
    
    local ply = LocalPlayer()
    if not IsValid(ply) then return end
    
    local sw, sh = ScrW(), ScrH()
    local remaining = math.ceil(ann.duration - elapsed)
    local pulse = math.abs(math.sin(CurTime() * 2)) * 0.3 + 0.7
    local fadeIn = math.Clamp(elapsed / 1, 0, 1)
    local alpha = 255 * fadeIn
    
    -- Get compass direction from player to zone center
    local plyPos = Vector(ply:GetPos().x, ply:GetPos().y, 0)
    local dirFull, dirShort = GetCompassDir(plyPos, ann.center)
    local dist = plyPos:Distance(Vector(ann.center.x, ann.center.y, 0))
    local distText = dist >= 1000 and string.format("%.1fk", dist / 1000) or math.floor(dist)
    
    -- Background panel
    local panelW = 320
    local panelH = 90
    local panelX = sw / 2 - panelW / 2
    local panelY = sh * 0.12
    
    draw.RoundedBox(8, panelX, panelY, panelW, panelH, Color(20, 20, 30, 200 * pulse * fadeIn))
    draw.RoundedBox(6, panelX + 2, panelY + 2, panelW - 4, panelH - 4, Color(40, 30, 50, 150 * fadeIn))
    
    -- Title
    draw.SimpleText("⚠ ZONE INCOMING ⚠", "Manhunt_HUD_Medium", sw / 2, panelY + 16, Color(255, 80, 80, alpha * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    
    -- Compass direction + distance
    draw.SimpleText(dirFull .. " — " .. distText .. " units away", "Manhunt_HUD_Small", sw / 2, panelY + 40, Color(255, 220, 100, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    
    -- Countdown
    local mins = math.floor(remaining / 60)
    local secs = remaining % 60
    draw.SimpleText(string.format("Activating in %d:%02d", mins, secs), "Manhunt_HUD_Small", sw / 2, panelY + 60, Color(200, 200, 255, alpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    
    -- Compass arrow pointing toward zone (relative to player's eye angle)
    local toZone = (Vector(ann.center.x, ann.center.y, 0) - plyPos):GetNormalized()
    local ang = math.deg(math.atan2(toZone.y, toZone.x))
    local eyeAng = ply:EyeAngles().y
    local relAngle = math.rad(math.NormalizeAngle(ang - eyeAng))
    
    local arrowDist = 55
    local arrowX = sw / 2 + math.sin(relAngle) * arrowDist
    local arrowY = panelY + panelH + 25 - math.cos(relAngle) * 15
    
    -- Arrow circle background
    draw.RoundedBox(20, sw / 2 - 25, panelY + panelH + 5, 50, 40, Color(30, 30, 40, 180 * fadeIn))
    
    -- Directional dot
    surface.SetDrawColor(255, 100, 100, alpha * pulse)
    for dx = -3, 3 do
        for dy = -3, 3 do
            if dx * dx + dy * dy <= 9 then
                surface.DrawRect(arrowX + dx, arrowY + dy, 1, 1)
            end
        end
    end
    
    -- Center dot (you are here)
    surface.SetDrawColor(100, 200, 255, alpha * 0.6)
    for dx = -2, 2 do
        for dy = -2, 2 do
            if dx * dx + dy * dy <= 4 then
                surface.DrawRect(sw / 2 + dx, panelY + panelH + 25 + dy, 1, 1)
            end
        end
    end
end)

-- ============================================================
-- MINIMAP ZONE CIRCLE (on the ping/radar if it exists)
-- ============================================================

-- Clean up zone on game end
hook.Add("Manhunt_PhaseChanged", "Manhunt_ZoneReset", function(phase)
    if phase == Manhunt.PHASE_IDLE or phase == Manhunt.PHASE_ENDGAME or phase == Manhunt.PHASE_LOBBY then
        Manhunt.Zone.Active = false
        Manhunt.Zone.Announcement = nil
    end
end)

print("[Manhunt] cl_zone.lua loaded")
