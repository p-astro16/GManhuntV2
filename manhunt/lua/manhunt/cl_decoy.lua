--[[
    Manhunt - Client Decoy System
    Fugitive throws a decoy grenade to place a fake blip
    Now handled by weapon_manhunt_decoy SWEP
]]

-- Receive decoy sync (visual confirmation for fugitive)
net.Receive("Manhunt_DecoySync", function()
    local pos = net.ReadVector()
    local active = net.ReadBool()

    if active then
        chat.AddText(Color(255, 200, 50), "[Manhunt] ", Color(255, 255, 255), "Decoy grenade deployed! Fake blip active.")
    end
end)
