-- RazagathMounts: a WotLK-native, modern-styled mount browser.
-- Known mounts are computed at runtime from the player's own spellbook
-- (AccountBound already syncs mount spells there) against the static
-- id->{name,icon,flying,modelPath} table in MountData.lua. No server
-- changes needed - this is a pure client addon.

local GRID_COLS = 7
local CELL = 44
local ICON_SIZE = 36
local VISIBLE_ROWS = 6
local GRID_LEFT = 20
local GRID_TOP = 96

local frame
local gridButtons = {}
local displayed = {}          -- currently filtered/sorted list
local searchText = ""
local filterMode = "ALL"      -- ALL / GROUND / FLYING
local selected = nil          -- currently previewed mount entry
local previewModel
local randomFavButton

-- ===== SavedVariables ======================================================
local function EnsureDB()
    RazagathMountsDB = RazagathMountsDB or {}
    RazagathMountsDB.favorites = RazagathMountsDB.favorites or {}
    RazagathMountsDB.minimapAngle = RazagathMountsDB.minimapAngle or 220
end

-- ===== Companion scan ========================================================
-- WotLK 3.3.5a tracks mounts through the native Companions system (the same
-- one backing the stock Pets/Mounts panel under the character frame) via
-- GetNumCompanions/GetCompanionInfo("MOUNT", index) - NOT the normal
-- spellbook enumeration. Confirmed the hard way: a spellbook scan resolved
-- every slot to a real spell ID but matched zero mounts, because mounts
-- simply aren't listed there on this client.
local function ScanKnownMounts()
    local result = {}
    local numCompanions = GetNumCompanions("MOUNT")
    for i = 1, numCompanions do
        local _, _, spellID = GetCompanionInfo("MOUNT", i)
        local data = spellID and RazagathMounts_Data[spellID]
        if data then
            table.insert(result, {
                id = spellID,
                name = data.name,
                icon = data.icon,
                flying = data.flying,
                displayId = data.displayId,
                modelPath = data.modelPath,
                favorite = RazagathMountsDB.favorites[spellID] or false,
            })
        end
    end
    table.sort(result, function(a, b) return a.name < b.name end)
    return result
end

local function GetFilteredMounts()
    local all = ScanKnownMounts()
    local out = {}
    local needle = string.lower(searchText)
    for _, m in ipairs(all) do
        local matchesSearch = searchText == "" or string.find(string.lower(m.name), needle, 1, true)
        local matchesFilter = filterMode == "ALL"
            or (filterMode == "FLYING" and m.flying)
            or (filterMode == "GROUND" and not m.flying)
        if matchesSearch and matchesFilter then
            table.insert(out, m)
        end
    end
    return out
end

-- ===== Preview panel ========================================================
local function UpdatePreview(mount)
    selected = mount
    if not mount then
        previewModel:Hide()
        RazagathMountsPreviewName:SetText("No mounts known")
        RazagathMountsPreviewType:SetText("")
        randomFavButton:Hide()
        RazagathMountsSummonButton:Hide()
        return
    end
    previewModel:Show()
    randomFavButton:Show()
    RazagathMountsSummonButton:Show()
    -- SetCreature(displayId) renders nothing at all on this client (no error,
    -- just a blank viewport) despite the displayId data now being correct -
    -- SetModel(path) is the one that reliably shows *something*. Confirmed via
    -- a full method enumeration that this client's Model widget has no
    -- SetTextureVariation/SetCustomization/SetItem equivalent at all, so a
    -- textured preview isn't reachable through this widget - untextured is
    -- the ceiling here, not a wrong-method-name issue.
    if mount.modelPath and mount.modelPath ~= "" then
        previewModel:SetModel(mount.modelPath)
        previewModel:SetPosition(0, 0, 0)
        previewModel:SetFacing(0.3)
        previewModel:SetCamera(0)
    end
    RazagathMountsPreviewName:SetText(mount.name)
    RazagathMountsPreviewType:SetText(mount.flying and "Flying" or "Ground")
    RazagathMountsSummonButton.mountName = mount.name
    RazagathMountsSummonButtonLabel:SetText(mount.name)
end

