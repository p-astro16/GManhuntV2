--[[
    Manhunt - Server Tracking
    Position tracking, statistics collection, replay data
]]

Manhunt.TrackingData = {}
Manhunt.Stats = {}
Manhunt.ReplayData = {}

local TRACK_INTERVAL = 2 -- Record position every 2 seconds

-- Initialize tracking for a new game
function Manhunt.InitTracking()
    Manhunt.TrackingData = {}
    Manhunt.ReplayData = {}
    Manhunt.Stats = {
        hunterDamage = {},    -- {steamid = total_damage}
        closestDistance = 99999,
        fugitiveDistance = 0, -- Total distance moved by fugitive
        hunterDistance = {},  -- {steamid = total_distance}
        lastPositions = {},   -- Last known positions for distance calc
    }

    -- Initialize per-hunter stats
    for _, hunter in ipairs(Manhunt.GetHunters()) do
        local sid = hunter:SteamID()
        Manhunt.Stats.hunterDamage[sid] = 0
        Manhunt.Stats.hunterDistance[sid] = 0
    end
end

-- Start position tracking
function Manhunt.StartTracking()
    timer.Create("Manhunt_Tracking", TRACK_INTERVAL, 0, function()
        if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then
            timer.Remove("Manhunt_Tracking")
            return
        end

        local fugitive = Manhunt.GetFugitive()
        if not IsValid(fugitive) then return end

        local entry = {
            time = CurTime() - Manhunt.StartTime,
            fugitive = {fugitive:GetPos().x, fugitive:GetPos().y, fugitive:GetPos().z},
            hunters = {},
        }

        -- Track fugitive distance
        local fugSID = fugitive:SteamID()
        local lastFugPos = Manhunt.Stats.lastPositions[fugSID]
        if lastFugPos then
            Manhunt.Stats.fugitiveDistance = Manhunt.Stats.fugitiveDistance + fugitive:GetPos():Distance(lastFugPos)
        end
        Manhunt.Stats.lastPositions[fugSID] = fugitive:GetPos()

        -- Track hunters
        for _, hunter in ipairs(Manhunt.GetHunters()) do
            if IsValid(hunter) and hunter:Alive() then
                local hSID = hunter:SteamID()
                entry.hunters[hSID] = {hunter:GetPos().x, hunter:GetPos().y, hunter:GetPos().z}

                -- Track hunter distance
                local lastHPos = Manhunt.Stats.lastPositions[hSID]
                if lastHPos then
                    Manhunt.Stats.hunterDistance[hSID] = (Manhunt.Stats.hunterDistance[hSID] or 0) + hunter:GetPos():Distance(lastHPos)
                end
                Manhunt.Stats.lastPositions[hSID] = hunter:GetPos()

                -- Track closest distance
                local dist = fugitive:GetPos():Distance(hunter:GetPos())
                if dist < Manhunt.Stats.closestDistance then
                    Manhunt.Stats.closestDistance = dist
                end
            end
        end

        table.insert(Manhunt.ReplayData, entry)
    end)
end

-- Stop tracking
function Manhunt.StopTracking()
    timer.Remove("Manhunt_Tracking")
    Manhunt.StopViewpointRecording()
end

-- ============================================================
-- Viewpoint recording for kill cam replays
-- Records each player's EyePos + EyeAngles at 10Hz for last 4 seconds
-- ============================================================

Manhunt.ViewpointBuffers = {}
local VP_INTERVAL = 0.1   -- Record every 100ms
local VP_DURATION = 4     -- Keep last 4 seconds (40 entries max)

function Manhunt.StartViewpointRecording()
    Manhunt.ViewpointBuffers = {}

    timer.Create("Manhunt_ViewpointRecord", VP_INTERVAL, 0, function()
        if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then
            timer.Remove("Manhunt_ViewpointRecord")
            return
        end

        for _, ply in ipairs(player.GetAll()) do
            if IsValid(ply) and ply:Alive() then
                local sid = ply:SteamID()
                if not Manhunt.ViewpointBuffers[sid] then
                    Manhunt.ViewpointBuffers[sid] = {}
                end

                local buffer = Manhunt.ViewpointBuffers[sid]
                table.insert(buffer, {
                    pos = ply:EyePos(),
                    ang = ply:EyeAngles(),
                })

                -- Trim old entries (keep last VP_DURATION / VP_INTERVAL entries)
                local maxEntries = math.floor(VP_DURATION / VP_INTERVAL)
                while #buffer > maxEntries do
                    table.remove(buffer, 1)
                end
            end
        end
    end)
end

function Manhunt.StopViewpointRecording()
    timer.Remove("Manhunt_ViewpointRecord")
end

function Manhunt.GetViewpointBuffer(ply)
    if not IsValid(ply) then return {} end
    return Manhunt.ViewpointBuffers[ply:SteamID()] or {}
end

-- Track damage dealt by hunters
hook.Add("EntityTakeDamage", "Manhunt_TrackDamage", function(target, dmgInfo)
    if Manhunt.Phase ~= Manhunt.PHASE_ACTIVE then return end

    local attacker = dmgInfo:GetAttacker()
    if not IsValid(attacker) or not attacker:IsPlayer() then return end
    if not IsValid(target) or not target:IsPlayer() then return end

    -- Only track hunter → fugitive damage
    if Manhunt.GetPlayerTeam(attacker) == Manhunt.TEAM_HUNTER and
       Manhunt.GetPlayerTeam(target) == Manhunt.TEAM_FUGITIVE then
        local sid = attacker:SteamID()
        Manhunt.Stats.hunterDamage[sid] = (Manhunt.Stats.hunterDamage[sid] or 0) + dmgInfo:GetDamage()
    end

    -- Spawn protection check
    if target.ManhuntSpawnProtected then
        dmgInfo:ScaleDamage(0)
        return true
    end
end)

-- Send stats to all clients at end of game
function Manhunt.SendStats()
    -- Convert distances from source units to km (1 source unit ≈ 0.01905m)
    local fugDistKM = math.Round((Manhunt.Stats.fugitiveDistance * 0.01905) / 1000, 2)
    local closestDistM = math.Round(Manhunt.Stats.closestDistance * 0.01905, 1)

    net.Start("Manhunt_Stats")
    -- Fugitive distance moved (km)
    net.WriteFloat(fugDistKM)
    -- Closest distance (meters)
    net.WriteFloat(closestDistM)

    -- Hunter stats
    local hunters = Manhunt.GetHunters()
    net.WriteUInt(#hunters, 4)
    for _, hunter in ipairs(hunters) do
        local sid = hunter:SteamID()
        net.WriteString(hunter:Nick())
        net.WriteFloat(Manhunt.Stats.hunterDamage[sid] or 0)
        local hDistKM = math.Round(((Manhunt.Stats.hunterDistance[sid] or 0) * 0.01905) / 1000, 2)
        net.WriteFloat(hDistKM)
    end
    net.Broadcast()
end

-- Send replay data to all clients (compressed)
function Manhunt.SendReplayData()
    -- Reduce data: only send every 4th point for replay
    local compressed = {}
    for i, entry in ipairs(Manhunt.ReplayData) do
        if i % 2 == 0 or i == 1 or i == #Manhunt.ReplayData then
            table.insert(compressed, entry)
        end
    end

    -- Serialize replay data
    local data = util.TableToJSON(compressed)
    if not data then return end

    data = util.Compress(data)
    if not data then return end

    net.Start("Manhunt_ReplayData")
    net.WriteUInt(#data, 32)
    net.WriteData(data, #data)
    net.Broadcast()
end
