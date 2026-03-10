--[[
    Manhunt - Scanner Weapon
    Fugitive: 1 charge, recharges every 5 minutes
    Hunter: 5 charges, no recharge
]]

AddCSLuaFile()

SWEP.PrintName = "Manhunt Scanner"
SWEP.Author = "Manhunt"
SWEP.Instructions = "Primary fire to scan for enemy location"
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

SWEP.Slot = 0
SWEP.SlotPos = 5
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/weapons/w_slam.mdl"

SWEP.UseHands = true
SWEP.HoldType = "slam"

function SWEP:Initialize()
    self:SetHoldType("slam")
end

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "RechargeEnd") -- when the next charge finishes recharging
end

function SWEP:PrimaryAttack()
    if not Manhunt or not Manhunt.IsActive or not Manhunt.IsActive() then return end

    local charges = self:GetNWInt("ManhuntCharges", 0)

    -- Check if recharging (fugitive only)
    if charges <= 0 then
        if CLIENT then
            local rechargeEnd = self:GetRechargeEnd()
            if rechargeEnd > CurTime() then
                local remaining = math.ceil(rechargeEnd - CurTime())
                local mins = math.floor(remaining / 60)
                local secs = remaining % 60
                surface.PlaySound("buttons/button10.wav")
                chat.AddText(Color(255, 100, 100), "[Manhunt] ", Color(255, 255, 255), string.format("Scanner recharging... %d:%02d remaining", mins, secs))
            else
                surface.PlaySound("buttons/button10.wav")
                chat.AddText(Color(255, 100, 100), "[Manhunt] ", Color(255, 255, 255), "No scanner charges remaining!")
            end
        end
        self:SetNextPrimaryFire(CurTime() + 1)
        return
    end

    if SERVER then
        -- Decrease charges (skip in test mode for infinite uses)
        if not Manhunt.TestMode then
            self:SetNWInt("ManhuntCharges", charges - 1)
            
            -- Start recharge timer for fugitive
            local owner = self:GetOwner()
            if IsValid(owner) and Manhunt.GetPlayerTeam(owner) == Manhunt.TEAM_FUGITIVE then
                self:SetRechargeEnd(CurTime() + 300) -- 5 minutes
            end
        end

        -- Trigger scan via the game logic (simulates receiving the net message)
        local owner = self:GetOwner()
        local team = Manhunt.GetPlayerTeam(owner)

        if team == Manhunt.TEAM_FUGITIVE then
            -- In test mode, scan shows camera of own position (to test camera system)
            if Manhunt.TestMode then
                local inVehicle = Manhunt.IsPlayerInVehicle(owner)
                local vehSpeed = inVehicle and Manhunt.GetVehicleSpeed(owner) or 0
                local vehDir = inVehicle and owner:GetVelocity():GetNormalized() or Vector(0, 0, 0)

                net.Start("Manhunt_CameraView")
                net.WriteVector(owner:GetPos())
                net.WriteBool(inVehicle)
                net.WriteVector(vehDir)
                net.WriteFloat(vehSpeed)
                net.WriteBool(false)
                net.WriteBool(false)
                net.WriteVector(Vector(0, 0, 0))
                net.Send(owner)

                net.Start("Manhunt_PingPos")
                net.WriteVector(owner:GetPos())
                net.WriteBool(true)
                net.Send(owner)
            else
                -- Fugitive scans nearest hunter
                local nearestHunter = nil
                local nearestDist = math.huge

                for _, hunter in ipairs(Manhunt.GetHunters()) do
                    if IsValid(hunter) and hunter:Alive() then
                        local dist = owner:GetPos():Distance(hunter:GetPos())
                        if dist < nearestDist then
                            nearestDist = dist
                            nearestHunter = hunter
                        end
                    end
                end

                if IsValid(nearestHunter) then
                    local inVehicle = Manhunt.IsPlayerInVehicle(nearestHunter)
                    local vehSpeed = inVehicle and Manhunt.GetVehicleSpeed(nearestHunter) or 0
                    local vehDir = inVehicle and nearestHunter:GetVelocity():GetNormalized() or Vector(0, 0, 0)

                    net.Start("Manhunt_CameraView")
                    net.WriteVector(nearestHunter:GetPos())
                    net.WriteBool(inVehicle)
                    net.WriteVector(vehDir)
                    net.WriteFloat(vehSpeed)
                    net.WriteBool(false)
                    net.WriteBool(false)
                    net.WriteVector(Vector(0, 0, 0))
                    net.Send(owner)
                end
            end

        elseif team == Manhunt.TEAM_HUNTER then
            -- Hunter scans fugitive
            local fugitive = Manhunt.GetFugitive()
            if IsValid(fugitive) and fugitive:Alive() then
                local inVehicle = Manhunt.IsPlayerInVehicle(fugitive)
                local vehSpeed = inVehicle and Manhunt.GetVehicleSpeed(fugitive) or 0
                local vehDir = inVehicle and fugitive:GetVelocity():GetNormalized() or Vector(0, 0, 0)

                net.Start("Manhunt_CameraView")
                net.WriteVector(fugitive:GetPos())
                net.WriteBool(inVehicle)
                net.WriteVector(vehDir)
                net.WriteFloat(vehSpeed)
                net.WriteBool(false)
                net.WriteBool(false)
                net.WriteVector(Vector(0, 0, 0))
                net.Send(owner)

                -- Also send ping for hunter
                net.Start("Manhunt_PingPos")
                net.WriteVector(fugitive:GetPos())
                net.WriteBool(true)
                net.Send(owner)
            end
        end

        -- Visual/audio feedback
        owner:EmitSound("buttons/blip1.wav")
        Manhunt.PlayAudioCue("scan")

        -- Notify remaining charges
        local remaining = charges - 1
        owner:ChatPrint("[Manhunt] Scanner used! " .. remaining .. " charges remaining.")
    end

    if CLIENT then
        surface.PlaySound("buttons/blip1.wav")
    end

    self:SetNextPrimaryFire(CurTime() + 3) -- 3 second cooldown
    self:SendWeaponAnim(ACT_VM_PRIMARYATTACK)
