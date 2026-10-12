-- Razagath Transmogrifier - a retail-style wardrobe window in place of the long gossip dialog.
--
-- Your character in the middle with one button per slot around it, a paged grid of every appearance your ACCOUNT has unlocked for the selected slot, and a single
-- Apply button with the total price. Everything is decided by the server (src/transmog_ui.cpp in mod-transmog): which looks fit the item in that slot, what it
-- costs, and whether the change is allowed - this file only draws the window and previews with the game's own try-on.
--
-- Opens when you talk to a Transmogrifier (or /transmog next to one). Chrome and inset art are the retail pieces already extracted for the Companions window.

RazagathCompanionsDB = RazagathCompanionsDB or {};

local PREFIX = "RazagathTransmog";
local CPATH = "Interface\\AddOns\\Razagath\\Companions\\";
local KIT = RazagathUIKit;
if ( not KIT ) then return; end           -- the Collection Log file publishes the shared frame helpers; without it there is nothing to draw with

local function SetShownCompat(region, shown)
	if ( shown ) then region:Show(); else region:Hide(); end
end

-- ===========================================================================
-- Slots: server slot id (EQUIPMENT_SLOT_*) <-> the paperdoll slot name the client knows
-- ===========================================================================

local SLOTS = {
	{ s = 0,  inv = "HeadSlot",          name = "Head",      col = "L" },
	{ s = 2,  inv = "ShoulderSlot",      name = "Shoulders", col = "L" },
	{ s = 14, inv = "BackSlot",          name = "Back",      col = "L" },
	{ s = 4,  inv = "ChestSlot",         name = "Chest",     col = "L" },
	{ s = 3,  inv = "ShirtSlot",         name = "Shirt",     col = "L" },
	{ s = 18, inv = "TabardSlot",        name = "Tabard",    col = "L" },
	{ s = 8,  inv = "WristSlot",         name = "Wrists",    col = "L" },
	{ s = 9,  inv = "HandsSlot",         name = "Hands",     col = "R" },
	{ s = 5,  inv = "WaistSlot",         name = "Waist",     col = "R" },
	{ s = 6,  inv = "LegsSlot",          name = "Legs",      col = "R" },
	{ s = 7,  inv = "FeetSlot",          name = "Feet",      col = "R" },
	{ s = 15, inv = "MainHandSlot",      name = "Main Hand", col = "B" },
	{ s = 16, inv = "SecondaryHandSlot", name = "Off Hand",  col = "B" },
	{ s = 17, inv = "RangedSlot",        name = "Ranged",    col = "B" },
};
local BY_SLOT = {};
for _, d in ipairs(SLOTS) do
	d.invId, d.emptyTex = GetInventorySlotInfo(d.inv);
	BY_SLOT[d.s] = d;
end

local HIDDEN = 1;       -- the server's "hide this slot" value
local ICON_HIDDEN = "Interface\\Icons\\Spell_Shadow_Invisibility";
local QUALITY = { [0] = { 0.6, 0.6, 0.6 }, [1] = { 1, 1, 1 }, [2] = { 0.12, 1, 0 }, [3] = { 0, 0.44, 0.87 }, [4] = { 0.64, 0.21, 0.93 }, [5] = { 1, 0.5, 0 }, [6] = { 0.9, 0.8, 0.5 }, [7] = { 0.9, 0.8, 0.5 } };

-- ===========================================================================
-- State
-- ===========================================================================

local state = {
	seq = 0,
	selected = nil,         -- server slot id
	page = 1,
	search = "",
};
local slotState = {};       -- slotState[slot] = { equipped = itemId, fake = 0 | HIDDEN | itemId }
local pending = {};         -- pending[slot] = itemId | 0 (remove) | HIDDEN
local lists = {};           -- lists[slot] = { ids... }  (appearances that fit that slot, for the current search)
local listFor = {};         -- listFor[slot] = search string the list was built for
local PER_PAGE = 9;
local COLS = 3;

local function Send(msg)
	SendAddonMessage(PREFIX, msg, "WHISPER", UnitName("player"));
end
local function SendSeq(fmt, ...)
	state.seq = state.seq + 1;
	Send(format(fmt, state.seq, ...));
	return state.seq;
end

-- ===========================================================================
-- Window
-- ===========================================================================

local frame = CreateFrame("Frame", "RazagathWardrobeFrame", UIParent);
frame:SetSize(1062, 666);
frame:SetPoint("CENTER");
frame:SetFrameStrata("HIGH");
frame:SetMovable(true);
frame:EnableMouse(true);
frame:RegisterForDrag("LeftButton");
frame:SetScript("OnDragStart", function(self) self:StartMoving(); end);
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); end);
frame:Hide();
tinsert(UISpecialFrames, "RazagathWardrobeFrame");

