--[[
    Manhunt - Airstrike SWEP
    Hunter-only weapon, cooldown = 20% of game time
    Click a position on the ground → custom bomb falls from the sky
    10 second countdown with alarm, then large explosion
]]

AddCSLuaFile()

SWEP.PrintName = "Airstrike Designator"
SWEP.Author = "Manhunt"
SWEP.Category = "Manhunt"
SWEP.Spawnable = true
SWEP.AdminOnly = false

SWEP.Primary.ClipSize = -1
SWEP.Primary.DefaultClip = -1
SWEP.Primary.Automatic = false
SWEP.Primary.Ammo = "none"

SWEP.Secondary.ClipSize = -1
SWEP.Secondary.DefaultClip = -1
SWEP.Secondary.Automatic = false
SWEP.Secondary.Ammo = "none"

SWEP.Weight = 5
SWEP.AutoSwitchTo = false
SWEP.AutoSwitchFrom = false

SWEP.Slot = 4
SWEP.SlotPos = 3
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/weapons/w_slam.mdl"
SWEP.HoldType = "slam"

SWEP.UseHands = true

local EXPLOSION_RADIUS = 7000  -- Damage radius (massive)
local EXPLOSION_DAMAGE = 400   -- Max damage at center
local COUNTDOWN = 10           -- Seconds before detonation (5 extra for fugitive to run)
local BOMB_FALL_SPEED = 1500   -- Units/s downward velocity

function SWEP:Initialize()
    self:SetHoldType("slam")
end

function SWEP:SetupDataTables()
    self:NetworkVar("Bool", 0, "AirstrikeUsed")
    self:NetworkVar("Float", 0, "CooldownEnd")
end

-- Cooldown = 20% of total game time
function SWEP:GetCooldownDuration()
    if Manhunt and Manhunt.GetTotalGameTime then
        return Manhunt.GetTotalGameTime() * 0.2
    end
    return 120 -- fallback 2 minutes
end

-- Always available (no time lock), just check cooldown
function SWEP:IsAvailable()
    if Manhunt and Manhunt.TestMode then return true end
    if not Manhunt or not Manhunt.IsActive() then return false end
    return true
end

-- Check if on cooldown
function SWEP:IsOnCooldown()
    if Manhunt and Manhunt.TestMode then return false end
    return self:GetCooldownEnd() > CurTime()
end

function SWEP:GetCooldownRemaining()
    return math.max(0, self:GetCooldownEnd() - CurTime())
end

-- Find the skybox ceiling above a position
local function GetSkyboxHeight(pos)
    local tr = util.TraceLine({
        start = pos,
        endpos = pos + Vector(0, 0, 50000),
        mask = MASK_SOLID_BRUSHONLY,
    })
    return tr.HitPos - Vector(0, 0, 100)
end

