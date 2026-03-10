--[[
    Manhunt - Server Inventory
    Inventory management, spawn blocking, hunter cooldowns
]]

Manhunt.HunterSpawnTimes = Manhunt.HunterSpawnTimes or {}
local HUNTER_SPAWN_COOLDOWN = 120 -- 2 minutes

-- Clear a player's inventory completely
function Manhunt.ClearInventory(ply)
    if not IsValid(ply) then return end
    ply:StripWeapons()
    ply:StripAmmo()
end

-- Give fugitive their starting loadout
function Manhunt.GiveFugitiveLoadout(ply)
    if not IsValid(ply) then return end

    Manhunt.ClearInventory(ply)

    timer.Simple(0.5, function()
        if not IsValid(ply) then return end
        ply:Give("arc9_eft_m7290")    -- Flash grenade
        ply:Give("arc9_eft_m18")      -- Smoke grenade
        ply:Give("weapon_medkit")     -- Medkit
        ply:Give("weapon_manhunt_scanner")  -- Scanner (1 charge for fugitive, recharges)
        ply:Give("weapon_manhunt_carbomb")  -- Car bomb (1 use)
        ply:Give("weapon_manhunt_vbeacon")  -- Vehicle beacon (throw to spawn car)
        ply:Give("weapon_manhunt_decoy")    -- Decoy grenade (fake scanner blip)

        -- Set scanner charges
        local scanner = ply:GetWeapon("weapon_manhunt_scanner")
        if IsValid(scanner) then
            scanner:SetNWInt("ManhuntCharges", 1)
        end

        local carbomb = ply:GetWeapon("weapon_manhunt_carbomb")
        if IsValid(carbomb) then
            carbomb:SetNWInt("ManhuntCharges", 1)
        end
    end)
end

