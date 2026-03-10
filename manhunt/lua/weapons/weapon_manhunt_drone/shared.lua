--[[
    Manhunt - Hunter Drone SWEP
    Hunters can deploy a bird's eye drone camera they control with WASD
    Duration: 5 seconds, Cooldown: 60 seconds
    The drone gives a top-down view centered on the hunter's position
    Use to scout the area for the fugitive
]]

AddCSLuaFile()

SWEP.PrintName = "Recon Drone"
SWEP.Author = "Manhunt"
SWEP.Instructions = "Deploy a bird's eye drone to scout for the fugitive"
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
SWEP.SlotPos = 3
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_slam.mdl"
SWEP.WorldModel = "models/weapons/w_slam.mdl"
SWEP.HoldType = "slam"

SWEP.UseHands = true

local DRONE_DURATION = 15       -- How long the drone lasts
local DRONE_COOLDOWN = 60       -- Cooldown between uses
local DRONE_HEIGHT = 1500       -- Height above the player (initial)
local DRONE_SPEED = 1600        -- Movement speed (units/sec)
local DRONE_MAX_RANGE = 4000    -- Max distance from deploy point

function SWEP:Initialize()
    self:SetHoldType("slam")
end

function SWEP:SetupDataTables()
    self:NetworkVar("Float", 0, "NextDroneTime")
    self:NetworkVar("Bool", 0, "DroneActive")
end

function SWEP:PrimaryAttack()
    if not IsFirstTimePredicted() then return end
    self:SetNextPrimaryFire(CurTime() + 1)

    if self:GetDroneActive() then return end

    -- Check cooldown
    local nextTime = self:GetNextDroneTime()
    if nextTime > CurTime() then
        if CLIENT then
            local remaining = math.ceil(nextTime - CurTime())
            chat.AddText(Color(255, 100, 100), "[Manhunt] ", Color(255, 255, 255), "Drone cooldown: " .. remaining .. "s")
            surface.PlaySound("buttons/button10.wav")
        end
        return
    end

    if SERVER then
        local owner = self:GetOwner()
        if not IsValid(owner) then return end

        -- Activate drone
        self:SetDroneActive(true)

        -- Send drone activation to the owner
        net.Start("Manhunt_DroneActivate")
        net.WriteVector(owner:GetPos())
        net.WriteFloat(DRONE_DURATION)
        net.Send(owner)

        -- Play deploy sound
        owner:EmitSound("buttons/blip2.wav")

        -- Block movement but keep weapon/view working
        owner:SetMoveType(MOVETYPE_NONE)

        -- Timer to end drone
        timer.Create("Manhunt_Drone_" .. owner:SteamID(), DRONE_DURATION, 1, function()
            if IsValid(self) then
                self:EndDrone()
            elseif IsValid(owner) then
                owner:SetMoveType(MOVETYPE_WALK)
            end
        end)
    end

    if CLIENT then
        surface.PlaySound("buttons/blip2.wav")
    end
end

function SWEP:EndDrone()
    if not SERVER then return end

    self:SetDroneActive(false)

    -- Set cooldown (skip in test mode)
    if not (Manhunt and Manhunt.TestMode) then
        self:SetNextDroneTime(CurTime() + DRONE_COOLDOWN)
    else
        self:SetNextDroneTime(CurTime() + 5) -- Short cooldown in test mode
    end

    local owner = self:GetOwner()
    if IsValid(owner) then
        owner:SetMoveType(MOVETYPE_WALK)
        owner:EmitSound("buttons/button15.wav")

        -- Tell client to deactivate
        net.Start("Manhunt_DroneDeactivate")
        net.Send(owner)
    end
end

function SWEP:SecondaryAttack()
    -- Secondary: cancel drone early
    if not IsFirstTimePredicted() then return end
    if not self:GetDroneActive() then return end

    if SERVER then
        timer.Remove("Manhunt_Drone_" .. self:GetOwner():SteamID())
        self:EndDrone()
    end
end

function SWEP:OnRemove()
    if SERVER and self:GetDroneActive() then
        local owner = self:GetOwner()
        if IsValid(owner) then
            owner:SetMoveType(MOVETYPE_WALK)
            timer.Remove("Manhunt_Drone_" .. owner:SteamID())
        end
    end
end

function SWEP:Holster()
    -- Can't holster during active drone
    if self:GetDroneActive() then return false end
    return true
end

function SWEP:Reload()
    -- No reload
end

function SWEP:Think()
    -- Auto-end drone if owner dies
    if SERVER and self:GetDroneActive() then
        local owner = self:GetOwner()
        if not IsValid(owner) or not owner:Alive() then
            timer.Remove("Manhunt_Drone_" .. (IsValid(owner) and owner:SteamID() or ""))
            self:EndDrone()
        end
    end
end

-- Custom HUD
if CLIENT then
    function SWEP:DrawHUD()
        local sw, sh = ScrW(), ScrH()
        local x = sw / 2
        local y = sh - 60

        if self:GetDroneActive() then
            -- Show "DRONE ACTIVE" when in use
            draw.RoundedBox(6, x - 80, y - 18, 160, 36, Color(0, 150, 255, 180))
            draw.SimpleText("DRONE ACTIVE", "Manhunt_HUD_Small", x, y, Color(255, 255, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            local nextTime = self:GetNextDroneTime()
            local cooldownLeft = math.max(0, nextTime - CurTime())

            local bgW = 200
            local bgH = 40
            draw.RoundedBox(6, x - bgW / 2, y - bgH / 2, bgW, bgH, Color(0, 0, 0, 180))

            if cooldownLeft > 0 then
                -- Cooldown bar
                local fraction = cooldownLeft / DRONE_COOLDOWN
                draw.RoundedBox(4, x - bgW / 2 + 4, y - bgH / 2 + 4, (bgW - 8) * (1 - fraction), bgH - 8, Color(50, 100, 200, 120))
                draw.SimpleText("DRONE: " .. math.ceil(cooldownLeft) .. "s", "Manhunt_HUD_Small", x, y, Color(150, 150, 150), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            else
                draw.RoundedBox(4, x - bgW / 2 + 4, y - bgH / 2 + 4, bgW - 8, bgH - 8, Color(0, 150, 255, 80))
                draw.SimpleText("DRONE READY", "Manhunt_HUD_Small", x, y, Color(50, 200, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
            end

            draw.SimpleText("RECON DRONE", "Manhunt_HUD_Small", x, y - bgH / 2 - 5, Color(200, 200, 200, 180), TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
        end
    end

    function SWEP:DrawWorldModel()
        self:DrawModel()
    end
end
