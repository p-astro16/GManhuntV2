--[[
    Manhunt - High Speed Chase (Client)
    HUD, ability bar, pickup rendering, effects, warnings
]]

Manhunt.Chase = Manhunt.Chase or {}
Manhunt.Chase.ClientAbilities = {}     -- {abilityId = {charges, cooldownEnd}}
Manhunt.Chase.ClientPickups = {}       -- {idx = {pos, abilityId}}
Manhunt.Chase.ExitWarning = false
Manhunt.Chase.ExitTimeLeft = 0
Manhunt.Chase.StationaryTimeLeft = 0
Manhunt.Chase.TrackerPos = nil
Manhunt.Chase.TrackerActive = false
Manhunt.Chase.VehicleHealthData = {}   -- {steamid = health}
Manhunt.Chase.LastEffect = nil         -- {abilityId, pos, time, ply}
Manhunt.Chase.ChaseActive = false

-- Client-side vehicle helpers (mirrors sv_vehicles.lua)
function Manhunt.GetPlayerVehicle(ply)
    if not IsValid(ply) then return nil end
    if ply:InVehicle() then return ply:GetVehicle() end
    local glideVeh = ply:GetNWEntity("GlideVehicle")
    if IsValid(glideVeh) then return glideVeh end
    return nil
end

function Manhunt.GetVehicleSpeed(ply)
    local veh = Manhunt.GetPlayerVehicle(ply)
    if not IsValid(veh) then return 0 end
    if veh.GetSpeed then return veh:GetSpeed() or 0 end
    local phys = veh:GetPhysicsObject()
    if IsValid(phys) then return phys:GetVelocity():Length() * 0.06858 end
    return 0
end

-- Fonts
surface.CreateFont("Chase_HUD_Large", {
    font = "Roboto", size = 32, weight = 800, antialias = true,
})
surface.CreateFont("Chase_HUD_Medium", {
    font = "Roboto", size = 22, weight = 700, antialias = true,
})
surface.CreateFont("Chase_HUD_Small", {
    font = "Roboto", size = 16, weight = 600, antialias = true,
})
surface.CreateFont("Chase_HUD_Tiny", {
    font = "Roboto", size = 13, weight = 500, antialias = true,
})
surface.CreateFont("Chase_HUD_Huge", {
    font = "Roboto", size = 64, weight = 900, antialias = true,
})
surface.CreateFont("Chase_HUD_Icon", {
    font = "Roboto", size = 26, weight = 900, antialias = true,
})

-- Colors
local COL_BG = Color(0, 0, 0, 180)
local COL_BG_DARK = Color(0, 0, 0, 220)
local COL_WHITE = Color(255, 255, 255)
local COL_RED = Color(255, 50, 50)
local COL_GREEN = Color(50, 255, 50)
local COL_BLUE = Color(50, 150, 255)
local COL_YELLOW = Color(255, 220, 50)
local COL_ORANGE = Color(255, 150, 0)
local COL_GRAY = Color(150, 150, 150)

-- ==========================================
-- NET RECEIVERS
-- ==========================================

-- Chase gamemode sync
net.Receive("Manhunt_ChaseGamemode", function()
    Manhunt.Chase.ChaseActive = net.ReadBool()
    if Manhunt.Chase.ChaseActive then
        Manhunt.Gamemode = Manhunt.GAMEMODE_CHASE
    end
end)

-- Ability sync
net.Receive("Manhunt_ChaseAbilityGrant", function()
    Manhunt.Chase.ClientAbilities = {}
    local count = net.ReadUInt(8)
    for i = 1, count do
        local abilityId = net.ReadUInt(8)
        local charges = net.ReadUInt(8)
        local cooldownEnd = net.ReadFloat()
        Manhunt.Chase.ClientAbilities[abilityId] = {
            charges = charges,
            cooldownEnd = cooldownEnd,
        }
    end
end)