local baseLevel = frame:GetFrameLevel();
local BIG, SMALL = 75, 32;
local PURPLE = { 0.80, 0.58, 1.00 };         -- the frame and insets (retail's transmogrifier is purple)
local PURPLE_DARK = { 0.55, 0.36, 0.85 };    -- the rock behind everything

local bgFrame = CreateFrame("Frame", nil, frame);
bgFrame:SetPoint("TOPLEFT", 2, -21);
bgFrame:SetPoint("BOTTOMRIGHT", -2, 2);
KIT.TileBackground(bgFrame, CPATH.."UI-Background-Rock", 512, PURPLE_DARK);

local chrome = CreateFrame("Frame", nil, frame);
chrome:SetAllPoints(frame);
chrome:SetFrameLevel(baseLevel + 30);
local function ChromeTexture(file)
	local t = chrome:CreateTexture(nil, "ARTWORK");
	t:SetTexture(CPATH..file);
	t:SetVertexColor(PURPLE[1], PURPLE[2], PURPLE[3]);
	return t;
end
local cornerTL = ChromeTexture("Frame-CornerTopLeft");
cornerTL:SetSize(BIG, BIG); cornerTL:SetPoint("TOPLEFT", frame, "TOPLEFT", -13, 16);
local cornerTR = ChromeTexture("Frame-CornerTopRight");
cornerTR:SetSize(BIG, BIG); cornerTR:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 4, 16);
local cornerBL = ChromeTexture("Frame-CornerBottomLeft");
cornerBL:SetSize(SMALL, SMALL); cornerBL:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -13, -3);
local cornerBR = ChromeTexture("Frame-CornerBottomRight");
cornerBR:SetSize(SMALL, SMALL); cornerBR:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 4, -3);
local edgeTop = ChromeTexture("Frame-EdgeTop");
edgeTop:SetPoint("TOPLEFT", cornerTL, "TOPRIGHT"); edgeTop:SetPoint("TOPRIGHT", cornerTR, "TOPLEFT"); edgeTop:SetHeight(BIG);
local edgeBottom = ChromeTexture("Frame-EdgeBottom");
edgeBottom:SetPoint("BOTTOMLEFT", cornerBL, "BOTTOMRIGHT"); edgeBottom:SetPoint("BOTTOMRIGHT", cornerBR, "BOTTOMLEFT"); edgeBottom:SetHeight(SMALL);
local edgeLeft = ChromeTexture("Frame-EdgeLeft");
edgeLeft:SetPoint("TOPLEFT", cornerTL, "BOTTOMLEFT"); edgeLeft:SetPoint("BOTTOMLEFT", cornerBL, "TOPLEFT"); edgeLeft:SetWidth(BIG);
local edgeRight = ChromeTexture("Frame-EdgeRight");
edgeRight:SetPoint("TOPRIGHT", cornerTR, "BOTTOMRIGHT"); edgeRight:SetPoint("BOTTOMRIGHT", cornerBR, "TOPRIGHT"); edgeRight:SetWidth(BIG);

local title = chrome:CreateFontString(nil, "OVERLAY", "GameFontNormal");
title:SetPoint("TOP", frame, "TOP", 0, -9);
title:SetText("Transmogrifier");
title:SetTextColor(0.9, 0.75, 1);

local closeButton = CreateFrame("Button", nil, frame);
closeButton:SetSize(24, 24);
closeButton:SetPoint("TOPRIGHT", 3, -1);
closeButton:SetFrameLevel(baseLevel + 31);
KIT.SetButtonAtlas(closeButton, "Normal", "RedButton-Exit");
KIT.SetButtonAtlas(closeButton, "Pushed", "RedButton-Exit-Pressed");
KIT.SetButtonAtlas(closeButton, "Disabled", "RedButton-Exit-Disabled");
KIT.SetButtonAtlas(closeButton, "Highlight", "RedButton-Highlight", "ADD");
closeButton:SetScript("OnClick", function() frame:Hide(); end);

local portraitFrame = CreateFrame("Frame", nil, frame);
portraitFrame:SetSize(56, 56);
portraitFrame:SetPoint("CENTER", frame, "TOPLEFT", 25, -22);
portraitFrame:SetFrameLevel(baseLevel + 2);
local portraitIcon = portraitFrame:CreateTexture(nil, "ARTWORK");
portraitIcon:SetAllPoints();
if ( SetPortraitToTexture ) then SetPortraitToTexture(portraitIcon, "Interface\\Icons\\INV_Chest_Cloth_17"); else portraitIcon:SetTexture("Interface\\Icons\\INV_Chest_Cloth_17"); end

local modelInset = KIT.CreateInset(frame, PURPLE);
modelInset:SetSize(560, 540);
modelInset:SetPoint("TOPLEFT", 4, -60);
local gridInset = KIT.CreateInset(frame, PURPLE);
gridInset:SetSize(490, 540);
gridInset:SetPoint("TOPLEFT", 568, -60);
local bottomInset = KIT.CreateInset(frame, PURPLE);
bottomInset:SetSize(1054, 56);
bottomInset:SetPoint("TOPLEFT", 4, -604);

-- ---------------------------------------------------------------------------
-- The character
-- ---------------------------------------------------------------------------

local model = CreateFrame("DressUpModel", "RazagathWardrobeModel", modelInset);
model:SetPoint("TOPLEFT", 70, -8);
model:SetPoint("BOTTOMRIGHT", -70, 60);
RazagathFreeCam(model);
model:SetScript("OnUpdateModel", function(self) self:ApplyView(); end);

local rotateHint = modelInset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
rotateHint:SetPoint("BOTTOM", modelInset, "BOTTOM", 0, 74);
rotateHint:SetText("Drag to rotate / zoom - right-drag to move - scroll to zoom");

-- item info arrives later for items the client has never seen: ask for them through a hidden tooltip, redraw a moment later
local tip = CreateFrame("GameTooltip", "RazagathWardrobeTip", UIParent, "GameTooltipTemplate");
tip:SetOwner(UIParent, "ANCHOR_NONE");
local function WarmItem(id)
	if ( id and id > 1 and not GetItemInfo(id) ) then
		tip:SetOwner(UIParent, "ANCHOR_NONE");
		pcall(tip.SetHyperlink, tip, "item:"..id);
		return true;
	end
	return false;
end

local function ItemIcon(id)
	if ( not id or id == 0 ) then return nil; end
	if ( id == HIDDEN ) then return ICON_HIDDEN; end
	return GetItemIcon(id);
end

-- redraw the character: your current look, then every pending change on top
local function RebuildModel()
	model:SetUnit("player");
	model:ApplyView();
	model:Settle(0.8);
	for slot, v in pairs(pending) do
		local d = BY_SLOT[slot];
		if ( d ) then
			if ( v == HIDDEN ) then
				model:UndressSlot(d.invId);
			elseif ( v == 0 ) then
				local link = GetInventoryItemLink("player", d.invId);
				if ( link ) then model:TryOn(link); end
			else
				model:TryOn("item:"..v);
			end
		end
	end
end

-- ---------------------------------------------------------------------------
-- Slot buttons
-- ---------------------------------------------------------------------------

local slotButtons = {};