end

function SWEP:SecondaryAttack()
    -- No secondary for scanner
end

function SWEP:Reload()
    -- No reload
end

function SWEP:Think()
    if SERVER then
        -- Recharge logic for fugitive scanner
        local owner = self:GetOwner()
        if not IsValid(owner) then return end
        if Manhunt.GetPlayerTeam(owner) ~= Manhunt.TEAM_FUGITIVE then return end
        
        local rechargeEnd = self:GetRechargeEnd()
        if rechargeEnd > 0 and CurTime() >= rechargeEnd then
            local charges = self:GetNWInt("ManhuntCharges", 0)
            if charges < 1 then
                self:SetNWInt("ManhuntCharges", 1)
                self:SetRechargeEnd(0)
                owner:ChatPrint("[Manhunt] Scanner recharged!")
                owner:EmitSound("items/battery_pickup.wav")
            end
        end
    end
end

-- Custom HUD
if CLIENT then
    function SWEP:DrawHUD()
        local charges = self:GetNWInt("ManhuntCharges", 0)
        local team = Manhunt.GetPlayerTeam(LocalPlayer())
        local isFugitive = team == Manhunt.TEAM_FUGITIVE
        local maxCharges = Manhunt.TestMode and 8 or (isFugitive and 1 or 5)

        local sw, sh = ScrW(), ScrH()
        local x = sw / 2
        local y = sh - 60

        -- Charges display
        local bgW = isFugitive and 220 or 200
        local bgH = 40
        draw.RoundedBox(6, x - bgW / 2, y - bgH / 2, bgW, bgH, Color(0, 0, 0, 180))

        -- Charge pips
        local pipSize = 20
        local pipSpacing = 30
        local startX = x - ((maxCharges - 1) * pipSpacing) / 2

        for i = 1, maxCharges do
            local pipX = startX + (i - 1) * pipSpacing
            local active = i <= charges
            local color = active and Color(50, 200, 255) or Color(50, 50, 50)
            draw.RoundedBox(pipSize / 2, pipX - pipSize / 2, y - pipSize / 2, pipSize, pipSize, color)
        end

        -- Recharge timer for fugitive
        if isFugitive and charges < 1 then
            local rechargeEnd = self:GetRechargeEnd()
            if rechargeEnd > CurTime() then
                local remaining = math.ceil(rechargeEnd - CurTime())
                local mins = math.floor(remaining / 60)
                local secs = remaining % 60
                local progress = 1 - (remaining / 300)
                
                -- Recharge bar
                local barW = bgW - 20
                local barH = 4
                local barX = x - barW / 2
                local barY = y + bgH / 2 + 4
                draw.RoundedBox(2, barX, barY, barW, barH, Color(30, 30, 30, 200))
                draw.RoundedBox(2, barX, barY, barW * progress, barH, Color(50, 150, 255, 200))
                
                draw.SimpleText(string.format("%d:%02d", mins, secs), "Manhunt_HUD_Small", x, barY + barH + 4, Color(150, 200, 255, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
            end
        end

        -- Label
        draw.SimpleText("SCANNER", "Manhunt_HUD_Small", x, y - bgH / 2 - 5, Color(200, 200, 200, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    end

    -- Custom world model rendering
    function SWEP:DrawWorldModel()
        self:DrawModel()
    end
end
