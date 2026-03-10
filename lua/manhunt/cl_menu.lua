--[[
    Manhunt - Client Menu (Standard Derma UI)
    Settings menu for game configuration and team assignment
    Uses built-in GMod Derma panels - no external libraries needed
]]

print("[Manhunt] [CL] cl_menu.lua loading...")

-- Open menu when server tells us to
net.Receive("Manhunt_OpenMenu", function()
    print("[Manhunt] [CL] Received Manhunt_OpenMenu net message!")
    Manhunt.OpenSettingsMenu()
end)

Manhunt.MenuFrame = nil

-- Colors
local COL_BG = Color(30, 30, 35, 255)
local COL_HEADER = Color(20, 20, 25, 255)
local COL_ACCENT = Color(200, 50, 50)
local COL_ACCENT2 = Color(50, 150, 255)
local COL_BTN = Color(50, 50, 60)
local COL_GREEN = Color(50, 180, 80)
local COL_RED = Color(200, 50, 50)
local COL_BLUE = Color(50, 120, 255)
local COL_YELLOW = Color(220, 180, 50)
local COL_WHITE = Color(255, 255, 255)
local COL_GRAY = Color(180, 180, 180)
local COL_DARK = Color(40, 40, 48)
local COL_DARKER = Color(25, 25, 30)

-- Styled button helper
local function CreateStyledButton(parent, text, color, w, h, callback)
    local btn = vgui.Create("DButton", parent)
    btn:SetSize(w, h)
    btn:SetText("")
    btn.label = text
    btn.baseColor = color
    btn.DoClick = callback

    btn.Paint = function(self, pw, ph)
        local col = self:IsHovered() and Color(
            math.min(255, self.baseColor.r + 25),
            math.min(255, self.baseColor.g + 25),
            math.min(255, self.baseColor.b + 25)
        ) or self.baseColor

        draw.RoundedBox(6, 0, 0, pw, ph, col)
        draw.SimpleText(self.label, "Manhunt_Menu_Btn", pw / 2, ph / 2, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    return btn
end

-- Section header helper
local function AddSectionHeader(parent, text)
    local header = vgui.Create("DPanel", parent)
    header:Dock(TOP)
    header:DockMargin(0, 10, 0, 5)
    header:SetTall(30)
    header.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, COL_DARKER)
        draw.SimpleText(text, "Manhunt_Menu_Header", 10, h / 2, COL_ACCENT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)
    end
    return header
end

