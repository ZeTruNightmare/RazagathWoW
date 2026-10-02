-- Razagath Companions - standalone Mounts/Pets window, a 1:1 port of retail's
-- Collections Journal (Mount Journal) layout and art onto WotLK's companion
-- API. Layout numbers (703x606 window, 260-wide list inset, 413-wide model
-- inset, 46px rows, bottom tabs, ...) come from the real retail
-- Blizzard_Collections XML; every texture is extracted from the user's own
-- retail client (see casc_get.pl / export_atlas.pl and the razagath-companions
-- memory). Retail atlases are referenced BY NAME via RazagathAtlasData
-- (generated Atlas_Data.lua) so the structure below reads like the retail XML.
--
-- WotLK API used: GetNumCompanions(mode), GetCompanionInfo(mode, index) ->
-- creatureID, creatureName, spellID, icon, active; CallCompanion(mode, index);
-- DismissCompanion(mode); mode "MOUNT" or "CRITTER". Favorites and search are
-- client-side (SavedVariables) - WotLK has no backend for either.

RazagathCompanionsDB = RazagathCompanionsDB or {};
RazagathCompanionsDB.favorites = RazagathCompanionsDB.favorites or {};

local ADDON_PATH = "Interface\\AddOns\\Razagath\\Companions\\";
local FILES = ADDON_PATH.."Files\\";
local MODE_MOUNT, MODE_PET = "MOUNT", "CRITTER";

local ROW_H, ROW_W = 46, 208;
local NUM_ROWS = 9;   -- rendered rows; the 9th is clipped by the scroll frame exactly like retail
local FULL_ROWS = 8;  -- rows that are completely visible (scroll range = count - FULL_ROWS)

local currentMode = MODE_MOUNT;
local selectedCreatureID = nil;
local searchText = "";
local favoritesOnly = false;
local scrollOffset = 0;
local filteredList = {}; -- {index=, creatureID=, name=, icon=, spellID=, active=, favorite=}

-- ===========================================================================
-- Helpers (WotLK 3.3.5a has no :SetShown, no atlas system, no NineSlice)
-- ===========================================================================

local function SetShownCompat(region, shown)
	if ( shown ) then region:Show(); else region:Hide(); end
end

local function AtlasInfo(name)
	return RazagathAtlasData and RazagathAtlasData[strlower(name)];
end

-- Atlas elements are padded to power-of-two with content at the top-left, so
-- the texcoord is 0..right / 0..bottom (a[4], a[5]); a[2], a[3] = native size.
local function SetAtlas(tex, name, useAtlasSize, flipV)
	local a = AtlasInfo(name);
	if ( not a ) then return; end
	tex:SetTexture(ADDON_PATH..a[1]);
	if ( flipV ) then
		tex:SetTexCoord(0, a[4], a[5], 0);
	else
		tex:SetTexCoord(0, a[4], 0, a[5]);
	end
	if ( useAtlasSize ) then tex:SetSize(a[2], a[3]); end
end

-- state: "Normal" | "Pushed" | "Highlight" | "Disabled"
local function SetButtonAtlas(btn, state, name, blendMode)
	local a = AtlasInfo(name);
	if ( not a ) then return nil; end
	if ( state == "Highlight" ) then
		btn:SetHighlightTexture(ADDON_PATH..a[1], blendMode or "ADD");
	else
		btn["Set"..state.."Texture"](btn, ADDON_PATH..a[1]);
	end
	local t = btn["Get"..state.."Texture"](btn);
	t:SetTexCoord(0, a[4], 0, a[5]);
	return t;
end

local function Clamp(v, lo, hi)
	if ( v < lo ) then return lo; end
	if ( v > hi ) then return hi; end
	return v;
end

-- ===========================================================================
-- Main window: retail PortraitFrameTemplate chrome (703x606, native scale)
-- ===========================================================================

local frame = CreateFrame("Frame", "RazagathCompanionsFrame", UIParent);
frame:SetSize(703, 606);
frame:SetPoint("CENTER");
frame:SetFrameStrata("HIGH");
frame:SetMovable(true);
frame:EnableMouse(true);
frame:RegisterForDrag("LeftButton");
frame:SetScript("OnDragStart", function(self) self:StartMoving(); end);
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); end);
frame:Hide();
tinsert(UISpecialFrames, "RazagathCompanionsFrame"); -- Escape closes it

local baseLevel = frame:GetFrameLevel();
local BIG, SMALL = 75, 32; -- native "-2x" crops / 2 (150px, 64px)

-- Retail PortraitFrameTexturedBaseTemplate: tiled UI-Background-Rock inset (2,-21)/(-2,2).
local bgFrame = CreateFrame("Frame", nil, frame);
bgFrame:SetPoint("TOPLEFT", 2, -21);
bgFrame:SetPoint("BOTTOMRIGHT", -2, 2);
bgFrame:SetBackdrop({ bgFile = ADDON_PATH.."UI-Background-Rock", tile = true, tileSize = 256 });

-- Retail NineSlice "PortraitFrameTemplate" offsets: TL(-13,16) TR(4,16) BL(-13,-3) BR(4,-3).
local chrome = CreateFrame("Frame", nil, frame);
chrome:SetAllPoints(frame);
chrome:SetFrameLevel(baseLevel + 20);

local function ChromeTexture(file)
	local t = chrome:CreateTexture(nil, "ARTWORK");
	t:SetTexture(ADDON_PATH..file);
	return t;
end

local cornerTL = ChromeTexture("Frame-CornerTopLeft");
cornerTL:SetSize(BIG, BIG);
cornerTL:SetPoint("TOPLEFT", frame, "TOPLEFT", -13, 16);
local cornerTR = ChromeTexture("Frame-CornerTopRight");
cornerTR:SetSize(BIG, BIG);
cornerTR:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 4, 16);
local cornerBL = ChromeTexture("Frame-CornerBottomLeft");
cornerBL:SetSize(SMALL, SMALL);
cornerBL:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -13, -3);
local cornerBR = ChromeTexture("Frame-CornerBottomRight");
cornerBR:SetSize(SMALL, SMALL);
cornerBR:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -3);

local edgeTop = ChromeTexture("Frame-EdgeTop");
edgeTop:SetPoint("TOPLEFT", cornerTL, "TOPRIGHT");
edgeTop:SetPoint("TOPRIGHT", cornerTR, "TOPLEFT");
edgeTop:SetHeight(BIG);
local edgeBottom = ChromeTexture("Frame-EdgeBottom");
edgeBottom:SetPoint("BOTTOMLEFT", cornerBL, "BOTTOMRIGHT");
edgeBottom:SetPoint("BOTTOMRIGHT", cornerBR, "BOTTOMLEFT");
edgeBottom:SetHeight(SMALL);
local edgeLeft = ChromeTexture("Frame-EdgeLeft");
edgeLeft:SetPoint("TOPLEFT", cornerTL, "BOTTOMLEFT");
edgeLeft:SetPoint("BOTTOMLEFT", cornerBL, "TOPLEFT");
edgeLeft:SetWidth(BIG);
local edgeRight = ChromeTexture("Frame-EdgeRight");
edgeRight:SetPoint("TOPRIGHT", cornerTR, "BOTTOMRIGHT");
edgeRight:SetPoint("BOTTOMRIGHT", cornerBR, "TOPRIGHT");
edgeRight:SetWidth(BIG);

local title = chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal");
title:SetPoint("TOP", frame, "TOP", 0, -9);
title:SetText("Collections");

