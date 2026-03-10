--[[
    Manhunt - Garry's Mod Addon
    A cat-and-mouse game: Fugitive vs Hunter(s)
]]

Manhunt = Manhunt or {}

print("[Manhunt] ============================================")
print("[Manhunt] Initializing Manhunt addon...")
print("[Manhunt] Realm: " .. (SERVER and "SERVER" or "CLIENT"))

local function AddFile(path)
    local prefix = string.sub(string.GetFileFromFilename(path), 1, 3)
    if prefix == "sv_" then
        if SERVER then
            local ok, err = pcall(include, path)
            if ok then
                print("[Manhunt] [SV] Loaded: " .. path)
            else
                print("[Manhunt] [SV] ERROR loading " .. path .. ": " .. tostring(err))
            end
        end
    elseif prefix == "cl_" then
        if SERVER then AddCSLuaFile(path) end
        if CLIENT then
            local ok, err = pcall(include, path)
            if ok then
                print("[Manhunt] [CL] Loaded: " .. path)
            else
                print("[Manhunt] [CL] ERROR loading " .. path .. ": " .. tostring(err))
            end
        end
    elseif prefix == "sh_" then
        if SERVER then AddCSLuaFile(path) end
        local ok, err = pcall(include, path)
        if ok then
            print("[Manhunt] [SH] Loaded: " .. path .. " (" .. (SERVER and "SERVER" or "CLIENT") .. ")")
        else
            print("[Manhunt] [SH] ERROR loading " .. path .. ": " .. tostring(err))
        end
    end
end

-- Shared (load first)
AddFile("manhunt/sh_config.lua")
AddFile("manhunt/sh_gamestate.lua")
AddFile("manhunt/sh_chase_config.lua")

-- Server
AddFile("manhunt/sv_teams.lua")
AddFile("manhunt/sv_inventory.lua")
AddFile("manhunt/sv_vehicles.lua")
AddFile("manhunt/sv_tracking.lua")
AddFile("manhunt/sv_rounds.lua")
AddFile("manhunt/sv_tutorial.lua")
AddFile("manhunt/sv_zone.lua")
AddFile("manhunt/sv_pickups.lua")
AddFile("manhunt/sv_chase.lua")
AddFile("manhunt/sv_chase_pickups.lua")
AddFile("manhunt/sv_game.lua")

-- Client
AddFile("manhunt/cl_menu.lua")
AddFile("manhunt/cl_hud.lua")
AddFile("manhunt/cl_camera.lua")
AddFile("manhunt/cl_ping.lua")
AddFile("manhunt/cl_lobby.lua")
AddFile("manhunt/cl_endgame.lua")
AddFile("manhunt/cl_replay.lua")
AddFile("manhunt/cl_decoy.lua")
AddFile("manhunt/cl_killcam.lua")
AddFile("manhunt/cl_rounds.lua")
AddFile("manhunt/cl_cinematic.lua")
AddFile("manhunt/cl_vbeacon.lua")
AddFile("manhunt/cl_drone.lua")
AddFile("manhunt/cl_tutorial.lua")
AddFile("manhunt/cl_zone.lua")
AddFile("manhunt/cl_pickups.lua")
AddFile("manhunt/cl_chase.lua")

print("[Manhunt] ============================================")
print("[Manhunt] Addon fully loaded! Realm: " .. (SERVER and "SERVER" or "CLIENT"))
print("[Manhunt] ============================================")
