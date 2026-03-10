--[[
    Manhunt - Client Menu (Premium UI)
    Settings menu for game configuration and team assignment
    Animated, polished Derma UI with sound effects
]]

print("[Manhunt] [CL] cl_menu.lua loading...")

-- Open menu when server tells us to
net.Receive("Manhunt_OpenMenu", function()
    Manhunt.OpenSettingsMenu()
end)

Manhunt.MenuFrame = nil

-- ============================================================
-- COLORS
-- ============================================================
local COL_BG          = Color(18, 18, 22, 252)
local COL_BG_CARD     = Color(28, 28, 35, 255)
local COL_BG_CARD_LIT = Color(35, 35, 44, 255)
local COL_HEADER      = Color(12, 12, 16, 255)
local COL_ACCENT      = Color(220, 40, 40)
local COL_ACCENT_DIM  = Color(160, 30, 30)
local COL_ACCENT2     = Color(45, 140, 255)
local COL_BTN         = Color(42, 42, 52)
local COL_BTN_HOVER   = Color(55, 55, 68)
local COL_GREEN       = Color(40, 190, 80)
local COL_GREEN_GLOW  = Color(40, 190, 80, 30)
local COL_RED         = Color(220, 45, 45)
local COL_BLUE        = Color(45, 120, 255)
local COL_YELLOW      = Color(230, 190, 40)
local COL_WHITE       = Color(240, 240, 245)
local COL_TEXT        = Color(200, 200, 210)
local COL_TEXT_DIM    = Color(120, 120, 135)
local COL_DIVIDER     = Color(50, 50, 60, 180)
local COL_SHADOW      = Color(0, 0, 0, 120)
local COL_NONE        = Color(0, 0, 0, 0)

-- ============================================================
-- SOUNDS
-- ============================================================
local SND_CLICK     = "UI/buttonclick.wav"
local SND_HOVER     = "UI/buttonrollover.wav"
local SND_OPEN      = "buttons/combine_button7.wav"
local SND_CLOSE     = "buttons/combine_button2.wav"
local SND_TOGGLE    = "buttons/button14.wav"
local SND_START     = "buttons/button9.wav"
local SND_SELECT    = "buttons/blip1.wav"

-- ============================================================
-- ANIMATION HELPERS
-- ============================================================
local function Lerp2(t, a, b)
    return a + (b - a) * t
end

local function LerpColor(t, a, b)
    return Color(
        Lerp2(t, a.r, b.r),
        Lerp2(t, a.g, b.g),
        Lerp2(t, a.b, b.b),
        Lerp2(t, a.a or 255, b.a or 255)
    )
end

-- ============================================================
-- FONTS
-- ============================================================
local fontsCreated = false
local function EnsureFonts()
    if fontsCreated then return end
    fontsCreated = true

    surface.CreateFont("MH_Title",      { font = "Roboto", size = 30, weight = 900, antialias = true })
    surface.CreateFont("MH_Subtitle",   { font = "Roboto", size = 13, weight = 600, antialias = true })
    surface.CreateFont("MH_Section",    { font = "Roboto", size = 14, weight = 700, antialias = true })
    surface.CreateFont("MH_Btn",        { font = "Roboto", size = 15, weight = 700, antialias = true })
    surface.CreateFont("MH_BtnLarge",   { font = "Roboto", size = 17, weight = 800, antialias = true })
    surface.CreateFont("MH_Text",       { font = "Roboto", size = 14, weight = 500, antialias = true })
    surface.CreateFont("MH_TextBold",   { font = "Roboto", size = 14, weight = 700, antialias = true })
    surface.CreateFont("MH_Small",      { font = "Roboto", size = 12, weight = 500, antialias = true })
    surface.CreateFont("MH_Tiny",       { font = "Roboto", size = 11, weight = 400, antialias = true })
    surface.CreateFont("MH_Value",      { font = "Roboto", size = 16, weight = 800, antialias = true })
    surface.CreateFont("MH_SliderVal",  { font = "Roboto", size = 22, weight = 900, antialias = true })
    surface.CreateFont("MH_PlayerName", { font = "Roboto", size = 14, weight = 600, antialias = true })
    surface.CreateFont("MH_Icon",       { font = "Marlett", size = 16, weight = 400, antialias = true })
    surface.CreateFont("MH_Close",      { font = "Marlett", size = 14, weight = 400, antialias = true })
    surface.CreateFont("MH_Tip",        { font = "Roboto", size = 13, weight = 400, antialias = true, italic = true })

    -- Keep old fonts for compatibility
    surface.CreateFont("Manhunt_Menu_Title",  { font = "Roboto", size = 28, weight = 800 })
    surface.CreateFont("Manhunt_Menu_Header", { font = "Roboto", size = 18, weight = 700 })
    surface.CreateFont("Manhunt_Menu_Btn",    { font = "Roboto", size = 16, weight = 600 })
    surface.CreateFont("Manhunt_Menu_Text",   { font = "Roboto", size = 16, weight = 500 })
    surface.CreateFont("Manhunt_Menu_Small",  { font = "Roboto", size = 14, weight = 400 })
