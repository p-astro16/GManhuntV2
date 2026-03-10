--[[
    Manhunt - Car Bomb Weapon
    Fugitive only: 1 use
    Primary fire near vehicle = place bomb
    Primary fire after placed = detonate
]]

AddCSLuaFile()

SWEP.PrintName = "Car Bomb"
SWEP.Author = "Manhunt"
SWEP.Instructions = "Aim at a vehicle and press primary fire to place. Fire again to detonate."
SWEP.Category = "Manhunt"

SWEP.Spawnable = false
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
SWEP.SlotPos = 5
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/weapons/w_slam.mdl"

SWEP.UseHands = true
SWEP.HoldType = "slam"

-- States
local STATE_READY = 0    -- Can place bomb
local STATE_PLACED = 1   -- Bomb placed, can detonate
local STATE_USED = 2     -- Already detonated, weapon spent

function SWEP:Initialize()
    self:SetHoldType("slam")
    self:SetNWInt("BombState", STATE_READY)
end

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "RechargeEnd") -- when the next charge finishes recharging
end

function SWEP:PrimaryAttack()
    if not Manhunt or not Manhunt.IsActive or not Manhunt.IsActive() then return end

    local state = self:GetNWInt("BombState", STATE_READY)
    local charges = self:GetNWInt("ManhuntCharges", 0)

    if (state == STATE_USED or charges <= 0) and not (Manhunt and Manhunt.TestMode) then
        -- Check if recharging
        local rechargeEnd = self:GetRechargeEnd()
        if rechargeEnd > CurTime() then
            if CLIENT then
                local remaining = math.ceil(rechargeEnd - CurTime())
                local mins = math.floor(remaining / 60)
                local secs = remaining % 60
                surface.PlaySound("buttons/button10.wav")
                chat.AddText(Color(255, 100, 100), "[Manhunt] ", Color(255, 255, 255), string.format("Car bomb recharging! %d:%02d", mins, secs))
            end
        else
            if CLIENT then
                surface.PlaySound("buttons/button10.wav")
                chat.AddText(Color(255, 100, 100), "[Manhunt] ", Color(255, 255, 255), "Car bomb already used!")
            end
        end
        self:SetNextPrimaryFire(CurTime() + 1)
        return
    end

    if state == STATE_READY then
        -- Try to place bomb on nearby vehicle
        if SERVER then
            local vehicle = self:FindNearbyVehicle()
            if IsValid(vehicle) then
                -- Place the bomb
                self:SetNWInt("BombState", STATE_PLACED)
                self:SetNWEntity("BombTarget", vehicle)

                -- Handle car bomb placement directly server-side
                if Manhunt.CarBomb then
                    Manhunt.CarBomb.placed = true
                    Manhunt.CarBomb.target = vehicle

                    -- Visual bomb entity
                    local bomb = ents.Create("prop_physics")
                    if IsValid(bomb) then
                        bomb:SetModel("models/props_junk/cardboard_box004a.mdl")
                        bomb:SetPos(vehicle:GetPos() + Vector(0, 0, -10))
                        bomb:Spawn()
                        bomb:SetParent(vehicle)
                        bomb:SetColor(Color(255, 0, 0))
                        bomb:SetModelScale(0.3)
                        bomb:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
                        Manhunt.CarBomb.entity = bomb
                    end
                end

                self:GetOwner():EmitSound("buttons/button14.wav")
                self:GetOwner():ChatPrint("[Manhunt] Car bomb placed! Press primary fire again to detonate.")
            else
                self:GetOwner():ChatPrint("[Manhunt] No vehicle nearby! Get closer to a vehicle.")
                self:GetOwner():EmitSound("buttons/button10.wav")
            end
        end

    elseif state == STATE_PLACED then
        -- Detonate
        if SERVER then
            -- In test mode, reset to ready state for infinite uses
            if Manhunt and Manhunt.TestMode then
                self:SetNWInt("BombState", STATE_READY)
            else
                self:SetNWInt("BombState", STATE_USED)
                self:SetNWInt("ManhuntCharges", 0)
                self:SetRechargeEnd(CurTime() + 120) -- 2 minute recharge (universal)
            end

            local target = Manhunt.CarBomb and Manhunt.CarBomb.target
            if IsValid(target) then
                -- Explosion
                local explode = ents.Create("env_explosion")
                if IsValid(explode) then
                    explode:SetPos(target:GetPos())
                    explode:SetOwner(self:GetOwner())
                    explode:Spawn()
                    explode:SetKeyValue("iMagnitude", "200")
                    explode:Fire("Explode", "", 0)
                end

                -- Damage vehicle
                local dmgInfo = DamageInfo()
                dmgInfo:SetDamage(500)
                dmgInfo:SetDamageType(DMG_BLAST)
                dmgInfo:SetAttacker(self:GetOwner())
                dmgInfo:SetInflictor(self:GetOwner())
                target:TakeDamageInfo(dmgInfo)

                -- Area damage
                for _, ply in ipairs(player.GetAll()) do
                    if IsValid(ply) and ply:Alive() then
                        local dist = ply:GetPos():Distance(target:GetPos())
                        if dist < 500 then
                            local dmg = DamageInfo()
                            dmg:SetDamage(math.max(0, 150 * (1 - dist / 500)))
                            dmg:SetDamageType(DMG_BLAST)
                            dmg:SetAttacker(self:GetOwner())
                            dmg:SetInflictor(self:GetOwner())
                            ply:TakeDamageInfo(dmg)
                        end
                    end
                end

                -- Cleanup bomb entity
                if Manhunt.CarBomb and IsValid(Manhunt.CarBomb.entity) then
                    Manhunt.CarBomb.entity:Remove()
                end
                Manhunt.CarBomb = { placed = false, entity = nil, target = nil }
            end

            self:GetOwner():EmitSound("ambient/explosions/explode_4.wav")
            self:GetOwner():ChatPrint("[Manhunt] BOOM! Car bomb detonated!")
        end
    end

    self:SetNextPrimaryFire(CurTime() + 1)
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
end