-- Retail UIPanelCloseButton: 24x24, redbutton-exit atlases.
local closeButton = CreateFrame("Button", nil, frame);
closeButton:SetSize(24, 24);
closeButton:SetPoint("TOPRIGHT", 3, -1);
closeButton:SetFrameLevel(baseLevel + 21);
SetButtonAtlas(closeButton, "Normal", "RedButton-Exit");
SetButtonAtlas(closeButton, "Pushed", "RedButton-Exit-Pressed");
SetButtonAtlas(closeButton, "Disabled", "RedButton-Exit-Disabled");
SetButtonAtlas(closeButton, "Highlight", "RedButton-Highlight", "ADD");
closeButton:SetScript("OnClick", function() frame:Hide(); end);

-- Circular portrait inside the ring built into the TL corner piece. Measured
-- from the texture: hole ~71% of the piece, centred ~51% -> (25,-22), 53px.
-- SetPortraitToTexture is WotLK's own circular-mask API.
local portraitFrame = CreateFrame("Frame", nil, frame);
portraitFrame:SetSize(56, 56);
portraitFrame:SetPoint("CENTER", frame, "TOPLEFT", 25, -22);
portraitFrame:SetFrameLevel(baseLevel + 2);
local portraitIcon = portraitFrame:CreateTexture(nil, "ARTWORK");
portraitIcon:SetAllPoints();
local function SetPortraitIcon(path)
	if ( SetPortraitToTexture ) then
		SetPortraitToTexture(portraitIcon, path);
	else
		portraitIcon:SetTexture(path);
	end
end

-- ===========================================================================
-- Insets (retail InsetFrameTemplate: marble background + 8-piece inner border)
-- ===========================================================================

local function CreateInset(parent)
	local f = CreateFrame("Frame", nil, parent);
	f:SetBackdrop({ bgFile = FILES.."UI-Background-Marble", tile = true, tileSize = 256 });
	local function piece(name)
		local t = f:CreateTexture(nil, "BORDER");
		SetAtlas(t, name);
		return t;
	end
	local tl = piece("UI-Frame-InnerTopLeft");     tl:SetSize(6, 6); tl:SetPoint("TOPLEFT");
	local tr = piece("UI-Frame-InnerTopRight");    tr:SetSize(6, 6); tr:SetPoint("TOPRIGHT");
	local bl = piece("UI-Frame-InnerBotLeftCorner"); bl:SetSize(6, 6); bl:SetPoint("BOTTOMLEFT", 0, -1);
	local br = piece("UI-Frame-InnerBotRight");    br:SetSize(6, 6); br:SetPoint("BOTTOMRIGHT", 0, -1);
	local top = piece("_UI-Frame-InnerTopTile");   top:SetHeight(3);
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("TOPRIGHT", tr, "TOPLEFT");
	local bot = piece("_UI-Frame-InnerBotTile");   bot:SetHeight(3);
	bot:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT"); bot:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT");
	local left = piece("!UI-Frame-InnerLeftTile"); left:SetWidth(3);
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT");
	local right = piece("!UI-Frame-InnerRightTile"); right:SetWidth(3);
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT");
	return f;
end

-- Retail MountJournal anchors, converted to window-relative coordinates.
local leftInset = CreateInset(frame);
leftInset:SetSize(260, 435);
leftInset:SetPoint("TOPLEFT", 4, -60);

local bottomLeftInset = CreateInset(frame);
bottomLeftInset:SetSize(279, 75);
bottomLeftInset:SetPoint("TOPLEFT", 4, -505);

local rightInset = CreateInset(frame);
rightInset:SetSize(413, 520);
rightInset:SetPoint("TOPLEFT", 284, -60);

-- ===========================================================================
-- Total count (retail InsetFrameTemplate3: Common-Input-Border 3-slice box)
-- ===========================================================================

local countFrame = CreateFrame("Frame", nil, frame);
countFrame:SetSize(130, 20);
countFrame:SetPoint("TOPLEFT", 70, -35);
countFrame:SetFrameLevel(baseLevel + 2);
do
	local FILE = FILES.."Common-Input-Border";
	local function slice(point, w, h, l, r, t, b, layer)
		local tex = countFrame:CreateTexture(nil, layer or "BORDER");
		tex:SetTexture(FILE);
		tex:SetTexCoord(l, r, t, b);
		return tex;
	end
	local tl = slice("TOPLEFT", 8, 8, 0, 0.0625, 0, 0.25);      tl:SetSize(8, 8); tl:SetPoint("TOPLEFT");
	local tr = slice("TOPRIGHT", 8, 8, 0.9375, 1, 0, 0.25);     tr:SetSize(8, 8); tr:SetPoint("TOPRIGHT");
	local bl = slice("BOTTOMLEFT", 8, 8, 0, 0.0625, 0.375, 0.625);  bl:SetSize(8, 8); bl:SetPoint("BOTTOMLEFT");
	local br = slice("BOTTOMRIGHT", 8, 8, 0.9375, 1, 0.375, 0.625); br:SetSize(8, 8); br:SetPoint("BOTTOMRIGHT");
	local tm = slice(nil, 0, 0, 0.0625, 0.9375, 0, 0.25);  tm:SetPoint("TOPLEFT", tl, "TOPRIGHT"); tm:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT");
	local bm = slice(nil, 0, 0, 0.0625, 0.9375, 0.375, 0.625); bm:SetPoint("TOPLEFT", bl, "TOPRIGHT"); bm:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT");
	local lm = slice(nil, 0, 0, 0, 0.0625, 0.25, 0.375);   lm:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); lm:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT");
	local rm = slice(nil, 0, 0, 0.9375, 1, 0.25, 0.375);   rm:SetPoint("TOPLEFT", tr, "BOTTOMLEFT"); rm:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT");
	local bg = slice(nil, 0, 0, 0.0625, 0.9375, 0.25, 0.375, "BACKGROUND");
	bg:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT"); bg:SetPoint("BOTTOMRIGHT", br, "TOPLEFT");
end
local countLabel = countFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
countLabel:SetPoint("LEFT", 10, 0);
local countValue = countFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall");
countValue:SetPoint("RIGHT", -10, 0);

-- ===========================================================================
-- Search box (retail SearchBoxTemplate look: 3-slice border, magnifier, clear)
-- ===========================================================================

local searchBox = CreateFrame("EditBox", "RazagathCompanionsSearchBox", leftInset);
searchBox:SetSize(145, 20);
searchBox:SetPoint("TOPLEFT", 15, -9);
searchBox:SetFontObject(GameFontHighlightSmall);
searchBox:SetAutoFocus(false);
searchBox:SetTextInsets(20, 18, 0, 0);
searchBox:SetMaxLetters(40);
do
	local l = searchBox:CreateTexture(nil, "BACKGROUND");
	SetAtlas(l, "common-search-border-left"); l:SetSize(8, 20); l:SetPoint("LEFT", -4, 0);
	local r = searchBox:CreateTexture(nil, "BACKGROUND");
	SetAtlas(r, "common-search-border-right"); r:SetSize(8, 20); r:SetPoint("RIGHT", 4, 0);
	local m = searchBox:CreateTexture(nil, "BACKGROUND");
	SetAtlas(m, "common-search-border-middle");
	m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT");
end
local searchIcon = searchBox:CreateTexture(nil, "OVERLAY");
SetAtlas(searchIcon, "common-search-magnifyingglass"); searchIcon:SetSize(12, 12); searchIcon:SetPoint("LEFT", 3, -1);
local searchHint = searchBox:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall");
searchHint:SetPoint("LEFT", 20, 0);
searchHint:SetText("Search");
searchHint:SetTextColor(0.5, 0.5, 0.5);
local searchClear = CreateFrame("Button", nil, searchBox);
searchClear:SetSize(14, 14);
searchClear:SetPoint("RIGHT", -2, 0);
SetButtonAtlas(searchClear, "Normal", "common-search-clearbutton");
searchClear:GetNormalTexture():SetAlpha(0.7);
searchClear:Hide();
local function UpdateSearchDecor(self)
	local empty = ( self:GetText() == "" );
	SetShownCompat(searchHint, empty and not self:HasFocus());
	SetShownCompat(searchClear, not empty);