function Manhunt.OpenSettingsMenu()
    print("[Manhunt] [CL] OpenSettingsMenu() called")

    -- Close existing menu
    if IsValid(Manhunt.MenuFrame) then
        Manhunt.MenuFrame:Remove()
    end

    -- Request latest config/teams from server
    net.Start("Manhunt_LobbySync")
    net.SendToServer()
    print("[Manhunt] [CL] Sent LobbySync request")

    -- Create fonts if not yet created
    if not Manhunt._menuFontsCreated then
        surface.CreateFont("Manhunt_Menu_Title", { font = "Roboto", size = 28, weight = 800 })
        surface.CreateFont("Manhunt_Menu_Header", { font = "Roboto", size = 18, weight = 700 })
        surface.CreateFont("Manhunt_Menu_Btn", { font = "Roboto", size = 16, weight = 600 })
        surface.CreateFont("Manhunt_Menu_Text", { font = "Roboto", size = 16, weight = 500 })
        surface.CreateFont("Manhunt_Menu_Small", { font = "Roboto", size = 14, weight = 400 })
        Manhunt._menuFontsCreated = true
    end

    -- Main frame
    local frame = vgui.Create("DFrame")
    frame:SetSize(480, 620)
    frame:Center()
    frame:SetTitle("")
    frame:SetDraggable(true)
    frame:MakePopup()
    frame:ShowCloseButton(false)
    Manhunt.MenuFrame = frame

    frame.Paint = function(self, w, h)
        -- Shadow
        draw.RoundedBox(10, -2, -2, w + 4, h + 4, Color(0, 0, 0, 100))
        -- Background
        draw.RoundedBox(8, 0, 0, w, h, COL_BG)
        -- Header bar
        draw.RoundedBoxEx(8, 0, 0, w, 45, COL_HEADER, true, true, false, false)
        -- Title
        draw.SimpleText("M A N H U N T", "Manhunt_Menu_Title", w / 2, 22, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        -- Accent line
        surface.SetDrawColor(COL_ACCENT)
        surface.DrawRect(20, 44, w - 40, 2)
    end

    -- Close button
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetPos(frame:GetWide() - 35, 8)
    closeBtn:SetSize(25, 25)
    closeBtn:SetText("")
    closeBtn.Paint = function(self, w, h)
        local col = self:IsHovered() and COL_RED or Color(150, 150, 150)
        draw.SimpleText("X", "Manhunt_Menu_Btn", w / 2, h / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end
    closeBtn.DoClick = function() frame:Remove() end

    -- Scroll panel
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(10, 50, 10, 10)

    local sbar = scroll:GetVBar()
    sbar:SetWide(6)
    sbar.Paint = function() end
    sbar.btnUp.Paint = function() end
    sbar.btnDown.Paint = function() end
    sbar.btnGrip.Paint = function(self, w, h)
        draw.RoundedBox(3, 0, 0, w, h, Color(100, 100, 120, 150))
    end

    -- ========== GAME SETTINGS ==========
    AddSectionHeader(scroll, "GAME SETTINGS")

    -- Game Time slider
    local gtPanel = vgui.Create("DPanel", scroll)
    gtPanel:Dock(TOP)
    gtPanel:DockMargin(5, 5, 5, 0)
    gtPanel:SetTall(50)
    gtPanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, COL_DARK)
    end

    local gtLabel = vgui.Create("DLabel", gtPanel)
    gtLabel:SetPos(10, 5)
    gtLabel:SetText("Game Time (minutes)")
    gtLabel:SetFont("Manhunt_Menu_Text")
    gtLabel:SetTextColor(COL_GRAY)
    gtLabel:SizeToContents()

    local gtSlider = vgui.Create("DNumSlider", gtPanel)
    gtSlider:Dock(BOTTOM)
    gtSlider:DockMargin(10, 0, 10, 2)
    gtSlider:SetMin(1)
    gtSlider:SetMax(120)
    gtSlider:SetDecimals(0)
    gtSlider:SetValue(Manhunt.Config.GameTime or 30)
    gtSlider:SetText("")
    gtSlider.OnValueChanged = function(self, val)
        val = math.max(1, math.floor(val))
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("GameTime")
        net.WriteUInt(val, 8)
        net.SendToServer()
    end

    -- Interval slider
    local intPanel = vgui.Create("DPanel", scroll)
    intPanel:Dock(TOP)
    intPanel:DockMargin(5, 5, 5, 0)
    intPanel:SetTall(50)
    intPanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, COL_DARK)
    end

    local intLabel = vgui.Create("DLabel", intPanel)
    intLabel:SetPos(10, 5)
    intLabel:SetText("Scan Interval (minutes)")
    intLabel:SetFont("Manhunt_Menu_Text")
    intLabel:SetTextColor(COL_GRAY)
    intLabel:SizeToContents()

    local intSlider = vgui.Create("DNumSlider", intPanel)
    intSlider:Dock(BOTTOM)
    intSlider:DockMargin(10, 0, 10, 2)
    intSlider:SetMin(0.5)
    intSlider:SetMax(10)
    intSlider:SetDecimals(1)
    intSlider:SetValue(Manhunt.Config.Interval or 3)
    intSlider:SetText("")
    intSlider.OnValueChanged = function(self, val)
        val = math.max(0.5, math.Round(val * 2) / 2) -- snap to 0.5 increments
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("Interval")
        net.WriteUInt(val * 2, 8) -- send as half-minutes (e.g. 1.5 = 3)
        net.SendToServer()
    end

    -- Rounds slider
    local rndPanel = vgui.Create("DPanel", scroll)
    rndPanel:Dock(TOP)
    rndPanel:DockMargin(5, 5, 5, 0)
    rndPanel:SetTall(50)
    rndPanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, COL_DARK)
    end

    local rndLabel = vgui.Create("DLabel", rndPanel)
    rndLabel:SetPos(10, 5)
    rndLabel:SetText("Rounds (1 = single game)")
    rndLabel:SetFont("Manhunt_Menu_Text")
    rndLabel:SetTextColor(COL_GRAY)
    rndLabel:SizeToContents()

    local rndSlider = vgui.Create("DNumSlider", rndPanel)
    rndSlider:Dock(BOTTOM)
    rndSlider:DockMargin(10, 0, 10, 2)
    rndSlider:SetMin(1)
    rndSlider:SetMax(10)
    rndSlider:SetDecimals(0)
    rndSlider:SetValue(Manhunt.Config.Rounds or 1)
    rndSlider:SetText("")
    rndSlider.OnValueChanged = function(self, val)
        val = math.max(1, math.floor(val))
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("Rounds")
        net.WriteUInt(val, 8)
        net.SendToServer()
    end

    -- Tutorial toggle
    local tutPanel = vgui.Create("DPanel", scroll)
    tutPanel:Dock(TOP)
    tutPanel:DockMargin(5, 5, 5, 0)
    tutPanel:SetTall(35)
    tutPanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, COL_DARK)
    end

    local tutCheck = vgui.Create("DCheckBoxLabel", tutPanel)
    tutCheck:SetPos(10, 8)
    tutCheck:SetText("")
    tutCheck:SetValue(Manhunt.Config.TutorialEnabled ~= false)
    tutCheck:SizeToContents()

    local tutLabel = vgui.Create("DLabel", tutPanel)
    tutLabel:SetPos(35, 0)
    tutLabel:SetSize(300, 35)
    tutLabel:SetText("Show Tutorial at Game Start")
    tutLabel:SetFont("Manhunt_Menu_Text")
    tutLabel:SetTextColor(COL_GRAY)

    tutCheck.OnChange = function(self, val)
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("TutorialEnabled")
        net.WriteUInt(val and 1 or 0, 8)
        net.SendToServer()
    end

    -- Zone toggle
    local zonePanel = vgui.Create("DPanel", scroll)
    zonePanel:Dock(TOP)
    zonePanel:DockMargin(5, 5, 5, 0)
    zonePanel:SetTall(35)
    zonePanel.Paint = function(self, w, h)
        draw.RoundedBox(4, 0, 0, w, h, COL_DARK)
    end

    local zoneCheck = vgui.Create("DCheckBoxLabel", zonePanel)
    zoneCheck:SetPos(10, 8)
    zoneCheck:SetText("")
    zoneCheck:SetValue(Manhunt.Config.ZoneEnabled ~= false)
    zoneCheck:SizeToContents()

    local zoneLabel = vgui.Create("DLabel", zonePanel)
    zoneLabel:SetPos(35, 0)
    zoneLabel:SetSize(300, 35)
    zoneLabel:SetText("Shrinking Zone (Endgame)")
    zoneLabel:SetFont("Manhunt_Menu_Text")
    zoneLabel:SetTextColor(COL_GRAY)

    zoneCheck.OnChange = function(self, val)
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("ZoneEnabled")
        net.WriteUInt(val and 1 or 0, 8)
        net.SendToServer()
    end

    -- ========== TEAM ASSIGNMENT ==========
    AddSectionHeader(scroll, "TEAM ASSIGNMENT")

    for _, ply in ipairs(player.GetAll()) do
        local sid = ply:SteamID()
        local currentTeam = Manhunt.TeamAssignments[sid] or Manhunt.TEAM_NONE

        local row = vgui.Create("DPanel", scroll)
        row:Dock(TOP)
        row:DockMargin(5, 3, 5, 0)
        row:SetTall(40)
        row.Paint = function(self, w, h)
            draw.RoundedBox(4, 0, 0, w, h, COL_DARK)
        end

        -- Player name
        local name = vgui.Create("DLabel", row)
        name:SetPos(10, 0)
        name:SetSize(150, 40)
        name:SetText(ply:Nick())
        name:SetFont("Manhunt_Menu_Text")
        name:SetTextColor(COL_WHITE)

        -- Team buttons (right-aligned)
        local btnW = 80
        local btnH = 28
        local startX = 430 - (btnW * 3 + 10)

        local noneColor = currentTeam == Manhunt.TEAM_NONE and COL_YELLOW or COL_BTN
        local noneBtn = CreateStyledButton(row, "None", noneColor, btnW, btnH, function()
            net.Start("Manhunt_SetTeam")
            net.WriteString(sid)
            net.WriteUInt(Manhunt.TEAM_NONE, 4)
            net.SendToServer()
            timer.Simple(0.3, function() Manhunt.OpenSettingsMenu() end)
        end)
        noneBtn:SetPos(startX, 6)

        local fugColor = currentTeam == Manhunt.TEAM_FUGITIVE and COL_BLUE or COL_BTN
        local fugBtn = CreateStyledButton(row, "Fugitive", fugColor, btnW, btnH, function()
            net.Start("Manhunt_SetTeam")
            net.WriteString(sid)
            net.WriteUInt(Manhunt.TEAM_FUGITIVE, 4)
            net.SendToServer()
            timer.Simple(0.3, function() Manhunt.OpenSettingsMenu() end)
        end)
        fugBtn:SetPos(startX + btnW + 5, 6)

        local huntColor = currentTeam == Manhunt.TEAM_HUNTER and COL_RED or COL_BTN
        local huntBtn = CreateStyledButton(row, "Hunter", huntColor, btnW, btnH, function()
            net.Start("Manhunt_SetTeam")
            net.WriteString(sid)
            net.WriteUInt(Manhunt.TEAM_HUNTER, 4)
            net.SendToServer()
            timer.Simple(0.3, function() Manhunt.OpenSettingsMenu() end)
        end)
        huntBtn:SetPos(startX + (btnW + 5) * 2, 6)
    end

    -- ========== GAME CONTROL ==========
    AddSectionHeader(scroll, "GAME CONTROL")

    local isActive = Manhunt.Phase ~= Manhunt.PHASE_IDLE

    if not isActive then
        -- Start button
        local startBtn = CreateStyledButton(scroll, "START MANHUNT", COL_GREEN, 0, 45, function()
            print("[Manhunt] [CL] START MANHUNT clicked")
            net.Start("Manhunt_RequestStart")
            net.SendToServer()
            timer.Simple(0.5, function()
                if IsValid(Manhunt.MenuFrame) then Manhunt.MenuFrame:Remove() end
            end)
        end)
        startBtn:Dock(TOP)
        startBtn:DockMargin(5, 8, 5, 3)

        -- Test mode button
        local testBtn = CreateStyledButton(scroll, "TEST MODE (Solo)", COL_ACCENT2, 0, 38, function()
            print("[Manhunt] [CL] TEST MODE clicked")
            net.Start("Manhunt_TestMode")
            net.WriteBool(true)
            net.SendToServer()
            timer.Simple(0.5, function()
                if IsValid(Manhunt.MenuFrame) then Manhunt.MenuFrame:Remove() end
            end)
        end)
        testBtn:Dock(TOP)
        testBtn:DockMargin(5, 3, 5, 3)
    else
        -- Stop button
        local stopBtn = CreateStyledButton(scroll, "STOP GAME", COL_RED, 0, 45, function()
            print("[Manhunt] [CL] STOP GAME clicked")
            net.Start("Manhunt_RequestStop")
            net.SendToServer()
        end)
        stopBtn:Dock(TOP)
        stopBtn:DockMargin(5, 8, 5, 3)
    end

    -- ========== HOW TO PLAY ==========
    AddSectionHeader(scroll, "HOW TO PLAY")

    local tips = {
        "Fugitive: Survive until time runs out!",
        "Hunter: Find and eliminate the Fugitive!",
        "Scanner weapon reveals enemy location",
        "Fugitive gets car bomb (1x) + decoy (F5, 1x)",
        "Hunter gets airstrike (1x, after 80% time)",
        "Set Rounds > 1 for multi-round matches",
        "Open menu: !manhunt in chat",
    }

    for _, tip in ipairs(tips) do
        local tipLabel = vgui.Create("DLabel", scroll)
        tipLabel:Dock(TOP)
        tipLabel:DockMargin(15, 2, 10, 0)
        tipLabel:SetText("  " .. tip)
        tipLabel:SetFont("Manhunt_Menu_Small")
        tipLabel:SetTextColor(COL_GRAY)
        tipLabel:SetTall(18)
    end

    print("[Manhunt] [CL] Menu created successfully!")