function SWEP:SecondaryAttack()
    -- No secondary
end

function SWEP:Reload()
    -- No reload
end

function SWEP:Think()
    if SERVER then
        -- Recharge logic
        local rechargeEnd = self:GetRechargeEnd()
        if rechargeEnd > 0 and CurTime() >= rechargeEnd then
            local charges = self:GetNWInt("ManhuntCharges", 0)
            if charges < 1 then
                self:SetNWInt("ManhuntCharges", 1)
                self:SetNWInt("BombState", STATE_READY)
                self:SetRechargeEnd(0)
                local owner = self:GetOwner()
                if IsValid(owner) then
                    owner:ChatPrint("[Manhunt] Car bomb recharged!")
                    owner:EmitSound("items/battery_pickup.wav")
                end
            end
        end
    end
end

-- Find nearby vehicle (within 200 units)
function SWEP:FindNearbyVehicle()
    if CLIENT then return nil end

    local owner = self:GetOwner()
    if not IsValid(owner) then return nil end

    local pos = owner:GetPos()
    local nearestVeh = nil
    local nearestDist = 200 -- max range

    -- Check all entities for vehicles
    for _, ent in ipairs(ents.GetAll()) do
        if not IsValid(ent) then continue end

        local isVehicle = ent:IsVehicle()
            or string.find(ent:GetClass(), "prop_vehicle")
            or string.find(ent:GetClass(), "gmod_sent_vehicle")
            or string.find(ent:GetClass(), "gtav_")
            or string.find(ent:GetClass(), "glide_")
            or (ent.IsGlideVehicle and ent:IsGlideVehicle())
            or ent.IsSimfphyscar

        if isVehicle then
            local dist = pos:Distance(ent:GetPos())
            if dist < nearestDist then
                nearestDist = dist
                nearestVeh = ent
            end
        end
    end

    return nearestVeh
end

-- Custom HUD
if CLIENT then
    function SWEP:DrawHUD()
        local state = self:GetNWInt("BombState", STATE_READY)
        local charges = self:GetNWInt("ManhuntCharges", 0)

        local sw, sh = ScrW(), ScrH()
        local x = sw / 2
        local y = sh - 60

        local bgW = 220
        local bgH = 50
        draw.RoundedBox(6, x - bgW / 2, y - bgH / 2, bgW, bgH, Color(0, 0, 0, 180))

        if state == STATE_READY and charges > 0 then
            draw.SimpleText("AIM AT VEHICLE + FIRE", "Manhunt_HUD_Small", x, y - 8, Color(255, 200, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            draw.SimpleText("to place bomb", "Manhunt_HUD_Small", x, y + 10, Color(200, 200, 200, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)

            -- Show if vehicle is nearby
            local tr = LocalPlayer():GetEyeTrace()
            if IsValid(tr.Entity) and (tr.Entity:IsVehicle() or string.find(tr.Entity:GetClass() or "", "glide_") or string.find(tr.Entity:GetClass() or "", "gtav_")) then
                if tr.HitPos:Distance(LocalPlayer():GetPos()) < 200 then
                    draw.SimpleText("VEHICLE IN RANGE", "Manhunt_HUD_Small", x, y - 30, Color(50, 255, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                end
            end

        elseif state == STATE_PLACED then
            local pulse = math.abs(math.sin(CurTime() * 3))
            draw.SimpleText("FIRE TO DETONATE", "Manhunt_HUD_Small", x, y, Color(255, 50 + pulse * 100, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            -- Show recharge timer if recharging
            local rechargeEnd = self:GetRechargeEnd()
            if rechargeEnd > CurTime() then
                local remaining = math.ceil(rechargeEnd - CurTime())
                local mins = math.floor(remaining / 60)
                local secs = remaining % 60
                local progress = 1 - (remaining / 120)
                
                draw.SimpleText(string.format("RECHARGING %d:%02d", mins, secs), "Manhunt_HUD_Small", x, y - 5, Color(255, 150, 50), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
                
                -- Recharge bar
                local barW = bgW - 20
                local barH = 4
                local barX = x - barW / 2
                local barY = y + 12
                draw.RoundedBox(2, barX, barY, barW, barH, Color(30, 30, 30, 200))
                draw.RoundedBox(2, barX, barY, barW * progress, barH, Color(255, 150, 50, 200))
            else
                draw.SimpleText("BOMB USED", "Manhunt_HUD_Small", x, y, Color(100, 100, 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end
        end

        draw.SimpleText("CAR BOMB", "Manhunt_HUD_Small", x, y - bgH / 2 - 5, Color(200, 200, 200, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    end

    function SWEP:DrawWorldModel()
        self:DrawModel()
    end
end