-- Custom explosion with massive radius
local function DoAirstrikeExplosion(pos, attacker)
    -- Main explosion at center
    local explode = ents.Create("env_explosion")
    if IsValid(explode) then
        explode:SetPos(pos)
        explode:SetOwner(attacker)
        explode:Spawn()
        explode:SetKeyValue("iMagnitude", "400")
        explode:Fire("Explode", "", 0)
    end

    -- Ring of secondary explosions around the center for a massive visual
    for i = 1, 10 do
        local angle = math.rad((i / 10) * 360)
        local offset = Vector(math.cos(angle) * 800, math.sin(angle) * 800, 0)
        timer.Simple(0.05 * i, function()
            local exp2 = ents.Create("env_explosion")
            if IsValid(exp2) then
                exp2:SetPos(pos + offset)
                exp2:SetOwner(attacker)
                exp2:Spawn()
                exp2:SetKeyValue("iMagnitude", "350")
                exp2:Fire("Explode", "", 0)
            end
        end)
    end

    -- Middle ring of explosions (delayed)
    for i = 1, 8 do
        local angle = math.rad((i / 8) * 360 + 22)
        local offset = Vector(math.cos(angle) * 1600, math.sin(angle) * 1600, 0)
        timer.Simple(0.15 + 0.06 * i, function()
            local exp3 = ents.Create("env_explosion")
            if IsValid(exp3) then
                exp3:SetPos(pos + offset)
                exp3:SetOwner(attacker)
                exp3:Spawn()
                exp3:SetKeyValue("iMagnitude", "300")
                exp3:Fire("Explode", "", 0)
            end
        end)
    end

    -- Outer ring of explosions (delayed, even wider)
    for i = 1, 8 do
        local angle = math.rad((i / 8) * 360 + 45)
        local offset = Vector(math.cos(angle) * 2400, math.sin(angle) * 2400, 0)
        timer.Simple(0.3 + 0.07 * i, function()
            local exp4 = ents.Create("env_explosion")
            if IsValid(exp4) then
                exp4:SetPos(pos + offset)
                exp4:SetOwner(attacker)
                exp4:Spawn()
                exp4:SetKeyValue("iMagnitude", "250")
                exp4:Fire("Explode", "", 0)
            end
        end)
    end

    -- Massive outer ring (delayed even more, maximum visual impact)
    for i = 1, 10 do
        local angle = math.rad((i / 10) * 360 + 18)
        local offset = Vector(math.cos(angle) * 3600, math.sin(angle) * 3600, 0)
        timer.Simple(0.5 + 0.08 * i, function()
            local exp5 = ents.Create("env_explosion")
            if IsValid(exp5) then
                exp5:SetPos(pos + offset)
                exp5:SetOwner(attacker)
                exp5:Spawn()
                exp5:SetKeyValue("iMagnitude", "200")
                exp5:Fire("Explode", "", 0)
            end
        end)
    end

    -- Extreme outer ring (new 5th ring for even bigger visual)
    for i = 1, 12 do
        local angle = math.rad((i / 12) * 360 + 30)
        local offset = Vector(math.cos(angle) * 5000, math.sin(angle) * 5000, 0)
        timer.Simple(0.7 + 0.09 * i, function()
            local exp6 = ents.Create("env_explosion")
            if IsValid(exp6) then
                exp6:SetPos(pos + offset)
                exp6:SetOwner(attacker)
                exp6:Spawn()
                exp6:SetKeyValue("iMagnitude", "180")
                exp6:Fire("Explode", "", 0)
            end
        end)
    end

    -- Outermost ring (6th ring, maximum devastation)
    for i = 1, 14 do
        local angle = math.rad((i / 14) * 360 + 10)
        local offset = Vector(math.cos(angle) * 6500, math.sin(angle) * 6500, 0)
        timer.Simple(0.9 + 0.1 * i, function()
            local exp7 = ents.Create("env_explosion")
            if IsValid(exp7) then
                exp7:SetPos(pos + offset)
                exp7:SetOwner(attacker)
                exp7:Spawn()
                exp7:SetKeyValue("iMagnitude", "150")
                exp7:Fire("Explode", "", 0)
            end
        end)
    end

    -- Massive screen shake for everyone in range
    util.ScreenShake(pos, 35, 5, 6, 8000)

    -- Extra shake + flash for nearby players
    for _, ply in ipairs(player.GetAll()) do
        local dist = ply:GetPos():Distance(pos)
        if dist < 7000 then
            local intensity = math.Clamp(1 - dist / 7000, 0.1, 1)
            util.ScreenShake(ply:GetPos(), intensity * 25, 8, 4, 500)
        end
    end

    -- Upward dust/debris effect
    local effectData = EffectData()
    effectData:SetOrigin(pos)
    effectData:SetScale(3)
    effectData:SetMagnitude(500)
    util.Effect("ThumperDust", effectData)
    util.Effect("Explosion", effectData)

    -- Area damage with falloff
    for _, ply in ipairs(player.GetAll()) do
        if IsValid(ply) and ply:Alive() then
            local dist = ply:GetPos():Distance(pos)
            if dist < EXPLOSION_RADIUS then
                -- Check line of sight (partial cover reduces damage)
                local tr = util.TraceLine({
                    start = pos + Vector(0, 0, 20),
                    endpos = ply:GetPos() + Vector(0, 0, 40),
                    filter = ply,
                    mask = MASK_SOLID_BRUSHONLY,
                })

                local coverMult = tr.Hit and 0.3 or 1.0
                local falloff = 1 - (dist / EXPLOSION_RADIUS)
                local dmg = EXPLOSION_DAMAGE * falloff * coverMult

                if dmg > 0 then
                    local dmgInfo = DamageInfo()
                    dmgInfo:SetDamage(dmg)
                    dmgInfo:SetDamageType(DMG_BLAST)
                    dmgInfo:SetAttacker(IsValid(attacker) and attacker or Entity(0))
                    dmgInfo:SetInflictor(IsValid(attacker) and attacker or Entity(0))
                    dmgInfo:SetDamagePosition(pos)
                    ply:TakeDamageInfo(dmgInfo)
                end
            end
        end
    end

    -- Damage nearby vehicles too
    for _, ent in ipairs(ents.FindInSphere(pos, EXPLOSION_RADIUS)) do
        if IsValid(ent) and (ent:IsVehicle() or ent.LVS or ent.IsGlideVehicle) then
            local dist = ent:GetPos():Distance(pos)
            local falloff = 1 - (dist / EXPLOSION_RADIUS)
            local dmgInfo = DamageInfo()
            dmgInfo:SetDamage(EXPLOSION_DAMAGE * 2 * falloff)
            dmgInfo:SetDamageType(DMG_BLAST)
            dmgInfo:SetAttacker(IsValid(attacker) and attacker or Entity(0))
            dmgInfo:SetInflictor(IsValid(attacker) and attacker or Entity(0))
            ent:TakeDamageInfo(dmgInfo)
        end
    end
