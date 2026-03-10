--[[
    Manhunt - Client Pickup System
    Shows markers for weapon and ammo pickups on the HUD
    Weapon: yellow marker with gun icon, visible through walls
    Ammo: smaller blue marker
]]

Manhunt.Pickups = Manhunt.Pickups or {}
Manhunt.Pickups.Markers = {}

-- Receive weapon spawn notification (now given directly to inventory)
net.Receive("Manhunt_WeaponSpawn", function()
    local pos = net.ReadVector()
    local weaponClass = net.ReadString()
    
    -- No map marker needed - weapon goes straight to inventory
    -- Just show the big notification
    surface.PlaySound("items/suitchargeok1.wav")
    
    Manhunt.Pickups._weaponNotify = CurTime()
end)

-- Receive ammo spawn notification
net.Receive("Manhunt_AmmoSpawn", function()
    local pos = net.ReadVector()
    
    table.insert(Manhunt.Pickups.Markers, {
        pos = pos,
        type = "ammo",
        time = CurTime(),
    })
    
    surface.PlaySound("items/ammo_pickup.wav")
    
    Manhunt.Pickups._ammoNotify = CurTime()
end)

-- Receive pickup collected (remove marker)
net.Receive("Manhunt_PickupCollected", function()
    local pos = net.ReadVector()
    
    for i = #Manhunt.Pickups.Markers, 1, -1 do
        if Manhunt.Pickups.Markers[i].pos:Distance(pos) < 100 then
            table.remove(Manhunt.Pickups.Markers, i)
            break
        end
    end
end)