end
searchBox:SetScript("OnTextChanged", function(self)
	searchText = strlower(self:GetText() or "");
	UpdateSearchDecor(self);
	RazagathCompanions_RefreshList(true);
end);
searchBox:SetScript("OnEditFocusGained", function(self) UpdateSearchDecor(self); end);
searchBox:SetScript("OnEditFocusLost", function(self) UpdateSearchDecor(self); end);
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); end);
searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus(); end);
searchClear:SetScript("OnClick", function()
	searchBox:SetText("");
	searchBox:ClearFocus();
end);

-- ===========================================================================
-- Filter dropdown (retail WowStyle1FilterDropdownTemplate look)
-- ===========================================================================

local filterButton = CreateFrame("Button", "RazagathCompanionsFilterButton", leftInset);
filterButton:SetSize(90, 18);
filterButton:SetPoint("TOPRIGHT", -5, -10);
local filterBg = filterButton:CreateTexture(nil, "BACKGROUND");
filterBg:SetPoint("TOPLEFT", -4, 4);
filterBg:SetPoint("BOTTOMRIGHT", 4, -4);
SetAtlas(filterBg, "common-dropdown-b-button");
local filterText = filterButton:CreateFontString(nil, "OVERLAY", "GameFontNormal");
filterText:SetPoint("LEFT", 10, 0);
filterText:SetText("Filter");

local filterMenu = CreateFrame("Frame", "RazagathCompanionsFilterMenu", UIParent, "UIDropDownMenuTemplate");
UIDropDownMenu_Initialize(filterMenu, function(self, level)
	local info = {};
	info.text = "Favorites";
	info.checked = favoritesOnly;
	info.keepShownOnClick = 1;
	info.isNotRadio = 1;
	info.func = function()
		favoritesOnly = not favoritesOnly;
		RazagathCompanions_RefreshList(true);
	end;
	UIDropDownMenu_AddButton(info, level);
end, "MENU");

filterButton:SetScript("OnEnter", function() SetAtlas(filterBg, "common-dropdown-b-button-hover"); end);
filterButton:SetScript("OnLeave", function() SetAtlas(filterBg, "common-dropdown-b-button"); end);
filterButton:SetScript("OnMouseDown", function() SetAtlas(filterBg, "common-dropdown-b-button-pressed"); end);
filterButton:SetScript("OnMouseUp", function() SetAtlas(filterBg, "common-dropdown-b-button-hover"); end);
filterButton:SetScript("OnClick", function(self)
	ToggleDropDownMenu(1, nil, filterMenu, "RazagathCompanionsFilterButton", 0, 0);
	PlaySound("igMainMenuOptionCheckBoxOn");
end);

-- ===========================================================================
-- Row context menu (retail: right-click a mount -> "Set Favorite")
-- ===========================================================================

local menuCreatureID = nil;
local rowMenu = CreateFrame("Frame", "RazagathCompanionsRowMenu", UIParent, "UIDropDownMenuTemplate");
UIDropDownMenu_Initialize(rowMenu, function(self, level)
	if ( not menuCreatureID ) then return; end
	local info = {};
	info.notCheckable = 1;
	if ( RazagathCompanionsDB.favorites[menuCreatureID] ) then
		info.text = "Remove Favorite";
	else
		info.text = "Set Favorite";
	end
	local id = menuCreatureID;
	info.func = function()
		if ( RazagathCompanionsDB.favorites[id] ) then
			RazagathCompanionsDB.favorites[id] = nil;
		else
			RazagathCompanionsDB.favorites[id] = true;
		end
		RazagathCompanions_RefreshList();
	end;
	UIDropDownMenu_AddButton(info, level);
	local cancel = {};
	cancel.text = CANCEL or "Cancel";
	cancel.notCheckable = 1;
	UIDropDownMenu_AddButton(cancel, level);
end, "MENU");

local function ShowRowMenu(creatureID)
	menuCreatureID = creatureID;
	ToggleDropDownMenu(1, nil, rowMenu, "cursor", 0, 0);
end

-- ===========================================================================
-- Retail MinimalScrollBar (custom: track, 3-part thumb, arrow steppers)
-- ===========================================================================

local scrollBar = CreateFrame("Frame", nil, frame);
scrollBar:SetFrameLevel(baseLevel + 3);
scrollBar:SetWidth(17);
scrollBar:SetPoint("TOPLEFT", leftInset, "TOPLEFT", 262, -5);
scrollBar:SetPoint("BOTTOMLEFT", leftInset, "TOPLEFT", 262, -433);

local track = CreateFrame("Frame", nil, scrollBar);
track:SetWidth(8);
track:SetPoint("TOP", 0, -19);
track:SetPoint("BOTTOM", 0, 19);
track:EnableMouse(true);
do
	local b = track:CreateTexture(nil, "ARTWORK");
	SetAtlas(b, "minimal-scrollbar-track-top"); b:SetSize(8, 8); b:SetPoint("TOPLEFT");
	local e = track:CreateTexture(nil, "ARTWORK");
	SetAtlas(e, "minimal-scrollbar-track-bottom"); e:SetSize(8, 8); e:SetPoint("BOTTOMLEFT");
	local m = track:CreateTexture(nil, "ARTWORK");
	SetAtlas(m, "!minimal-scrollbar-track-middle");
	m:SetPoint("TOPLEFT", b, "BOTTOMLEFT"); m:SetPoint("BOTTOMRIGHT", e, "TOPRIGHT");
end

local thumb = CreateFrame("Button", nil, track);
thumb:SetWidth(8);
thumb:SetHitRectInsets(-4, -4, -4, -4);
local thumbBegin = thumb:CreateTexture(nil, "ARTWORK");
thumbBegin:SetSize(8, 8); thumbBegin:SetPoint("TOPLEFT");
local thumbEnd = thumb:CreateTexture(nil, "ARTWORK");
thumbEnd:SetSize(8, 8); thumbEnd:SetPoint("BOTTOMLEFT");
local thumbMid = thumb:CreateTexture(nil, "ARTWORK");
thumbMid:SetPoint("TOPLEFT", thumbBegin, "BOTTOMLEFT"); thumbMid:SetPoint("BOTTOMRIGHT", thumbEnd, "TOPRIGHT");
local function SetThumbState(suffix)
	SetAtlas(thumbBegin, "minimal-scrollbar-small-thumb-top"..suffix);
	SetAtlas(thumbMid, "minimal-scrollbar-small-thumb-middle"..suffix);
	SetAtlas(thumbEnd, "minimal-scrollbar-small-thumb-bottom"..suffix);
end
SetThumbState("");

local function MakeStepper(point, atlasBase, direction)
	local b = CreateFrame("Button", nil, scrollBar);
	b:SetSize(17, 11);
	b:SetPoint(point);
	b.atlasBase = atlasBase;
	b.tex = b:CreateTexture(nil, "BACKGROUND");
	b.tex:SetAllPoints();
	SetAtlas(b.tex, atlasBase);
	b.direction = direction;
	b:SetScript("OnEnter", function(self) if ( self:IsEnabled() == 1 ) then SetAtlas(self.tex, self.atlasBase.."-over"); end end);
	b:SetScript("OnLeave", function(self) SetAtlas(self.tex, self.atlasBase); self.holdTime = nil; end);
	b:SetScript("OnMouseDown", function(self)
		if ( self:IsEnabled() == 1 ) then
			SetAtlas(self.tex, self.atlasBase.."-down");
			RazagathCompanions_SetOffset(scrollOffset + self.direction);
			self.holdTime = 0;
		end
	end);
	b:SetScript("OnMouseUp", function(self)
		SetAtlas(self.tex, self.atlasBase.."-over");
		self.holdTime = nil;
	end);
	b:SetScript("OnUpdate", function(self, elapsed)
		if ( self.holdTime ) then
			if ( not IsMouseButtonDown("LeftButton") ) then self.holdTime = nil; return; end
			self.holdTime = self.holdTime + elapsed;
			if ( self.holdTime > 0.4 ) then
				self.holdTime = 0.32;
				RazagathCompanions_SetOffset(scrollOffset + self.direction);
			end
		end
	end);
	return b;
