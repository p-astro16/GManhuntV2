--[[
    Manhunt - High Speed Chase Config (Shared)
    Gamemode definitions, ability configs, net strings
]]

Manhunt.Chase = Manhunt.Chase or {}

-- Gamemode enum
Manhunt.GAMEMODE_CLASSIC = 0
Manhunt.GAMEMODE_CHASE = 1

-- Current gamemode (default classic)
Manhunt.Gamemode = Manhunt.Gamemode or Manhunt.GAMEMODE_CLASSIC

-- Chase-specific config defaults
Manhunt.Chase.DefaultConfig = {
    GameTime = 10,           -- minutes
    Interval = 2,            -- minutes (scan interval, kept for compatibility)
}

-- Win conditions
Manhunt.Chase.STATIONARY_THRESHOLD = 5    -- seconds stationary = fugitive loses
Manhunt.Chase.STATIONARY_SPEED = 5        -- km/h below this = "stationary"
Manhunt.Chase.EXIT_VEHICLE_TIME = 5       -- seconds to get back in car or lose
Manhunt.Chase.COUNTDOWN_TIME = 10         -- seconds before game starts

-- Ability types
Manhunt.Chase.ABILITY_NONE = 0
Manhunt.Chase.ABILITY_OIL_SLICK = 1
Manhunt.Chase.ABILITY_SMOKE_SCREEN = 2
Manhunt.Chase.ABILITY_EMP_BLAST = 3
Manhunt.Chase.ABILITY_NITRO_BOOST = 4
Manhunt.Chase.ABILITY_SHIELD = 5
Manhunt.Chase.ABILITY_GHOST_MODE = 6
Manhunt.Chase.ABILITY_SHOCKWAVE = 7
Manhunt.Chase.ABILITY_ROADBLOCK = 8
Manhunt.Chase.ABILITY_MISSILE = 9
Manhunt.Chase.ABILITY_TRACKER_DART = 10
Manhunt.Chase.ABILITY_REPAIR_KIT = 11
Manhunt.Chase.ABILITY_SPEED_TRAP = 12

-- Ability definitions
Manhunt.Chase.Abilities = {
    [Manhunt.Chase.ABILITY_OIL_SLICK] = {
        name = "Oil Slick",
        team = Manhunt.TEAM_FUGITIVE,
        color = Color(40, 40, 40),
        icon = "O",
        duration = 8,       -- how long the slick stays
        cooldown = 15,
        description = "Drop oil behind your car, causes spin-out",
    },
    [Manhunt.Chase.ABILITY_SMOKE_SCREEN] = {
        name = "Smoke Screen",
        team = Manhunt.TEAM_FUGITIVE,
        color = Color(150, 150, 150),
        icon = "S",
        duration = 6,
        cooldown = 20,
        description = "Deploy thick smoke cloud behind you",
    },
    [Manhunt.Chase.ABILITY_EMP_BLAST] = {
        name = "EMP Blast",
        team = Manhunt.TEAM_FUGITIVE,
        color = Color(0, 150, 255),
        icon = "E",
        radius = 1500,
        stunDuration = 3,   -- seconds vehicles are disabled
        cooldown = 30,
        description = "Disable nearby hunter vehicles briefly",
    },
    [Manhunt.Chase.ABILITY_NITRO_BOOST] = {
        name = "Nitro Boost",
        team = 0,            -- 0 = both teams
        color = Color(255, 100, 0),
        icon = "N",
        boostDuration = 3,
        boostForce = 800000,
        cooldown = 12,
        description = "Massive speed boost forward",
    },
    [Manhunt.Chase.ABILITY_SHIELD] = {
        name = "Shield",
        team = Manhunt.TEAM_FUGITIVE,
        color = Color(0, 200, 255),
        icon = "SH",
        duration = 4,
        cooldown = 25,
        description = "Temporary invulnerability shield",
    },
    [Manhunt.Chase.ABILITY_GHOST_MODE] = {
        name = "Ghost Mode",
        team = Manhunt.TEAM_FUGITIVE,
        color = Color(200, 200, 255),
        icon = "G",
        duration = 5,
        cooldown = 35,
        description = "Become invisible and pass through vehicles",
    },
    [Manhunt.Chase.ABILITY_SHOCKWAVE] = {
        name = "Shockwave",
        team = Manhunt.TEAM_HUNTER,
        color = Color(255, 50, 50),
        icon = "SW",
        radius = 800,
        knockForce = 600000,
        cooldown = 18,
        description = "Push nearby vehicles away with force",
    },
    [Manhunt.Chase.ABILITY_ROADBLOCK] = {
        name = "Roadblock",
        team = Manhunt.TEAM_HUNTER,
        color = Color(200, 100, 0),
        icon = "RB",
        duration = 15,
        cooldown = 25,
        description = "Spawn barriers ahead on the road",
    },
    [Manhunt.Chase.ABILITY_MISSILE] = {
        name = "Missile",
        team = Manhunt.TEAM_HUNTER,
        color = Color(255, 0, 0),
        icon = "M",
        damage = 150,
        speed = 3000,
        cooldown = 20,
        description = "Lock on and fire a homing missile",
    },
    [Manhunt.Chase.ABILITY_TRACKER_DART] = {
        name = "Tracker Dart",
        team = Manhunt.TEAM_HUNTER,
        color = Color(0, 255, 100),
        icon = "TD",
        trackDuration = 15,
        cooldown = 30,
        description = "Tag fugitive - reveals position for 15s",
    },
    [Manhunt.Chase.ABILITY_REPAIR_KIT] = {
        name = "Repair Kit",
        team = 0,            -- both teams
        color = Color(0, 255, 0),
        icon = "+",
        healAmount = 200,
        cooldown = 0,        -- single use pickup
        description = "Repair your vehicle's health",
    },
    [Manhunt.Chase.ABILITY_SPEED_TRAP] = {
        name = "Speed Trap",
        team = 0,            -- both teams
        color = Color(255, 255, 0),
        icon = "ST",
        slowDuration = 3,
        slowFactor = 0.3,
        cooldown = 0,        -- placed trap
        description = "Place a trap that slows vehicles driving over it",
    },
}