end

function SWEP:PrimaryAttack()
    if not IsFirstTimePredicted() then return end
    self:SetNextPrimaryFire(CurTime() + 1)

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    if self:GetAirstrikeUsed() and not (Manhunt and Manhunt.TestMode) then
        if CLIENT then
            notification.AddLegacy("Airstrike already used!", NOTIFY_ERROR, 3)
        end
        return
    end

    -- Check cooldown
    if self:IsOnCooldown() then
        if CLIENT then
            local remaining = math.ceil(self:GetCooldownRemaining())
            local mins = math.floor(remaining / 60)
            local secs = remaining % 60
            notification.AddLegacy(string.format("Airstrike on cooldown! %d:%02d remaining", mins, secs), NOTIFY_ERROR, 3)
        end
        return
    end

    if not self:IsAvailable() then
        if CLIENT then
            notification.AddLegacy("Airstrike not available!", NOTIFY_ERROR, 3)
        end
        return
    end

    if SERVER then
        -- Get target position
        local tr = owner:GetEyeTrace()
        local targetPos = tr.HitPos

        -- Find skybox height above target
        local skyPos = GetSkyboxHeight(targetPos)

        -- Mark as used (skip in test mode for infinite uses)
        if not Manhunt.TestMode then
            self:SetCooldownEnd(CurTime() + self:GetCooldownDuration())
        end

        -- Play designator beep
        owner:EmitSound("buttons/button17.wav", 70, 150)

        -- Send airstrike marker + countdown to all clients
        net.Start("Manhunt_AirstrikeMarker")
        net.WriteVector(targetPos)
        net.WriteFloat(COUNTDOWN)
        net.Broadcast()

        -- Notify in chat
        for _, ply in ipairs(player.GetAll()) do
            ply:ChatPrint("[Manhunt] AIRSTRIKE INCOMING! You have " .. COUNTDOWN .. " seconds!")
        end

        -- Play alarm sound for everyone (repeating during countdown)
        for i = 0, COUNTDOWN - 1 do
            timer.Simple(i, function()
                for _, ply in ipairs(player.GetAll()) do
                    if IsValid(ply) then
                        -- Play alarm louder for players near the target
                        local dist = ply:GetPos():Distance(targetPos)
                        if dist < 3000 then
                            ply:EmitSound("ambient/alarms/klaxon1.wav", 80, 120 + i * 5)
                        else
                            ply:EmitSound("ambient/alarms/klaxon1.wav", 60, 120 + i * 5)
                        end
                    end
                end
            end)
        end

        -- Spawn the bomb prop falling from the sky after a short delay
        timer.Simple(0.5, function()
            local bomb = ents.Create("prop_physics")
            if not IsValid(bomb) then return end

            bomb:SetModel("models/props_phx/ww2bomb.mdl")
            bomb:SetPos(skyPos)
            bomb:SetAngles(Angle(0, 0, 0))
            bomb:Spawn()
            bomb:Activate()
            bomb:SetColor(Color(60, 60, 60))
            bomb:SetCollisionGroup(COLLISION_GROUP_DEBRIS) -- Don't block players

            local phys = bomb:GetPhysicsObject()
            if IsValid(phys) then
                phys:SetVelocity(Vector(0, 0, -BOMB_FALL_SPEED))
                phys:SetAngleVelocity(Vector(0, 0, 0))
                phys:EnableGravity(true)
            end

            -- Trail effect
            util.SpriteTrail(bomb, 0, Color(255, 100, 30, 200), false, 30, 5, 2, 1 / 15, "trails/smoke")

            -- Store for cleanup
            bomb.ManhuntAirstrike = true
        end)

        -- Detonate after countdown
        timer.Simple(COUNTDOWN, function()
            -- Find and remove the bomb prop
            for _, ent in ipairs(ents.GetAll()) do
                if IsValid(ent) and ent.ManhuntAirstrike then
                    ent:Remove()
                end
            end

            -- Big explosion at target
            DoAirstrikeExplosion(targetPos, owner)

            -- Massive fire effects spread across the blast zone
            for i = 1, 12 do
                local spread = 600
                local firePos = targetPos + Vector(math.random(-spread, spread), math.random(-spread, spread), 0)
                -- Trace down to ground
                local groundTr = util.TraceLine({
                    start = firePos + Vector(0, 0, 200),
                    endpos = firePos - Vector(0, 0, 200),
                    mask = MASK_SOLID_BRUSHONLY,
                })
                if groundTr.Hit then firePos = groundTr.HitPos end

                timer.Simple(math.random() * 0.4, function()
                    local fire = ents.Create("env_fire")
                    if IsValid(fire) then
                        fire:SetPos(firePos)
                        fire:SetKeyValue("health", "8")
                        fire:SetKeyValue("firesize", "180")
                        fire:SetKeyValue("fireattack", "1")
                        fire:SetKeyValue("damagescale", "0")
                        fire:SetKeyValue("spawnflags", "289")
                        fire:Spawn()
                        fire:Activate()
                        fire:Fire("StartFire", "", 0)

                        timer.Simple(10, function()
                            if IsValid(fire) then fire:Remove() end
                        end)
                    end
                end)
            end
        end)
    end