end
local stepBack = MakeStepper("TOP", "minimal-scrollbar-arrow-top", -1);
local stepForward = MakeStepper("BOTTOM", "minimal-scrollbar-arrow-bottom", 1);

local thumbDragging, thumbDragStartY, thumbDragStartFrac = false, 0, 0;
local function GetCursorY()
	local _, y = GetCursorPosition();
	return y / thumb:GetEffectiveScale();
end
local function ThumbRange()
	return math.max(1, track:GetHeight() - thumb:GetHeight());
end

thumb:SetScript("OnEnter", function() if ( not thumbDragging ) then SetThumbState("-over"); end end);
thumb:SetScript("OnLeave", function() if ( not thumbDragging ) then SetThumbState(""); end end);
thumb:SetScript("OnMouseDown", function()
	local maxOffset = math.max(0, #filteredList - FULL_ROWS);
	if ( maxOffset == 0 ) then return; end
	thumbDragging = true;
	thumbDragStartY = GetCursorY();
	thumbDragStartFrac = scrollOffset / maxOffset;
	SetThumbState("-down");
end);
thumb:SetScript("OnMouseUp", function(self)
	thumbDragging = false;
	SetThumbState(MouseIsOver(self) and "-over" or "");
end);
thumb:SetScript("OnUpdate", function(self)
	if ( thumbDragging ) then
		if ( not IsMouseButtonDown("LeftButton") ) then
			thumbDragging = false;
			SetThumbState("");
			return;
		end
		local maxOffset = math.max(0, #filteredList - FULL_ROWS);
		local frac = Clamp(thumbDragStartFrac + (thumbDragStartY - GetCursorY()) / ThumbRange(), 0, 1);
		RazagathCompanions_SetOffset(math.floor(frac * maxOffset + 0.5));
	end
end);
track:SetScript("OnMouseDown", function(self)
	local maxOffset = math.max(0, #filteredList - FULL_ROWS);
	if ( maxOffset == 0 ) then return; end
	if ( GetCursorY() > (thumb:GetTop() + thumb:GetBottom()) / 2 ) then
		RazagathCompanions_SetOffset(scrollOffset - FULL_ROWS);
	else
		RazagathCompanions_SetOffset(scrollOffset + FULL_ROWS);
	end
end);

local function UpdateScrollBar()
	local total = #filteredList;
	local maxOffset = math.max(0, total - FULL_ROWS);
	local trackH = math.max(1, track:GetHeight());
	if ( maxOffset == 0 ) then
		thumb:Hide();
		stepBack:Disable(); stepForward:Disable();
		stepBack:SetAlpha(0.5); stepForward:SetAlpha(0.5);
		return;
	end
	stepBack:SetAlpha(1); stepForward:SetAlpha(1);
	SetShownCompat(thumb, true);
	local visibleFloat = 396 / ROW_H;
	local h = math.max(23, trackH * visibleFloat / total);
	if ( h > trackH ) then h = trackH; end
	thumb:SetHeight(h);
	thumb:ClearAllPoints();
	thumb:SetPoint("TOP", track, "TOP", 0, -((trackH - h) * scrollOffset / maxOffset));
	if ( scrollOffset <= 0 ) then stepBack:Disable(); else stepBack:Enable(); end
	if ( scrollOffset >= maxOffset ) then stepForward:Disable(); else stepForward:Enable(); end
end

-- ===========================================================================
-- Scrollable list: ScrollFrame used purely as a clip region (9th row is cut
-- off like retail), rows are a fixed pool relabelled on scroll.
-- ===========================================================================

local scrollFrame = CreateFrame("ScrollFrame", nil, leftInset);
scrollFrame:SetSize(255, 396);
scrollFrame:SetPoint("TOPLEFT", 3, -36);
local listChild = CreateFrame("Frame", nil, scrollFrame);
listChild:SetSize(255, NUM_ROWS * ROW_H);
scrollFrame:SetScrollChild(listChild);
scrollFrame:EnableMouseWheel(true);
scrollFrame:SetScript("OnMouseWheel", function(self, delta)
	RazagathCompanions_SetOffset(scrollOffset - delta * 2);
end);

local rowPool = {};
for i = 1, NUM_ROWS do
	local row = CreateFrame("Button", "RazagathCompanionsRow"..i, listChild);
	row:SetSize(ROW_W, ROW_H);
	row:SetPoint("TOPLEFT", 44, -(i - 1) * ROW_H);
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp");

	-- Retail MountListButtonTemplate layers.
	local bg = row:CreateTexture(nil, "BACKGROUND");
	SetAtlas(bg, "PetList-ButtonBackground", true);
	bg:SetPoint("TOPLEFT");

	local highlight = row:CreateTexture(nil, "HIGHLIGHT");
	SetAtlas(highlight, "PetList-ButtonHighlight", true);
	highlight:SetPoint("TOPLEFT");
	highlight:SetBlendMode("ADD");

	local selected = row:CreateTexture(nil, "OVERLAY");
	SetAtlas(selected, "PetList-ButtonSelect", true);
	selected:SetPoint("TOPLEFT");
	selected:Hide();
	row.selectedTex = selected;

	-- Icon sits 42px LEFT of the plate (retail: icon x=-42, list padded 44).
	local icon = row:CreateTexture(nil, "BORDER");
	icon:SetSize(38, 38);
	icon:SetPoint("LEFT", -42, 0);
	row.icon = icon;

	local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal");
	name:SetSize(147, 38);
	name:SetPoint("LEFT", icon, "RIGHT", 10, 1);
	name:SetJustifyH("LEFT");
	name:SetJustifyV("MIDDLE");
	row.name = name;

	local fav = row:CreateTexture(nil, "OVERLAY");
	SetAtlas(fav, "PetJournal-FavoritesIcon", true);
	fav:SetPoint("TOPLEFT", icon, "TOPLEFT", -8, 8);
	row.favorite = fav;

	-- Retail DragButton: clicking the icon itself uses (summons/dismisses) the mount.
	local drag = CreateFrame("Button", nil, row);
	drag:SetSize(40, 40);
	drag:SetPoint("CENTER", icon, "CENTER");
	drag:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	drag:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	local active = drag:CreateTexture(nil, "OVERLAY");
	active:SetAllPoints();
	active:SetTexture("Interface\\Buttons\\CheckButtonHilight");
	active:SetBlendMode("ADD");
	active:Hide();
	row.activeTex = active;
	drag:SetScript("OnClick", function(self, button)
		if ( not row.creatureID ) then return; end
		if ( button == "RightButton" ) then
			ShowRowMenu(row.creatureID);
		else
			RazagathCompanions_SelectCreature(row.creatureID);
			RazagathCompanions_ToggleSummon(row.creatureID);
		end
	end);
	drag:SetScript("OnEnter", function(self)
		if ( row.spellID ) then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT");
			GameTooltip:SetHyperlink("spell:"..row.spellID);
			GameTooltip:Show();
		end
	end);
	drag:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	-- Drag the icon (or the row) to an action bar, like retail's C_MountJournal.Pickup.
	local function pickup()
		if ( not row.creatureID ) then return; end
		local idx = RazagathCompanions_FindIndex(currentMode, row.creatureID);
		if ( idx ) then PickupCompanion(currentMode, idx); end
	end
	drag:RegisterForDrag("LeftButton");
	drag:SetScript("OnDragStart", pickup);
	row:RegisterForDrag("LeftButton");
	row:SetScript("OnDragStart", pickup);
	drag:EnableMouseWheel(true);
	drag:SetScript("OnMouseWheel", function(self, delta) RazagathCompanions_SetOffset(scrollOffset - delta * 2); end);

	row:SetScript("OnClick", function(self, button)
		if ( not self.creatureID ) then return; end
		if ( button == "RightButton" ) then
			ShowRowMenu(self.creatureID);
		else
			RazagathCompanions_SelectCreature(self.creatureID);
		end
	end);
	row:EnableMouseWheel(true);
	row:SetScript("OnMouseWheel", function(self, delta) RazagathCompanions_SetOffset(scrollOffset - delta * 2); end);

	rowPool[i] = row;
end

-- ===========================================================================
-- Mount equipment inset (placeholder, per user request: inert but present)
-- ===========================================================================

local equipBg = bottomLeftInset:CreateTexture(nil, "BORDER");
SetAtlas(equipBg, "mountequipment-background");
equipBg:SetSize(273, 70);
equipBg:SetPoint("TOPLEFT", 3, -3);
local equipOverlay = bottomLeftInset:CreateTexture(nil, "BORDER");
equipOverlay:SetTexture(0, 0, 0, 0.1);
equipOverlay:SetAllPoints(equipBg);
local equipShadow = bottomLeftInset:CreateTexture(nil, "ARTWORK");
SetAtlas(equipShadow, "mountequipment-insetshadow");
equipShadow:SetSize(273, 70);
equipShadow:SetPoint("TOPLEFT", equipBg);

local slotButton = CreateFrame("Button", nil, bottomLeftInset);
slotButton:SetSize(49, 49);
slotButton:SetPoint("LEFT", 23, 0);
local slotBg = slotButton:CreateTexture(nil, "BACKGROUND");
SetAtlas(slotBg, "mountequipment-slot-background"); slotBg:SetSize(69, 69); slotBg:SetPoint("CENTER");
local slotCorners = slotButton:CreateTexture(nil, "ARTWORK");
SetAtlas(slotCorners, "mountequipment-slot-corners"); slotCorners:SetSize(67, 67); slotCorners:SetPoint("CENTER");
slotButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
slotButton:GetHighlightTexture():SetAlpha(0.5);
local slotLabel = bottomLeftInset:CreateFontString(nil, "ARTWORK", "GameFontNormal");
slotLabel:SetPoint("LEFT", slotButton, "RIGHT", 12, 0);
slotLabel:SetPoint("RIGHT", -40, 0);
slotLabel:SetHeight(60); -- explicit height lets the text wrap instead of truncating with "..."
slotLabel:SetJustifyH("LEFT");
slotLabel:SetJustifyV("MIDDLE");
slotLabel:SetText("Enhance your mounts with Mount Equipment");
slotButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText("Mount Equipment");
	GameTooltip:AddLine("Not available yet - reserved for future use.", 1, 1, 1, true);
	GameTooltip:Show();
end);
slotButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);

-- ===========================================================================
-- Right panel: MountDisplay (BG + shadow overlay + info + 3D model + controls)
-- ===========================================================================

local display = CreateFrame("Frame", nil, frame);
display:SetFrameLevel(baseLevel + 3);
display:SetPoint("TOPLEFT", rightInset, "TOPLEFT", 3, -3);
display:SetPoint("BOTTOMRIGHT", rightInset, "BOTTOMRIGHT", -3, 3);
local displayBg = display:CreateTexture(nil, "BACKGROUND");
displayBg:SetAllPoints();
displayBg:SetTexture(FILES.."MountJournal-BG");
displayBg:SetTexCoord(0, 0.78515625, 0, 1);

-- Retail ShadowOverlayTemplate (edges/corners as in the XML; 8-arg texcoords
-- reproduce the retail rotated corner mappings).
local shadow = CreateFrame("Frame", nil, display);
shadow:SetAllPoints();
do
	local function corner(point, ...)
		local t = shadow:CreateTexture(nil, "OVERLAY");
		t:SetTexture(FILES.."ShadowOverlay-Corner");
		t:SetSize(64, 64);
		t:SetPoint(point);
		if ( select("#", ...) > 0 ) then t:SetTexCoord(...); end
		return t;
	end
	local tl = corner("TOPLEFT");
	local tr = corner("TOPRIGHT", 0, 1, 1, 1, 0, 0, 1, 0);
	local bl = corner("BOTTOMLEFT", 1, 0, 0, 0, 1, 1, 0, 1);
	local br = corner("BOTTOMRIGHT", 1, 1, 1, 0, 0, 1, 0, 0);
	local top = shadow:CreateTexture(nil, "OVERLAY");
	top:SetTexture(FILES.."ShadowOverlay-Top"); top:SetHeight(64);
	top:SetPoint("TOPLEFT", tl, "TOPRIGHT"); top:SetPoint("TOPRIGHT", tr, "TOPLEFT");
	local bottom = shadow:CreateTexture(nil, "OVERLAY");
	bottom:SetTexture(FILES.."ShadowOverlay-Bottom"); bottom:SetHeight(64);
	bottom:SetPoint("BOTTOMLEFT", bl, "BOTTOMRIGHT"); bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT");
	local left = shadow:CreateTexture(nil, "OVERLAY");
	left:SetTexture(FILES.."ShadowOverlay-Left"); left:SetWidth(64);
	left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT"); left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT");
	local right = shadow:CreateTexture(nil, "OVERLAY");
	right:SetTexture(FILES.."ShadowOverlay-Right"); right:SetWidth(64);
	right:SetPoint("TOPRIGHT", tr, "BOTTOMRIGHT"); right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT");