local function SlotButton(d)
	local b = CreateFrame("Button", nil, modelInset);
	b:SetSize(46, 46);
	b.slot = d.s;
	b.icon = b:CreateTexture(nil, "ARTWORK");
	b.icon:SetPoint("TOPLEFT", 3, -3);
	b.icon:SetPoint("BOTTOMRIGHT", -3, 3);
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93);
	b.border = CreateFrame("Frame", nil, b);
	b.border:SetAllPoints();
	b.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 14 });
	b.sel = b:CreateTexture(nil, "OVERLAY");
	b.sel:SetPoint("TOPLEFT", -4, 4);
	b.sel:SetPoint("BOTTOMRIGHT", 4, -4);
	b.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight");
	b.sel:SetBlendMode("ADD");
	b.sel:Hide();
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	b:SetScript("OnClick", function(self, button)
		if ( button == "RightButton" ) then
			RazagathWardrobe_RightClickSlot(self.slot);
		else
			RazagathWardrobe_SelectSlot(self.slot);
		end
	end);
	b:SetScript("OnEnter", function(self)
		local ss = slotState[self.slot];
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetText(d.name, 1, 1, 1);
		if ( not ss ) then
			GameTooltip:AddLine("Nothing equipped here.", 0.6, 0.6, 0.6);
		else
			local _, link = GetItemInfo(ss.equipped);
			GameTooltip:AddLine("Equipped: "..(link or ("item "..ss.equipped)), 0.8, 0.8, 0.8);
			local v = pending[self.slot];
			if ( v == nil ) then v = ss.fake; end
			if ( v == HIDDEN ) then
				GameTooltip:AddLine("Appearance: hidden", 0.9, 0.5, 0.9);
			elseif ( v and v > 1 ) then
				local _, l2 = GetItemInfo(v);
				GameTooltip:AddLine("Appearance: "..(l2 or ("item "..v)), 0.9, 0.5, 0.9);
			end
			if ( pending[self.slot] ~= nil ) then GameTooltip:AddLine("Change not applied yet", 1, 0.82, 0); end
			GameTooltip:AddLine("Left-click: choose a look   Right-click: undo / restore the item's own look", 0.5, 0.5, 0.5, 1);
		end
		GameTooltip:Show();
	end);
	b:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	slotButtons[d.s] = b;
	return b;
end