-- Give hunter their scanner weapon
function Manhunt.GiveHunterLoadout(ply)
    if not IsValid(ply) then return end

    timer.Simple(0.5, function()
        if not IsValid(ply) then return end
        ply:Give("weapon_manhunt_scanner")
        ply:Give("weapon_manhunt_airstrike")
        ply:Give("weapon_manhunt_vbeacon")  -- Vehicle beacon (throw to spawn car)
        ply:Give("weapon_manhunt_drone")    -- Recon drone (bird's eye view)
        ply:Give("weapon_manhunt_carbomb")  -- Car bomb (infinite with 2min cooldown)

        -- Set scanner charges (retry to ensure weapon entity is ready)
        timer.Simple(0.1, function()
            if not IsValid(ply) then return end
            local scanner = ply:GetWeapon("weapon_manhunt_scanner")
            if IsValid(scanner) then
                scanner:SetNWInt("ManhuntCharges", 5)
            end
            -- Set car bomb charge
            local carbomb = ply:GetWeapon("weapon_manhunt_carbomb")
            if IsValid(carbomb) then
                carbomb:SetNWInt("ManhuntCharges", 1)
            end
        end)
    end)
end

-- Give test mode loadout (combined fugitive + hunter, extra charges)
function Manhunt.GiveTestModeLoadout(ply)
    if not IsValid(ply) then return end

    Manhunt.ClearInventory(ply)

    timer.Simple(0.5, function()
        if not IsValid(ply) then return end
        ply:Give("arc9_eft_m7290")    -- Flash grenade
        ply:Give("arc9_eft_m18")      -- Smoke grenade
        ply:Give("weapon_medkit")     -- Medkit
        ply:Give("weapon_manhunt_scanner")  -- Scanner (8 charges = 3+5)
        ply:Give("weapon_manhunt_carbomb")  -- Car bomb (1 use)
        ply:Give("weapon_manhunt_airstrike")  -- Airstrike (1 use, available after 80%)
        ply:Give("weapon_manhunt_vbeacon")  -- Vehicle beacon
        ply:Give("weapon_manhunt_drone")    -- Recon drone
        ply:Give("weapon_manhunt_decoy")    -- Decoy grenade

        -- Combined charges
        local scanner = ply:GetWeapon("weapon_manhunt_scanner")
        if IsValid(scanner) then
            scanner:SetNWInt("ManhuntCharges", 8) -- 3 fugitive + 5 hunter
        end

        local carbomb = ply:GetWeapon("weapon_manhunt_carbomb")
        if IsValid(carbomb) then
            carbomb:SetNWInt("ManhuntCharges", 1)
        end
    end)
end

-- Re-give test mode loadout on respawn
hook.Add("PlayerSpawn", "Manhunt_TestModeRespawn", function(ply)
    if not Manhunt.TestMode then return end
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end

    timer.Simple(0.1, function()
        if not IsValid(ply) then return end
        Manhunt.GiveTestModeLoadout(ply)
        Manhunt.ApplySpawnProtection(ply, 3)
    end)
end)

-- Block fugitive from spawning anything (skip in test mode)
local function BlockFugitiveSpawn(ply)
    if not Manhunt.IsActive() then return end
    if Manhunt.TestMode then return end -- Allow spawning in test mode
    if Manhunt.GetPlayerTeam(ply) == Manhunt.TEAM_FUGITIVE then
        return false
    end
end

-- Hunter spawn cooldown (disabled - hunters can spawn freely)
local function HunterSpawnCooldown(ply)
    return -- no cooldown
end

-- Block spawning hooks for fugitive + cooldown for hunter
hook.Add("PlayerSpawnObject", "Manhunt_BlockSpawn", function(ply) 
    local result = BlockFugitiveSpawn(ply)
    if result == false then return false end
    return HunterSpawnCooldown(ply)
end)

hook.Add("PlayerSpawnSENT", "Manhunt_BlockSpawnSENT", function(ply)
    local result = BlockFugitiveSpawn(ply)
    if result == false then return false end
    return HunterSpawnCooldown(ply)
end)

hook.Add("PlayerSpawnSWEP", "Manhunt_BlockSpawnSWEP", function(ply)
    local result = BlockFugitiveSpawn(ply)
    if result == false then return false end
    return HunterSpawnCooldown(ply)
end)

hook.Add("PlayerSpawnVehicle", "Manhunt_BlockSpawnVehicle", function(ply)
    local result = BlockFugitiveSpawn(ply)
    if result == false then return false end
    return HunterSpawnCooldown(ply)
end)

hook.Add("PlayerSpawnNPC", "Manhunt_BlockSpawnNPC", function(ply)
    local result = BlockFugitiveSpawn(ply)
    if result == false then return false end
    return HunterSpawnCooldown(ply)
end)

hook.Add("PlayerSpawnProp", "Manhunt_BlockSpawnProp", function(ply)
    local result = BlockFugitiveSpawn(ply)
    if result == false then return false end
    return HunterSpawnCooldown(ply)
end)

hook.Add("PlayerSpawnRagdoll", "Manhunt_BlockSpawnRagdoll", function(ply)
    local result = BlockFugitiveSpawn(ply)
    if result == false then return false end
    return HunterSpawnCooldown(ply)
end)

hook.Add("PlayerSpawnEffect", "Manhunt_BlockSpawnEffect", function(ply)
    local result = BlockFugitiveSpawn(ply)
    if result == false then return false end
    return HunterSpawnCooldown(ply)
end)

hook.Add("CanTool", "Manhunt_BlockTool", function(ply)
    if not Manhunt.IsActive() then return end
    if Manhunt.GetPlayerTeam(ply) == Manhunt.TEAM_FUGITIVE then
        return false
    end
end)

-- Block fugitive from picking up weapons during game (skip in test mode)
hook.Add("PlayerCanPickupWeapon", "Manhunt_BlockPickup", function(ply, wep)
    if not Manhunt.IsActive() then return end
    if Manhunt.TestMode then return end -- Allow pickup in test mode
    if Manhunt.GetPlayerTeam(ply) == Manhunt.TEAM_FUGITIVE then
        local allowed = {
            ["arc9_eft_m7290"] = true,
            ["arc9_eft_m18"] = true,
            ["arc9_eft_fn57"] = true,
            ["weapon_medkit"] = true,
            ["weapon_manhunt_scanner"] = true,
            ["weapon_manhunt_carbomb"] = true,
            ["weapon_manhunt_vbeacon"] = true,
            ["weapon_manhunt_decoy"] = true,
        }
        if not allowed[wep:GetClass()] then
            return false
        end
    end
end)

-- Anti-cheese: block noclip during active game (allow outside of games and in test mode)
hook.Add("PlayerNoClip", "Manhunt_BlockNoclip", function(ply)
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end -- only block during active game
    if Manhunt.TestMode then return end -- Allow noclip in test mode
    return false
end)

-- Spawn protection
function Manhunt.ApplySpawnProtection(ply, duration)
    if not IsValid(ply) then return end
    ply:GodEnable()
    ply.ManhuntSpawnProtected = true

    net.Start("Manhunt_SpawnProtect")
    net.WriteBool(true)
    net.Send(ply)

    timer.Create("Manhunt_SpawnProtection_" .. ply:SteamID(), duration, 1, function()
        if not IsValid(ply) then return end
        ply:GodDisable()
        ply.ManhuntSpawnProtected = false

        net.Start("Manhunt_SpawnProtect")
        net.WriteBool(false)
        net.Send(ply)
    end)
end
