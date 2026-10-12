-- Razagath: shows the server's custom Spell Blade loot inside AtlasLoot.
--
-- AtlasLoot (v5.x "Enhanced") only knows the stock loot tables, so the sets / leveling gear / weapons this server adds are invisible there. This file adds a
-- "Razagath Loot" button to AtlasLoot's item window for every boss table that can drop custom loot; clicking it opens a panel over the window with the
-- boss's custom drops (grouped by set/weapon type, with the drop chance and every piece, hover for the tooltip). The data (Data.lua) is generated from
-- the server's own loot tables, so it is always what the boss really drops.
--
-- SAFE WITHOUT ATLASLOOT: Data.lua is skipped entirely when the AtlasLoot add-on is not installed, nothing here runs unless AtlasLoot's functions exist,
-- and every callback is wrapped in pcall, so a missing, disabled or different AtlasLoot version can never cause an error.

local DATA = RazagathAtlasLoot
if not DATA or not DATA.boss then return end

local ROW_H, VISIBLE = 22, 16
local panel, button, scroll, titleText
local rows = {}
local flat = {}
local installed = false

local function BaseKey(id)
    -- the very same suffix stripping AtlasLoot_GetLoottableHeroic does (faction / heroic / 25-man variants share one entry)
    id = string.gsub(id, "_H", "")
    id = string.gsub(id, "_A", "")
    id = string.gsub(id, "HEROIC", "")
    id = string.gsub(id, "25Man", "")
    return id
end