end

-- 3D model (WotLK PlayerModel + SetCreature - the stock companion preview).
local modelFrame = CreateFrame("PlayerModel", "RazagathCompanionsModel", display);
modelFrame:SetAllPoints();
Model_OnLoad(modelFrame);
local DEFAULT_CAM = 1.0;
local camScale = DEFAULT_CAM;
local rotating = 0;
local function ApplyCamScale()
	if ( modelFrame.SetCamDistanceScale ) then modelFrame:SetCamDistanceScale(camScale); end
end

-- Info header (retail InfoButton): icon, large name, description lines.
local info = CreateFrame("Frame", nil, display);
info:SetFrameLevel(display:GetFrameLevel() + 2);
info:SetSize(ROW_W, ROW_H);
info:SetPoint("TOPLEFT", 6, -6);
local infoIcon = info:CreateTexture(nil, "BORDER");
infoIcon:SetSize(38, 38);
infoIcon:SetPoint("LEFT", 20, -20);
local infoName = info:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
infoName:SetSize(270, 35);
infoName:SetPoint("LEFT", infoIcon, "RIGHT", 10, 0);
infoName:SetJustifyH("LEFT");
infoName:SetJustifyV("MIDDLE");
local infoSource = info:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
infoSource:SetWidth(345);
infoSource:SetPoint("TOPLEFT", infoIcon, "BOTTOMLEFT", 0, -6);
infoSource:SetJustifyH("LEFT");
infoSource:SetJustifyV("TOP");

-- Retail ModelSceneControlFrame: zoom in/out, rotate left/right, reset.
local controls = CreateFrame("Frame", nil, display);
controls:SetFrameLevel(display:GetFrameLevel() + 10);
controls:SetSize(136, 32);
controls:SetPoint("BOTTOM", 0, 10);
controls:SetAlpha(0.5);
controls:EnableMouse(true);
controls:SetScript("OnEnter", function(self) self:SetAlpha(1); end);
controls:SetScript("OnLeave", function(self) self:SetAlpha(0.5); end);