do
	local L, R, B = {}, {}, {};
	for _, d in ipairs(SLOTS) do
		local b = SlotButton(d);
		if ( d.col == "L" ) then L[#L + 1] = b; elseif ( d.col == "R" ) then R[#R + 1] = b; else B[#B + 1] = b; end
	end
	for i, b in ipairs(L) do b:SetPoint("TOPLEFT", modelInset, "TOPLEFT", 12, -12 - (i - 1) * 56); end
	for i, b in ipairs(R) do b:SetPoint("TOPRIGHT", modelInset, "TOPRIGHT", -12, -12 - (i - 1) * 56); end
	for i, b in ipairs(B) do b:SetPoint("BOTTOM", modelInset, "BOTTOM", (i - 2) * 66, 12); end
end

local function RefreshSlots()
	for slot, b in pairs(slotButtons) do
		local d = BY_SLOT[slot];
		local ss = slotState[slot];
		local v = pending[slot];
		local isPending = ( v ~= nil );
		if ( v == nil and ss ) then v = ss.fake; end

		if ( not ss ) then
			b.icon:SetTexture(d.emptyTex or "Interface\\PaperDoll\\UI-Backpack-EmptySlot");
			b.icon:SetDesaturated(true);
			b.icon:SetVertexColor(0.5, 0.5, 0.5);
			b.border:SetBackdropBorderColor(0.3, 0.3, 0.3);
			b:Disable();
		else
			b:Enable();
			local tex;
			if ( v == HIDDEN ) then tex = ICON_HIDDEN;
			elseif ( v and v > 1 ) then tex = GetItemIcon(v);
			else tex = GetItemIcon(ss.equipped); end
			b.icon:SetTexture(tex or GetInventoryItemTexture("player", d.invId) or "Interface\\Icons\\INV_Misc_QuestionMark");
			b.icon:SetDesaturated(false);
			b.icon:SetVertexColor(1, 1, 1);
			if ( isPending ) then b.border:SetBackdropBorderColor(1, 0.82, 0);              -- change waiting to be applied
			elseif ( v and v ~= 0 ) then b.border:SetBackdropBorderColor(0.95, 0.4, 0.95);  -- already transmogrified
			else b.border:SetBackdropBorderColor(0.5, 0.5, 0.5); end
		end
		SetShownCompat(b.sel, state.selected == slot);
	end
end

-- ---------------------------------------------------------------------------
-- Appearance grid
-- ---------------------------------------------------------------------------

local gridTitle = gridInset:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
gridTitle:SetPoint("TOPLEFT", 14, -12);
gridTitle:SetText("Choose a slot");
local gridHint = gridInset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
gridHint:SetPoint("TOPLEFT", gridTitle, "BOTTOMLEFT", 0, -2);
gridHint:SetText("Unlocked on this account - drag a look to rotate / zoom, right-drag to move, wheel to zoom");

local searchBox = CreateFrame("EditBox", "RazagathWardrobeSearch", gridInset, "InputBoxTemplate");
searchBox:SetSize(150, 20);
searchBox:SetPoint("TOPRIGHT", gridInset, "TOPRIGHT", -16, -12);
searchBox:SetAutoFocus(false);
local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
searchHint:SetPoint("LEFT", 2, 0);
searchHint:SetText("Search");

local cells = {};
local CELL_W, CELL_H = 150, 140;

-- Each grid cell is a small model of YOUR character wearing just that appearance (retail style). How the camera frames each slot is data: CAM below, with live
-- tuning: /wardrobe cam <slot> <scale> <x> <y> <z> [facing]   (slot = server slot id, e.g. 2 = shoulders)   /wardrobe cam head <zoom>   /wardrobe cam reset
-- The values you set are remembered (saved variables), so a good framing can be copied back into the defaults.
-- Free camera, exactly like MogIt's preview: every look is drawn with SetModelScale(2) and SetPosition(depth, left/right, up/down) - drag = rotate + zoom, right-drag = move,
-- wheel = zoom. All the looks of the slot on screen move together, and the view is remembered per slot (saved variables), so each slot only ever needs setting up once.
-- (the saved-variables table is replaced after this file has run, so it is looked up each time instead of being cached)
local DEFAULT_FACE = { [14] = 3.14 };                -- the cloak is seen from behind
local function ViewDB()
	RazagathCompanionsDB = RazagathCompanionsDB or {};
	RazagathCompanionsDB.wardrobeView = RazagathCompanionsDB.wardrobeView or {};
	return RazagathCompanionsDB.wardrobeView;
end
local function GetView(slot)
	local db = ViewDB();
	db[slot] = db[slot] or { depth = 0, x = 0, y = 0, face = DEFAULT_FACE[slot] or 0 };
	return db[slot];
end
local function GetCam(slot)
	local v = GetView(slot);
	return { scale = 2, x = v.depth, y = v.x, z = v.y, f = v.face };
end

-- Dressing a cell takes three passes, because the game resets a model's camera while it loads: (1) put the player on it and the item on the player, (2) once it has
-- had a moment, set scale / position / facing (MogIt's order: model first, SetPosition after), (3) dress it again when the item data has arrived.
local dressing = {};
local function ApplyCam(c)
	local m = c.model;
	local cam = GetCam(c.dressSlot or 0);
	m:SetModelScale(cam.scale or 2);
	m:SetPosition(cam.x or 0, cam.y or 0, cam.z or 0);
	m:SetPortraitZoom(cam.zoom or 0);
	m:SetFacing(cam.f or 0);
end

local lastError;
local function Guard(label, fn, ...)
	local ok, err = pcall(fn, ...);
	if ( not ok ) then lastError = label..": "..tostring(err); end
	return ok;
end

local function DressCell(c)
	if ( not c.itemId ) then return; end
	local m = c.model;
	c.dressSlot = state.selected;
	Guard("dress", function()
		m:SetModelScale(GetCam(c.dressSlot or 0).scale);
		m:SetUnit("player");
		m:Undress();
		m:TryOn("item:"..c.itemId);
	end);
	c.stage, c.timer = 1, 0;
	dressing[c] = true;
	c.dressedWith = c.itemId;                        -- (the last pass clears this again if the item data never showed up)
	c.dressedSlot = c.dressSlot;
end


local function MoveCam(c)
	local cam = GetCam(c.dressSlot or 0);
	c.model:SetPosition(cam.x or 0, cam.y or 0, cam.z or 0);
	c.model:SetFacing(cam.f or 0);
end
local function ApplyAllCams()
	for _, c in ipairs(cells) do if ( c:IsShown() and c.itemId ) then Guard("cam", MoveCam, c); end end
end

-- dragging over any look: left button = rotate (sideways) + zoom (up / down), right button = move; the wheel zooms.  Same maths and speed as MogIt.
local mover = CreateFrame("Frame");
mover:Hide();
mover:SetScript("OnUpdate", function(self)
	local cx, cy = GetCursorPosition();
	local dX, dY = (cx - self.px) / 50, (cy - self.py) / 50;
	local v = GetView(self.slot);
	if ( self.btn == "LeftButton" ) then
		v.depth = v.depth + dY;
		v.face = v.face + dX;
	else
		v.x = v.x + dX;
		v.y = v.y + dY;
	end
	self.px, self.py = cx, cy;
	ApplyAllCams();
end);
local function StartMove(slot, button)
	if ( not slot ) then return; end
	mover.slot, mover.btn = slot, button;
	mover.px, mover.py = GetCursorPosition();
	mover:Show();
end
local function StopMove() mover:Hide(); end
local function WheelZoom(delta)
	local slot = state.selected;
	if ( not slot ) then return; end
	local v = GetView(slot);
	v.depth = v.depth + (delta > 0 and 0.6 or -0.6);
	ApplyAllCams();
end
function RazagathWardrobe_ResetViews()
	wipe(ViewDB());
	ApplyAllCams();
end

local cellDriver = CreateFrame("Frame");
cellDriver:SetScript("OnUpdate", function(self, elapsed)
	for c in pairs(dressing) do
		if ( not c.itemId or not c:IsShown() ) then
			dressing[c] = nil;
		else
			c.timer = c.timer + elapsed;
			if ( c.stage == 1 and c.timer >= 0.12 ) then
				Guard("pass2", function() ApplyCam(c); c.model:TryOn("item:"..c.itemId); end);
				c.stage, c.timer = 2, 0;
			elseif ( c.stage == 2 and c.timer >= 0.5 ) then
				if ( GetItemInfo(c.itemId) ) then
					Guard("pass3", function() c.model:TryOn("item:"..c.itemId); ApplyCam(c); end);
				else
					c.dressedWith = nil;               -- not cached yet: the next grid refresh dresses it again
				end
				dressing[c] = nil;
			end
		end
	end
end);

local function Cell(i)
	local c = cells[i];
	if ( c ) then return c; end
	c = CreateFrame("Button", nil, gridInset);
	c:SetSize(CELL_W, CELL_H);
	local col, row = (i - 1) % COLS, math.floor((i - 1) / COLS);
	c:SetPoint("TOPLEFT", 10 + col * (CELL_W + 4), -58 - row * (CELL_H + 4));
	c.bg = c:CreateTexture(nil, "BACKGROUND");
	c.bg:SetAllPoints();
	c.bg:SetTexture(0, 0, 0, 0.45);
	c.model = CreateFrame("DressUpModel", nil, c);
	c.model:SetPoint("TOPLEFT", 3, -3);
	c.model:SetPoint("BOTTOMRIGHT", -3, 22);
	c.model:EnableMouse(false);
	c.frame = CreateFrame("Frame", nil, c);
	c.frame:SetPoint("TOPLEFT", 1, -1);
	c.frame:SetPoint("BOTTOMRIGHT", -1, 1);
	c.frame:SetFrameLevel(c.model:GetFrameLevel() + 2);
	c.frame:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 });
	c.name = c.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	c.name:SetPoint("BOTTOM", 0, 6);
	c.name:SetWidth(CELL_W - 10);
	c.name:SetHeight(12);
	c.chosen = c.frame:CreateTexture(nil, "OVERLAY");
	c.chosen:SetAllPoints();
	c.chosen:SetTexture(1, 0.82, 0, 0.16);
	c:EnableMouseWheel(true);
	c:SetScript("OnMouseWheel", function(self, delta) WheelZoom(delta); end);
	c:RegisterForDrag("LeftButton", "RightButton");
	c:SetScript("OnDragStart", function(self, button) StartMove(state.selected, button); end);
	c:SetScript("OnDragStop", StopMove);
	c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	c:SetScript("OnClick", function(self) RazagathWardrobe_PickAppearance(self.itemId); end);
	c:SetScript("OnEnter", function(self)
		if ( not self.itemId ) then return; end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink("item:"..self.itemId);
		GameTooltip:Show();
	end);
	c:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	cells[i] = c;
	return c;