-- Pickup spawning config
Manhunt.Chase.PickupConfig = {
    SpawnInterval = 20,       -- seconds between pickup spawns
    MaxPickups = 8,           -- max active pickups on map
    MinDistance = 500,         -- min distance between pickups
    CollectRadius = 200,      -- drive-through collection radius
}

-- Vehicle health
Manhunt.Chase.MaxVehicleHealth = 1000

-- Fugitive starting abilities (each has 1 charge to start)
Manhunt.Chase.FugitiveAbilities = {
    Manhunt.Chase.ABILITY_OIL_SLICK,
    Manhunt.Chase.ABILITY_SMOKE_SCREEN,
    Manhunt.Chase.ABILITY_EMP_BLAST,
    Manhunt.Chase.ABILITY_NITRO_BOOST,
    Manhunt.Chase.ABILITY_SHIELD,
    Manhunt.Chase.ABILITY_GHOST_MODE,
}

-- Hunter starting abilities
Manhunt.Chase.HunterAbilities = {
    Manhunt.Chase.ABILITY_NITRO_BOOST,
    Manhunt.Chase.ABILITY_SHOCKWAVE,
    Manhunt.Chase.ABILITY_ROADBLOCK,
    Manhunt.Chase.ABILITY_MISSILE,
    Manhunt.Chase.ABILITY_TRACKER_DART,
}

-- Abilities that can spawn as pickups (recharges)
Manhunt.Chase.PickupAbilities = {
    Manhunt.Chase.ABILITY_OIL_SLICK,
    Manhunt.Chase.ABILITY_SMOKE_SCREEN,
    Manhunt.Chase.ABILITY_NITRO_BOOST,
    Manhunt.Chase.ABILITY_SHIELD,
    Manhunt.Chase.ABILITY_SHOCKWAVE,
    Manhunt.Chase.ABILITY_MISSILE,
    Manhunt.Chase.ABILITY_REPAIR_KIT,
    Manhunt.Chase.ABILITY_SPEED_TRAP,
}

-- Register chase-specific network strings
if SERVER then
    util.AddNetworkString("Manhunt_ChaseSync")
    util.AddNetworkString("Manhunt_ChaseAbilityUse")
    util.AddNetworkString("Manhunt_ChaseAbilityGrant")
    util.AddNetworkString("Manhunt_ChasePickupSpawn")
    util.AddNetworkString("Manhunt_ChasePickupCollect")
    util.AddNetworkString("Manhunt_ChaseEffect")
    util.AddNetworkString("Manhunt_ChaseExitWarning")
    util.AddNetworkString("Manhunt_ChaseStationaryWarn")
    util.AddNetworkString("Manhunt_ChaseTracker")
    util.AddNetworkString("Manhunt_ChaseVehicleHealth")
    util.AddNetworkString("Manhunt_ChaseGamemode")
end

-- Helper: is chase mode?
function Manhunt.IsChaseMode()
    return Manhunt.Gamemode == Manhunt.GAMEMODE_CHASE
end

-- Helper: get ability info
function Manhunt.Chase.GetAbility(id)
    return Manhunt.Chase.Abilities[id]
end

-- Helper: can this team use this ability?
function Manhunt.Chase.CanTeamUse(abilityId, team)
    local ability = Manhunt.Chase.Abilities[abilityId]
    if not ability then return false end
    return ability.team == 0 or ability.team == team
end

print("[Manhunt] sh_chase_config.lua loaded (" .. (SERVER and "SERVER" or "CLIENT") .. ")")