local function MakeControlButton(iconAtlas, index, onDown, onUp)
	local b = CreateFrame("Button", nil, controls);
	b:SetSize(32, 32);
	b:SetHitRectInsets(4, 4, 4, 4);
	b:SetPoint("LEFT", controls, "LEFT", (index - 1) * 26, 0);
	SetButtonAtlas(b, "Normal", "common-button-square-gray-up");
	local pushed = SetButtonAtlas(b, "Pushed", "common-button-square-gray-down");
	pushed:ClearAllPoints();
	pushed:SetPoint("TOPLEFT", 1, -1);
	pushed:SetPoint("BOTTOMRIGHT", 1, -1);
	local ic = b:CreateTexture(nil, "OVERLAY");
	SetAtlas(ic, iconAtlas);
	ic:SetSize(16, 16);
	ic:SetPoint("CENTER");
	b.icon = ic;
	local hl = b:CreateTexture(nil, "HIGHLIGHT");
	SetAtlas(hl, iconAtlas);
	hl:SetAllPoints(ic);
	hl:SetBlendMode("ADD");
	hl:SetAlpha(0.4);
	b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("CENTER", 1, -1); if ( onDown ) then onDown(); end end);
	b:SetScript("OnMouseUp", function(self) self.icon:SetPoint("CENTER", 0, 0); if ( onUp ) then onUp(); end end);
	return b;
end
local ROT_SPEED = 2;
MakeControlButton("common-icon-zoomin", 1, function() camScale = Clamp(camScale * 0.85, 0.3, 4); ApplyCamScale(); end);
MakeControlButton("common-icon-zoomout", 2, function() camScale = Clamp(camScale / 0.85, 0.3, 4); ApplyCamScale(); end);
MakeControlButton("common-icon-rotateleft", 3, function() rotating = -1; end, function() rotating = 0; end);
MakeControlButton("common-icon-rotateright", 4, function() rotating = 1; end, function() rotating = 0; end);
MakeControlButton("common-icon-undo", 5, function()
	camScale = DEFAULT_CAM; ApplyCamScale();
	modelFrame.rotation = 0.61; modelFrame:SetRotation(modelFrame.rotation);
end);

-- Drag the model itself to rotate it.
local modelDragging, modelDragX = false, 0;
modelFrame:EnableMouse(true);
modelFrame:SetScript("OnMouseDown", function(self)
	modelDragging = true;
	modelDragX = GetCursorPosition();
end);
modelFrame:SetScript("OnMouseUp", function() modelDragging = false; end);
modelFrame:SetScript("OnUpdate", function(self, elapsed)
	if ( modelDragging ) then
		if ( not IsMouseButtonDown("LeftButton") ) then
			modelDragging = false;
		else
			local x = GetCursorPosition();
			self.rotation = (self.rotation or 0) + (x - modelDragX) * 0.012;
			modelDragX = x;
			self:SetRotation(self.rotation);
		end
	end
	if ( rotating ~= 0 ) then
		self.rotation = (self.rotation or 0) + rotating * ROT_SPEED * elapsed;
		self:SetRotation(self.rotation);
	end
end);

-- ===========================================================================
-- Retail "MagicButtonTemplate" (3-piece red button) used for Mount / Summon
-- ===========================================================================

local function CreateMagicButton(parent, w, h, text)
	local b = CreateFrame("Button", nil, parent);
	b:SetSize(w, h);
	local left = b:CreateTexture(nil, "BACKGROUND");
	left:SetSize(64, h); left:SetPoint("TOPLEFT"); left:SetPoint("BOTTOMLEFT");
	local right = b:CreateTexture(nil, "BACKGROUND");
	right:SetSize(32, h); right:SetPoint("TOPRIGHT"); right:SetPoint("BOTTOMRIGHT");
	local mid = b:CreateTexture(nil, "BACKGROUND");
	mid:SetPoint("TOPLEFT", left, "TOPRIGHT"); mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT");
	b.parts = { left, mid, right };
	local function setState(state)
		left:SetTexture(FILES.."goldbutton-"..state.."-left");
		mid:SetTexture(FILES.."goldbutton-"..state.."-middle");
		right:SetTexture(FILES.."goldbutton-"..state.."-right");
	end
	b.setState = setState;
	setState("up");
	b:SetNormalFontObject(GameFontNormal);
	b:SetHighlightFontObject(GameFontHighlight);
	b:SetDisabledFontObject(GameFontDisable);
	b:SetText(text);
	b:GetFontString():SetPoint("CENTER", 0, 1);
	b:SetHighlightTexture(FILES.."UI-Panel-Button-Highlight", "ADD");
	b:GetHighlightTexture():SetPoint("TOPLEFT", 12, 6);
	b:GetHighlightTexture():SetPoint("BOTTOMRIGHT", -12, 0);
	b:SetScript("OnMouseDown", function(self) if ( self:IsEnabled() == 1 ) then setState("down"); end end);
	b:SetScript("OnMouseUp", function(self) if ( self:IsEnabled() == 1 ) then setState("up"); end end);
	b:SetScript("OnShow", function(self) setState(self:IsEnabled() == 1 and "up" or "disabled"); end);
	return b;
end

local function SetMagicEnabled(b, enabled)
	if ( enabled ) then b:Enable(); b.setState("up"); else b:Disable(); b.setState("disabled"); end
end

local mountButton = CreateMagicButton(frame, 140, 22, "Mount");
mountButton:SetPoint("BOTTOMLEFT", 6, 4);
mountButton:SetFrameLevel(baseLevel + 4);
SetMagicEnabled(mountButton, false);

-- ===========================================================================
-- Summon Random Favorite (retail UIPanelSpellButtonFrame: icon + label)
-- ===========================================================================

local randomFrame = CreateFrame("Button", nil, frame);
randomFrame:SetSize(206, 33);
randomFrame:SetPoint("TOPRIGHT", -8, -25);
randomFrame:SetFrameLevel(baseLevel + 4);
local randomIcon = randomFrame:CreateTexture(nil, "ARTWORK");
randomIcon:SetSize(30, 30);
randomIcon:SetPoint("RIGHT", -1, 0);
randomIcon:SetTexture("Interface\\Icons\\Ability_Mount_RidingHorse");
local randomBorder = randomFrame:CreateTexture(nil, "OVERLAY");
SetAtlas(randomBorder, "UI-HUD-ActionBar-IconFrame");
randomBorder:SetSize(40, 39);
randomBorder:SetPoint("CENTER", randomIcon, "CENTER");
local randomText = randomFrame:CreateFontString(nil, "ARTWORK", "GameFontNormal");
randomText:SetWidth(165);
randomText:SetPoint("RIGHT", randomIcon, "LEFT", -8, 0);
randomText:SetJustifyH("RIGHT");
randomFrame:SetHighlightTexture(ADDON_PATH.."Atlas\\ui-hud-actionbar-iconframe-mouseover", "ADD");
local rh = randomFrame:GetHighlightTexture();
rh:ClearAllPoints();
rh:SetAllPoints(randomBorder);
do
	local a = AtlasInfo("UI-HUD-ActionBar-IconFrame-Mouseover");
	if ( a ) then rh:SetTexCoord(0, a[4], 0, a[5]); end