end

local pageText = gridInset:CreateFontString(nil, "OVERLAY", "GameFontNormal");
pageText:SetPoint("BOTTOM", 0, 14);
local prevButton = CreateFrame("Button", nil, gridInset);
prevButton:SetSize(28, 28);
prevButton:SetPoint("RIGHT", pageText, "LEFT", -24, 0);
prevButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up");
prevButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down");
prevButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled");
prevButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");
local nextButton = CreateFrame("Button", nil, gridInset);
nextButton:SetSize(28, 28);
nextButton:SetPoint("LEFT", pageText, "RIGHT", 24, 0);
nextButton:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up");
nextButton:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down");
nextButton:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled");
nextButton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD");
prevButton:SetScript("OnClick", function() state.page = state.page - 1; RazagathWardrobe_RefreshGrid(); end);
nextButton:SetScript("OnClick", function() state.page = state.page + 1; RazagathWardrobe_RefreshGrid(); end);

local emptyText = gridInset:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
emptyText:SetPoint("CENTER", 0, 0);
emptyText:SetWidth(300);

local warmTimer;           -- redraw while item names are still arriving
function RazagathWardrobe_RefreshGrid()
	local slot = state.selected;
	local list = slot and lists[slot] or {};
	local d = slot and BY_SLOT[slot];
	local loading = slot and listFor[slot] ~= state.search;
	gridTitle:SetText(d and d.name or "Choose a slot");

	local pages = math.max(1, math.ceil(#list / PER_PAGE));
	if ( state.page > pages ) then state.page = pages; end
	if ( state.page < 1 ) then state.page = 1; end
	local first = (state.page - 1) * PER_PAGE;
	local missing = false;
	for i = 1, PER_PAGE do
		local id = list[first + i];
		local c = Cell(i);
		if ( id ) then
			c.itemId = id;
			if ( WarmItem(id) ) then missing = true; end
			local name, _, quality = GetItemInfo(id);
			c.name:SetText(name or "...");
			local q = QUALITY[quality or 1] or QUALITY[1];
			c.name:SetTextColor(q[1], q[2], q[3]);
			c.frame:SetBackdropBorderColor(q[1], q[2], q[3]);
			SetShownCompat(c.chosen, pending[slot] == id);
			c:Show();
			if ( c.dressedWith ~= id or c.dressedSlot ~= slot ) then DressCell(c); end
		else
			c.itemId = nil;
			c.dressedWith = nil;
			c:Hide();
		end
	end
	for i = PER_PAGE + 1, #cells do cells[i]:Hide(); end

	pageText:SetText(format("Page %d / %d", state.page, pages));
	if ( state.page <= 1 ) then prevButton:Disable(); else prevButton:Enable(); end
	if ( state.page >= pages ) then nextButton:Disable(); else nextButton:Enable(); end
	if ( not slot ) then
		emptyText:SetText("Pick a slot on the left to see the looks you can use.");
	elseif ( not slotState[slot] ) then
		emptyText:SetText("Nothing is equipped in this slot.");
	elseif ( loading and #list == 0 ) then
		emptyText:SetText("Loading...");
	elseif ( #list == 0 ) then
		emptyText:SetText(state.search ~= "" and "No appearance matches that search." or "You have not unlocked any other appearance that fits this slot yet.\nPick items up (or equip them) to unlock them.");
	else
		emptyText:SetText("");
	end
	warmTimer = missing and 0.6 or nil;
end

-- ---------------------------------------------------------------------------
-- Bottom bar: price + buttons
-- ---------------------------------------------------------------------------

local costLabel = bottomInset:CreateFontString(nil, "OVERLAY", "GameFontNormal");
costLabel:SetPoint("LEFT", 18, 0);
costLabel:SetText("Total cost:");
local costValue = bottomInset:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge");
costValue:SetPoint("LEFT", costLabel, "RIGHT", 10, 0);

local function Button(text, w, x)
	local b = CreateFrame("Button", nil, bottomInset, "UIPanelButtonTemplate");
	b:SetSize(w, 28);
	b:SetPoint("RIGHT", bottomInset, "RIGHT", x, 0);
	b:SetText(text);
	return b;
end
local applyButton = Button("Apply", 130, -18);
local undoButton = Button("Undo changes", 120, -156);
local clearButton = Button("Remove all", 110, -284);
local hideButton = Button("Hide slot", 100, -402);

local quoteTimer;
local function Quote()
	local parts = {};
	for slot, v in pairs(pending) do parts[#parts + 1] = slot.."="..v; end
	if ( #parts == 0 ) then
		costValue:SetText("|cff9d9d9dnothing to apply|r");
		return;
	end
	costValue:SetText("...");
	SendSeq("Q;%d;%s", table.concat(parts, ","));
end

local function PendingCount()
	local n = 0;
	for _ in pairs(pending) do n = n + 1; end
	return n;
end

local function UpdateButtons()
	local n = PendingCount();
	if ( n > 0 ) then applyButton:Enable(); undoButton:Enable(); else applyButton:Disable(); undoButton:Disable(); end
	local any = false;
	for _, ss in pairs(slotState) do if ( ss.fake and ss.fake ~= 0 ) then any = true; end end
	if ( any ) then clearButton:Enable(); else clearButton:Disable(); end
	if ( state.selected and slotState[state.selected] ) then hideButton:Enable(); else hideButton:Disable(); end
end

local function SetPending(slot, value)
	local ss = slotState[slot];
	if ( not ss ) then return; end
	if ( value == nil or value == ss.fake or (value == 0 and (not ss.fake or ss.fake == 0)) ) then
		pending[slot] = nil;
	else
		pending[slot] = value;
	end
	RefreshSlots();
	RebuildModel();
	RazagathWardrobe_RefreshGrid();
	UpdateButtons();
	quoteTimer = 0.25;
end

function RazagathWardrobe_PickAppearance(itemId)
	local slot = state.selected;
	if ( not slot or not itemId ) then return; end
	if ( pending[slot] == itemId ) then SetPending(slot, nil); else SetPending(slot, itemId); end
end

function RazagathWardrobe_RightClickSlot(slot)
	local ss = slotState[slot];
	if ( not ss ) then return; end
	if ( pending[slot] ~= nil ) then
		SetPending(slot, nil);                              -- drop the pending change
	elseif ( ss.fake and ss.fake ~= 0 ) then
		SetPending(slot, 0);                                -- take the existing transmog off
	end
end

function RazagathWardrobe_SelectSlot(slot)
	state.selected = slot;
	state.page = 1;
	RefreshSlots();
	UpdateButtons();
	if ( slotState[slot] ) then
		if ( listFor[slot] ~= state.search ) then lists[slot] = {}; SendSeq("L;%d;%d;%s", slot, state.search); end
	end
	RazagathWardrobe_RefreshGrid();
end

hideButton:SetScript("OnClick", function()
	local slot = state.selected;
	if ( slot ) then SetPending(slot, pending[slot] == HIDDEN and nil or HIDDEN); end
end);
undoButton:SetScript("OnClick", function()
	wipe(pending);
	RefreshSlots(); RebuildModel(); RazagathWardrobe_RefreshGrid(); UpdateButtons(); Quote();
end);
clearButton:SetScript("OnClick", function()
	for slot, ss in pairs(slotState) do
		if ( ss.fake and ss.fake ~= 0 ) then pending[slot] = 0; end
	end
	RefreshSlots(); RebuildModel(); RazagathWardrobe_RefreshGrid(); UpdateButtons(); Quote();
end);
applyButton:SetScript("OnClick", function()
	local parts = {};
	for slot, v in pairs(pending) do parts[#parts + 1] = slot.."="..v; end
	if ( #parts == 0 ) then return; end
	applyButton:Disable();
	SendSeq("A;%d;%s", table.concat(parts, ","));
end);

-- ---------------------------------------------------------------------------
-- Outfits: named looks you can save and put back on with one click. Kept in the saved variables of this client install (not on the server); applying one just
-- fills in the pending changes, so the normal Apply button / cost / "do I own it" checks still decide what actually happens.
-- ---------------------------------------------------------------------------

local MAX_OUTFITS, OUTFIT_ROWS = 12, 12;
local function OutfitDB()
	RazagathCompanionsDB = RazagathCompanionsDB or {};
	RazagathCompanionsDB.outfits = RazagathCompanionsDB.outfits or {};
	return RazagathCompanionsDB.outfits;
end
local function FindOutfit(name)
	for i, o in ipairs(OutfitDB()) do if ( strlower(o.name) == strlower(name) ) then return o, i; end end
end

local outfitButton = CreateFrame("Button", "RazagathWardrobeOutfitButton", modelInset, "UIPanelButtonTemplate");
outfitButton:SetSize(110, 24);
outfitButton:SetPoint("TOP", modelInset, "TOP", 0, -10);
outfitButton:SetText("Outfits");
outfitButton:SetFrameLevel(model:GetFrameLevel() + 10);        -- the 3D model covers this part of the inset and would otherwise eat the clicks

local outfitPanel = CreateFrame("Frame", "RazagathWardrobeOutfitPanel", frame);
outfitPanel:SetSize(260, 74 + OUTFIT_ROWS * 22);
outfitPanel:SetPoint("TOP", outfitButton, "BOTTOM", 0, -2);
outfitPanel:SetFrameStrata("DIALOG");
outfitPanel:SetFrameLevel(baseLevel + 25);
outfitPanel:EnableMouse(true);
outfitPanel:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
	tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } });
outfitPanel:SetBackdropColor(PURPLE_DARK[1], PURPLE_DARK[2], PURPLE_DARK[3], 1);
outfitPanel:Hide();

local outfitName = CreateFrame("EditBox", "RazagathWardrobeOutfitName", outfitPanel, "InputBoxTemplate");
outfitName:SetSize(150, 20);
outfitName:SetPoint("TOPLEFT", 20, -16);
outfitName:SetAutoFocus(false);
outfitName:SetMaxLetters(24);
local outfitSave = CreateFrame("Button", nil, outfitPanel, "UIPanelButtonTemplate");
outfitSave:SetSize(70, 22);
outfitSave:SetPoint("LEFT", outfitName, "RIGHT", 6, 0);
outfitSave:SetText("Save");
local outfitHelp = outfitPanel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
outfitHelp:SetPoint("TOPLEFT", 20, -42);
outfitHelp:SetWidth(222);
outfitHelp:SetJustifyH("LEFT");
outfitHelp:SetText("Name the look on the model, then Save. Click an outfit to try it on.");

local outfitRows = {};
local function OutfitTooltip(self)
	local o = self.outfit;
	if ( not o ) then return; end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(o.name, 1, 1, 1);
	for _, d in ipairs(SLOTS) do
		local v = o.items[d.s];
		if ( v ) then
			local text;
			if ( v == HIDDEN ) then text = "|cffe680e6hidden|r";
			elseif ( v == 0 ) then text = "|cff9d9d9dthe item's own look|r";
			else local _, link = GetItemInfo(v); text = link or ("item "..v); end
			GameTooltip:AddDoubleLine(d.name, text, 0.8, 0.8, 0.8, 1, 1, 1);
		end
	end
	GameTooltip:AddLine("Right-click: delete", 0.5, 0.5, 0.5);
	GameTooltip:Show();
end

local function LoadOutfit(o)
	local changed = false;
	for slot, v in pairs(o.items) do
		local ss = slotState[slot];
		if ( ss ) then
			if ( v == ss.fake or (v == 0 and (not ss.fake or ss.fake == 0)) ) then pending[slot] = nil; else pending[slot] = v; end
			if ( v > 1 ) then WarmItem(v); end
			changed = true;
		end
	end
	if ( changed ) then
		RefreshSlots(); RebuildModel(); RazagathWardrobe_RefreshGrid(); UpdateButtons();
		quoteTimer = 0.25;
	end
	outfitPanel:Hide();
end

local function RefreshOutfits()
	local list = OutfitDB();
	for i = 1, OUTFIT_ROWS do
		local r = outfitRows[i];
		if ( not r ) then
			r = CreateFrame("Button", nil, outfitPanel);
			r:SetSize(222, 20);
			r:SetPoint("TOPLEFT", 20, -62 - (i - 1) * 22);
			r:RegisterForClicks("LeftButtonUp", "RightButtonUp");
			r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");
			r.text = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
			r.text:SetPoint("LEFT", 4, 0);
			r.text:SetWidth(190);
			r.text:SetJustifyH("LEFT");
			r.count = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
			r.count:SetPoint("RIGHT", -4, 0);
			r:SetScript("OnClick", function(self, button)
				if ( not self.outfit ) then return; end
				if ( button == "RightButton" ) then
					StaticPopup_Show("RAZAGATH_WARDROBE_DELETE_OUTFIT", self.outfit.name, nil, self.outfit.name);
				else
					LoadOutfit(self.outfit);
				end
			end);
			r:SetScript("OnEnter", OutfitTooltip);
			r:SetScript("OnLeave", function() GameTooltip:Hide(); end);
			outfitRows[i] = r;
		end
		local o = list[i];
		r.outfit = o;
		if ( o ) then
			local n = 0;
			for _ in pairs(o.items) do n = n + 1; end
			r.text:SetText(o.name);
			r.count:SetText(n.." pcs");
			r:Show();
		else
			r:Hide();
		end
	end
end

StaticPopupDialogs["RAZAGATH_WARDROBE_DELETE_OUTFIT"] = {
	text = "Delete the outfit \"%s\"?",
	button1 = YES, button2 = NO,
	OnAccept = function(self, data)
		local _, i = FindOutfit(data or "");
		if ( i ) then tremove(OutfitDB(), i); end
		RefreshOutfits();
	end,
	timeout = 0, whileDead = 1, hideOnEscape = 1,
};

-- the look as it would be after Apply: pending changes on top of what is already transmogrified
local function SaveOutfit()
	local name = strtrim(outfitName:GetText() or "");
	if ( name == "" ) then UIErrorsFrame:AddMessage("Give the outfit a name first.", 1, 0.3, 0.3); return; end
	local items = {};
	for slot, ss in pairs(slotState) do
		local v = pending[slot];
		if ( v == nil ) then v = ss.fake or 0; end
		items[slot] = v;
	end
	if ( next(items) == nil ) then return; end
	local o = FindOutfit(name);
	if ( o ) then
		o.items = items;
	else
		local list = OutfitDB();
		if ( #list >= MAX_OUTFITS ) then UIErrorsFrame:AddMessage("You can keep "..MAX_OUTFITS.." outfits - delete one first.", 1, 0.3, 0.3); return; end
		list[#list + 1] = { name = name, items = items };
	end
	outfitName:SetText("");
	outfitName:ClearFocus();
	RefreshOutfits();
	print("Wardrobe: saved the outfit \""..name.."\".");
end
outfitSave:SetScript("OnClick", SaveOutfit);
outfitName:SetScript("OnEnterPressed", SaveOutfit);
outfitName:SetScript("OnEscapePressed", function(self) self:ClearFocus(); end);

outfitButton:SetScript("OnClick", function()
	if ( outfitPanel:IsShown() ) then outfitPanel:Hide(); else RefreshOutfits(); outfitPanel:Show(); end
end);
frame:HookScript("OnHide", function() outfitPanel:Hide(); end);

-- search: ask the server again a moment after the player stops typing
local searchTimer;
searchBox:SetScript("OnTextChanged", function(self)
	local t = strlower(strtrim(self:GetText() or ""));
	SetShownCompat(searchHint, t == "" and not self:HasFocus());
	if ( t ~= state.search ) then
		state.search = t;
		searchTimer = 0.4;
	end
end);
searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide(); end);
searchBox:SetScript("OnEditFocusLost", function(self) SetShownCompat(searchHint, (self:GetText() or "") == ""); end);
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); end);

-- ---------------------------------------------------------------------------
-- Timers (3.3.5 has no C_Timer)
-- ---------------------------------------------------------------------------

frame:SetScript("OnUpdate", function(self, elapsed)
	if ( searchTimer ) then
		searchTimer = searchTimer - elapsed;
		if ( searchTimer <= 0 ) then
			searchTimer = nil;
			for slot in pairs(lists) do lists[slot] = nil; listFor[slot] = nil; end
			state.page = 1;
			if ( state.selected and slotState[state.selected] ) then lists[state.selected] = {}; SendSeq("L;%d;%d;%s", state.selected, state.search); end
			RazagathWardrobe_RefreshGrid();
		end
	end
	if ( quoteTimer ) then
		quoteTimer = quoteTimer - elapsed;
		if ( quoteTimer <= 0 ) then quoteTimer = nil; Quote(); end
	end
	if ( warmTimer ) then
		warmTimer = warmTimer - elapsed;
		if ( warmTimer <= 0 ) then warmTimer = nil; RazagathWardrobe_RefreshGrid(); end
	end
end);

-- ---------------------------------------------------------------------------
-- Server messages
-- ---------------------------------------------------------------------------

local function Open()
	if ( not frame:IsShown() ) then
		wipe(pending);
		wipe(lists); wipe(listFor);
		frame:Show();
	end
	SendSeq("S;%d");
end

frame:SetScript("OnShow", function()
	model:ResetView();
	RebuildModel();
	UpdateButtons();
	Quote();
end);
frame:SetScript("OnHide", function()
	wipe(pending);
	GameTooltip:Hide();
end);

local ev = CreateFrame("Frame");
ev:RegisterEvent("CHAT_MSG_ADDON");
ev:RegisterEvent("PLAYER_ENTERING_WORLD");
ev:RegisterEvent("UNIT_INVENTORY_CHANGED");
local helloTimer;
ev:SetScript("OnUpdate", function(self, elapsed)
	if ( helloTimer ) then
		helloTimer = helloTimer - elapsed;
		if ( helloTimer <= 0 ) then helloTimer = nil; SendSeq("H;%d"); end
	end
end);
ev:SetScript("OnEvent", function(self, event, prefix, message)
	if ( event == "PLAYER_ENTERING_WORLD" ) then
		helloTimer = 4;                                    -- let the connection settle, then tell the server this client has the window
		return;
	end
	if ( event == "UNIT_INVENTORY_CHANGED" ) then
		if ( prefix == "player" and frame:IsShown() ) then SendSeq("S;%d"); end
		return;
	end
	if ( prefix ~= PREFIX or type(message) ~= "string" ) then return; end
	local t = strsub(message, 1, 1);

	if ( t == "O" ) then
		Open();

	elseif ( t == "P" ) then
		-- P;seq;slot:equipped:fake,...
		local _, seq, body = strsplit(";", message);
		if ( not state.stateLoading ) then state.stateLoading = true; wipe(slotState); end
		for slot, eq, fake in string.gmatch(body or "", "(%d+):(%d+):(%d+)") do
			slotState[tonumber(slot)] = { equipped = tonumber(eq), fake = tonumber(fake) };
		end

	elseif ( t == "E" ) then
		local _, seq, what, count = strsplit(";", message);
		if ( what == "P" ) then
			state.stateLoading = nil;
			if ( state.selected and not slotState[state.selected] ) then state.selected = nil; end
			RefreshSlots(); RebuildModel(); UpdateButtons(); RazagathWardrobe_RefreshGrid();
		elseif ( what == "A" ) then
			wipe(pending);
			SendSeq("S;%d");
			Quote();
			UpdateButtons();
		else
			-- E;seq;slot;count  - end of a list
			local slot = tonumber(what);
			if ( slot ) then
				lists[slot] = lists[slot] or {};
				listFor[slot] = state.search;
				if ( slot == state.selected ) then RazagathWardrobe_RefreshGrid(); end
			end
		end

	elseif ( t == "I" ) then
		-- I;seq;slot;id,id,...
		local _, seq, slot, ids = strsplit(";", message);
		slot = tonumber(slot);
		if ( slot and ids ) then
			lists[slot] = lists[slot] or {};
			for id in string.gmatch(ids, "%d+") do lists[slot][#lists[slot] + 1] = tonumber(id); end
			if ( slot == state.selected ) then RazagathWardrobe_RefreshGrid(); end
		end

	elseif ( t == "K" ) then
		local _, seq, copper, tokens = strsplit(";", message);
		copper = tonumber(copper) or 0;
		if ( PendingCount() == 0 ) then
			costValue:SetText("|cff9d9d9dnothing to apply|r");
		elseif ( copper == 0 ) then
			costValue:SetText("|cff33ff33free|r");
		else
			local enough = GetMoney() >= copper;
			costValue:SetText((enough and "" or "|cffff5555")..GetCoinTextureString(copper)..(enough and "" or "|r"));
		end

	elseif ( t == "R" ) then
		-- R;seq;slot;ok;text
		local _, seq, slot, ok, text = strsplit(";", message);
		if ( ok == "1" ) then
			local d = BY_SLOT[tonumber(slot)];
			if ( d ) then UIErrorsFrame:AddMessage(d.name..": "..(text or "done"), 0.4, 1, 0.4); end
		else
			UIErrorsFrame:AddMessage("Transmog: "..(text or "failed"), 1, 0.3, 0.3);
		end
	end
end);

function RazagathWardrobe_Toggle()
	if ( frame:IsShown() ) then frame:Hide(); else Send("X;"..(state.seq + 1)); state.seq = state.seq + 1; end
end

SLASH_RAZAGATHWARDROBE1 = "/transmog";
SLASH_RAZAGATHWARDROBE2 = "/wardrobe";
SlashCmdList["RAZAGATHWARDROBE"] = function(msg)
	local cmd = strlower((strmatch(msg or "", "^(%S*)")) or "");
	if ( cmd == "reset" ) then
		RazagathWardrobe_ResetViews();
		print("Wardrobe: every slot's view is back to the default.");
		return;
	end
	if ( cmd == "dbg" ) then
		local c = cells[1];
		if ( c ) then
			local m = c.model;
			print("cell1 item", c.itemId, "dressedWith", c.dressedWith, "info", GetItemInfo(c.itemId or 0) and "cached" or "NOT cached", "model", tostring(m:GetModel()), "slot", tostring(c.dressSlot));
		end
		return;
	end
	RazagathWardrobe_Toggle();
end;