-- Draw 3D markers for pickups (visible through walls)
hook.Add("HUDPaint", "Manhunt_PickupMarkers", function()
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:Alive() then return end
    
    local sw, sh = ScrW(), ScrH()
    local now = CurTime()
    local eyePos = ply:EyePos()
    
    for _, marker in ipairs(Manhunt.Pickups.Markers) do
        local markerPos = marker.pos + Vector(0, 0, 40)
        local dist = eyePos:Distance(marker.pos)
        local screenPos = markerPos:ToScreen()
        
        local isWeapon = marker.type == "weapon"
        local baseColor = isWeapon and Color(255, 200, 50) or Color(80, 180, 255)
        local pulse = math.abs(math.sin(now * 3)) * 0.3 + 0.7
        local newAlpha = isWeapon and 240 or 200
        
        -- Spawn animation (fade in + scale up)
        local age = now - marker.time
        local spawnFrac = math.Clamp(age / 0.5, 0, 1)
        local scale = Lerp(spawnFrac, 0.3, 1)
        
        if screenPos.visible then
            local sx, sy = screenPos.x, screenPos.y
            
            if isWeapon then
                -- Weapon marker: large golden diamond + label
                local size = 16 * scale
                
                -- Pulsing outer glow
                local glowSize = size + 8 + math.sin(now * 4) * 4
                draw.RoundedBox(8, sx - glowSize, sy - glowSize, glowSize * 2, glowSize * 2, Color(255, 200, 50, 30 * pulse))
                
                -- Diamond shape
                draw.NoTexture()
                surface.SetDrawColor(baseColor.r, baseColor.g, baseColor.b, newAlpha * pulse)
                for d = -size, size do
                    local w = size - math.abs(d)
                    surface.DrawRect(sx - w, sy + d, w * 2, 1)
                end
                
                -- Inner bright dot
                draw.RoundedBox(4, sx - 4, sy - 4, 8, 8, Color(255, 255, 255, 230))
                
                -- Labels
                draw.SimpleText("WEAPON", "Manhunt_HUD_Small", sx, sy - size - 12, Color(255, 220, 80, newAlpha * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
                
                local distText = math.floor(dist / 52.5) .. "m" -- Convert units to approximate meters
                draw.SimpleText(distText, "Manhunt_HUD_Small", sx, sy + size + 4, Color(200, 200, 200, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
                
                -- Vertical beam effect
                surface.SetDrawColor(255, 200, 50, 40 * pulse)
                surface.DrawRect(sx - 1, sy - 60, 2, 120)
            else
                -- Ammo marker: smaller blue marker
                local size = 10 * scale
                
                draw.RoundedBox(4, sx - size, sy - size, size * 2, size * 2, Color(baseColor.r, baseColor.g, baseColor.b, 60 * pulse))
                draw.RoundedBox(3, sx - size + 2, sy - size + 2, (size - 2) * 2, (size - 2) * 2, Color(baseColor.r, baseColor.g, baseColor.b, newAlpha * pulse * 0.5))
                draw.RoundedBox(2, sx - 3, sy - 3, 6, 6, Color(255, 255, 255, 200))
                
                draw.SimpleText("AMMO", "Manhunt_HUD_Small", sx, sy - size - 6, Color(80, 180, 255, 180 * pulse), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
                
                local distText = math.floor(dist / 52.5) .. "m"
                draw.SimpleText(distText, "Manhunt_HUD_Small", sx, sy + size + 2, Color(180, 180, 180, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
        else
            -- Off-screen: edge indicator
            local toMarker = (marker.pos - ply:GetPos()):GetNormalized()
            local eyeAng = ply:EyeAngles().y
            local ang = math.deg(math.atan2(toMarker.y, toMarker.x))
            local relAngle = math.rad(math.NormalizeAngle(ang - eyeAng))
            
            local edgeX = sw / 2 + math.sin(relAngle) * (sw / 2 - 60)
            local edgeY = sh / 2 - math.cos(relAngle) * (sh / 2 - 60)
            edgeX = math.Clamp(edgeX, 40, sw - 40)
            edgeY = math.Clamp(edgeY, 40, sh - 40)
            
            local edgeColor = isWeapon and Color(255, 200, 50, 200 * pulse) or Color(80, 180, 255, 150 * pulse)
            local edgeSize = isWeapon and 12 or 8
            
            -- Arrow/indicator on screen edge
            draw.RoundedBox(edgeSize / 2, edgeX - edgeSize / 2, edgeY - edgeSize / 2, edgeSize, edgeSize, edgeColor)
            local label = isWeapon and "WEAPON" or "AMMO"
            draw.SimpleText(label, "Manhunt_HUD_Small", edgeX, edgeY - edgeSize, edgeColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
        end
    end
    
    -- Big notification when weapon first spawns
    if Manhunt.Pickups._weaponNotify then
        local age = now - Manhunt.Pickups._weaponNotify
        if age < 5 then
            local alpha = age < 4 and 255 or (255 * (5 - age))
            local scale = age < 0.3 and Lerp(age / 0.3, 2, 1) or 1
            
            draw.SimpleText("WEAPON RECEIVED!", "Manhunt_HUD_Large", sw / 2 + 2, sh * 0.35 + 2, Color(0, 0, 0, alpha * 0.7), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("WEAPON RECEIVED!", "Manhunt_HUD_Large", sw / 2, sh * 0.35, Color(255, 220, 50, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("The fugitive can now fight back!", "Manhunt_HUD_Small", sw / 2, sh * 0.35 + 35, Color(255, 200, 100, alpha * 0.8), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            Manhunt.Pickups._weaponNotify = nil
        end
    end
    
    -- Ammo notification
    if Manhunt.Pickups._ammoNotify then
        local age = now - Manhunt.Pickups._ammoNotify
        if age < 3 then
            local alpha = age < 2 and 200 or (200 * (3 - age))
            draw.SimpleText("Ammo has spawned on the map!", "Manhunt_HUD_Small", sw / 2, sh * 0.4, Color(80, 180, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            Manhunt.Pickups._ammoNotify = nil
        end
    end
end)

-- Clean up on game end
hook.Add("Manhunt_PhaseChanged", "Manhunt_PickupsReset", function(phase)
    if phase == Manhunt.PHASE_IDLE or phase == Manhunt.PHASE_ENDGAME or phase == Manhunt.PHASE_LOBBY then
        Manhunt.Pickups.Markers = {}
    end
end)

print("[Manhunt] cl_pickups.lua loaded")
