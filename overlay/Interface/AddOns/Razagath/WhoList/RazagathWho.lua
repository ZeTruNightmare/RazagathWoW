-- Razagath: "Players Online" - replaces the CONTENT of the stock Who tab.
--
-- Why: the stock Who window can only keep 50 entries (the cap is inside the game client; raising the server's MaxWhoListReturns only makes it throw rows away), which is
-- useless with ~650 playerbots online. This panel is drawn on top of the Who tab (the tab, its title and the friends-frame window stay), hides the stock widgets and shows ONE
-- PAGE at a time that the server (src/mod_razagath_who.cpp) filters, sorts and sends over the add-on message channel. Wire format: see that file's header.
--   Request  "Q;seq;page;perPage;sortKey;desc;hideBots;minLevel;maxLevel;text"   (sent as a self-whisper add-on message, answered by the server)
--   Reply    "H;seq;matches;page;pages;onlineVisible;onlineBots", "R;seq;name,level,classId,race,zone,guild,b|p^...", "E;seq"
-- Typing /who in chat still works exactly as before (results go to chat); /players opens this tab.
-- NOTE for editing: this is a 3.3.5a client - no Region:SetShown, no FontString:SetWordWrap, etc. (a missing method made the first version fail after hiding the stock list).

local PREFIX = "RazagathWho"
local ROWS, ROW_H = 16, 16
local REFRESH_SECONDS = 30

local CLASS_TOKEN = { [1] = "WARRIOR", [2] = "PALADIN", [3] = "HUNTER", [4] = "ROGUE", [5] = "PRIEST", [6] = "DEATHKNIGHT", [7] = "SHAMAN",
                      [8] = "MAGE", [9] = "WARLOCK", [10] = "SPELLBLADE", [11] = "DRUID" }
local SORT_NAME, SORT_LEVEL, SORT_CLASS = 0, 1, 2
-- the last column can show the zone, the guild or the race (like the stock Who list's drop-down); each has its own server sort key
local MODES = { { key = "zone", label = "Zone", sort = 3 }, { key = "guild", label = "Guild", sort = 4 }, { key = "race", label = "Race", sort = 5 } }
-- column layout inside the 298 px wide list (x offset, width)
local COL = { name = { 0, 78 }, level = { 78, 40 }, class = { 118, 72 }, extra = { 190, 108 } }

local state = { page = 0, pages = 1, matches = 0, online = 0, bots = 0, seq = 0, rows = {}, loading = false, lastRequest = 0,
                sort = SORT_NAME, desc = false, hideBots = false, mode = 1 }

local panel, search, hideBotsCheck, minBox, maxBox, totals, pageText, prevBtn, nextBtn, colBtn, menuFrame, addFriendBtn, inviteBtn, guildInviteBtn
local rowButtons, headerButtons = {}, {}
local stockWhoListUpdate

-- ---- stock widgets we replace ----------------------------------------------------------------------------------------------------------------------------------
local STOCK = { "WhoFrameTotals", "WhoFrameColumnHeader1", "WhoFrameColumnHeader2", "WhoFrameColumnHeader3", "WhoFrameColumnHeader4", "WhoListScrollFrame",
                "WhoFrameEditBox", "WhoFrameWhoButton", "WhoFrameAddFriendButton", "WhoFrameGroupInviteButton" }
local function HideStock()
    for _, name in ipairs(STOCK) do
        local w = _G[name]
        if w then w:Hide() end
    end
    for i = 1, 17 do
        local b = _G["WhoFrameButton" .. i]
        if b then b:Hide() end
    end
end

-- ---- helpers --------------------------------------------------------------------------------------------------------------------------------------------------------------
local function Sanitize(s)
    local cleaned = (s or ""):gsub("[;,%^~%c]", " ")
    return cleaned
end

local function Save()
    RazagathWhoChar = RazagathWhoChar or {}
    RazagathWhoChar.hideBots, RazagathWhoChar.sort, RazagathWhoChar.desc, RazagathWhoChar.mode = state.hideBots, state.sort, state.desc, state.mode
end

-- one line only: shorten the text (adding "..") until it fits the column; the font strings have no fixed width, so GetStringWidth is the true single-line width
local function Fit(fs, text, maxW)
    fs:SetText(text)
    if fs:GetStringWidth() <= maxW then return end
    local t = text
    while #t > 1 do
        t = t:sub(1, -2)
        fs:SetText(t .. "..")
        if fs:GetStringWidth() <= maxW then return end
    end
end

local function ExtraText(r)
    local m = MODES[state.mode].key
    if m == "guild" then return (r.guild ~= "" and r.guild) or "-" end
    if m == "race" then return r.race end
    return r.zone
end

local function Render()
    if not panel then return end
    local names = LOCALIZED_CLASS_NAMES_MALE or {}
    for i = 1, ROWS do
        local btn, r = rowButtons[i], state.rows[i]
        if r then
            btn.data = r
            if r.name == state.selected then btn:LockHighlight() else btn:UnlockHighlight() end
            Fit(btn.name, r.name, COL.name[2] - 6)
            if r.bot then btn.name:SetTextColor(0.62, 0.62, 0.68) else btn.name:SetTextColor(1, 0.82, 0) end
            btn.level:SetText(r.level)
            local c = GetQuestDifficultyColor and GetQuestDifficultyColor(r.level)
            if c then btn.level:SetTextColor(c.r, c.g, c.b) else btn.level:SetTextColor(1, 1, 1) end
            local token = CLASS_TOKEN[r.class]
            Fit(btn.class, (token and names[token]) or token or "?", COL.class[2] - 4)
            local cc = token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
            if cc then btn.class:SetTextColor(cc.r, cc.g, cc.b) else btn.class:SetTextColor(1, 1, 1) end
            Fit(btn.extra, ExtraText(r), COL.extra[2] - 6)
            btn:Show()
        else
            btn.data = nil
            btn:UnlockHighlight()
            btn:Hide()
        end
    end
    if state.loading and #state.rows == 0 then
        totals:SetText("Loading...")
    else
        local real = state.online - state.bots
        local text = string.format("%d online (%d %s, %d %s)", state.online, real, real == 1 and "player" or "players", state.bots, state.bots == 1 and "bot" or "bots")
        if state.matches ~= state.online then text = text .. " - " .. state.matches .. " match" end
        totals:SetText(text)
    end
    if addFriendBtn then
        if state.selected then addFriendBtn:Enable(); inviteBtn:Enable() else addFriendBtn:Disable(); inviteBtn:Disable() end
        -- Guild Invite: only when a player is selected AND we are in a guild AND our rank may invite (CanGuildInvite)
        local canGuild = state.selected and IsInGuild and IsInGuild() and CanGuildInvite and CanGuildInvite()
        if canGuild then guildInviteBtn:Enable() else guildInviteBtn:Disable() end
    end
    pageText:SetText(string.format("Page %d / %d", state.page + 1, state.pages))
    if state.page > 0 then prevBtn:Enable() else prevBtn:Disable() end
    if state.page + 1 < state.pages then nextBtn:Enable() else nextBtn:Disable() end
    headerButtons.extra.label:SetText(MODES[state.mode].label)
    colBtn:SetText("Column: " .. MODES[state.mode].label)
    for _, btn in pairs(headerButtons) do
        local key = (btn.sortKey ~= nil) and btn.sortKey or MODES[state.mode].sort
        if state.sort == key then
            btn.arrow:Show()
            if state.desc then btn.arrow:SetTexCoord(0, 1, 1, 0) else btn.arrow:SetTexCoord(0, 1, 0, 1) end
        else
            btn.arrow:Hide()
        end
    end
end

-- ---- server requests -------------------------------------------------------------------------------------------------------------------------------------------
local function Request(page)
    if page then state.page = page end
    state.seq = state.seq + 1
    state.rows, state.loading, state.lastRequest = {}, true, GetTime()
    local minL = tonumber(minBox:GetText()) or 0
    local maxL = tonumber(maxBox:GetText()) or 255
    SendAddonMessage(PREFIX, string.format("Q;%d;%d;%d;%d;%d;%d;%d;%d;%s", state.seq, state.page, ROWS, state.sort, state.desc and 1 or 0,
        state.hideBots and 1 or 0, minL, maxL, Sanitize(search:GetText())), "WHISPER", UnitName("player"))
    Render()
end

local function OnAddonMessage(prefix, message)
    if prefix ~= PREFIX or type(message) ~= "string" then return end
    local kind = message:sub(1, 1)
    if kind == "H" then
        local _, seq, matches, page, pages, online, bots = strsplit(";", message)
        if tonumber(seq) ~= state.seq then return end
        state.matches, state.page, state.pages = tonumber(matches) or 0, tonumber(page) or 0, tonumber(pages) or 1
        state.online, state.bots = tonumber(online) or 0, tonumber(bots) or 0
    elseif kind == "R" then
        local _, seq, list = strsplit(";", message, 3)
        if tonumber(seq) ~= state.seq or not list then return end
        for entry in string.gmatch(list, "[^%^]+") do
            local name, level, class, race, zone, guild, flag = strsplit(",", entry)
            if name then
                state.rows[#state.rows + 1] = { name = name, level = tonumber(level) or 0, class = tonumber(class) or 0, race = race or "", zone = zone or "",
                                                guild = guild or "", bot = (flag == "b") }
            end
        end
    elseif kind == "E" then
        local _, seq = strsplit(";", message)
        if tonumber(seq) ~= state.seq then return end
        state.loading = false
        Render()
    end
end

-- ---- UI ------------------------------------------------------------------------------------------------------------------------------------------------------------------
local function MakeText(parent, template, justify)
    local fs = parent:CreateFontString(nil, "ARTWORK", template or "GameFontHighlightSmall")
    fs:SetJustifyH(justify or "LEFT")
    return fs
end

-- a plain bordered edit box: the stock InputBoxTemplate art misbehaves at small sizes (end caps drawn outside the width), this looks the same at any width
local function MakeBox(parent, w, h, numeric, maxLetters)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetSize(w, h)
    e:SetFontObject(ChatFontNormal or GameFontHighlight)
    e:SetAutoFocus(false)
    e:SetTextInsets(6, 6, 0, 0)
    e:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
                    insets = { left = 3, right = 3, top = 3, bottom = 3 } })
    e:SetBackdropColor(0, 0, 0, 0.75)
    e:SetBackdropBorderColor(0.55, 0.55, 0.55, 1)
    if numeric then e:SetNumeric(true) end
    if maxLetters then e:SetMaxLetters(maxLetters) end
    return e