end

-- ============================================================
-- UI COMPONENTS
-- ============================================================

-- Animated button with hover glow, press feedback, and sound
local function MHButton(parent, text, color, icon, h, callback)
    h = h or 36
    local btn = vgui.Create("DButton", parent)
    btn:SetTall(h)
    btn:SetText("")
    btn._label = text
    btn._icon = icon
    btn._baseColor = color
    btn._hoverAnim = 0
    btn._pressAnim = 0
    btn._hovered = false

    btn.DoClick = function(self)
        surface.PlaySound(SND_CLICK)
        self._pressAnim = 1
        if callback then callback(self) end
    end

    btn.OnCursorEntered = function(self)
        if not self._hovered then
            surface.PlaySound(SND_HOVER)
            self._hovered = true
        end
    end

    btn.OnCursorExited = function(self)
        self._hovered = false
    end

    btn.Paint = function(self, w, ph)
        -- Animate hover
        local targetHover = self:IsHovered() and 1 or 0
        self._hoverAnim = Lerp(FrameTime() * 12, self._hoverAnim, targetHover)
        self._pressAnim = Lerp(FrameTime() * 10, self._pressAnim, 0)

        local baseCol = self._baseColor
        local hoverCol = Color(
            math.min(255, baseCol.r + 30),
            math.min(255, baseCol.g + 30),
            math.min(255, baseCol.b + 30)
        )
        local col = LerpColor(self._hoverAnim, baseCol, hoverCol)

        -- Press scale effect (subtle inset)
        local inset = self._pressAnim * 2
        draw.RoundedBox(6, inset, inset, w - inset * 2, ph - inset * 2, col)

        -- Subtle glow on hover
        if self._hoverAnim > 0.05 then
            local glowAlpha = self._hoverAnim * 25
            draw.RoundedBox(8, -2, -2, w + 4, ph + 4, Color(baseCol.r, baseCol.g, baseCol.b, glowAlpha))
        end

        -- Bottom highlight line
        if self._hoverAnim > 0.05 then
            local lineW = w * self._hoverAnim * 0.6
            surface.SetDrawColor(255, 255, 255, 30 * self._hoverAnim)
            surface.DrawRect(w / 2 - lineW / 2, ph - 2, lineW, 1)
        end

        -- Icon + Text
        local textX = w / 2
        local fullText = self._label
        if self._icon then
            fullText = self._icon .. "  " .. self._label
        end
        draw.SimpleText(fullText, h >= 42 and "MH_BtnLarge" or "MH_Btn", textX, ph / 2, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    return btn
end

-- Gamemode toggle card (large, with description and active indicator)
local function MHGamemodeCard(parent, title, subtitle, isActive, accentColor, callback)
    local card = vgui.Create("DButton", parent)
    card:SetTall(58)
    card:SetText("")
    card._active = isActive
    card._hoverAnim = 0
    card._hovered = false

    card.DoClick = function(self)
        surface.PlaySound(SND_SELECT)
        if callback then callback(self) end
    end

    card.OnCursorEntered = function(self)
        if not self._hovered then
            surface.PlaySound(SND_HOVER)
            self._hovered = true
        end
    end

    card.OnCursorExited = function(self)
        self._hovered = false
    end

    card.Paint = function(self, w, h)
        self._hoverAnim = Lerp(FrameTime() * 10, self._hoverAnim, self:IsHovered() and 1 or 0)

        local bgCol = self._active and Color(accentColor.r, accentColor.g, accentColor.b, 25) or COL_BG_CARD
        if not self._active and self._hoverAnim > 0.01 then
            bgCol = LerpColor(self._hoverAnim, COL_BG_CARD, COL_BG_CARD_LIT)
        end

        draw.RoundedBox(6, 0, 0, w, h, bgCol)

        -- Left accent bar
        if self._active then
            draw.RoundedBox(2, 0, 4, 3, h - 8, accentColor)
        end

        -- Active indicator dot
        local dotX = w - 20
        local dotY = h / 2
        if self._active then
            draw.RoundedBox(5, dotX - 5, dotY - 5, 10, 10, accentColor)
        else
            draw.RoundedBox(5, dotX - 5, dotY - 5, 10, 10, COL_BTN)
        end

        -- Title
        local textColor = self._active and COL_WHITE or COL_TEXT
        draw.SimpleText(title, "MH_TextBold", 14, h / 2 - 9, textColor, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)

        -- Subtitle
        draw.SimpleText(subtitle, "MH_Tiny", 14, h / 2 + 5, COL_TEXT_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    return card
end

-- Custom slider with big value display
local function MHSlider(parent, label, icon, min, max, decimals, value, unit, callback)
    local panel = vgui.Create("DPanel", parent)
    panel:Dock(TOP)
    panel:DockMargin(0, 3, 0, 0)
    panel:SetTall(62)

    panel._value = value
    panel.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, COL_BG_CARD)
    end

    -- Top row: icon + label + value display
    local topRow = vgui.Create("DPanel", panel)
    topRow:Dock(TOP)
    topRow:DockMargin(12, 6, 12, 0)
    topRow:SetTall(20)
    topRow.Paint = function(self, w, h)
        draw.SimpleText((icon or "") .. "  " .. label, "MH_Text", 0, h / 2, COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        local valStr
        if decimals == 0 then
            valStr = tostring(math.floor(panel._value))
        else
            valStr = string.format("%." .. decimals .. "f", panel._value)
        end
        draw.SimpleText(valStr .. " " .. (unit or ""), "MH_Value", w, h / 2, COL_ACCENT2, TEXT_ALIGN_RIGHT, TEXT_ALIGN_CENTER)
    end

    -- Slider (custom-painted)
    local slider = vgui.Create("DNumSlider", panel)
    slider:Dock(TOP)
    slider:DockMargin(8, 2, 8, 4)
    slider:SetTall(28)
    slider:SetMin(min)
    slider:SetMax(max)
    slider:SetDecimals(decimals)
    slider:SetValue(value)
    slider:SetText("")

    -- Style the slider knob and groove
    local sliderObj = slider.Slider
    if IsValid(sliderObj) then
        sliderObj.Paint = function(self, w, h)
            -- Track background
            local trackY = h / 2 - 2
            draw.RoundedBox(2, 8, trackY, w - 16, 4, Color(50, 50, 60))

            -- Fill (progress)
            local frac = (panel._value - min) / (max - min)
            local fillW = (w - 16) * frac
            draw.RoundedBox(2, 8, trackY, fillW, 4, COL_ACCENT2)
        end

        local knob = sliderObj:GetChildren()[1]
        if IsValid(knob) then
            knob:SetSize(14, 14)
            knob.Paint = function(self, w, h)
                draw.RoundedBox(7, 0, 0, w, h, COL_WHITE)
                draw.RoundedBox(4, 3, 3, w - 6, h - 6, COL_ACCENT2)
            end
        end
    end

    -- Hide default text entry
    local textArea = slider.TextArea
    if IsValid(textArea) then
        textArea:SetWide(0)
        textArea:SetVisible(false)
    end

    slider.OnValueChanged = function(self, val)
        if decimals == 0 then
            val = math.floor(val)
        end
        panel._value = val
        if callback then callback(val) end
    end

    return panel
end

-- Custom toggle switch
local function MHToggle(parent, label, icon, value, callback)
    local panel = vgui.Create("DButton", parent)
    panel:Dock(TOP)
    panel:DockMargin(0, 3, 0, 0)
    panel:SetTall(40)
    panel:SetText("")
    panel._on = value
    panel._anim = value and 1 or 0
    panel._hoverAnim = 0
    panel._hovered = false

    panel.DoClick = function(self)
        self._on = not self._on
        surface.PlaySound(SND_TOGGLE)
        if callback then callback(self._on) end
    end

    panel.OnCursorEntered = function(self)
        if not self._hovered then
            surface.PlaySound(SND_HOVER)
            self._hovered = true
        end
    end

    panel.OnCursorExited = function(self)
        self._hovered = false
    end

    panel.Paint = function(self, w, h)
        self._anim = Lerp(FrameTime() * 10, self._anim, self._on and 1 or 0)
        self._hoverAnim = Lerp(FrameTime() * 10, self._hoverAnim, self:IsHovered() and 1 or 0)

        local bgCol = LerpColor(self._hoverAnim, COL_BG_CARD, COL_BG_CARD_LIT)
        draw.RoundedBox(6, 0, 0, w, h, bgCol)

        -- Icon + Label
        draw.SimpleText((icon or "") .. "  " .. label, "MH_Text", 14, h / 2, COL_TEXT, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Toggle switch track
        local trackW = 38
        local trackH = 20
        local trackX = w - trackW - 14
        local trackY = h / 2 - trackH / 2

        local trackOff = Color(55, 55, 65)
        local trackOn = Color(COL_GREEN.r, COL_GREEN.g, COL_GREEN.b, 200)
        local trackCol = LerpColor(self._anim, trackOff, trackOn)

        draw.RoundedBox(10, trackX, trackY, trackW, trackH, trackCol)

        -- Knob
        local knobSize = 16
        local knobX = Lerp(self._anim, trackX + 2, trackX + trackW - knobSize - 2)
        local knobY = trackY + 2
        draw.RoundedBox(8, knobX, knobY, knobSize, knobSize, COL_WHITE)
    end

    return panel
end

-- Player row for team assignment
local function MHPlayerRow(parent, ply, currentTeam, onTeamChange)
    local sid = ply:SteamID()

    local row = vgui.Create("DPanel", parent)
    row:Dock(TOP)
    row:DockMargin(0, 2, 0, 0)
    row:SetTall(44)

    row.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, COL_BG_CARD)

        -- Team color indicator on left
        local indicatorCol = COL_TEXT_DIM
        if currentTeam == Manhunt.TEAM_FUGITIVE then
            indicatorCol = COL_BLUE
        elseif currentTeam == Manhunt.TEAM_HUNTER then
            indicatorCol = COL_RED
        end
        draw.RoundedBox(2, 0, 6, 3, h - 12, indicatorCol)
    end

    -- Avatar
    local av = vgui.Create("AvatarImage", row)
    av:SetPos(12, 7)
    av:SetSize(30, 30)
    av:SetPlayer(ply, 32)

    -- Mask the avatar to rounded
    local avMask = vgui.Create("DPanel", row)
    avMask:SetPos(12, 7)
    avMask:SetSize(30, 30)
    avMask.Paint = function(self, w, h)
        -- Draw rounded corners over avatar edges
        draw.RoundedBox(15, 0, 0, w, h, COL_NONE)
    end

    -- Player name
    local nameLabel = vgui.Create("DLabel", row)
    nameLabel:SetPos(50, 0)
    nameLabel:SetSize(120, 44)
    nameLabel:SetText(ply:Nick())
    nameLabel:SetFont("MH_PlayerName")
    nameLabel:SetTextColor(COL_WHITE)

    -- Team buttons
    local teamButtons = {
        { label = "---",       team = Manhunt.TEAM_NONE,     color = COL_YELLOW, activeCol = COL_YELLOW },
        { label = "FUGITIVE",  team = Manhunt.TEAM_FUGITIVE, color = COL_BLUE,   activeCol = COL_BLUE },
        { label = "HUNTER",    team = Manhunt.TEAM_HUNTER,   color = COL_RED,    activeCol = COL_RED },
    }

    local btnW = 72
    local btnH = 26
    local btnSpacing = 4
    local totalBtnW = (#teamButtons * btnW) + ((#teamButtons - 1) * btnSpacing)
    local startX = row:GetWide() - totalBtnW - 10

    -- We need to defer position setting since GetWide returns 0 initially
    row.PerformLayout = function(self, w, h)
        local sx = w - totalBtnW - 10
        for i, child in ipairs(self._teamBtns or {}) do
            child:SetPos(sx + (i - 1) * (btnW + btnSpacing), (h - btnH) / 2)
        end
    end

    row._teamBtns = {}
    for i, info in ipairs(teamButtons) do
        local isActive = (currentTeam == info.team)

        local btn = vgui.Create("DButton", row)
        btn:SetSize(btnW, btnH)
        btn:SetText("")
        btn._hoverAnim = 0
        btn._hovered = false

        btn.DoClick = function(self)
            surface.PlaySound(SND_SELECT)
            if onTeamChange then onTeamChange(sid, info.team) end
        end

        btn.OnCursorEntered = function(self)
            if not self._hovered then
                surface.PlaySound(SND_HOVER)
                self._hovered = true
            end
        end

        btn.OnCursorExited = function(self)
            self._hovered = false
        end

        btn.Paint = function(self, w, h)
            self._hoverAnim = Lerp(FrameTime() * 12, self._hoverAnim, self:IsHovered() and 1 or 0)

            local bgCol
            if isActive then
                bgCol = Color(info.activeCol.r, info.activeCol.g, info.activeCol.b, 180)
            else
                bgCol = LerpColor(self._hoverAnim, COL_BTN, COL_BTN_HOVER)
            end

            draw.RoundedBox(4, 0, 0, w, h, bgCol)

            local textCol = isActive and COL_WHITE or LerpColor(self._hoverAnim, COL_TEXT_DIM, COL_TEXT)
            draw.SimpleText(info.label, "MH_Small", w / 2, h / 2, textCol, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
        end

        table.insert(row._teamBtns, btn)
    end

    return row
end

-- Section header with accent line
local function MHSection(parent, text)
    local header = vgui.Create("DPanel", parent)
    header:Dock(TOP)
    header:DockMargin(0, 14, 0, 4)
    header:SetTall(22)
    header.Paint = function(self, w, h)
        -- Section text
        draw.SimpleText(text, "MH_Section", 2, h / 2, COL_TEXT_DIM, TEXT_ALIGN_LEFT, TEXT_ALIGN_CENTER)

        -- Line after text
        surface.SetFont("MH_Section")
        local textW = surface.GetTextSize(text)
        surface.SetDrawColor(COL_DIVIDER)
        surface.DrawRect(textW + 10, h / 2, w - textW - 12, 1)
    end
end

-- ============================================================
-- MAIN MENU
-- ============================================================

function Manhunt.OpenSettingsMenu()
    -- Close existing menu
    if IsValid(Manhunt.MenuFrame) then
        Manhunt.MenuFrame:Remove()
    end

    EnsureFonts()

    -- Request latest config/teams from server
    net.Start("Manhunt_LobbySync")
    net.SendToServer()

    -- Play open sound
    surface.PlaySound(SND_OPEN)

    local menuW = 500
    local menuH = 720

    -- Main frame
    local frame = vgui.Create("DFrame")
    frame:SetSize(menuW, menuH)
    frame:Center()
    frame:SetTitle("")
    frame:SetDraggable(true)
    frame:MakePopup()
    frame:ShowCloseButton(false)
    Manhunt.MenuFrame = frame

    -- Open animation
    frame:SetAlpha(0)
    frame:AlphaTo(255, 0.15, 0)

    -- Frame paint
    frame.Paint = function(self, w, h)
        -- Shadow layers
        draw.RoundedBox(12, -4, -4, w + 8, h + 8, Color(0, 0, 0, 50))
        draw.RoundedBox(11, -2, -2, w + 4, h + 4, Color(0, 0, 0, 80))

        -- Background
        draw.RoundedBox(10, 0, 0, w, h, COL_BG)

        -- Header area
        draw.RoundedBoxEx(10, 0, 0, w, 56, COL_HEADER, true, true, false, false)

        -- Accent line under header
        local pulse = 0.85 + math.sin(CurTime() * 1.5) * 0.15
        surface.SetDrawColor(COL_ACCENT.r, COL_ACCENT.g, COL_ACCENT.b, 255 * pulse)
        surface.DrawRect(0, 55, w, 2)

        -- Title
        draw.SimpleText("M A N H U N T", "MH_Title", w / 2, 20, COL_WHITE, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)

        -- Version tag
        draw.SimpleText("V3", "MH_Tiny", w / 2 + 85, 22, COL_ACCENT, TEXT_ALIGN_LEFT, TEXT_ALIGN_TOP)
    end

    -- Close button (top right)
    local closeBtn = vgui.Create("DButton", frame)
    closeBtn:SetPos(menuW - 40, 8)
    closeBtn:SetSize(30, 30)
    closeBtn:SetText("")
    closeBtn._hoverAnim = 0

    closeBtn.Paint = function(self, w, h)
        self._hoverAnim = Lerp(FrameTime() * 12, self._hoverAnim, self:IsHovered() and 1 or 0)
        local bgAlpha = self._hoverAnim * 255
        draw.RoundedBox(6, 0, 0, w, h, Color(COL_RED.r, COL_RED.g, COL_RED.b, bgAlpha * 0.4))

        local col = LerpColor(self._hoverAnim, COL_TEXT_DIM, COL_RED)
        draw.SimpleText("r", "MH_Close", w / 2, h / 2, col, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER)
    end

    closeBtn.DoClick = function()
        surface.PlaySound(SND_CLOSE)
        frame:AlphaTo(0, 0.1, 0, function() frame:Remove() end)
    end

    -- Scroll panel
    local scroll = vgui.Create("DScrollPanel", frame)
    scroll:Dock(FILL)
    scroll:DockMargin(14, 62, 14, 14)

    -- Style scrollbar
    local sbar = scroll:GetVBar()
    sbar:SetWide(4)
    sbar.Paint = function(self, w, h)
        draw.RoundedBox(2, 0, 0, w, h, Color(30, 30, 38))
    end
    sbar.btnUp.Paint = function() end
    sbar.btnDown.Paint = function() end
    sbar.btnGrip.Paint = function(self, w, h)
        draw.RoundedBox(2, 0, 0, w, h, Color(80, 80, 100, 180))
    end

    -- ========== GAMEMODE SELECTION ==========
    MHSection(scroll, "GAMEMODE")

    local currentGM = Manhunt.Gamemode or 0

    local gmContainer = vgui.Create("DPanel", scroll)
    gmContainer:Dock(TOP)
    gmContainer:DockMargin(0, 0, 0, 0)
    gmContainer:SetTall(124)
    gmContainer.Paint = function() end

    local classicCard = MHGamemodeCard(gmContainer, "CLASSIC", "On foot  ·  Stealth & survival  ·  Up to 30 min", currentGM == Manhunt.GAMEMODE_CLASSIC, COL_GREEN, function()
        Manhunt.Gamemode = Manhunt.GAMEMODE_CLASSIC
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("Gamemode")
        net.WriteUInt(Manhunt.GAMEMODE_CLASSIC, 8)
        net.SendToServer()
        timer.Simple(0.2, function() Manhunt.OpenSettingsMenu() end)
    end)
    classicCard:Dock(TOP)
    classicCard:DockMargin(0, 0, 0, 4)

    local chaseCard = MHGamemodeCard(gmContainer, "HIGH SPEED CHASE", "Vehicle pursuit  ·  12 abilities  ·  10 min", currentGM == Manhunt.GAMEMODE_CHASE, COL_ACCENT2, function()
        Manhunt.Gamemode = Manhunt.GAMEMODE_CHASE
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("Gamemode")
        net.WriteUInt(Manhunt.GAMEMODE_CHASE, 8)
        net.SendToServer()
        timer.Simple(0.2, function() Manhunt.OpenSettingsMenu() end)
    end)
    chaseCard:Dock(TOP)

    -- ========== GAME SETTINGS ==========
    MHSection(scroll, "SETTINGS")

    MHSlider(scroll, "Game Time", nil, 1, 120, 0, Manhunt.Config.GameTime or 30, "min", function(val)
        val = math.max(1, math.floor(val))
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("GameTime")
        net.WriteUInt(val, 8)
        net.SendToServer()
    end)

    MHSlider(scroll, "Scan Interval", nil, 0.5, 10, 1, Manhunt.Config.Interval or 3, "min", function(val)
        val = math.max(0.5, math.Round(val * 2) / 2)
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("Interval")
        net.WriteUInt(val * 2, 8)
        net.SendToServer()
    end)

    MHSlider(scroll, "Rounds", nil, 1, 10, 0, Manhunt.Config.Rounds or 1, "", function(val)
        val = math.max(1, math.floor(val))
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("Rounds")
        net.WriteUInt(val, 8)
        net.SendToServer()
    end)

    MHToggle(scroll, "Tutorial at game start", nil, Manhunt.Config.TutorialEnabled ~= false, function(on)
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("TutorialEnabled")
        net.WriteUInt(on and 1 or 0, 8)
        net.SendToServer()
    end)

    MHToggle(scroll, "Shrinking zone (endgame)", nil, Manhunt.Config.ZoneEnabled ~= false, function(on)
        net.Start("Manhunt_UpdateConfig")
        net.WriteString("ZoneEnabled")
        net.WriteUInt(on and 1 or 0, 8)
        net.SendToServer()
    end)

    -- ========== TEAM ASSIGNMENT ==========
    MHSection(scroll, "PLAYERS")

    local function onTeamChange(sid, team)
        net.Start("Manhunt_SetTeam")
        net.WriteString(sid)
        net.WriteUInt(team, 4)
        net.SendToServer()
        timer.Simple(0.25, function() Manhunt.OpenSettingsMenu() end)
    end

    for _, ply in ipairs(player.GetAll()) do
        local sid = ply:SteamID()
        local currentTeam = Manhunt.TeamAssignments[sid] or Manhunt.TEAM_NONE
        MHPlayerRow(scroll, ply, currentTeam, onTeamChange)
    end

    -- ========== GAME CONTROLS ==========
    MHSection(scroll, "GAME")

    local isActive = Manhunt.Phase ~= Manhunt.PHASE_IDLE

    if not isActive then
        local startLabel = Manhunt.Gamemode == Manhunt.GAMEMODE_CHASE and "START CHASE" or "START MANHUNT"
        local startBtn = MHButton(scroll, startLabel, COL_GREEN, "►", 48, function()
            net.Start("Manhunt_RequestStart")
            net.SendToServer()
            timer.Simple(0.4, function()
                if IsValid(Manhunt.MenuFrame) then
                    surface.PlaySound(SND_START)
                    Manhunt.MenuFrame:AlphaTo(0, 0.15, 0, function()
                        if IsValid(Manhunt.MenuFrame) then Manhunt.MenuFrame:Remove() end
                    end)
                end
            end)
        end)
        startBtn:Dock(TOP)
        startBtn:DockMargin(0, 4, 0, 2)

        -- Glow effect for start button
        local origPaint = startBtn.Paint
        startBtn.Paint = function(self, w, h)
            -- Pulsing green glow behind
            local pulse = 0.4 + math.sin(CurTime() * 2) * 0.2
            draw.RoundedBox(10, -3, -3, w + 6, h + 6, Color(COL_GREEN.r, COL_GREEN.g, COL_GREEN.b, 255 * pulse * 0.15))
            origPaint(self, w, h)
        end

        local testBtn = MHButton(scroll, "TEST MODE (Solo)", COL_BTN, nil, 36, function()
            net.Start("Manhunt_TestMode")
            net.WriteBool(true)
            net.SendToServer()
            timer.Simple(0.4, function()
                if IsValid(Manhunt.MenuFrame) then Manhunt.MenuFrame:Remove() end
            end)
        end)
        testBtn:Dock(TOP)
        testBtn:DockMargin(0, 2, 0, 0)
        testBtn:SetVisible(false)

        -- Dev mode toggle to reveal test button
        local devRow = vgui.Create("DPanel", scroll)
        devRow:Dock(TOP)
        devRow:DockMargin(0, 6, 0, 0)
        devRow:SetTall(24)
        devRow.Paint = function() end

        local devCheck = vgui.Create("DCheckBoxLabel", devRow)
        devCheck:SetPos(4, 2)
        devCheck:SetText("Developer Mode")
        devCheck:SetTextColor(COL_TEXT_DIM)
        devCheck:SetFont("Manhunt_Menu_Small")
        devCheck:SizeToContents()
        devCheck:SetValue(0)
        devCheck.OnChange = function(self, val)
            if IsValid(testBtn) then
                testBtn:SetVisible(val)
            end
        end
    else
        local stopBtn = MHButton(scroll, "STOP GAME", COL_RED, "■", 48, function()
            net.Start("Manhunt_RequestStop")
            net.SendToServer()
        end)
        stopBtn:Dock(TOP)
        stopBtn:DockMargin(0, 4, 0, 0)
    end

    -- ========== HOW TO PLAY ==========
    MHSection(scroll, "HOW TO PLAY")

    local tips
    if Manhunt.Gamemode == Manhunt.GAMEMODE_CHASE then
        tips = {
            { "Vehicle combat gamemode — drive or die", COL_ACCENT2 },
            { "Fugitive: Survive until time runs out", COL_BLUE },
            { "Hunter: Destroy the fugitive's vehicle", COL_RED },
            { "Exit vehicle > 5s = eliminated", COL_YELLOW },
            { "Stationary > 5s = eliminated", COL_YELLOW },
            { "Number keys (1-6) to use abilities", COL_TEXT_DIM },
            { "Drive over pickups to collect them", COL_TEXT_DIM },
        }
    else
        tips = {
            { "Fugitive: Survive until time runs out", COL_BLUE },
            { "Hunter: Find and eliminate the fugitive", COL_RED },
            { "Scanner reveals enemy location", COL_TEXT_DIM },
            { "Fugitive: car bomb (1x) + decoy (1x)", COL_TEXT_DIM },
            { "Hunter: airstrike + drone + car bomb", COL_TEXT_DIM },
            { "Set Rounds > 1 for multi-round matches", COL_TEXT_DIM },
        }
    end

    local tipBg = vgui.Create("DPanel", scroll)
    tipBg:Dock(TOP)
    tipBg:DockMargin(0, 0, 0, 10)
    tipBg:SetTall(#tips * 20 + 12)
    tipBg.Paint = function(self, w, h)
        draw.RoundedBox(6, 0, 0, w, h, COL_BG_CARD)
    end

    for i, tip in ipairs(tips) do
        local tipLabel = vgui.Create("DLabel", tipBg)
        tipLabel:SetPos(14, (i - 1) * 20 + 6)
        tipLabel:SetSize(450, 18)
        tipLabel:SetText("›  " .. tip[1])
        tipLabel:SetFont("MH_Tip")
        tipLabel:SetTextColor(tip[2])
    end
end

-- ============================================================
-- CONSOLE COMMANDS
-- ============================================================

concommand.Add("manhunt_menu_cl", function()
    Manhunt.OpenSettingsMenu()
end)

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

print("[Manhunt] [CL] cl_menu.lua loaded")