end

-- Client-side console command
concommand.Add("manhunt_menu_cl", function()
    print("[Manhunt] [CL] Console command 'manhunt_menu_cl' executed")
    Manhunt.OpenSettingsMenu()
end)

-- Debug command to show full state
concommand.Add("manhunt_debug", function()
    print("[Manhunt] ======= CLIENT DEBUG =======")
    print("[Manhunt] Phase: " .. tostring(Manhunt.Phase))
    print("[Manhunt] TestMode: " .. tostring(Manhunt.TestMode))
    print("[Manhunt] Config.GameTime: " .. tostring(Manhunt.Config.GameTime))
    print("[Manhunt] Config.Interval: " .. tostring(Manhunt.Config.Interval))
    print("[Manhunt] MenuFrame valid: " .. tostring(IsValid(Manhunt.MenuFrame)))
    print("[Manhunt] LocalPlayer: " .. tostring(LocalPlayer()))
    print("[Manhunt] LocalPlayer team: " .. tostring(Manhunt.GetPlayerTeam(LocalPlayer())))
    print("[Manhunt] TeamAssignments: " .. tostring(table.Count(Manhunt.TeamAssignments or {})))
    for sid, team in pairs(Manhunt.TeamAssignments or {}) do
        print("[Manhunt]   " .. sid .. " = " .. tostring(team))
    end
    print("[Manhunt] =============================")
end)

print("[Manhunt] [CL] cl_menu.lua fully loaded!")