-- Pickup spawn
net.Receive("Manhunt_ChasePickupSpawn", function()
    local idx = net.ReadUInt(8)
    local abilityId = net.ReadUInt(8)
    local pos = net.ReadVector()
    Manhunt.Chase.ClientPickups[idx] = {
        pos = pos,
        abilityId = abilityId,
    }
end)

-- Pickup collected
net.Receive("Manhunt_ChasePickupCollect", function()
    local idx = net.ReadUInt(8)
    local collector = net.ReadEntity()
    local abilityId = net.ReadUInt(8)
    Manhunt.Chase.ClientPickups[idx] = nil
end)

-- Ability effect
net.Receive("Manhunt_ChaseEffect", function()
    local abilityId = net.ReadUInt(8)
    local pos = net.ReadVector()
    local ang = net.ReadAngle()
    local ply = net.ReadEntity()

    Manhunt.Chase.LastEffect = {
        abilityId = abilityId,
        pos = pos,
        ang = ang,
        ply = ply,
        time = CurTime(),
    }

    -- Play ability-specific client effects
    Manhunt.Chase.PlayEffect(abilityId, pos, ang, ply)
end)

-- Exit vehicle warning
net.Receive("Manhunt_ChaseExitWarning", function()
    Manhunt.Chase.ExitWarning = net.ReadBool()
    Manhunt.Chase.ExitTimeLeft = net.ReadFloat()
    Manhunt.Chase.ExitWarningStart = CurTime()
end)

-- Stationary warning
net.Receive("Manhunt_ChaseStationaryWarn", function()
    Manhunt.Chase.StationaryTimeLeft = net.ReadFloat()
end)

-- Tracker position
net.Receive("Manhunt_ChaseTracker", function()
    Manhunt.Chase.TrackerPos = net.ReadVector()
    Manhunt.Chase.TrackerActive = net.ReadBool()
end)

-- Vehicle health
net.Receive("Manhunt_ChaseVehicleHealth", function()
    Manhunt.Chase.VehicleHealthData = {}
    local count = net.ReadUInt(8)
    for i = 1, count do
        local sid = net.ReadString()
        local health = net.ReadFloat()
        Manhunt.Chase.VehicleHealthData[sid] = health
    end
end)

-- ==========================================
-- HUD DRAWING
-- ==========================================

-- Timer bar (top center)
local function FormatTime(seconds)
    seconds = math.max(0, math.floor(seconds))
    local mins = math.floor(seconds / 60)
    local secs = seconds % 60
    return string.format("%02d:%02d", mins, secs)
end