local function Refresh()
    if not (panel and scroll) then return end
    local offset = FauxScrollFrame_GetOffset(scroll)
    for i = 1, VISIBLE do
        local e, row = flat[offset + i], rows[i]
        if e then
            row.entry = e
            row:Show()
            if e.kind == "item" then
                local info = DATA.items[e.id]
                local name, quality = info and info[1] or ("item " .. e.id), info and info[2] or 1
                local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] or { r = 1, g = 1, b = 1 }
                row.icon:SetTexture(GetItemIcon and GetItemIcon(e.id) or "Interface\\Icons\\INV_Misc_QuestionMark")
                row.icon:Show()
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
                row.text:SetText(name)
                row.text:SetTextColor(c.r, c.g, c.b)
                row.chance:SetText("")
            elseif e.kind == "group" then
                row.icon:Hide()
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.text:SetText(e.text)
                row.text:SetTextColor(1, 0.82, 0)
                row.chance:SetText(e.chance .. "%")
            else
                row.icon:Hide()
                row.text:ClearAllPoints()
                row.text:SetPoint("LEFT", row, "LEFT", 4, 0)
                row.text:SetText("- " .. e.text .. " -")
                row.text:SetTextColor(0.4, 0.8, 1)
                row.chance:SetText("")
            end
        else
            row.entry = nil
            row:Hide()
        end
    end
    FauxScrollFrame_Update(scroll, #flat, VISIBLE, ROW_H)
end

local function Build(key)
    for i = #flat, 1, -1 do flat[i] = nil end
    local blocks = DATA.boss[key]
    if not blocks then return false end
    for _, blk in ipairs(blocks) do
        local mode, groups = blk[1], blk[2]
        if mode ~= "" then flat[#flat + 1] = { kind = "mode", text = mode } end
        for _, g in ipairs(groups) do
            flat[#flat + 1] = { kind = "group", text = g[1], chance = g[2] }
            for _, id in ipairs(g[3]) do flat[#flat + 1] = { kind = "item", id = id } end
        end
    end
    return #flat > 0
end

local function CreateRow(i)
    local row = CreateFrame("Button", nil, panel)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, -(i - 1) * ROW_H)
    row:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
    row.icon = row:CreateTexture(nil, "ARTWORK")
    row.icon:SetWidth(ROW_H - 4)
    row.icon:SetHeight(ROW_H - 4)
    row.icon:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.text = row:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    row.text:SetJustifyH("LEFT")
    row.chance = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    row.chance:SetPoint("RIGHT", row, "RIGHT", -6, 0)
    row.chance:SetJustifyH("RIGHT")
    row.text:SetPoint("RIGHT", row.chance, "LEFT", -6, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    row:SetScript("OnEnter", function(self)
        local e = self.entry
        if e and e.kind == "item" then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. e.id .. ":0:0:0:0:0:0:0")
            GameTooltip:Show()
        end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
        local e = self.entry
        if e and e.kind == "item" and IsModifiedClick and IsModifiedClick("CHATLINK") then
            local _, link = GetItemInfo(e.id)
            if link then ChatEdit_InsertLink(link) end
        end
    end)
    return row
end

local function CreateUI()
    if panel then return true end
    if not AtlasLootItemsFrame then return false end

    button = CreateFrame("Button", "RazagathAtlasLootButton", AtlasLootItemsFrame, "UIPanelButtonTemplate")
    button:SetWidth(110)
    button:SetHeight(22)
    button:SetText("Razagath Loot")
    button:SetPoint("TOPRIGHT", AtlasLootItemsFrame, "TOPRIGHT", -38, -6)
    button:SetFrameLevel(AtlasLootItemsFrame:GetFrameLevel() + 5)
    button:Hide()

    panel = CreateFrame("Frame", "RazagathAtlasLootPanel", AtlasLootItemsFrame)
    panel:SetPoint("TOPLEFT", AtlasLootItemsFrame, "TOPLEFT", 12, -32)
    panel:SetPoint("BOTTOMRIGHT", AtlasLootItemsFrame, "BOTTOMRIGHT", -12, 40)
    panel:SetFrameLevel(AtlasLootItemsFrame:GetFrameLevel() + 30)
    panel:EnableMouse(true)
    panel:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    panel:Hide()

    titleText = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    titleText:SetPoint("TOPLEFT", panel, "TOPLEFT", 12, -10)
    titleText:SetPoint("RIGHT", panel, "RIGHT", -110, 0)
    titleText:SetJustifyH("LEFT")

    local back = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    back:SetWidth(90)
    back:SetHeight(22)
    back:SetText("Back")
    back:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -10, -8)
    back:SetScript("OnClick", function() panel:Hide() end)

    local hint = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    hint:SetPoint("TOPLEFT", titleText, "BOTTOMLEFT", 0, -2)
    hint:SetText("Spell Blade drops added by this server. Each line is one roll per kill; you get one piece of the set or weapon group.")
    hint:SetTextColor(0.7, 0.7, 0.7)
    hint:SetPoint("RIGHT", panel, "RIGHT", -12, 0)
    hint:SetJustifyH("LEFT")

    scroll = CreateFrame("ScrollFrame", "RazagathAtlasLootScroll", panel, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -50)
    scroll:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 10)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, Refresh)
    end)
    for i = 1, VISIBLE do rows[i] = CreateRow(i) end

    button:SetScript("OnClick", function()
        if panel:IsShown() then panel:Hide() else
            FauxScrollFrame_SetOffset(scroll, 0)
            scroll:SetVerticalScroll(0)
            Refresh()
            panel:Show()
        end
    end)
    panel:SetScript("OnShow", Refresh)
    return true
end

local function OnTable(dataID)
    if type(dataID) ~= "string" then return end
    if not CreateUI() then return end
    panel:Hide()
    local key = BaseKey(dataID)
    if Build(key) then
        local name = AtlasLoot_TableNames and AtlasLoot_TableNames[dataID] and AtlasLoot_TableNames[dataID][1]
        titleText:SetText("Razagath loot" .. (name and (" - " .. name) or ""))
        button:Show()
    else
        button:Hide()
    end
end

local function Install()
    if installed then return end
    if type(AtlasLoot_ShowItemsFrame) ~= "function" or not AtlasLootItemsFrame then return end
    installed = true
    hooksecurefunc("AtlasLoot_ShowItemsFrame", function(dataID)
        pcall(OnTable, dataID)
    end)
    -- a table may already be open
    local r = AtlasLootItemsFrame.refresh
    if r and r[1] then pcall(OnTable, r[1]) end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("ADDON_LOADED")
f:SetScript("OnEvent", function(self, event)
    pcall(Install)
    if installed then self:UnregisterAllEvents() end
end)
pcall(Install)