end
randomFrame:SetScript("OnClick", function()
	local favIndexes = {};
	for i = 1, GetNumCompanions(currentMode) do
		local creatureID = GetCompanionInfo(currentMode, i);
		if ( RazagathCompanionsDB.favorites[creatureID] ) then
			tinsert(favIndexes, i);
		end
	end
	if ( #favIndexes > 0 ) then
		CallCompanion(currentMode, favIndexes[math.random(#favIndexes)]);
		PlaySound("igMainMenuOptionCheckBoxOff");
	else
		UIErrorsFrame:AddMessage("You have no favorites to summon.", 1.0, 0.1, 0.1, 1.0);
	end
end);
randomFrame:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT");
	GameTooltip:SetText("Summon a random favorite");
	GameTooltip:Show();
end);
randomFrame:SetScript("OnLeave", function() GameTooltip:Hide(); end);

-- ===========================================================================
-- Bottom tabs (retail PanelTabButtonTemplate: uiframe-tab-* atlases)
-- ===========================================================================

local function CreateTab(text, anchorTo, anchorPoint, x)
	local b = CreateFrame("Button", nil, frame);
	b:SetHeight(32);
	b:SetFrameLevel(baseLevel + 4);
	if ( anchorTo == frame ) then
		b:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", x, 2);
	else
		b:SetPoint("LEFT", anchorTo, "RIGHT", x, 0);
	end
	local label = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	label:SetPoint("CENTER", 0, 2);
	label:SetText(text);
	b.label = label;
	b:SetWidth(math.max(70, label:GetStringWidth() + 36));

	local function makeSet(prefix, h, layer)
		local l = b:CreateTexture(nil, layer);
		SetAtlas(l, "uiframe-"..prefix.."-left"); l:SetSize(35, h); l:SetPoint("TOPLEFT", prefix == "tab" and -3 or -1, 0);
		local r = b:CreateTexture(nil, layer);
		SetAtlas(r, "uiframe-"..prefix.."-right"); r:SetSize(37, h); r:SetPoint("TOPRIGHT", prefix == "tab" and 7 or 8, 0);
		local m = b:CreateTexture(nil, layer);
		SetAtlas(m, "_uiframe-"..prefix.."-center");
		m:SetPoint("TOPLEFT", l, "TOPRIGHT"); m:SetPoint("BOTTOMRIGHT", r, "BOTTOMLEFT");
		return { l, m, r };
	end
	b.inactive = makeSet("tab", 36, "BACKGROUND");
	b.active = makeSet("activetab", 42, "BACKGROUND");
	local function hl(tex, src)
		tex:SetTexture(src:GetTexture());
		local l, r, t, bo = src:GetTexCoord();
		tex:SetTexCoord(l, r, t, bo);
	end
	local hlLeft = b:CreateTexture(nil, "HIGHLIGHT");
	SetAtlas(hlLeft, "uiframe-tab-left"); hlLeft:SetSize(35, 36); hlLeft:SetPoint("TOPLEFT", -3, 0);
	local hlRight = b:CreateTexture(nil, "HIGHLIGHT");
	SetAtlas(hlRight, "uiframe-tab-right"); hlRight:SetSize(37, 36); hlRight:SetPoint("TOPRIGHT", 7, 0);
	local hlMid = b:CreateTexture(nil, "HIGHLIGHT");
	SetAtlas(hlMid, "_uiframe-tab-center");
	hlMid:SetPoint("TOPLEFT", hlLeft, "TOPRIGHT"); hlMid:SetPoint("BOTTOMRIGHT", hlRight, "BOTTOMLEFT");
	for _, t in ipairs({ hlLeft, hlMid, hlRight }) do t:SetBlendMode("ADD"); t:SetAlpha(0.4); end

	function b:SetTabSelected(selected)
		for _, t in ipairs(self.active) do SetShownCompat(t, selected); end
		for _, t in ipairs(self.inactive) do SetShownCompat(t, not selected); end
		self.label:SetFontObject(selected and GameFontHighlightSmall or GameFontNormalSmall);
		self.label:ClearAllPoints();
		self.label:SetPoint("CENTER", 0, selected and 0 or 2);
	end
	return b;
end

local mountsTab = CreateTab("Mounts", frame, nil, 11);
-- Tab art overhangs 7px right / 3px left of each button, so +4 leaves the
-- slanted edges just touching instead of overlapping.
local petsTab = CreateTab("Pet Journal", mountsTab, nil, 4);

-- ===========================================================================
-- Data: filtering / sorting / selection
-- ===========================================================================

function RazagathCompanions_FindIndex(mode, creatureID)
	for i = 1, GetNumCompanions(mode) do
		if ( GetCompanionInfo(mode, i) == creatureID ) then
			return i;
		end
	end
	return nil;
end

local function BuildFilteredList()
	for i = #filteredList, 1, -1 do filteredList[i] = nil; end
	for i = 1, GetNumCompanions(currentMode) do
		local creatureID, creatureName, spellID, icon, active = GetCompanionInfo(currentMode, i);
		local isFav = RazagathCompanionsDB.favorites[creatureID] and true or false;
		if ( favoritesOnly and not isFav ) then
			-- excluded
		elseif ( searchText ~= "" and not strfind(strlower(creatureName or ""), searchText, 1, true) ) then
			-- excluded
		else
			tinsert(filteredList, {index = i, creatureID = creatureID, name = creatureName, icon = icon, spellID = spellID, active = active, favorite = isFav});
		end
	end
	table.sort(filteredList, function(a, b)
		if ( a.favorite ~= b.favorite ) then return a.favorite; end
		return (a.name or "") < (b.name or "");
	end);
end

function RazagathCompanions_UpdateList()
	local numItems = #filteredList;
	local maxOffset = math.max(0, numItems - FULL_ROWS);
	scrollOffset = Clamp(scrollOffset, 0, maxOffset);
	for i = 1, NUM_ROWS do
		local row = rowPool[i];
		local entry = filteredList[i + scrollOffset];
		if ( entry ) then
			row.creatureID = entry.creatureID;
			row.spellID = entry.spellID;
			row.icon:SetTexture(entry.icon);
			row.name:SetText(entry.name);
			SetShownCompat(row.favorite, entry.favorite);
			SetShownCompat(row.activeTex, entry.active);
			SetShownCompat(row.selectedTex, entry.creatureID == selectedCreatureID);
			row:Show();
		else
			row.creatureID = nil;
			row.spellID = nil;
			row:Hide();
		end
	end
	UpdateScrollBar();
end

function RazagathCompanions_SetOffset(offset)
	local maxOffset = math.max(0, #filteredList - FULL_ROWS);
	offset = Clamp(offset, 0, maxOffset);
	if ( offset ~= scrollOffset ) then
		scrollOffset = offset;
		RazagathCompanions_UpdateList();
	end
end

function RazagathCompanions_RefreshList(resetScroll)
	if ( resetScroll ) then scrollOffset = 0; end
	BuildFilteredList();
	RazagathCompanions_UpdateList();
end

-- Spell description via a hidden tooltip (WotLK has no spell-description API).
local scanTooltip = CreateFrame("GameTooltip", "RazagathCompanionsScanTooltip", UIParent, "GameTooltipTemplate");
scanTooltip:SetOwner(UIParent, "ANCHOR_NONE");
local function GetSpellDescription(spellID)
	if ( not spellID ) then return ""; end
	scanTooltip:ClearLines();
	scanTooltip:SetOwner(UIParent, "ANCHOR_NONE");
	scanTooltip:SetHyperlink("spell:"..spellID);
	local lines = {};
	for i = 2, scanTooltip:NumLines() do
		local fs = _G["RazagathCompanionsScanTooltipTextLeft"..i];
		local text = fs and fs:GetText();
		if ( text and text ~= "" ) then tinsert(lines, text); end
	end
	return table.concat(lines, "\n");
end

local function UpdateMountButton(active, hasSelection)
	if ( currentMode == MODE_MOUNT ) then
		mountButton:SetText(active and "Dismount" or "Mount");
	else
		mountButton:SetText(active and "Dismiss" or "Summon");
	end
	SetMagicEnabled(mountButton, hasSelection);
end

function RazagathCompanions_SelectCreature(creatureID)
	selectedCreatureID = creatureID;
	local idx = RazagathCompanions_FindIndex(currentMode, creatureID);
	if ( not idx ) then return; end
	local id, creatureName, spellID, icon, active = GetCompanionInfo(currentMode, idx);
	modelFrame:SetCreature(id);
	ApplyCamScale();
	infoIcon:SetTexture(icon);
	infoName:SetText(creatureName);
	infoSource:SetText(GetSpellDescription(spellID));
	UpdateMountButton(active, true);
	RazagathCompanions_UpdateList();
end

function RazagathCompanions_ToggleSummon(creatureID)
	local idx = RazagathCompanions_FindIndex(currentMode, creatureID);
	if ( not idx ) then return; end
	local _, _, _, _, active = GetCompanionInfo(currentMode, idx);
	if ( active ) then
		DismissCompanion(currentMode);
		PlaySound("igMainMenuOptionCheckBoxOn");
	else
		CallCompanion(currentMode, idx);
		PlaySound("igMainMenuOptionCheckBoxOff");
	end
end

mountButton:SetScript("OnClick", function()
	if ( selectedCreatureID ) then RazagathCompanions_ToggleSummon(selectedCreatureID); end
end);

local function SetMode(mode)
	currentMode = mode;
	mountsTab:SetTabSelected(mode == MODE_MOUNT);
	petsTab:SetTabSelected(mode == MODE_PET);
	selectedCreatureID = nil;
	infoIcon:SetTexture(nil);
	infoName:SetText("");
	infoSource:SetText("");
	UpdateMountButton(false, false);
	SetShownCompat(bottomLeftInset, mode == MODE_MOUNT); -- mount equipment is a mount-only concept
	SetShownCompat(slotButton, mode == MODE_MOUNT);
	SetShownCompat(slotLabel, mode == MODE_MOUNT);
	countLabel:SetText(mode == MODE_MOUNT and "Total Mounts:" or "Total Pets:");
	countValue:SetText(GetNumCompanions(mode));
	randomText:SetText(mode == MODE_MOUNT and "Summon Random Favorite Mount" or "Summon Random Favorite Pet");
	SetPortraitIcon(mode == MODE_MOUNT and FILES.."MountJournalPortrait" or FILES.."PetJournalPortrait");
	RazagathCompanions_RefreshList(true);
	if ( filteredList[1] ) then
		RazagathCompanions_SelectCreature(filteredList[1].creatureID);
	end
end

mountsTab:SetScript("OnClick", function() SetMode(MODE_MOUNT); PlaySound("igCharacterInfoTab"); end);
petsTab:SetScript("OnClick", function() SetMode(MODE_PET); PlaySound("igCharacterInfoTab"); end);

-- ===========================================================================
-- Events + global toggle
-- ===========================================================================

frame:RegisterEvent("COMPANION_LEARNED");
frame:RegisterEvent("COMPANION_UPDATE");
frame:SetScript("OnEvent", function(self, event)
	if ( self:IsShown() ) then
		countValue:SetText(GetNumCompanions(currentMode));
		RazagathCompanions_RefreshList();
		-- COMPANION_UPDATE fires on every summon/dismiss; re-run selection so
		-- the Mount/Dismount button and row highlights track the active state.
		if ( selectedCreatureID ) then
			RazagathCompanions_SelectCreature(selectedCreatureID);
		end
	end
end);

frame:SetScript("OnShow", function()
	SetMode(currentMode);
end);

function RazagathCompanions_Toggle()
	if ( frame:IsShown() ) then
		frame:Hide();
	else
		frame:Show();
	end
end

-- ===========================================================================
-- Access: key binding (Key Bindings > AddOns > Razagath Companions), slash
-- commands, and a one-time default of "N" (retail's Mount Journal key) when
-- that key is unbound. No floating button - and NOT in the Character pane.
-- ===========================================================================

-- Retail's "Collections" micro-menu button (real art), docked in the bottom-right
-- corner like retail's micro menu. Shift-drag to move it; the position is saved.
local microButton = CreateFrame("Button", "RazagathCompanionsMicroButton", UIParent);
microButton:SetSize(32, 41);
microButton:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -70, 8);
microButton:SetFrameStrata("MEDIUM");
microButton:SetMovable(true);
microButton:SetClampedToScreen(true);
SetButtonAtlas(microButton, "Normal", "ui-hud-micromenu-collections-up-2x");
SetButtonAtlas(microButton, "Pushed", "ui-hud-micromenu-collections-down-2x");
SetButtonAtlas(microButton, "Highlight", "ui-hud-micromenu-collections-mouseover-2x", "ADD");
-- Retail draws a separate background plate (up/down) beneath the icon art.
local microBg = microButton:CreateTexture(nil, "BACKGROUND");
microBg:SetAllPoints();
SetAtlas(microBg, "ui-hud-micromenu-buttonbg-up-2x");
microButton:HookScript("OnMouseDown", function() SetAtlas(microBg, "ui-hud-micromenu-buttonbg-down-2x"); end);
microButton:HookScript("OnMouseUp", function() SetAtlas(microBg, "ui-hud-micromenu-buttonbg-up-2x"); end);
microButton:RegisterForDrag("LeftButton");
microButton:SetScript("OnDragStart", function(self) if ( IsShiftKeyDown() ) then self:StartMoving(); end end);
microButton:SetScript("OnDragStop", function(self)
	self:StopMovingOrSizing();
	local x, y = self:GetLeft(), self:GetBottom();
	if ( x and y ) then RazagathCompanionsDB.microPos = { x, y }; end
end);
microButton:SetScript("OnClick", function() RazagathCompanions_Toggle(); end);
microButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT");
	GameTooltip:SetText("Mounts & Pets");
	GameTooltip:AddLine("Click to open. Shift-drag to move.", 0.8, 0.8, 0.8);
	GameTooltip:Show();
end);
microButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);

BINDING_HEADER_RAZAGATHCOMPANIONS = "Razagath Companions";
BINDING_NAME_RAZAGATHCOMPANIONS_TOGGLE = "Toggle Mounts & Pets";

SLASH_RAZAGATHCOMPANIONS1 = "/companions";
SLASH_RAZAGATHCOMPANIONS2 = "/mounts";
SLASH_RAZAGATHCOMPANIONS3 = "/pets";
SlashCmdList["RAZAGATHCOMPANIONS"] = RazagathCompanions_Toggle;

local setupFrame = CreateFrame("Frame");
setupFrame:RegisterEvent("PLAYER_LOGIN");
setupFrame:SetScript("OnEvent", function()
	local pos = RazagathCompanionsDB.microPos;
	if ( pos ) then
		microButton:ClearAllPoints();
		microButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2]);
	end
	if ( not RazagathCompanionsDB.defaultKeySet ) then
		RazagathCompanionsDB.defaultKeySet = true;
		local current = GetBindingAction("N");
		if ( not current or current == "" ) then
			SetBinding("N", "RAZAGATHCOMPANIONS_TOGGLE");
			SaveBindings(GetCurrentBindingSet());
		end
	end
end);

-- ===========================================================================
-- Hide the stock Character-pane "Pets" tab for classes without a real pet UI
-- (this window replaces its Companions/Mounts sub-tabs). Hunters/warlocks keep
-- it since it also carries their pet stats. Stock PetPaperDollFrame_UpdateTabs
-- re-shows the tab whenever companions exist, so hook it and re-hide.
-- ===========================================================================

local function HideStockPetsTab()
	if ( CharacterFrameTab2 and not HasPetUI() ) then
		CharacterFrameTab2:Hide();
		CharacterFrameTab3:SetPoint("LEFT", "CharacterFrameTab2", "LEFT", 0, 0);
		if ( PetPaperDollFrame ) then PetPaperDollFrame.hidden = true; end
	end
end
if ( PetPaperDollFrame_UpdateTabs ) then
	hooksecurefunc("PetPaperDollFrame_UpdateTabs", HideStockPetsTab);
end
setupFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
setupFrame:HookScript("OnEvent", function(self, event)
	if ( event == "PLAYER_ENTERING_WORLD" ) then HideStockPetsTab(); end
end);
