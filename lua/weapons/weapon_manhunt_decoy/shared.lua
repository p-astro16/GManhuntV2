--[[
    Manhunt - Decoy Grenade SWEP
    Fugitive throws this grenade to place a fake blip on the next scanner pulse
    Shows a decoy position to confuse the hunters
    Recharges every 25% of game time (infinite in test mode)
]]

AddCSLuaFile()

SWEP.PrintName = "Decoy Grenade"
SWEP.Author = "Manhunt"
SWEP.Instructions = "Throw to create a fake blip on the hunters' scanner"
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

SWEP.Slot = 3
SWEP.SlotPos = 2
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_grenade.mdl"
SWEP.WorldModel = "models/weapons/w_grenade.mdl"
SWEP.HoldType = "grenade"

SWEP.UseHands = true

local DECOY_DURATION = 30  -- How long the decoy blip stays active (multiple scans)

function SWEP:Initialize()
    self:SetHoldType("grenade")
    self._lastThreshold = 0 -- track which 25% threshold we last recharged at
end

function SWEP:SetupDataTables()
    self:NetworkVar("Bool", 0, "DecoyUsed")
end

-- Get current game time progress (0 to 1)
function SWEP:GetGameProgress()
    if not Manhunt or not Manhunt.IsActive or not Manhunt.IsActive() then return 0 end
    local total = Manhunt.GetTotalGameTime()
    local remaining = Manhunt.GetRemainingTime()
    if total <= 0 then return 0 end
    return math.Clamp(1 - (remaining / total), 0, 1)
end

-- Check if decoy should recharge based on 25% game time thresholds
function SWEP:Think()
    if CLIENT then return end
    if not self:GetDecoyUsed() then return end
    if Manhunt and Manhunt.TestMode then return end
    if not Manhunt or not Manhunt.IsActive or not Manhunt.IsActive() then return end

    local progress = self:GetGameProgress()
    -- Thresholds: 0.25, 0.50, 0.75
    local currentThreshold = math.floor(progress * 4) -- 0, 1, 2, 3

    if currentThreshold > (self._lastThreshold or 0) then
        self._lastThreshold = currentThreshold
        self:SetDecoyUsed(false)

        local owner = self:GetOwner()
        if IsValid(owner) then
            owner:ChatPrint("[Manhunt] Decoy Grenade recharged! (" .. (currentThreshold * 25) .. "% game time reached)")
            owner:EmitSound("items/battery_pickup.wav", 60, 120)
        end
    end

    self:SetNextThink(CurTime() + 1)
    return true
end