end

function SWEP:SecondaryAttack() end
function SWEP:Reload() end

-- Custom HUD
function SWEP:DrawHUD()
    if not Manhunt or not Manhunt.IsActive() then return end

    local sw, sh = ScrW(), ScrH()

    if self:IsOnCooldown() then
        local remaining = math.ceil(self:GetCooldownRemaining())
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        local cooldownDuration = self:GetCooldownDuration()
        local progress = 1 - (remaining / cooldownDuration)
        
        draw.RoundedBox(6, sw / 2 - 120, sh - 80, 240, 35, Color(60, 40, 30, 200))
        -- Cooldown bar
        draw.RoundedBox(4, sw / 2 - 116, sh - 76, 232 * progress, 27, Color(200, 80, 30, 100))
        draw.SimpleText(string.format("COOLDOWN %d:%02d", mins, secs), "Manhunt_HUD_Small", sw / 2, sh - 62, Color(255, 150, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    elseif not self:IsAvailable() then
        draw.RoundedBox(6, sw / 2 - 120, sh - 80, 240, 35, Color(60, 60, 30, 200))
        draw.SimpleText("AIRSTRIKE NOT AVAILABLE", "Manhunt_HUD_Small", sw / 2, sh - 62, Color(255, 200, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    else
        local pulse = math.abs(math.sin(CurTime() * 3))
        draw.RoundedBox(6, sw / 2 - 140, sh - 80, 280, 35, Color(30, 60, 30, 200))
        draw.SimpleText("AIRSTRIKE READY — Aim & Click", "Manhunt_HUD_Small", sw / 2, sh - 62, Color(50 + pulse * 100, 255, 50 + pulse * 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

        -- Draw crosshair target indicator
        local tr = self:GetOwner():GetEyeTrace()
        if tr.Hit then
            local screenPos = tr.HitPos:ToScreen()
            if screenPos.visible then
                local x, y = screenPos.x, screenPos.y
                local size = 20
                surface.SetDrawColor(255, 50, 50, 200)
                for i = 0, 360, 10 do
                    local rad = math.rad(i)
                    local rad2 = math.rad(i + 10)
                    surface.DrawLine(
                        x + math.cos(rad) * size, y + math.sin(rad) * size,
                        x + math.cos(rad2) * size, y + math.sin(rad2) * size
                    )
                end
                surface.DrawLine(x - size * 0.5, y, x + size * 0.5, y)
                surface.DrawLine(x, y - size * 0.5, x, y + size * 0.5)

                draw.SimpleText("TARGET", "Manhunt_HUD_Small", x, y - size - 5, Color(255, 50, 50, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
            end
        end
    end

    -- Charge indicator
    local chargeX = sw / 2 - 15
    local chargeY = sh - 110
    local onCooldown = self:IsOnCooldown()

    draw.RoundedBox(4, chargeX, chargeY, 30, 30, onCooldown and Color(80, 50, 30, 200) or Color(30, 80, 30, 200))
    draw.SimpleText("A", "Manhunt_HUD_Medium", chargeX + 15, chargeY + 15, onCooldown and Color(255, 150, 80) or Color(50, 255, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
end

function SWEP:CanBePickedUpByNPCs() return false end