end

local debounce
local function ScheduleRequest() debounce = 0.45 end

local function SetMode(i)
    state.mode = i
    local sortKeys = { [3] = true, [4] = true, [5] = true }
    if sortKeys[state.sort] then state.sort = MODES[i].sort end      -- keep sorting by the visible column
    Save()
    Request(0)
end

local function Build()
    panel = CreateFrame("Frame", "RazagathWhoPanel", WhoFrame)
    panel:SetAllPoints(WhoFrame)

    -- row A: search box (starts right of the round portrait, so no label: a grey hint inside the box says what it does) + hide-bots checkbox
    search = MakeBox(panel, 124, 20, false, 24)
    search:SetPoint("TOPLEFT", panel, "TOPLEFT", 88, -46)
    local searchHint = search:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", search, "LEFT", 6, 0)
    searchHint:SetText("name, zone or guild")
    local function UpdateHint() if search:GetText() == "" and not search:HasFocus() then searchHint:Show() else searchHint:Hide() end end
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Request(0) end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    search:SetScript("OnTextChanged", function(self, user) UpdateHint(); if user then ScheduleRequest() end end)
    search:SetScript("OnEditFocusGained", UpdateHint)
    search:SetScript("OnEditFocusLost", UpdateHint)

    hideBotsCheck = CreateFrame("CheckButton", "RazagathWhoHideBots", panel, "UICheckButtonTemplate")
    hideBotsCheck:SetSize(24, 24)
    hideBotsCheck:SetPoint("TOPLEFT", panel, "TOPLEFT", 218, -44)
    _G["RazagathWhoHideBotsText"]:SetText("Hide bots")
    _G["RazagathWhoHideBotsText"]:SetFontObject(GameFontNormalSmall)
    hideBotsCheck:SetScript("OnClick", function(self)
        state.hideBots = self:GetChecked() and true or false
        Save()
        Request(0)
    end)

    -- row B: level range + which column to show
    local lv = MakeText(panel, "GameFontNormalSmall")
    lv:SetPoint("TOPLEFT", panel, "TOPLEFT", 22, -78)
    lv:SetText("Level")
    local function LevelBox(x)
        local e = MakeBox(panel, 36, 20, true, 3)
        e:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -75)
        e:SetJustifyH("CENTER")
        e:SetScript("OnEnterPressed", function(self) self:ClearFocus(); Request(0) end)
        e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
        e:SetScript("OnTextChanged", function(self, user) if user then ScheduleRequest() end end)
        return e
    end
    minBox = LevelBox(62)
    local dash = MakeText(panel, "GameFontNormalSmall", "CENTER")
    dash:SetPoint("TOPLEFT", panel, "TOPLEFT", 103, -78)
    dash:SetText("-")
    maxBox = LevelBox(114)

    -- (EasyMenu does not exist in 3.3.5: use the plain UIDropDownMenu calls the stock Who list uses; the template frame itself stays hidden, only the list pops up)
    menuFrame = CreateFrame("Frame", "RazagathWhoModeMenu", UIParent, "UIDropDownMenuTemplate")
    menuFrame:Hide()
    UIDropDownMenu_Initialize(menuFrame, function(self, level)
        for i, m in ipairs(MODES) do
            local info = {}
            info.text = m.label
            info.checked = (state.mode == i)
            info.func = function() SetMode(i) end
            UIDropDownMenu_AddButton(info, level)
        end
    end, "MENU")
    colBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    colBtn:SetSize(92, 20)
    colBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 154, -74)
    colBtn:SetScript("OnClick", function(self)
        ToggleDropDownMenu(1, nil, menuFrame, self, 0, 0)
    end)
    local refreshBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    refreshBtn:SetSize(62, 20)
    refreshBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 250, -74)
    refreshBtn:SetText("Refresh")
    refreshBtn:SetScript("OnClick", function() Request(state.page) end)

    -- column headers (click = sort, click again = reverse)
    local function Header(key, label, sortKey)
        local b = CreateFrame("Button", nil, panel)
        b:SetSize(COL[key][2], 16)
        b:SetPoint("TOPLEFT", panel, "TOPLEFT", 25 + COL[key][1], -96)
        b.sortKey = sortKey                      -- nil for the switchable column: its key follows the chosen mode
        local t = MakeText(b, "GameFontNormalSmall")
        t:SetPoint("LEFT", b, "LEFT", 4, 0)
        t:SetText(label)
        b.label = t
        b.arrow = b:CreateTexture(nil, "ARTWORK")
        b.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
        b.arrow:SetSize(9, 8)
        b.arrow:SetPoint("LEFT", t, "RIGHT", 3, 0)
        b.arrow:Hide()
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:SetScript("OnClick", function(self)
            local k = (self.sortKey ~= nil) and self.sortKey or MODES[state.mode].sort
            if state.sort == k then
                state.desc = not state.desc
            else
                state.sort = k
                state.desc = (k == SORT_LEVEL)   -- level sorts high -> low first, everything else A -> Z
            end
            Save()
            Request(0)
        end)
        headerButtons[key] = b
    end
    Header("name", "Name", SORT_NAME)
    Header("level", "Level", SORT_LEVEL)
    Header("class", "Class", SORT_CLASS)
    Header("extra", "Zone", nil)

    -- the 16 rows (one line each; text columns have no fixed width so Fit() can measure them)
    for i = 1, ROWS do
        local b = CreateFrame("Button", "RazagathWhoRow" .. i, panel)
        b:SetSize(298, ROW_H)
        if i == 1 then b:SetPoint("TOPLEFT", panel, "TOPLEFT", 25, -112) else b:SetPoint("TOPLEFT", rowButtons[i - 1], "BOTTOMLEFT", 0, 0) end
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:RegisterForClicks("LeftButtonUp")
        for _, key in ipairs({ "name", "level", "class", "extra" }) do
            local fs = MakeText(b, "GameFontHighlightSmall", key == "level" and "CENTER" or "LEFT")
            if key == "level" then
                fs:SetPoint("LEFT", b, "LEFT", COL.level[1], 0)
                fs:SetWidth(COL.level[2])
            else
                fs:SetPoint("LEFT", b, "LEFT", COL[key][1] + 4, 0)
            end
            b[key] = fs
        end
        b:SetScript("OnClick", function(self)
            local d = self.data
            if not d then return end
            state.selected = d.name
            Render()
        end)
        b:SetScript("OnDoubleClick", function(self)
            local d = self.data
            if d and ChatFrame_SendTell then ChatFrame_SendTell(d.name) end
        end)
        b:SetScript("OnEnter", function(self)
            local d = self.data
            if not d then return end
            local token = CLASS_TOKEN[d.class]
            local cname = (LOCALIZED_CLASS_NAMES_MALE and token and LOCALIZED_CLASS_NAMES_MALE[token]) or token or "?"
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:AddLine(d.name .. (d.bot and "  (bot)" or ""), 1, 0.82, 0)
            GameTooltip:AddLine(string.format("Level %d %s %s", d.level, d.race, cname), 1, 1, 1)
            GameTooltip:AddLine(d.zone, 0.8, 0.8, 0.8)
            if d.guild ~= "" then GameTooltip:AddLine("<" .. d.guild .. ">", 0.25, 1, 0.25) end
            GameTooltip:AddLine("Click: select   Double-click: whisper", 0.5, 0.5, 0.5)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)
        b:Hide()
        rowButtons[i] = b
    end

    -- footer: total (same spot as the stock one), page buttons in the stock edit-box bar, Refresh in the stock button slot
    totals = MakeText(panel, "GameFontNormalSmall", "CENTER")
    totals:SetPoint("BOTTOM", panel, "BOTTOM", -10, 127)
    totals:SetWidth(310)

    -- the frame art has a bar where the stock edit box sat (WhoFrameEditBox, still there but hidden: its position is the bar's position)
    prevBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    prevBtn:SetSize(50, 18)
    prevBtn:SetPoint("LEFT", WhoFrameEditBox, "LEFT", 10, 0)
    prevBtn:SetText("Prev")
    prevBtn:SetScript("OnClick", function() if state.page > 0 then Request(state.page - 1) end end)
    nextBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    nextBtn:SetSize(50, 18)
    nextBtn:SetPoint("RIGHT", WhoFrameEditBox, "RIGHT", -10, 0)
    nextBtn:SetText("Next")
    nextBtn:SetScript("OnClick", function() if state.page + 1 < state.pages then Request(state.page + 1) end end)
    pageText = MakeText(panel, "GameFontHighlightSmall", "CENTER")
    pageText:SetPoint("LEFT", prevBtn, "RIGHT", 2, 0)
    pageText:SetPoint("RIGHT", nextBtn, "LEFT", -2, 0)

    -- the frame art draws three button slots; the stock buttons (hidden) sit exactly on them, so ours are laid over the same rectangles
    local function OnSlot(stock, text, onClick)
        local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        b:SetPoint("TOPLEFT", stock, "TOPLEFT", 0, 0)
        b:SetPoint("BOTTOMRIGHT", stock, "BOTTOMRIGHT", 0, 0)
        b:SetText(text)
        b:SetScript("OnClick", onClick)
        return b
    end
    guildInviteBtn = OnSlot(WhoFrameWhoButton, "Guild Invite", function() if state.selected and GuildInvite then GuildInvite(state.selected) end end)
    addFriendBtn = OnSlot(WhoFrameAddFriendButton, "Add Friend", function() if state.selected then AddFriend(state.selected) end end)
    inviteBtn = OnSlot(WhoFrameGroupInviteButton, "Group Invite", function() if state.selected then InviteUnit(state.selected) end end)

    -- refresh when shown, every REFRESH_SECONDS while open (not while typing), and after the typing pause
    local acc = 0
    panel:SetScript("OnUpdate", function(self, elapsed)
        if debounce then
            debounce = debounce - elapsed
            if debounce <= 0 then debounce = nil; Request(0) end
        end
        acc = acc + elapsed
        if acc >= REFRESH_SECONDS then
            acc = 0
            if not search:HasFocus() and not minBox:HasFocus() and not maxBox:HasFocus() then Request(state.page) end
        end
    end)
    panel:SetScript("OnShow", function()
        HideStock()
        Request(state.page)
    end)
    panel:SetScript("OnEvent", function(self, event, prefix, message)
        if event == "CHAT_MSG_ADDON" then OnAddonMessage(prefix, message) else Render() end     -- guild changes: re-evaluate the Guild Invite button
    end)
    panel:RegisterEvent("CHAT_MSG_ADDON")
    panel:RegisterEvent("PLAYER_GUILD_UPDATE")
    panel:RegisterEvent("GUILD_ROSTER_UPDATE")

    -- restore the saved view (per character)
    local saved = RazagathWhoChar or {}
    state.hideBots = saved.hideBots and true or false
    state.sort = saved.sort or SORT_NAME
    state.desc = saved.desc and true or false
    state.mode = (saved.mode and MODES[saved.mode]) and saved.mode or 1
    hideBotsCheck:SetChecked(state.hideBots)

    -- everything above is built; only now take the stock list away (so a failure while building can never leave the tab blank)
    local ok, err = pcall(Render)
    if not ok then error("render: " .. tostring(err)) end
    stockWhoListUpdate = WhoList_Update
    -- the stock code calls WhoList_Update() whenever the tab opens or a /who result arrives: keep the stock widgets hidden instead of drawing them
    WhoList_Update = function()
        HideStock()
        if panel:IsVisible() and (GetTime() - state.lastRequest) > 1.0 then Request(state.page) end
    end
    WhoFrame:HookScript("OnShow", function() if panel and panel:IsShown() then HideStock() end end)
    HideStock()
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    if RAZAGATH_WHOLIST_OFF or not WhoFrame then return end
    local ok, err = pcall(Build)
    if not ok then
        -- never leave the player with a broken Who tab: hide whatever we created and give the stock list back
        if panel then panel:Hide(); panel:SetScript("OnShow", nil); panel:SetScript("OnUpdate", nil); panel:UnregisterAllEvents() end
        if stockWhoListUpdate then WhoList_Update = stockWhoListUpdate end
        for _, name in ipairs(STOCK) do
            local w = _G[name]
            if w then w:Show() end
        end
        if WhoFrame:IsVisible() and WhoList_Update then pcall(WhoList_Update) end
        DEFAULT_CHAT_FRAME:AddMessage("|cffff8800[Razagath]|r Players Online list failed to load (" .. tostring(err) .. ") - the normal Who list is used instead.")
    end
end)

SLASH_RAZAGATHWHO1 = "/players"
SlashCmdList["RAZAGATHWHO"] = function()
    if ToggleFriendsFrame then ToggleFriendsFrame(2) end
end