function SWEP:PrimaryAttack()
    if not IsFirstTimePredicted() then return end
    self:SetNextPrimaryFire(CurTime() + 1)

    if self:GetDecoyUsed() and not (Manhunt and Manhunt.TestMode) then
        if CLIENT then
            notification.AddLegacy("Decoy already used!", NOTIFY_ERROR, 2)
        end
        return
    end

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    if SERVER then
        -- Create a thrown grenade prop
        local throwDir = owner:GetAimVector()
        local throwPos = owner:GetShootPos() + throwDir * 10

        local grenade = ents.Create("prop_physics")
        if not IsValid(grenade) then return end

        grenade:SetModel("models/weapons/w_grenade.mdl")
        grenade:SetPos(throwPos)
        grenade:SetAngles(owner:EyeAngles())
        grenade:Spawn()
        grenade:Activate()

        grenade:SetModelScale(0.8)
        grenade:SetColor(Color(255, 200, 50))

        -- Throw it
        local phys = grenade:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(throwDir * 700 + Vector(0, 0, 250))
            phys:AddAngleVelocity(VectorRand() * 200)
        end

        -- Play throw sound
        owner:EmitSound("weapons/grenade/grmagnet_pickup.wav", 70, 100)

        -- Mark as used (skip in test mode)
        if not Manhunt.TestMode then
            self:SetDecoyUsed(true)
            -- Track which threshold we're at so next 25% recharges it
            self._lastThreshold = math.floor(self:GetGameProgress() * 4)
        end

        local decoyOwner = owner

        -- When grenade lands, activate the decoy at that position
        timer.Simple(1.5, function()
            if not IsValid(grenade) then return end

            local landPos = grenade:GetPos()

            -- Trace down to ground
            local tr = util.TraceLine({
                start = landPos + Vector(0, 0, 10),
                endpos = landPos - Vector(0, 0, 100),
                mask = MASK_SOLID_BRUSHONLY,
            })

            local decoyPos = tr.HitPos or landPos

            -- Remove the grenade prop
            grenade:Remove()

            -- Activate decoy in the game system
            Manhunt.DecoyActive = true
            Manhunt.DecoyPos = decoyPos

            -- Mark on the player too (legacy)
            if IsValid(decoyOwner) then
                decoyOwner.ManhuntDecoyUsed = not Manhunt.TestMode
                decoyOwner:SetNWBool("ManhuntDecoyUsed", not Manhunt.TestMode)
            end

            -- Create a subtle glowing effect at the decoy position
            local marker = ents.Create("prop_dynamic")
            if IsValid(marker) then
                marker:SetModel("models/hunter/plates/plate.mdl")
                marker:SetPos(decoyPos + Vector(0, 0, 1))
                marker:SetAngles(Angle(0, 0, 0))
                marker:SetModelScale(1.5)
                marker:SetColor(Color(255, 200, 50, 150))
                marker:SetRenderMode(RENDERMODE_TRANSALPHA)
                marker:Spawn()
                marker:Activate()
                marker:SetMaterial("models/debug/debugwhite")

                -- Remove marker after duration
                timer.Simple(DECOY_DURATION, function()
                    if IsValid(marker) then marker:Remove() end
                end)
            end

            -- Emit a subtle sound at decoy location (mimics footsteps)
            sound.Play("npc/footsteps/hardboot_generic" .. math.random(1, 6) .. ".wav", decoyPos, 60, 100)

            -- Notify the owner
            if IsValid(decoyOwner) then
                decoyOwner:ChatPrint("[Manhunt] Decoy deployed! Fake blip will appear on the next scanner pulse.")
            end

            -- Sync to the owner for visual feedback
            net.Start("Manhunt_DecoySync")
            net.WriteVector(decoyPos)
            net.WriteBool(true)
            if IsValid(decoyOwner) then
                net.Send(decoyOwner)
            end

            -- The decoy stays active for DECOY_DURATION seconds (shows on multiple scans)
            timer.Simple(DECOY_DURATION, function()
                if Manhunt.DecoyActive and Manhunt.DecoyPos == decoyPos then
                    Manhunt.DecoyActive = false
                    Manhunt.DecoyPos = nil
                end
            end)
        end)
    end

    if CLIENT then
        surface.PlaySound("weapons/grenade/grmagnet_pickup.wav")
    end
end

function SWEP:SecondaryAttack()
    -- No secondary
end

function SWEP:Reload()
    -- No reload
end

-- Custom HUD
if CLIENT then
    function SWEP:DrawHUD()
        local sw, sh = ScrW(), ScrH()
        local x = sw / 2
        local y = sh - 60

        local bgW = 200
        local bgH = 40

        draw.RoundedBox(6, x - bgW / 2, y - bgH / 2, bgW, bgH, Color(0, 0, 0, 180))

        if self:GetDecoyUsed() then
            -- Show recharge progress toward next 25% threshold
            local progress = self:GetGameProgress()
            local currentThreshold = math.floor(progress * 4)
            local nextThreshold = (currentThreshold + 1) / 4
            local thresholdProgress = 0
            if nextThreshold <= 1 then
                local prevThreshold = currentThreshold / 4
                thresholdProgress = math.Clamp((progress - prevThreshold) / (nextThreshold - prevThreshold), 0, 1)
            end

            draw.RoundedBox(4, x - bgW / 2 + 4, y - bgH / 2 + 4, bgW - 8, bgH - 8, Color(80, 60, 20, 80))
            -- Recharge progress bar
            draw.RoundedBox(2, x - bgW / 2 + 6, y + bgH / 2 - 10, (bgW - 12) * thresholdProgress, 4, Color(255, 200, 50, 150))
            local nextPct = math.floor(nextThreshold * 100)
            if nextPct > 100 then
                draw.SimpleText("DECOY USED (FINAL)", "Manhunt_HUD_Small", x, y - 4, Color(150, 120, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                draw.SimpleText("RECHARGING AT " .. nextPct .. "%", "Manhunt_HUD_Small", x, y - 4, Color(255, 180, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        else
            -- Pulsing ready indicator
            local pulse = math.abs(math.sin(CurTime() * 2)) * 30
            draw.RoundedBox(4, x - bgW / 2 + 4, y - bgH / 2 + 4, bgW - 8, bgH - 8, Color(200 + pulse, 170 + pulse, 30, 80))
            draw.SimpleText("DECOY READY - THROW!", "Manhunt_HUD_Small", x, y, Color(255, 220, 80), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        draw.SimpleText("DECOY GRENADE", "Manhunt_HUD_Small", x, y - bgH / 2 - 5, Color(255, 200, 50, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    end

    function SWEP:DrawWorldModel()
        self:DrawModel()
    end
end