-- Mounting isn't a combat-protected action in this era (you can't mount in
-- combat anyway), so a plain insecure API call works fine - no need for
-- SecureActionButtonTemplate/macro attributes, which turned out to silently
-- block SetPoint on the button entirely (confirmed: an identical anchor call
-- on a non-secure FontString resolved fine, the same call on a
-- SecureActionButtonTemplate button never took effect - 0 anchor points).
local function SummonMountByName(name)
    if not name then return end
    if IsMounted() then Dismount() end
    CastSpellByName(name)
end

-- ===== Grid ==================================================================
local function GridButton_OnClick(self)
    local mount = self.mountData
    if not mount then return end
    UpdatePreview(mount)
end

local function GridButton_OnEnter(self)
    local mount = self.mountData
    if not mount then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(mount.name)
    GameTooltip:AddLine(mount.flying and "Flying mount" or "Ground mount", 0.6, 0.8, 1)
    GameTooltip:AddLine(mount.favorite and "Right-click to remove favorite" or "Right-click to favorite", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end

local function GridButton_OnLeave()
    GameTooltip:Hide()
end

local function GridButton_OnRightClick(self)
    local mount = self.mountData
    if not mount then return end
    if RazagathMountsDB.favorites[mount.id] then
        RazagathMountsDB.favorites[mount.id] = nil
    else
        RazagathMountsDB.favorites[mount.id] = true
    end
    RazagathMounts_RefreshGrid()
end

local function CreateGridButton(index)
    local row = math.floor((index - 1) / GRID_COLS)
    local col = (index - 1) % GRID_COLS

    -- Plain (non-secure) button: grid icons only select/favorite, they never
    -- summon directly - summoning happens through the dedicated secure
    -- Summon button in the preview pane. Mixing SecureActionButtonTemplate's
    -- own click dispatch with a custom OnClick on the same button risked the
    -- two interfering with each other.
    local b = CreateFrame("Button", "RazagathMountsGridButton" .. index, frame)
    b:SetSize(ICON_SIZE, ICON_SIZE)
    b:SetPoint("TOPLEFT", frame, "TOPLEFT", GRID_LEFT + col * CELL, -(GRID_TOP + row * CELL))
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(b)
    b.icon = icon

    -- A text glyph rather than a texture path - after several wrong texture/
    -- method guesses today, this sidesteps asset-availability risk entirely.
    local favStar = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    favStar:SetPoint("TOPRIGHT", b, "TOPRIGHT", 3, 3)
    favStar:SetText("*")
    favStar:SetTextColor(1, 0.82, 0)
    favStar:Hide()
    b.favStar = favStar

    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(b)
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")

    b:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            GridButton_OnRightClick(self)
        else
            GridButton_OnClick(self)
        end
    end)
    b:SetScript("OnEnter", GridButton_OnEnter)
    b:SetScript("OnLeave", GridButton_OnLeave)

    return b
end

function RazagathMounts_RefreshGrid()
    EnsureDB()
    displayed = GetFilteredMounts()

    local scroll = RazagathMountsScrollFrame
    local numItems = #displayed
    local numRows = math.ceil(numItems / GRID_COLS)
    FauxScrollFrame_Update(scroll, numRows, VISIBLE_ROWS, CELL)
    local offset = FauxScrollFrame_GetOffset(scroll)

    for i = 1, GRID_COLS * VISIBLE_ROWS do
        local b = gridButtons[i]
        local dataIndex = offset * GRID_COLS + i
        local mount = displayed[dataIndex]
        if mount then
            b.mountData = mount
            b.icon:SetTexture(mount.icon)
            if RazagathMountsDB.favorites[mount.id] then b.favStar:Show() else b.favStar:Hide() end
            b:Show()
        else
            b.mountData = nil
            b:Hide()
        end
    end

    RazagathMountsCountText:SetText(numItems .. " mount" .. (numItems == 1 and "" or "s"))
end

-- ===== Filter buttons ========================================================
local function SetFilterMode(mode)
    filterMode = mode
    RazagathMountsFilterAll:SetChecked(mode == "ALL")
    RazagathMountsFilterGround:SetChecked(mode == "GROUND")
    RazagathMountsFilterFlying:SetChecked(mode == "FLYING")
    RazagathMounts_RefreshGrid()