function Manhunt.Chase.DrawTimerBar(sw, sh)
    local barW = sw * 0.4
    local barH = 30
    local barX = (sw - barW) / 2
    local barY = 15

    local remaining = Manhunt.GetRemainingTime()
    local total = Manhunt.GetTotalGameTime()
    local fraction = total > 0 and (remaining / total) or 0

    draw.RoundedBox(6, barX - 2, barY - 2, barW + 4, barH + 4, Color(0, 0, 0, 200))

    local barColor = COL_GREEN
    if fraction < 0.25 then barColor = COL_RED
    elseif fraction < 0.5 then barColor = COL_YELLOW end

    draw.RoundedBox(4, barX, barY, barW * math.Clamp(fraction, 0, 1), barH, barColor)
    draw.SimpleText(FormatTime(remaining), "Chase_HUD_Medium", sw / 2, barY + barH / 2, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- "HIGH SPEED CHASE" label above bar
    draw.SimpleText("HIGH SPEED CHASE", "Chase_HUD_Tiny", sw / 2, barY - 4, COL_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
end

hook.Add("HUDPaint", "Manhunt_ChaseHUD", function()
    if not Manhunt.IsChaseMode() then return end
    if not Manhunt.Chase.ChaseActive then return end
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE and Manhunt.Phase ~= Manhunt.PHASE_COUNTDOWN then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    local sw, sh = ScrW(), ScrH()

    if Manhunt.Phase == Manhunt.PHASE_COUNTDOWN then
        Manhunt.Chase.DrawCountdown(sw, sh)
        return
    end

    -- Active game HUD
    Manhunt.Chase.DrawTimerBar(sw, sh)
    Manhunt.Chase.DrawSpeedometer(sw, sh, ply)
    Manhunt.Chase.DrawAbilityBar(sw, sh, ply)
    Manhunt.Chase.DrawVehicleHealth(sw, sh, ply)
    Manhunt.Chase.DrawGraceIndicator(sw, sh)
    Manhunt.Chase.DrawExitWarning(sw, sh)
    Manhunt.Chase.DrawStationaryWarning(sw, sh)
    Manhunt.Chase.DrawTrackerHUD(sw, sh)
    Manhunt.Chase.DrawTeamLabel(sw, sh, ply)
    Manhunt.Chase.DrawPickupIndicators(sw, sh, ply)

    -- Test mode indicator
    if Manhunt.TestMode then
        local pulse = math.abs(math.sin(CurTime() * 2))
        draw.SimpleText("CHASE TEST MODE", "Chase_HUD_Medium", sw / 2, 55, Color(100, 200, 255, 155 + pulse * 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end)

-- Countdown overlay
function Manhunt.Chase.DrawCountdown(sw, sh)
    local remaining = math.max(0, Manhunt.CountdownEnd - CurTime())
    local seconds = math.ceil(remaining)

    -- Full screen dark overlay
    draw.RoundedBox(0, 0, 0, sw, sh, Color(0, 0, 0, 150))

    -- Title
    draw.SimpleText("HIGH SPEED CHASE", "Chase_HUD_Huge", sw / 2, sh * 0.3, COL_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Countdown number
    local pulse = 1 + math.sin(CurTime() * 8) * 0.1
    local size = 120 * pulse
    draw.SimpleText(tostring(seconds), "Chase_HUD_Huge", sw / 2, sh * 0.5, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Instruction
    draw.SimpleText("GET TO YOUR CAR!", "Chase_HUD_Large", sw / 2, sh * 0.65, COL_YELLOW, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    local team = Manhunt.GetPlayerTeam(LocalPlayer())
    local teamName = team == Manhunt.TEAM_FUGITIVE and "FUGITIVE" or "HUNTER"
    local teamColor = team == Manhunt.TEAM_FUGITIVE and COL_BLUE or COL_RED
    draw.SimpleText("You are the " .. teamName, "Chase_HUD_Medium", sw / 2, sh * 0.72, teamColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Speedometer (bottom center)
function Manhunt.Chase.DrawSpeedometer(sw, sh, ply)
    local speed = Manhunt.GetVehicleSpeed(ply)
    local speedText = math.floor(speed) .. " km/h"

    local x = sw / 2
    local y = sh - 60

    -- Background
    draw.RoundedBox(8, x - 80, y - 20, 160, 45, COL_BG)

    -- Speed text
    local speedColor = COL_WHITE
    if speed > 150 then speedColor = COL_ORANGE end
    if speed > 200 then speedColor = COL_RED end
    draw.SimpleText(speedText, "Chase_HUD_Large", x, y, speedColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Ability bar (bottom center, above speedometer)
function Manhunt.Chase.DrawAbilityBar(sw, sh, ply)
    local abilities = Manhunt.Chase.ClientAbilities
    local abilityList = {}
    for id, data in pairs(abilities) do
        table.insert(abilityList, { id = id, data = data })
    end
    table.sort(abilityList, function(a, b) return a.id < b.id end)

    -- Show "no abilities" message if empty
    if #abilityList == 0 then
        draw.SimpleText("Abilities loading...", "Chase_HUD_Small", sw / 2, sh - 140, COL_YELLOW, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        return
    end

    local slotW = 65
    local slotH = 65
    local gap = 8
    local totalW = #abilityList * (slotW + gap) - gap
    local startX = (sw - totalW) / 2
    local startY = sh - 145

    for i, slot in ipairs(abilityList) do
        local abilityDef = Manhunt.Chase.Abilities[slot.id]
        if not abilityDef then continue end

        local x = startX + (i - 1) * (slotW + gap)
        local y = startY

        local now = CurTime()
        local onCooldown = slot.data.cooldownEnd > now
        local hasCharges = slot.data.charges > 0

        -- Background
        local bgColor = Color(30, 30, 40, 220)
        if onCooldown then
            bgColor = Color(60, 20, 20, 220)
        elseif hasCharges then
            bgColor = Color(20, 40, 20, 220)
        end
        draw.RoundedBox(6, x, y, slotW, slotH, bgColor)

        -- Border (ability color)
        local borderCol = abilityDef.color
        if onCooldown then borderCol = Color(80, 80, 80) end
        surface.SetDrawColor(borderCol)
        surface.DrawOutlinedRect(x, y, slotW, slotH, 2)

        -- Icon letter
        local iconCol = hasCharges and COL_WHITE or COL_GRAY
        draw.SimpleText(abilityDef.icon, "Chase_HUD_Icon", x + slotW / 2, y + 22, iconCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Charges
        if hasCharges then
            draw.SimpleText("x" .. slot.data.charges, "Chase_HUD_Tiny", x + slotW - 5, y + slotH - 5, COL_GREEN, TEXT_ALIGN_RIGHT, TEXT_ALIGN_BOTTOM)
        end

        -- Cooldown overlay
        if onCooldown then
            local cdRemaining = slot.data.cooldownEnd - now
            local cdFraction = math.Clamp(cdRemaining / (abilityDef.cooldown or 10), 0, 1)
            draw.RoundedBox(0, x + 2, y + 2, slotW - 4, (slotH - 4) * cdFraction, Color(0, 0, 0, 150))
            draw.SimpleText(math.ceil(cdRemaining) .. "s", "Chase_HUD_Small", x + slotW / 2, y + slotH / 2 + 10, COL_RED, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        -- Key binding hint
        draw.SimpleText(tostring(i), "Chase_HUD_Tiny", x + 5, y + slotH - 5, Color(180, 180, 180, 150), TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)

        -- Name tooltip on hover (not really hoverable in HUD, so show abbreviated name below)
        local shortName = string.sub(abilityDef.name, 1, 8)
        draw.SimpleText(shortName, "Chase_HUD_Tiny", x + slotW / 2, y + slotH + 5, COL_GRAY, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end

-- Vehicle health bar (top left)
function Manhunt.Chase.DrawVehicleHealth(sw, sh, ply)
    local sid = ply:SteamID()
    local health = Manhunt.Chase.VehicleHealthData[sid] or Manhunt.Chase.MaxVehicleHealth
    local maxHP = Manhunt.Chase.MaxVehicleHealth
    local fraction = math.Clamp(health / maxHP, 0, 1)

    local barW = 200
    local barH = 20
    local x = 20
    local y = 20

    -- Label
    draw.SimpleText("VEHICLE", "Chase_HUD_Small", x, y - 2, COL_WHITE, TEXT_ALIGN_LEFT, TEXT_ALIGN_BOTTOM)

    -- Background
    draw.RoundedBox(4, x, y, barW, barH, Color(30, 30, 30, 200))

    -- Fill
    local healthColor = COL_GREEN
    if fraction < 0.3 then healthColor = COL_RED
    elseif fraction < 0.6 then healthColor = COL_YELLOW end

    draw.RoundedBox(4, x, y, barW * fraction, barH, healthColor)

    -- Text
    draw.SimpleText(math.floor(health) .. " / " .. maxHP, "Chase_HUD_Tiny", x + barW / 2, y + barH / 2, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Grace period indicator (center screen, first 15s)
function Manhunt.Chase.DrawGraceIndicator(sw, sh)
    if not Manhunt.StartTime then return end
    local graceEnd = Manhunt.StartTime + 15
    local remaining = graceEnd - CurTime()
    if remaining <= 0 then return end

    local flash = math.abs(math.sin(CurTime() * 3))
    local alpha = 180 + flash * 75

    draw.SimpleText("GET IN YOUR CAR!", "Chase_HUD_Large", sw / 2, sh * 0.22, Color(50, 255, 50, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(math.ceil(remaining) .. "s", "Chase_HUD_Medium", sw / 2, sh * 0.27, Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Exit vehicle warning (center screen, red flashing)
function Manhunt.Chase.DrawExitWarning(sw, sh)
    if not Manhunt.Chase.ExitWarning then return end

    local elapsed = CurTime() - (Manhunt.Chase.ExitWarningStart or CurTime())
    local timeLeft = math.max(0, Manhunt.Chase.ExitTimeLeft - elapsed)

    local flash = math.abs(math.sin(CurTime() * 6))
    local alpha = 150 + flash * 105

    -- Red vignette
    draw.RoundedBox(0, 0, 0, sw, sh, Color(255, 0, 0, flash * 40))

    -- Warning text
    draw.SimpleText("⚠ GET BACK IN YOUR CAR! ⚠", "Chase_HUD_Large", sw / 2, sh * 0.35, Color(255, 50, 50, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(string.format("%.1fs", timeLeft), "Chase_HUD_Huge", sw / 2, sh * 0.45, Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

-- Stationary warning (center, yellow)
function Manhunt.Chase.DrawStationaryWarning(sw, sh)
    if Manhunt.Chase.StationaryTimeLeft <= 0 then return end

    local flash = math.abs(math.sin(CurTime() * 4))
    local alpha = 180 + flash * 75

    draw.SimpleText("⚠ KEEP MOVING! ⚠", "Chase_HUD_Medium", sw / 2, sh * 0.28, Color(255, 200, 50, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    draw.SimpleText(string.format("%.1fs until elimination", Manhunt.Chase.StationaryTimeLeft), "Chase_HUD_Small", sw / 2, sh * 0.32, Color(255, 255, 255, alpha), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

    -- Reset after displaying (server sends periodic updates)
    Manhunt.Chase.StationaryTimeLeft = math.max(0, Manhunt.Chase.StationaryTimeLeft - FrameTime())
end

-- Tracker HUD (shows fugitive position if tracker dart is active)
function Manhunt.Chase.DrawTrackerHUD(sw, sh)
    if not Manhunt.Chase.TrackerActive or not Manhunt.Chase.TrackerPos then return end

    local ply = LocalPlayer()
    if not IsValid(ply) then return end

    -- Only hunters see this
    local team = Manhunt.GetPlayerTeam(ply)
    if team ~= Manhunt.TEAM_HUNTER and not Manhunt.TestMode then return end

    local scrPos = Manhunt.Chase.TrackerPos:ToScreen()
    if scrPos.visible then
        -- Draw marker
        local pulse = math.abs(math.sin(CurTime() * 3))
        local size = 15 + pulse * 5
        draw.RoundedBox(size, scrPos.x - size, scrPos.y - size, size * 2, size * 2, Color(0, 255, 100, 150 + pulse * 50))
        draw.SimpleText("TRACKED", "Chase_HUD_Tiny", scrPos.x, scrPos.y - size - 10, Color(0, 255, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    else
        -- Off screen: show direction arrow at edge
        local dir = (Manhunt.Chase.TrackerPos - ply:GetPos()):GetNormalized()
        local ang = math.atan2(dir.y, dir.x)
        local edgeX = sw / 2 + math.cos(ang) * (sw / 2 - 50)
        local edgeY = sh / 2 - math.sin(ang) * (sh / 2 - 50)
        edgeX = math.Clamp(edgeX, 30, sw - 30)
        edgeY = math.Clamp(edgeY, 30, sh - 30)

        draw.RoundedBox(8, edgeX - 15, edgeY - 15, 30, 30, Color(0, 255, 100, 200))
        draw.SimpleText("►", "Chase_HUD_Medium", edgeX, edgeY, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
end

-- Team label (top right)
function Manhunt.Chase.DrawTeamLabel(sw, sh, ply)
    local team = Manhunt.GetPlayerTeam(ply)
    local teamName = team == Manhunt.TEAM_FUGITIVE and "FUGITIVE" or "HUNTER"
    local teamColor = team == Manhunt.TEAM_FUGITIVE and COL_BLUE or COL_RED

    draw.SimpleText(teamName, "Chase_HUD_Medium", sw - 20, 20, teamColor, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)

    -- Objective
    local objective = team == Manhunt.TEAM_FUGITIVE
        and "Survive until time runs out!"
        or "Destroy the fugitive's car!"
    draw.SimpleText(objective, "Chase_HUD_Tiny", sw - 20, 45, COL_GRAY, TEXT_ALIGN_RIGHT, TEXT_ALIGN_TOP)
end

-- Pickup indicators (3D world markers)
function Manhunt.Chase.DrawPickupIndicators(sw, sh, ply)
    local myTeam = Manhunt.GetPlayerTeam(ply)

    for idx, pickup in pairs(Manhunt.Chase.ClientPickups) do
        local abilityDef = Manhunt.Chase.Abilities[pickup.abilityId]
        if not abilityDef then continue end

        -- Only show pickups for your team (or both-team pickups)
        if abilityDef.team ~= 0 and abilityDef.team ~= myTeam and not Manhunt.TestMode then
            continue
        end

        local scrPos = pickup.pos:ToScreen()
        if not scrPos.visible then continue end

        local dist = ply:GetPos():Distance(pickup.pos)
        if dist > 3000 then continue end -- don't show very far pickups

        local alpha = math.Clamp(255 - (dist / 3000) * 155, 100, 255)
        local pulse = math.abs(math.sin(CurTime() * 2 + idx))
        local col = Color(abilityDef.color.r, abilityDef.color.g, abilityDef.color.b, alpha)

        -- Glow circle
        local glowSize = 12 + pulse * 6
        draw.RoundedBox(glowSize, scrPos.x - glowSize, scrPos.y - glowSize, glowSize * 2, glowSize * 2, Color(col.r, col.g, col.b, alpha * 0.4))

        -- Inner dot
        draw.RoundedBox(6, scrPos.x - 6, scrPos.y - 6, 12, 12, col)

        -- Label
        draw.SimpleText(abilityDef.icon, "Chase_HUD_Tiny", scrPos.x, scrPos.y - 18, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)

        -- Distance
        local distText = math.floor(dist) .. "m"
        draw.SimpleText(distText, "Chase_HUD_Tiny", scrPos.x, scrPos.y + 14, Color(200, 200, 200, alpha * 0.7), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
    end
end

-- ==========================================
-- 3D EFFECTS
-- ==========================================

hook.Add("PostDrawTranslucentRenderables", "Manhunt_Chase3D", function()
    if not Manhunt.IsChaseMode() then return end
    if not Manhunt.Chase.ChaseActive then return end
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end

    -- Draw pickup glow orbs in 3D
    for idx, pickup in pairs(Manhunt.Chase.ClientPickups) do
        local abilityDef = Manhunt.Chase.Abilities[pickup.abilityId]
        if not abilityDef then continue end

        local ply = LocalPlayer()
        if not IsValid(ply) then continue end
        local myTeam = Manhunt.GetPlayerTeam(ply)
        if abilityDef.team ~= 0 and abilityDef.team ~= myTeam and not Manhunt.TestMode then
            continue
        end

        local dist = ply:GetPos():Distance(pickup.pos)
        if dist > 3000 then continue end

        -- Spinning glow
        local t = CurTime() * 2 + idx
        local bob = math.sin(t) * 15
        local drawPos = pickup.pos + Vector(0, 0, bob)

        local col = abilityDef.color
        render.SetColorMaterial()
        render.DrawSphere(drawPos, 20 + math.sin(t * 2) * 5, 12, 12, Color(col.r, col.g, col.b, 150))

        -- Light beam upward
        render.DrawBeam(drawPos, drawPos + Vector(0, 0, 200), 8, 0, 1, Color(col.r, col.g, col.b, 80))
    end
end)

-- ==========================================
-- CLIENT-SIDE EFFECTS
-- ==========================================

function Manhunt.Chase.PlayEffect(abilityId, pos, ang, ply)
    local isLocal = IsValid(ply) and ply == LocalPlayer()

    if abilityId == Manhunt.Chase.ABILITY_EMP_BLAST then
        -- Blue flash
        if isLocal then
            -- The user who activated it sees a pulse outward
        end
        local emitter = ParticleEmitter(pos)
        if emitter then
            for i = 1, 30 do
                local p = emitter:Add("sprites/light_glow02_add", pos + VectorRand() * 50)
                if p then
                    p:SetVelocity(VectorRand() * 500)
                    p:SetLifeTime(0)
                    p:SetDieTime(0.8)
                    p:SetStartAlpha(255)
                    p:SetEndAlpha(0)
                    p:SetStartSize(40)
                    p:SetEndSize(80)
                    p:SetColor(0, 150, 255)
                end
            end
            emitter:Finish()
        end

    elseif abilityId == Manhunt.Chase.ABILITY_NITRO_BOOST then
        -- Orange flame burst
        local emitter = ParticleEmitter(pos)
        if emitter then
            for i = 1, 20 do
                local p = emitter:Add("sprites/light_glow02_add", pos - ang:Forward() * 100 + VectorRand() * 20)
                if p then
                    p:SetVelocity(-ang:Forward() * 800 + VectorRand() * 100)
                    p:SetLifeTime(0)
                    p:SetDieTime(0.5)
                    p:SetStartAlpha(255)
                    p:SetEndAlpha(0)
                    p:SetStartSize(30)
                    p:SetEndSize(60)
                    p:SetColor(255, 150, 0)
                end
            end
            emitter:Finish()
        end

    elseif abilityId == Manhunt.Chase.ABILITY_SHIELD then
        -- Blue shield shimmer
        sound.Play("ambient/energy/weld" .. math.random(1, 2) .. ".wav", pos, 75, 100, 0.5)

    elseif abilityId == Manhunt.Chase.ABILITY_GHOST_MODE then
        -- Ghostly whoosh
        sound.Play("ambient/wind/wind_snippet2.wav", pos, 75, 80, 0.6)

    elseif abilityId == Manhunt.Chase.ABILITY_SHOCKWAVE then
        -- Shockwave visual
        local effectData = EffectData()
        effectData:SetOrigin(pos)
        effectData:SetMagnitude(5)
        effectData:SetScale(10)
        util.Effect("cball_explode", effectData)
        sound.Play("ambient/explosions/exp1.wav", pos, 80, 100, 0.7)

    elseif abilityId == Manhunt.Chase.ABILITY_MISSILE then
        -- Missile launch sound
        sound.Play("weapons/rpg/rocketfire1.wav", pos, 80, 100, 0.6)

    elseif abilityId == Manhunt.Chase.ABILITY_ROADBLOCK then
        -- Impact sound
        sound.Play("physics/concrete/concrete_block_impact_hard2.wav", pos, 80, 90, 0.8)
    end
end

-- ==========================================
-- KEY BINDINGS (number keys 1-9 for abilities)
-- ==========================================

hook.Add("PlayerBindPress", "Manhunt_ChaseAbilityKeys", function(ply, bind, pressed)
    if not Manhunt.IsChaseMode() then return end
    if not Manhunt.Chase.ChaseActive then return end
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end
    if not pressed then return end

    -- Check for slot keys (slot1 through slot9)
    local slotNum = string.match(bind, "^slot(%d)$")
    if not slotNum then return end
    slotNum = tonumber(slotNum)

    -- Build sorted ability list (same order as HUD)
    local abilityList = {}
    for id, data in pairs(Manhunt.Chase.ClientAbilities) do
        table.insert(abilityList, { id = id, data = data })
    end
    table.sort(abilityList, function(a, b) return a.id < b.id end)

    if abilityList[slotNum] then
        local abilityId = abilityList[slotNum].id
        -- Send to server
        net.Start("Manhunt_ChaseAbilityUse")
        net.WriteUInt(abilityId, 8)
        net.SendToServer()
    end

    return true -- block weapon switch
end)

print("[Manhunt] [CL] cl_chase.lua loaded!")
