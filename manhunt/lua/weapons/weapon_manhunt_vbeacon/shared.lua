--[[
    Manhunt - Vehicle Beacon SWEP
    Fugitive throws this grenade to mark where their vehicle spawns
    Grenade lands → marker appears → 3 second countdown → car spawns
]]

AddCSLuaFile()

SWEP.PrintName = "Vehicle Beacon"
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
SWEP.SlotPos = 4
SWEP.DrawAmmo = false
SWEP.DrawCrosshair = true

SWEP.ViewModel = "models/weapons/c_grenade.mdl"
SWEP.WorldModel = "models/weapons/w_grenade.mdl"
SWEP.HoldType = "grenade"

SWEP.UseHands = true

function SWEP:Initialize()
    self:SetHoldType("grenade")
end

function SWEP:SetupDataTables()
    self:NetworkVar("Bool", 0, "BeaconUsed")
    self:NetworkVar("Float", 0, "CooldownEnd") -- hunter cooldown end time
end

function SWEP:PrimaryAttack()
    if not IsFirstTimePredicted() then return end
    self:SetNextPrimaryFire(CurTime() + 1)

    local owner = self:GetOwner()
    if not IsValid(owner) then return end

    local isHunter = Manhunt and Manhunt.GetPlayerTeam and Manhunt.GetPlayerTeam(owner) == Manhunt.TEAM_HUNTER

    if not (Manhunt and Manhunt.TestMode) then
        if isHunter then
            -- Hunter: infinite uses, but 2-minute cooldown
            if self:GetCooldownEnd() > CurTime() then
                if CLIENT then
                    local remaining = math.ceil(self:GetCooldownEnd() - CurTime())
                    local mins = math.floor(remaining / 60)
                    local secs = remaining % 60
                    notification.AddLegacy(string.format("Vehicle beacon on cooldown! %d:%02d remaining", mins, secs), NOTIFY_ERROR, 2)
                end
                return
            end
        else
            -- Fugitive: single use
            if self:GetBeaconUsed() then
                if CLIENT then
                    notification.AddLegacy("Vehicle beacon already used!", NOTIFY_ERROR, 2)
                end
                return
            end
        end
    end

    if SERVER then
        -- Create a thrown grenade prop
        local throwDir = owner:GetAimVector()
        local throwPos = owner:GetShootPos() + throwDir * 10

        local beacon = ents.Create("prop_physics")
        if not IsValid(beacon) then return end

        beacon:SetModel("models/weapons/w_grenade.mdl")
        beacon:SetPos(throwPos)
        beacon:SetAngles(owner:EyeAngles())
        beacon:Spawn()
        beacon:Activate()

        -- Scale it down a bit
        beacon:SetModelScale(0.8)

        -- Throw it
        local phys = beacon:GetPhysicsObject()
        if IsValid(phys) then
            phys:SetVelocity(throwDir * 600 + Vector(0, 0, 200))
            phys:AddAngleVelocity(VectorRand() * 200)
        end

        -- Play throw sound
        owner:EmitSound("weapons/grenade/grmagnet_pickup.wav", 70, 100)

        -- Mark as used / set cooldown (skip in test mode for infinite uses)
        if not Manhunt.TestMode then
            local isHunterSV = Manhunt.GetPlayerTeam and Manhunt.GetPlayerTeam(owner) == Manhunt.TEAM_HUNTER
            if isHunterSV then
                self:SetCooldownEnd(CurTime() + 120) -- 2 minute cooldown
            else
                self:SetBeaconUsed(true) -- fugitive single use
            end
        end

        -- Track the beacon entity
        local beaconOwner = owner

        -- When the grenade stops or after a short delay, place the marker
        timer.Simple(1.5, function()
            if not IsValid(beacon) then return end

            local landPos = beacon:GetPos()

            -- Trace down to find the ground
            local tr = util.TraceLine({
                start = landPos + Vector(0, 0, 10),
                endpos = landPos - Vector(0, 0, 100),
                mask = MASK_SOLID_BRUSHONLY,
            })

            local spawnPos = tr.HitPos or landPos

            -- Remove the grenade prop
            beacon:Remove()

            -- Create a visible marker effect at the spot
            local marker = ents.Create("prop_dynamic")
            if IsValid(marker) then
                marker:SetModel("models/hunter/plates/plate.mdl")
                marker:SetPos(spawnPos + Vector(0, 0, 1))
                marker:SetAngles(Angle(0, 0, 0))
                marker:SetModelScale(2)
                marker:SetColor(Color(50, 150, 255, 200))
                marker:SetRenderMode(RENDERMODE_TRANSALPHA)
                marker:Spawn()
                marker:Activate()

                -- Glow effect
                marker:SetMaterial("models/debug/debugwhite")
            end

            -- Notify the vehicle spawn location
            net.Start("Manhunt_VehicleBeacon")
            net.WriteVector(spawnPos)
            net.WriteFloat(3) -- countdown seconds
            net.Broadcast()

            -- Play beacon sound
            sound.Play("ambient/machines/thumper_startup1.wav", spawnPos, 80, 100)

            -- Notify owner
            if IsValid(beaconOwner) then
                beaconOwner:ChatPrint("[Manhunt] Vehicle spawning in 3 seconds!")
            end

            -- Spawn vehicle after 3 seconds
            timer.Simple(3, function()
                -- Remove marker
                if IsValid(marker) then
                    marker:Remove()
                end

                -- Spawn the vehicle at the marker position
                if Manhunt and Manhunt.SpawnFugitiveVehicleAt then
                    Manhunt.SpawnFugitiveVehicleAt(spawnPos, beaconOwner)
                end

                -- Spawn effect
                local ef = EffectData()
                ef:SetOrigin(spawnPos)
                ef:SetScale(2)
                util.Effect("propspawn", ef)

                sound.Play("ambient/machines/thumper_hit.wav", spawnPos, 80, 80)
            end)
        end)
    end

    -- Weapon swing animation
    local vm = owner:GetViewModel()
    if IsValid(vm) then
        vm:SendViewModelMatchingSequence(vm:SelectWeightedSequence(ACT_VM_THROW))
    end