end

-- ===== Random favorite =======================================================
local function SummonRandomFavorite()
    local favIDs = {}
    for id, isFav in pairs(RazagathMountsDB.favorites) do
        if isFav and RazagathMounts_Data[id] then
            table.insert(favIDs, id)
        end
    end
    if #favIDs == 0 then return end
    local pick = RazagathMounts_Data[favIDs[math.random(#favIDs)]]
    SummonMountByName(pick.name)
end

-- ===== Frame construction (called once from XML OnLoad) ====================
function RazagathMounts_OnLoad(self)
    frame = self
    self:RegisterForDrag("LeftButton")
    self:SetClampedToScreen(true)
    self:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 11, top = 12, bottom = 11 },
    })

    -- title bar
    local title = self:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOP", self, "TOP", 0, -16)
    title:SetText("Razagath Mounts")

    local close = CreateFrame("Button", nil, self, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", self, "TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() self:Hide() end)

    -- search box
    local search = CreateFrame("EditBox", "RazagathMountsSearchBox", self)
    search:SetSize(180, 20)
    search:SetPoint("TOPLEFT", self, "TOPLEFT", 20, -44)
    search:SetAutoFocus(false)
    search:SetFontObject(GameFontHighlight)
    search:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    search:SetBackdropColor(0, 0, 0, 0.5)
    search:SetTextInsets(6, 6, 0, 0)
    search:SetScript("OnTextChanged", function(self)
        searchText = self:GetText()
        RazagathMounts_RefreshGrid()
    end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local searchHint = self:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    searchHint:SetPoint("LEFT", search, "LEFT", 6, 0)
    searchHint:SetText("Search...")
    search:SetScript("OnEditFocusGained", function() searchHint:Hide() end)
    local function UpdateSearchHint(self)
        if self:GetText() == "" then searchHint:Show() else searchHint:Hide() end
    end
    search:SetScript("OnEditFocusLost", UpdateSearchHint)
    search:HookScript("OnTextChanged", UpdateSearchHint)

    -- filter checkbuttons
    local function MakeFilterButton(nameSuffix, label, xOffset, mode)
        local b = CreateFrame("CheckButton", "RazagathMountsFilter" .. nameSuffix, self, "UICheckButtonTemplate")
        b:SetSize(20, 20)
        b:SetPoint("TOPLEFT", self, "TOPLEFT", xOffset, -70)
        _G[b:GetName() .. "Text"]:SetText(label)
        b:SetScript("OnClick", function() SetFilterMode(mode) end)
        return b
    end
    MakeFilterButton("All", "All", 20, "ALL")
    MakeFilterButton("Ground", "Ground", 110, "GROUND")
    MakeFilterButton("Flying", "Flying", 210, "FLYING")
    RazagathMountsFilterAll:SetChecked(true)

    local countText = self:CreateFontString("RazagathMountsCountText", "ARTWORK", "GameFontDisableSmall")
    countText:SetPoint("TOPLEFT", self, "TOPLEFT", 300, -73)

    -- scroll frame driving the grid (grid buttons are created directly on the
    -- main frame, positioned by GRID_LEFT/GRID_TOP - this FauxScrollFrame just
    -- owns the scrollbar + offset math, standard WotLK virtualized-list pattern)
    local scroll = CreateFrame("ScrollFrame", "RazagathMountsScrollFrame", self, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", self, "TOPLEFT", GRID_LEFT, -GRID_TOP)
    scroll:SetSize(GRID_COLS * CELL, VISIBLE_ROWS * CELL)
    scroll:SetScript("OnVerticalScroll", function(self, offsetDelta)
        FauxScrollFrame_OnVerticalScroll(self, offsetDelta, CELL, RazagathMounts_RefreshGrid)
    end)

    for i = 1, GRID_COLS * VISIBLE_ROWS do
        gridButtons[i] = CreateGridButton(i)
    end

    -- preview pane (right side)
    local previewFrame = CreateFrame("Frame", nil, self)
    previewFrame:SetSize(150, 150)
    previewFrame:SetPoint("TOPRIGHT", self, "TOPRIGHT", -20, -70)
    previewFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    previewFrame:SetBackdropColor(0, 0, 0, 0.4)

    previewModel = CreateFrame("PlayerModel", "RazagathMountsPreviewModel", previewFrame)
    previewModel:SetPoint("TOPLEFT", previewFrame, "TOPLEFT", 4, -4)
    previewModel:SetPoint("BOTTOMRIGHT", previewFrame, "BOTTOMRIGHT", -4, 4)


    local previewName = self:CreateFontString("RazagathMountsPreviewName", "ARTWORK", "GameFontNormal")
    previewName:SetPoint("TOP", previewFrame, "BOTTOM", 0, -6)
    previewName:SetWidth(150)

    local previewType = self:CreateFontString("RazagathMountsPreviewType", "ARTWORK", "GameFontDisableSmall")
    previewType:SetPoint("TOP", previewName, "BOTTOM", 0, -2)

    -- Plain button (no secure template - see SummonMountByName's comment for
    -- why) + a hand-drawn backdrop matching the search box's proven-working one.
    local summon = CreateFrame("Button", "RazagathMountsSummonButton", self)
    summon:SetSize(150, 24)
    summon:SetPoint("TOP", previewType, "BOTTOM", 0, -10)
    summon:RegisterForClicks("LeftButtonUp")
    summon:SetScript("OnClick", function(self) SummonMountByName(self.mountName) end)
    summon:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    summon:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    summon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local summonLabel = summon:CreateFontString("RazagathMountsSummonButtonLabel", "OVERLAY", "GameFontNormal")
    summonLabel:SetPoint("CENTER")
    summonLabel:SetText("Summon")

    randomFavButton = CreateFrame("Button", "RazagathMountsRandomFavoriteButton", self)
    randomFavButton:SetSize(150, 24)
    randomFavButton:SetPoint("TOP", summon, "BOTTOM", 0, -6)
    randomFavButton:RegisterForClicks("LeftButtonUp")
    randomFavButton:SetScript("OnClick", SummonRandomFavorite)
    randomFavButton:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12, insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    randomFavButton:SetBackdropColor(0.15, 0.15, 0.15, 0.9)
    randomFavButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    local randomLabel = randomFavButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    randomLabel:SetPoint("CENTER")
    randomLabel:SetText("Random Favorite")

    -- slash command
    SLASH_RAZAGATHMOUNTS1 = "/mounts"
    SlashCmdList["RAZAGATHMOUNTS"] = function()
        if frame:IsShown() then frame:Hide() else frame:Show() end
    end
end

function RazagathMounts_OnShow()
    EnsureDB()
    RazagathMounts_RefreshGrid()
    if #displayed > 0 then
        UpdatePreview(displayed[1])
    else
        UpdatePreview(nil)
    end
end

function RazagathMounts_OnHide()
    GameTooltip:Hide()
end

-- ===== Minimap button ========================================================
local function GetMinimapButtonPosition(angle)
    local radius = 80
    local x = math.cos(math.rad(angle)) * radius
    local y = math.sin(math.rad(angle)) * radius
    return x, y
end

local function PlaceMinimapButton(self, angle)
    local x, y = GetMinimapButtonPosition(angle)
    self:ClearAllPoints()
    self:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function RazagathMountsMinimapButton_OnLoad(self)
    EnsureDB()
    PlaceMinimapButton(self, RazagathMountsDB.minimapAngle)
end

function RazagathMountsMinimapButton_SavePosition()
    local mx, my = Minimap:GetCenter()
    local px, py = RazagathMountsMinimapButton:GetCenter()
    RazagathMountsDB.minimapAngle = math.deg(math.atan2(py - my, px - mx))
end

function RazagathMountsMinimapButton_OnUpdate(self)
    if self.isMoving then
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        local angle = math.deg(math.atan2(py - my, px - mx))
        PlaceMinimapButton(self, angle)
    end
end

function RazagathMountsMinimapButton_OnClick()
    if not frame then return end
    if frame:IsShown() then frame:Hide() else frame:Show() end
end

function RazagathMountsMinimapButton_OnEnter(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText("Razagath Mounts")
    GameTooltip:AddLine("Click to open the mount browser", 0.6, 0.6, 0.6)
    GameTooltip:Show()
end