end

function SWEP:SecondaryAttack()
end

function SWEP:Reload()
end

-- HUD
function SWEP:DrawHUD()
    local sw, sh = ScrW(), ScrH()

    local owner = self:GetOwner()
    local isHunter = IsValid(owner) and Manhunt and Manhunt.GetPlayerTeam and Manhunt.GetPlayerTeam(owner) == Manhunt.TEAM_HUNTER

    if isHunter then
        -- Hunter HUD: show cooldown or ready
        local cooldownEnd = self:GetCooldownEnd()
        if cooldownEnd > CurTime() then
            local remaining = math.ceil(cooldownEnd - CurTime())
            local mins = math.floor(remaining / 60)
            local secs = remaining % 60
            local progress = 1 - (remaining / 120)
            
            draw.RoundedBox(6, sw / 2 - 130, sh - 80, 260, 35, Color(40, 30, 30, 200))
            -- Cooldown bar
            draw.RoundedBox(4, sw / 2 - 126, sh - 76, 252 * progress, 27, Color(50, 80, 150, 100))
            draw.SimpleText(string.format("COOLDOWN %d:%02d", mins, secs), "Manhunt_HUD_Small", sw / 2, sh - 62, Color(150, 150, 200), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            local pulse = math.abs(math.sin(CurTime() * 3))
            draw.RoundedBox(6, sw / 2 - 130, sh - 80, 260, 35, Color(30, 50, 30, 200))
            draw.SimpleText("Throw to spawn your vehicle", "Manhunt_HUD_Small", sw / 2, sh - 62, Color(50 + pulse * 100, 200, 50 + pulse * 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    else
        -- Fugitive HUD: single use
        if self:GetBeaconUsed() then
            draw.RoundedBox(6, sw / 2 - 110, sh - 80, 220, 35, Color(30, 60, 80, 200))
            draw.SimpleText("VEHICLE BEACON DEPLOYED", "Manhunt_HUD_Small", sw / 2, sh - 62, Color(50, 150, 255), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        else
            local pulse = math.abs(math.sin(CurTime() * 3))
            draw.RoundedBox(6, sw / 2 - 130, sh - 80, 260, 35, Color(30, 50, 30, 200))
            draw.SimpleText("Throw to spawn your vehicle", "Manhunt_HUD_Small", sw / 2, sh - 62, Color(50 + pulse * 100, 200, 50 + pulse * 100), TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end
    end
end

function SWEP:CanBePickedUpByNPCs() return false end
