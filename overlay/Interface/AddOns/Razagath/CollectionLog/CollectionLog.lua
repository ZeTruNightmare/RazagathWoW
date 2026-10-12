-- Razagath Collection Log - one window for everything an ACCOUNT has collected: mounts, pets, achievements (more tabs follow: recipes, eternals,
-- appearances). RuneScape-style: pick a category, see a grid of everything in it with what is missing greyed out, click an entry for a 3D preview and
-- every place it comes from. Completing a section pays a reward (claimed from the panel at the bottom).
--
-- Account-wide because the server answers "what has any character on this account got?" (src/mod_collection_log.cpp); the current character's live state is
-- OR-ed in so a mount learned a second ago shows up before the server has saved it.
--
-- Catalogue data (mounts / pets, with sources and models) is generated into Data.lua by client-patch/mk_collection_log.pl. Names and icons come from the
-- client (GetSpellInfo / GetItemIcon) so nothing here needs updating when a spell is renamed. Achievements are read live from the client's achievement API.
--
-- Chrome and inset art are the retail frame pieces already extracted for the Companions window (Razagath\Companions\), the launcher button is retail's
-- Adventure Guide micro-menu art (Atlas_Data.lua / Files\ next to this file).

RazagathCompanionsDB = RazagathCompanionsDB or {};
RazagathCompanionsDB.log = RazagathCompanionsDB.log or {};

local DB = RazagathCompanionsDB.log;
local PATH = "Interface\\AddOns\\Razagath\\CollectionLog\\";
local CPATH = "Interface\\AddOns\\Razagath\\Companions\\";
local PREFIX = "RazagathCollection";
local ADDON_ICON = "Interface\\Icons\\INV_Misc_Book_09";

-- ===========================================================================
-- Helpers (3.3.5a has no :SetShown, no atlas system)
-- ===========================================================================

local function SetShownCompat(region, shown)
	if ( shown ) then region:Show(); else region:Hide(); end
end

local function CompanionAtlas(name)
	return RazagathAtlasData and RazagathAtlasData[strlower(name)];
end

-- Atlas elements are padded to power-of-two with content at the top-left: texcoord 0..a[4] / 0..a[5]; a[2], a[3] = native size.
local function SetAtlas(tex, name, useAtlasSize)
	local a = CompanionAtlas(name);
	if ( not a ) then return; end
	tex:SetTexture(CPATH..a[1]);
	tex:SetTexCoord(0, a[4], 0, a[5]);
	if ( useAtlasSize ) then tex:SetSize(a[2], a[3]); end
end

local function SetButtonAtlas(btn, state, name, blendMode, own)
	local a = own and RazagathCollectionAtlas and RazagathCollectionAtlas[strlower(name)] or CompanionAtlas(name);
	if ( not a ) then return nil; end
	local path = (own and PATH.."Files\\" or CPATH)..a[1];
	if ( state == "Highlight" ) then
		btn:SetHighlightTexture(path, blendMode or "ADD");
	else
		btn["Set"..state.."Texture"](btn, path);
	end
	local t = btn["Get"..state.."Texture"](btn);
	t:SetTexCoord(0, a[4], 0, a[5]);
	return t;
end

-- ===========================================================================
-- State
-- ===========================================================================

local KINDS = {
	{ id = 1, key = "mounts",       label = "Mounts" },
	{ id = 2, key = "pets",         label = "Pets" },
	{ id = 3, key = "achievements", label = "Achievements" },
	{ id = 4, key = "recipes",      label = "Recipes" },
	{ id = 5, key = "eternals",     label = "Eternals" },
	{ id = 6, key = "appearances",  label = "Appearances" },
	{ id = 7, key = "unobtainable", label = "Unobtainable" },
};
local IMPLEMENTED = { 1, 2, 3, 4, 5, 6, 7 };
local NOT_IN_TOTAL = { [6] = true, [7] = true };      -- appearances are thousands of entries and the unobtainable tab is a museum: neither belongs in the headline percentage
local LAZY = { [6] = true, [7] = true };               -- built only when their tab is on screen
local UNOB_SOURCES = { [1] = true, [2] = true, [4] = true, [6] = true };   -- kinds whose unobtainable entries show up on the Unobtainable tab

local CAT_LABEL = {
	razagath = "Razagath Exclusive", achievement = "Achievements", dungeon = "Dungeons & Raids", world = "World Drops & Rares",
	vendor = "Vendors", quest = "Quest Rewards", object = "Chests & Containers", other = "Other / Unknown Source",
};
local CAT_ORDER = { "razagath", "achievement", "dungeon", "world", "vendor", "quest", "object", "other" };

local state = {
	kind = DB.kind or 1,
	section = "all",
	filter = "all",          -- all | got | missing
	search = "",
	selected = nil,          -- entry
	seq = 0,
};
local discChance = {};                                -- eternal recipe spell -> effective discovery chance in % (sent by the server: base chance x realm rate)
local srv = { [1] = {}, [2] = {}, [3] = {}, [4] = {}, [5] = {}, [6] = {} };       -- server sets: [kind][id] = true (account-wide, from the saved character tables)
local srvReady = {};
local localSpells = { [1] = {}, [2] = {} };         -- the current character's live companions
local cache = {};                                    -- cache[kind] = { entries =, sections =, total =, got = }
local entries = {};                                  -- entries of the current kind
local sections = {};                                 -- sections of the current kind
local shown = {};                                    -- entries passing section / filter / search
local achCache;                                      -- achievement list, built once per session
local rewards = {};                                  -- rewards[id] = { id, state (0 locked / 1 ready / 2 claimed), scope, kind, section, rtype, rid, rcount, desc }
local rewardOrder = {};

-- ===========================================================================
-- Data: entries per kind
-- ===========================================================================

local function RefreshLocal()
	for _, k in ipairs({ { 1, "MOUNT" }, { 2, "CRITTER" } }) do
		wipe(localSpells[k[1]]);
		for i = 1, GetNumCompanions(k[2]) do
			local _, _, spellID = GetCompanionInfo(k[2], i);
			if ( spellID ) then localSpells[k[1]][spellID] = true; end
		end
	end
end

local function IsCollectedSpells(kind, spells)
	for _, sp in ipairs(spells) do
		if ( localSpells[kind][sp] or srv[kind][sp] ) then return true; end
	end
	return false;
end

local function EntryIcon(e)
	if ( e.sp and e.sp[1] ) then
		local _, _, icon = GetSpellInfo(e.sp[1]);
		if ( icon ) then return icon; end
	end
	if ( e.items and e.items[1] ) then
		local icon = GetItemIcon(e.items[1].id);
		if ( icon ) then return icon; end
	end
	return "Interface\\Icons\\INV_Misc_QuestionMark";
end

local staticEntries = {};                             -- staticEntries[kind] = the entry list, built once (names / icons / sources never change)
local unobEntries = {};                               -- unobEntries[kind] = entries nobody can currently obtain; they are listed on the Unobtainable tab only

local function BuildCompanionEntries(kind, list)
	if ( not staticEntries[kind] ) then
		local out, unob = {}, {};
		for i, d in ipairs(list or {}) do
			local e = { kind = kind, name = d.n, cat = d.cat, cr = d.cr, mp = d.mp, sp = d.sp, items = d.items, src = d.src,
				icon = EntryIcon(d), section = d.cat };
			if ( d.cat == "unob" ) then e.section = "u"..kind; unob[#unob + 1] = e; else out[#out + 1] = e; end
		end
		sort(out, function(a, b) return a.name < b.name; end);
		sort(unob, function(a, b) return a.name < b.name; end);
		staticEntries[kind] = out;
		unobEntries[kind] = unob;
	end
	for _, e in ipairs(staticEntries[kind]) do e.collected = IsCollectedSpells(kind, e.sp); end
	for _, e in ipairs(unobEntries[kind]) do e.collected = IsCollectedSpells(kind, e.sp); end
	return staticEntries[kind];
end

-- recipes (kind 4) and eternal recipes (kind 5): one entry per recipe spell, collected when ANY character of the account knows it
local function BuildRecipeEntries(kind, list)
	if ( not staticEntries[kind] ) then
		local out, unob = {}, {};
		for _, d in ipairs(list or {}) do
			local name, _, icon = GetSpellInfo(d.sp);
			local e = { kind = kind, name = d.n or name or "Unknown", spell = d.sp, sp = { d.sp }, itemId = d.it, eq = d.eq == 1, sk = d.sk, src = d.src,
				icon = (d.it and d.it > 0 and GetItemIcon(d.it)) or icon or "Interface\\Icons\\INV_Misc_QuestionMark", section = d.s, prof = d.s };
			if ( d.u ) then e.section = "u"..kind; unob[#unob + 1] = e; else out[#out + 1] = e; end
		end
		sort(out, function(a, b) return a.name < b.name; end);
		sort(unob, function(a, b) return a.name < b.name; end);
		staticEntries[kind] = out;
		unobEntries[kind] = unob;
	end
	local set = srv[kind];
	for _, e in ipairs(staticEntries[kind]) do e.collected = (IsSpellKnown(e.spell) or set[e.spell]) and true or false; end
	for _, e in ipairs(unobEntries[kind] or {}) do e.collected = (IsSpellKnown(e.spell) or set[e.spell]) and true or false; end
	return staticEntries[kind];
end

-- transmog appearances (kind 6): one entry per LOOK; the server reports the item that names a look once it is unlocked on the account
local function BuildAppearanceEntries(list)
	if ( not staticEntries[6] ) then
		local out, unob = {}, {};
		for _, d in ipairs(list or {}) do
			local id = d[1];
			local items = { { id = id } };
			for _, m in ipairs(d[5] or {}) do items[#items + 1] = { id = m }; end
			local src = {};
			for _, s in ipairs(d[6] or {}) do src[#src + 1] = { t = s[1], x = s[2], a = s[3], q = s[4], ql = s[5] }; end
			local e = { kind = 6, id = id, name = d[2], quality = d[3], section = d[4], itemId = id, eq = true, items = items, src = src,
				icon = GetItemIcon(id) or "Interface\\Icons\\INV_Misc_QuestionMark" };
			if ( d[7] ) then e.section = "u6"; unob[#unob + 1] = e; else out[#out + 1] = e; end
		end
		sort(out, function(a, b) return a.name < b.name; end);
		sort(unob, function(a, b) return a.name < b.name; end);
		staticEntries[6] = out;
		unobEntries[6] = unob;
	end
	local set = srv[6];
	for _, e in ipairs(staticEntries[6]) do e.collected = set[e.id] and true or false; end
	for _, e in ipairs(unobEntries[6]) do e.collected = set[e.id] and true or false; end
	return staticEntries[6];
end

local function BuildAchievements()
	if ( not achCache ) then
		achCache = { list = {}, secs = {} };
		for _, cat in ipairs(GetCategoryList()) do
			local title, parent = GetCategoryInfo(cat);
			local num = GetCategoryNumAchievements(cat);
			if ( num and num > 0 ) then
				local ptitle = parent and parent > 0 and GetCategoryInfo(parent) or nil;
				local label = ptitle and (ptitle.." - "..title) or title;
				local key = "c"..cat;
				achCache.secs[#achCache.secs + 1] = { key = key, label = label };
				for i = 1, num do
					local id, name, points, completed, month, day, year, desc, flags, icon, reward = GetAchievementInfo(cat, i);
					if ( id ) then
						achCache.list[#achCache.list + 1] = { kind = 3, id = id, name = name, points = points, desc = desc,
							icon = icon, reward = reward, section = key, cat = key };
					end
				end
			end
		end
	end
	for _, e in ipairs(achCache.list) do
		local _, _, _, done, month, day, year = GetAchievementInfo(e.id);
		e.localDone = done;
		e.date = done and format("%02d/%02d/%02d", day or 0, month or 0, year or 0) or nil;
		e.collected = (done or srv[3][e.id]) and true or false;
	end
	return achCache.list, achCache.secs;
end

-- returns entries, sections, total, got for one kind
local function MakeKind(kind)
	local list, secDefs;
	if ( kind == 1 ) then
		list = BuildCompanionEntries(1, RazagathCollectionData and RazagathCollectionData.mounts);
	elseif ( kind == 2 ) then
		list = BuildCompanionEntries(2, RazagathCollectionData and RazagathCollectionData.pets);
	elseif ( kind == 3 ) then
		list, secDefs = BuildAchievements();
	elseif ( kind == 4 or kind == 5 ) then
		local d = RazagathCollectionData or {};
		list = BuildRecipeEntries(kind, kind == 4 and d.recipes or d.eternals);
		secDefs = d.sections and d.sections[kind] or {};
	elseif ( kind == 6 ) then
		local d = RazagathCollectionData or {};
		list = BuildAppearanceEntries(d.appearances);
		secDefs = d.sections and d.sections[6] or {};
	elseif ( kind == 7 ) then
		local d = RazagathCollectionData or {};
		BuildCompanionEntries(1, d.mounts); BuildCompanionEntries(2, d.pets); BuildRecipeEntries(4, d.recipes); BuildAppearanceEntries(d.appearances);
		list = {};
		for _, k in ipairs({ 1, 2, 4, 6 }) do for _, e in ipairs(unobEntries[k] or {}) do list[#list + 1] = e; end end
		secDefs = { { key = "u1", label = "Mounts" }, { key = "u2", label = "Pets" }, { key = "u4", label = "Recipes" }, { key = "u6", label = "Appearances" } };
	else
		list = {};
	end

	if ( not secDefs ) then
		secDefs = {};
		for _, c in ipairs(CAT_ORDER) do secDefs[#secDefs + 1] = { key = c, label = CAT_LABEL[c] }; end
	end
	local counts = {};
	local total, got = 0, 0;
	for _, e in ipairs(list) do
		local c = counts[e.section] or { total = 0, got = 0 };
		counts[e.section] = c;
		c.total = c.total + 1;
		total = total + 1;
		if ( e.collected ) then c.got = c.got + 1; got = got + 1; end
	end
	local secs = { { key = "all", label = "All", total = total, got = got } };
	for _, s in ipairs(secDefs) do
		local c = counts[s.key];
		if ( c ) then secs[#secs + 1] = { key = s.key, label = s.label, total = c.total, got = c.got }; end
	end
	return list, secs, total, got;
end

local function RebuildAll(onlyKind)
	for _, k in ipairs(IMPLEMENTED) do
		if ( LAZY[k] and state.kind ~= k ) then
			cache[k] = nil;
		elseif ( not onlyKind or onlyKind == k or not cache[k] or (k == 7 and UNOB_SOURCES[onlyKind]) ) then
			local list, secs, total, got = MakeKind(k);
			cache[k] = { entries = list, sections = secs, total = total, got = got };
		end
	end
	local c = cache[state.kind];
	entries, sections = c and c.entries or {}, c and c.sections or { { key = "all", label = "All", total = 0, got = 0 } };
end

-- ===========================================================================
-- Server sync
-- ===========================================================================

local function RequestKind(kind)
	state.seq = state.seq + 1;
	SendAddonMessage(PREFIX, format("Q;%d;%d", state.seq, kind), "WHISPER", UnitName("player"));
end

local function RequestRewards()
	state.seq = state.seq + 1;
	state.rewardSeq = state.seq;
	SendAddonMessage(PREFIX, format("W;%d", state.seq), "WHISPER", UnitName("player"));
end

-- ===========================================================================
-- Window
-- ===========================================================================

local frame = CreateFrame("Frame", "RazagathCollectionFrame", UIParent);
frame:SetSize(860, 606);
frame:SetPoint("CENTER");
frame:SetFrameStrata("HIGH");
frame:SetMovable(true);
frame:EnableMouse(true);
frame:RegisterForDrag("LeftButton");
frame:SetScript("OnDragStart", function(self) self:StartMoving(); end);
frame:SetScript("OnDragStop", function(self) self:StopMovingOrSizing(); end);
frame:Hide();
tinsert(UISpecialFrames, "RazagathCollectionFrame");

local baseLevel = frame:GetFrameLevel();
local BIG, SMALL = 75, 32;

-- Tiled background built from plain textures. The engine's backdrop tiling smeared everything past the first tile row into vertical streaks, so each tile is
-- placed by hand (the last row / column is cropped with texture coordinates, never stretched).
local function TileBackground(parent, file, tile, tint)
	parent.tiles = {};
	local function layout()
		local w, h = parent:GetWidth(), parent:GetHeight();
		if ( not w or not h or w < 1 or h < 1 ) then return; end
		local cols, rows = math.ceil(w / tile), math.ceil(h / tile);
		local n = 0;
		for ty = 0, rows - 1 do
			for tx = 0, cols - 1 do
				n = n + 1;
				local t = parent.tiles[n];
				if ( not t ) then
					t = parent:CreateTexture(nil, "BACKGROUND");
					t:SetTexture(file);
					if ( tint ) then t:SetVertexColor(tint[1], tint[2], tint[3]); end
					parent.tiles[n] = t;
				end
				local sw, sh = math.min(tile, w - tx * tile), math.min(tile, h - ty * tile);
				t:ClearAllPoints();
				t:SetPoint("TOPLEFT", parent, "TOPLEFT", tx * tile, -ty * tile);
				t:SetSize(sw, sh);
				t:SetTexCoord(0, sw / tile, 0, sh / tile);
				t:Show();
			end
		end
		for i = n + 1, #parent.tiles do parent.tiles[i]:Hide(); end
	end
	parent:SetScript("OnSizeChanged", layout);
	parent.TileLayout = layout;
end

local bgFrame = CreateFrame("Frame", nil, frame);
bgFrame:SetPoint("TOPLEFT", 2, -21);
bgFrame:SetPoint("BOTTOMRIGHT", -2, 2);
-- the rock texture is 1024x1024: drawn at 512 so the grain keeps a natural size
TileBackground(bgFrame, CPATH.."UI-Background-Rock", 512);

local chrome = CreateFrame("Frame", nil, frame);
chrome:SetAllPoints(frame);
chrome:SetFrameLevel(baseLevel + 20);

local function ChromeTexture(file)
	local t = chrome:CreateTexture(nil, "ARTWORK");
	t:SetTexture(CPATH..file);
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
title:SetText("Collection Log");

local closeButton = CreateFrame("Button", nil, frame);
closeButton:SetSize(24, 24);
closeButton:SetPoint("TOPRIGHT", 3, -1);
closeButton:SetFrameLevel(baseLevel + 21);
SetButtonAtlas(closeButton, "Normal", "RedButton-Exit");
SetButtonAtlas(closeButton, "Pushed", "RedButton-Exit-Pressed");
SetButtonAtlas(closeButton, "Disabled", "RedButton-Exit-Disabled");
SetButtonAtlas(closeButton, "Highlight", "RedButton-Highlight", "ADD");
closeButton:SetScript("OnClick", function() frame:Hide(); end);

local portraitFrame = CreateFrame("Frame", nil, frame);
portraitFrame:SetSize(56, 56);
portraitFrame:SetPoint("CENTER", frame, "TOPLEFT", 25, -22);
portraitFrame:SetFrameLevel(baseLevel + 2);
local portraitIcon = portraitFrame:CreateTexture(nil, "ARTWORK");
portraitIcon:SetAllPoints();
if ( SetPortraitToTexture ) then SetPortraitToTexture(portraitIcon, ADDON_ICON); else portraitIcon:SetTexture(ADDON_ICON); end

-- Retail InsetFrameTemplate: marble background + 8-piece inner border
local function CreateInset(parent, tint)
	local f = CreateFrame("Frame", nil, parent);
	TileBackground(f, CPATH.."Files\\UI-Background-Marble", 256, tint);
	local function piece(name)
		local t = f:CreateTexture(nil, "BORDER");
		SetAtlas(t, name);
		if ( tint ) then t:SetVertexColor(tint[1], tint[2], tint[3]); end
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

local INSET_H = 400;
local leftInset = CreateInset(frame);
leftInset:SetSize(206, INSET_H);
leftInset:SetPoint("TOPLEFT", 4, -60);
local midInset = CreateInset(frame);
midInset:SetSize(396, INSET_H);
midInset:SetPoint("TOPLEFT", 214, -60);
local rightInset = CreateInset(frame);
rightInset:SetSize(236, INSET_H);
rightInset:SetPoint("TOPLEFT", 614, -60);
local rewardInset = CreateInset(frame);
rewardInset:SetSize(846, 130);
rewardInset:SetPoint("TOPLEFT", 4, -466);

-- ---------------------------------------------------------------------------
-- Header: total + section progress bars, search
-- ---------------------------------------------------------------------------

local function CreateBar(width, r, g, b)
	local bar = CreateFrame("StatusBar", nil, frame);
	bar:SetSize(width, 14);
	bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar");
	bar:SetStatusBarColor(r, g, b);
	bar:SetMinMaxValues(0, 1);
	bar:SetFrameLevel(baseLevel + 3);
	local bg = bar:CreateTexture(nil, "BACKGROUND");
	bg:SetAllPoints();
	bg:SetTexture(0, 0, 0, 0.6);
	local edge = CreateFrame("Frame", nil, bar);
	edge:SetPoint("TOPLEFT", -2, 2); edge:SetPoint("BOTTOMRIGHT", 2, -2);
	edge:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10 });
	edge:SetBackdropBorderColor(0.6, 0.5, 0.2);
	bar.text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	bar.text:SetPoint("CENTER");
	bar.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	bar.label:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, 2);
	return bar;
end

local totalBar = CreateBar(250, 0.2, 0.7, 0.25);
totalBar:SetPoint("TOPLEFT", 76, -42);
totalBar.label:SetText("Total completion");
local sectionBar = CreateBar(250, 0.25, 0.5, 0.85);
sectionBar:SetPoint("LEFT", totalBar, "RIGHT", 24, 0);

local searchBox = CreateFrame("EditBox", "RazagathCollectionSearch", frame, "InputBoxTemplate");
searchBox:SetSize(150, 20);
searchBox:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -22, -34);
searchBox:SetAutoFocus(false);
searchBox:SetFrameLevel(baseLevel + 3);
local searchHint = searchBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
searchHint:SetPoint("LEFT", 2, 0);
searchHint:SetText("Search");

-- ---------------------------------------------------------------------------
-- Left: sections
-- ---------------------------------------------------------------------------

local secScroll = CreateFrame("ScrollFrame", "RazagathCollectionSecScroll", leftInset, "UIPanelScrollFrameTemplate");
secScroll:SetPoint("TOPLEFT", 6, -6);
secScroll:SetPoint("BOTTOMRIGHT", -26, 6);
local secChild = CreateFrame("Frame", nil, secScroll);
secChild:SetSize(172, 10);
secScroll:SetScrollChild(secChild);
local secRows = {};
local SEC_H = 22;

local function SectionRow(i)
	local r = secRows[i];
	if ( r ) then return r; end
	r = CreateFrame("Button", nil, secChild);
	r:SetSize(172, SEC_H);
	r:SetPoint("TOPLEFT", 0, -(i - 1) * SEC_H);
	r.label = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	r.label:SetPoint("LEFT", 6, 0);
	r.label:SetJustifyH("LEFT");
	r.label:SetWidth(112);
	r.count = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	r.count:SetPoint("RIGHT", -6, 0);
	r.count:SetJustifyH("RIGHT");
	r.sel = r:CreateTexture(nil, "BACKGROUND");
	r.sel:SetAllPoints();
	r.sel:SetTexture(1, 0.82, 0, 0.18);
	r:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");
	r:SetScript("OnClick", function(self)
		state.section = self.key;
		RazagathCollection_Refresh(false);
	end);
	secRows[i] = r;
	return r;
end

-- ---------------------------------------------------------------------------
-- Middle: filters + grid
-- ---------------------------------------------------------------------------

local filterButtons = {};
local function CreateFilter(key, text, x)
	local b = CreateFrame("Button", nil, midInset);
	b:SetSize(70, 20);
	b:SetPoint("TOPLEFT", x, -6);
	b:SetNormalFontObject(GameFontNormalSmall);
	b:SetHighlightFontObject(GameFontHighlightSmall);
	b:SetText(text);
	b.bg = b:CreateTexture(nil, "BACKGROUND");
	b.bg:SetAllPoints();
	b.bg:SetTexture(1, 0.82, 0, 0.2);
	b:SetScript("OnClick", function() state.filter = key; RazagathCollection_Refresh(false); end);
	b.key = key;
	filterButtons[#filterButtons + 1] = b;
	return b;
end
CreateFilter("all", "All", 8);
CreateFilter("got", "Collected", 82);
CreateFilter("missing", "Missing", 156);

local gridCount = midInset:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
gridCount:SetPoint("TOPRIGHT", -10, -10);

local gridScroll = CreateFrame("ScrollFrame", "RazagathCollectionGridScroll", midInset, "UIPanelScrollFrameTemplate");
gridScroll:SetPoint("TOPLEFT", 6, -32);
gridScroll:SetPoint("BOTTOMRIGHT", -26, 6);
local gridChild = CreateFrame("Frame", nil, gridScroll);
gridChild:SetSize(360, 10);
gridScroll:SetScrollChild(gridChild);
local cells = {};
local CELL, GAP, COLS = 44, 8, 7;

local function ShowEntryTooltip(self)
	local e = self.entry;
	if ( not e ) then return; end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
	GameTooltip:SetText(e.name, 1, 1, 1);
	if ( e.collected ) then
		GameTooltip:AddLine("Collected", 0.2, 1, 0.2);
	else
		GameTooltip:AddLine("Not collected", 1, 0.3, 0.3);
	end
	if ( e.kind == 3 ) then
		if ( e.desc and e.desc ~= "" ) then GameTooltip:AddLine(e.desc, 0.9, 0.9, 0.9, 1); end
		if ( e.points and e.points > 0 ) then GameTooltip:AddLine(e.points.." points", 1, 0.82, 0); end
	elseif ( e.src ) then
		for i = 1, math.min(#e.src, 3) do GameTooltip:AddLine(e.src[i].x, 0.8, 0.8, 0.8, 1); end
	end
	GameTooltip:Show();
end

local function Cell(i)
	local c = cells[i];
	if ( c ) then return c; end
	c = CreateFrame("Button", nil, gridChild);
	c:SetSize(CELL, CELL);
	c.icon = c:CreateTexture(nil, "ARTWORK");
	c.icon:SetPoint("TOPLEFT", 3, -3);
	c.icon:SetPoint("BOTTOMRIGHT", -3, 3);
	c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93);
	c.border = CreateFrame("Frame", nil, c);
	c.border:SetAllPoints();
	c.border:SetBackdrop({ edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 12 });
	c.sel = c:CreateTexture(nil, "OVERLAY");
	c.sel:SetPoint("TOPLEFT", -2, 2);
	c.sel:SetPoint("BOTTOMRIGHT", 2, -2);
	c.sel:SetTexture("Interface\\Buttons\\CheckButtonHilight");
	c.sel:SetBlendMode("ADD");
	c.sel:Hide();
	c:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	c:SetScript("OnClick", function(self) state.selected = self.entry; RazagathCollection_Refresh(false); end);
	c:SetScript("OnEnter", ShowEntryTooltip);
	c:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	cells[i] = c;
	return c;
end

-- ---------------------------------------------------------------------------
-- Right: detail (3D preview for mounts / pets, big icon for achievements)
-- ---------------------------------------------------------------------------

-- A creature the client has never seen has no model to show; asking for its tooltip makes the server send it, after which SetCreature works.
local cacheTip = CreateFrame("GameTooltip", "RazagathCollectionCacheTip", UIParent, "GameTooltipTemplate");
cacheTip:SetOwner(UIParent, "ANCHOR_NONE");
local function CacheCreature(entry)
	-- same unit-GUID hyperlink the _NPCScan add-on uses to make the server send a creature the client has never seen
	if ( entry and entry > 0 and entry < 0x100000 ) then
		cacheTip:SetOwner(UIParent, "ANCHOR_NONE");
		pcall(cacheTip.SetHyperlink, cacheTip, format("unit:0xF5300%05X000000", entry));
		pcall(cacheTip.SetHyperlink, cacheTip, format("unit:0xF1300%05X000000", entry));
	end
end

local model = CreateFrame("PlayerModel", "RazagathCollectionModel", rightInset);
model:SetSize(224, 170);
model:SetPoint("TOP", 0, -8);
RazagathFreeCam(model);
local noPreview = rightInset:CreateFontString("RazagathCollectionNoPreview", "OVERLAY", "GameFontDisableSmall");
noPreview:SetPoint("CENTER", model, "CENTER");
noPreview:SetText("No preview available");
noPreview:Hide();

local function ModelLoaded()
	return model.loaded or type(model:GetModel()) == "string";
end

-- Ask for the creature, give the server time to send it if the client has never seen it, ask again; as a last resort show the bare model file.
local function StartModel(e)
	model:ClearModel();
	model:SetModelScale(1);
	model:ResetView();
	model:Settle(1.2);
	model.entry = e;
	model.attempt = 0;
	model.loaded = false;
	model.check = 0;
	noPreview:Hide();
end

model:SetScript("OnUpdateModel", function(self)
	self.loaded = true;
	self:ApplyView();
	self:Settle(0.5);
	noPreview:Hide();
end);
model:SetScript("OnUpdate", function(self, elapsed)
	if ( self.check and self.entry ) then
		self.check = self.check - elapsed;
		if ( self.check <= 0 ) then
			local e = self.entry;
			if ( self.attempt > 0 and ModelLoaded() ) then
				self.check = nil;
				noPreview:Hide();
			elseif ( self.attempt < 6 ) then
				self.attempt = self.attempt + 1;
				CacheCreature(e.cr);
				self:SetCreature(e.cr or 0);
				self:Settle(1.2);
				self.check = 0.7;
			else
				self.check = nil;
				if ( e.mp and e.mp ~= "" ) then
					self:ClearModel();
					self:SetModel(e.mp);
					self:Settle(1.2);
				end
				SetShownCompat(noPreview, not ModelLoaded());
			end
		end
	end
end);

local bigIcon = rightInset:CreateTexture(nil, "ARTWORK");
bigIcon:SetSize(64, 64);
bigIcon:SetPoint("TOP", 0, -50);
bigIcon:Hide();

local detailName = rightInset:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge");
detailName:SetPoint("TOP", model, "BOTTOM", 0, -4);
detailName:SetWidth(216);
detailName:SetJustifyH("CENTER");
local detailStatus = rightInset:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
detailStatus:SetPoint("TOP", detailName, "BOTTOM", 0, -2);

local itemRow = {};
local function ItemButton(i)
	local b = itemRow[i];
	if ( b ) then return b; end
	b = CreateFrame("Button", nil, rightInset);
	b:SetSize(26, 26);
	b:SetPoint("TOPLEFT", rightInset, "TOPLEFT", 10 + (i - 1) * 30, -252);
	b.icon = b:CreateTexture(nil, "ARTWORK");
	b.icon:SetAllPoints();
	b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93);
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
		GameTooltip:SetHyperlink("item:"..self.itemId);
		GameTooltip:Show();
	end);
	b:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	b:SetScript("OnClick", function(self)
		if ( IsModifiedClick("CHATLINK") ) then
			local _, link = GetItemInfo(self.itemId);
			if ( link ) then ChatEdit_InsertLink(link); end
		end
	end);
	itemRow[i] = b;
	return b;
end

-- source lines: one button per line so achievement / quest lines can be clicked
local srcScroll = CreateFrame("ScrollFrame", "RazagathCollectionSrcScroll", rightInset, "UIPanelScrollFrameTemplate");
srcScroll:SetPoint("TOPLEFT", 8, -284);
srcScroll:SetPoint("BOTTOMRIGHT", -28, 8);
local srcChild = CreateFrame("Frame", nil, srcScroll);
srcChild:SetSize(196, 10);
srcScroll:SetScrollChild(srcChild);
local srcLines = {};

local function OpenAchievement(id)
	if ( not AchievementFrame ) then AchievementFrame_LoadUI(); end
	if ( AchievementFrame and not AchievementFrame:IsShown() ) then ShowUIPanel(AchievementFrame); end
	if ( AchievementFrame_SelectAchievement ) then AchievementFrame_SelectAchievement(id); end
end

local function SourceLine(i)
	local b = srcLines[i];
	if ( b ) then return b; end
	b = CreateFrame("Button", nil, srcChild);
	b:SetWidth(196);
	b.fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	b.fs:SetPoint("TOPLEFT");
	b.fs:SetWidth(196);
	b.fs:SetJustifyH("LEFT");
	b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD");
	b:SetScript("OnEnter", function(self)
		if ( self.ach ) then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT");
			GameTooltip:SetHyperlink("achievement:"..self.ach..":"..strsub(UnitGUID("player"), 3)..":0:0:0:0:0:0:0:0");
			GameTooltip:AddLine("|cff71d5ffClick to open in the Achievements window|r");
			GameTooltip:Show();
		elseif ( self.quest ) then
			GameTooltip:SetOwner(self, "ANCHOR_LEFT");
			GameTooltip:SetHyperlink("quest:"..self.quest..":"..(self.qlevel or 0));
			GameTooltip:Show();
		end
	end);
	b:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	b:SetScript("OnClick", function(self)
		if ( self.ach ) then OpenAchievement(self.ach); end
	end);
	srcLines[i] = b;
	return b;
end

local function SetSourceLines(lines)
	local y = 0;
	for i, l in ipairs(lines) do
		local b = SourceLine(i);
		b.ach, b.quest, b.qlevel = l.a, l.q, l.ql;
		local text = "|cffffd100-|r "..l.x;
		if ( l.a ) then
			local name = select(2, GetAchievementInfo(l.a));
			text = text..(name and (" |cff71d5ff["..name.."]|r") or "");
		end
		b.fs:SetText(text);
		local h = b.fs:GetStringHeight() + 6;
		b:SetHeight(h);
		b:ClearAllPoints();
		b:SetPoint("TOPLEFT", srcChild, "TOPLEFT", 0, -y);
		b:EnableMouse((l.a or l.q) and true or false);
		b:Show();
		y = y + h;
	end
	for i = #lines + 1, #srcLines do srcLines[i]:Hide(); end
	srcChild:SetHeight(math.max(10, y));
	srcScroll:SetVerticalScroll(0);
end

-- recipes that make wearable gear show the item on YOUR character (DressUpModel), everything else a big icon
local dressModel = CreateFrame("DressUpModel", "RazagathCollectionDress", rightInset);
dressModel:SetSize(224, 170);
dressModel:SetPoint("TOP", 0, -8);
dressModel:Hide();
RazagathFreeCam(dressModel);
dressModel:SetScript("OnUpdateModel", function(self) self:ApplyView(); self:Settle(0.5); end);

-- "about 1 in N crafts" for a discovery line, from the realm's real chance (the server sends it)
local function DiscoveryText(spell)
	local pct = discChance[spell];
	if ( not pct or pct <= 0 ) then return ""; end
	local n = math.floor(100 / pct + 0.5);
	return format(" - %s%% per craft (about 1 in %d)", pct >= 1 and format("%.1f", pct) or format("%.3f", pct), n);
end

local function ShowDetail()
	local e = state.selected;
	for _, b in ipairs(itemRow) do b:Hide(); end
	if ( not e ) then
		model:Hide(); bigIcon:Hide(); noPreview:Hide(); dressModel:Hide();
		model.entry, model.check = nil, nil;
		detailName:SetText("");
		detailStatus:SetText("");
		SetSourceLines({ { x = "Select an entry to see its preview and where to get it." } });
		return;
	end

	detailName:SetText(e.name);
	detailStatus:SetText(e.collected and "|cff33ff33Collected|r" or "|cffff5555Not collected|r");

	if ( e.kind == 4 or e.kind == 5 or e.kind == 6 ) then
		model:Hide(); noPreview:Hide();
		model.entry, model.check = nil, nil;
		if ( e.eq and e.itemId and e.itemId > 0 ) then
			bigIcon:Hide();
			dressModel:Show();
			dressModel:SetUnit("player");
			dressModel:Undress();
			dressModel:ResetView();
			dressModel:TryOn("item:"..e.itemId);
			dressModel:Settle(1.2);
		else
			dressModel:Hide();
			bigIcon:SetTexture(e.icon);
			bigIcon:Show();
		end
		local lines, seen = {}, {};
		if ( e.sk and e.sk > 1 ) then lines[#lines + 1] = { x = "|cffffd100Skill required:|r "..(e.prof and e.prof:gsub("^%l", string.upper) or "").." "..e.sk }; end
		for _, s in ipairs(e.src or {}) do
			if ( not seen[s.x] ) then
				seen[s.x] = true;
				lines[#lines + 1] = { x = s.x..(s.dc and DiscoveryText(e.spell) or ""), q = s.q, ql = s.ql };
			end
		end
		if ( e.kind == 6 ) then
			if ( #lines == 0 ) then lines[1] = { x = "|cff9d9d9dNo known source - this look cannot currently be obtained.|r" }; end
			if ( not e.collected ) then lines[#lines + 1] = { x = "|cff9d9d9dUnlocks for good the first time you pick up any item with this look.|r" }; end
			SetSourceLines(lines);
			for i, it in ipairs(e.items or {}) do
				if ( i > 7 ) then break; end
				local b = ItemButton(i);
				b.itemId = it.id;
				b.icon:SetTexture(GetItemIcon(it.id) or "Interface\\Icons\\INV_Misc_QuestionMark");
				b:Show();
			end
			return;
		end
		if ( #lines == 0 ) then lines[1] = { x = "|cff9d9d9dNo known source.|r" }; end
		SetSourceLines(lines);
		local shownItems = 0;
		if ( e.itemId and e.itemId > 0 ) then
			shownItems = shownItems + 1;
			local b = ItemButton(shownItems);
			b.itemId = e.itemId;
			b.icon:SetTexture(GetItemIcon(e.itemId) or "Interface\\Icons\\INV_Misc_QuestionMark");
			b:Show();
		end
		local itemSeen = {};
		for _, s in ipairs(e.src or {}) do
			if ( s.i and not itemSeen[s.i] and shownItems < 7 ) then
				itemSeen[s.i] = true;
				shownItems = shownItems + 1;
				local b = ItemButton(shownItems);
				b.itemId = s.i;
				b.icon:SetTexture(GetItemIcon(s.i) or "Interface\\Icons\\INV_Misc_QuestionMark");
				b:Show();
			end
		end
		return;
	end
	dressModel:Hide();

	if ( e.kind == 3 ) then
		model:Hide(); noPreview:Hide();
		model.entry, model.check = nil, nil;
		bigIcon:SetTexture(e.icon);
		bigIcon:Show();
		local lines = {};
		if ( e.desc and e.desc ~= "" ) then lines[#lines + 1] = { x = e.desc }; end
		if ( e.points and e.points > 0 ) then lines[#lines + 1] = { x = "|cffffd100"..e.points.." achievement points|r" }; end
		if ( e.reward and e.reward ~= "" ) then lines[#lines + 1] = { x = "|cff33ff33Reward: "..e.reward.."|r" }; end
		if ( e.localDone and e.date ) then lines[#lines + 1] = { x = "Earned on this character: "..e.date }; end
		if ( e.collected and not e.localDone ) then lines[#lines + 1] = { x = "|cff9d9d9dEarned by another character on your account.|r" }; end
		SetSourceLines(lines);
	else
		bigIcon:Hide();
		model:Show();
		if ( not model.entry or model.entry.cr ~= e.cr or model.entry.name ~= e.name ) then StartModel(e); else model.entry = e; end

		local lines, seen = {}, {};
		for _, s in ipairs(e.src or {}) do
			if ( not seen[s.x] ) then seen[s.x] = true; lines[#lines + 1] = s; end
		end
		if ( #lines == 0 ) then lines[1] = { x = "|cff9d9d9dNo known source.|r" }; end
		SetSourceLines(lines);

		for i, it in ipairs(e.items or {}) do
			if ( i > 7 ) then break; end
			local b = ItemButton(i);
			b.itemId = it.id;
			b.icon:SetTexture(GetItemIcon(it.id) or "Interface\\Icons\\INV_Misc_QuestionMark");
			b:Show();
		end
	end
end

-- ---------------------------------------------------------------------------
-- Bottom: rewards for the section on screen
-- ---------------------------------------------------------------------------

local rewardTitle = rewardInset:CreateFontString(nil, "OVERLAY", "GameFontNormal");
rewardTitle:SetPoint("TOPLEFT", 12, -10);
rewardTitle:SetText("Rewards");
local rewardHint = rewardInset:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall");
rewardHint:SetPoint("TOPRIGHT", -12, -12);
rewardHint:SetText("Complete a section to unlock its reward. Rewards are claimed once per account and arrive by mail.");
local rewardEmpty = rewardInset:CreateFontString(nil, "OVERLAY", "GameFontHighlight");
rewardEmpty:SetPoint("CENTER", 0, -8);
rewardEmpty:SetText("|cff9d9d9dNo rewards for this section yet.|r");
rewardEmpty:Hide();

local cards = {};
local CARD_W, CARD_H = 200, 78;

local function RewardIcon(r)
	if ( r.rtype == "item" ) then return GetItemIcon(r.rid) or "Interface\\Icons\\INV_Misc_QuestionMark"; end
	if ( r.rtype == "gold" ) then return "Interface\\Icons\\INV_Misc_Coin_01"; end
	if ( r.rtype == "title" ) then return "Interface\\Icons\\INV_Scroll_01"; end
	local _, _, icon = GetSpellInfo(r.rid);
	return icon or "Interface\\Icons\\INV_Misc_QuestionMark";
end

local function Card(i)
	local c = cards[i];
	if ( c ) then return c; end
	c = CreateFrame("Frame", nil, rewardInset);
	c:SetSize(CARD_W, CARD_H);
	c:SetPoint("TOPLEFT", 12 + (i - 1) * (CARD_W + 8), -34);
	c:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 12,
		insets = { left = 3, right = 3, top = 3, bottom = 3 } });
	c:SetBackdropColor(0, 0, 0, 0.55);
	c.icon = c:CreateTexture(nil, "ARTWORK");
	c.icon:SetSize(34, 34);
	c.icon:SetPoint("TOPLEFT", 8, -8);
	c.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93);
	c.scope = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	c.scope:SetPoint("TOPLEFT", c.icon, "TOPRIGHT", 6, 0);
	c.scope:SetWidth(CARD_W - 60);
	c.scope:SetJustifyH("LEFT");
	c.desc = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
	c.desc:SetPoint("TOPLEFT", c.scope, "BOTTOMLEFT", 0, -2);
	c.desc:SetWidth(CARD_W - 60);
	c.desc:SetJustifyH("LEFT");
	c.status = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
	c.status:SetPoint("BOTTOMLEFT", 10, 8);
	c.claim = CreateFrame("Button", nil, c, "UIPanelButtonTemplate");
	c.claim:SetSize(70, 22);
	c.claim:SetPoint("BOTTOMRIGHT", -8, 6);
	c.claim:SetText("Claim");
	c.claim:SetScript("OnClick", function(self)
		local r = self:GetParent().reward;
		if ( r and r.state == 1 ) then
			self:Disable();
			state.seq = state.seq + 1;
			SendAddonMessage(PREFIX, format("G;%d;%d", state.seq, r.id), "WHISPER", UnitName("player"));
		end
	end);
	c:EnableMouse(true);
	c:SetScript("OnEnter", function(self)
		local r = self.reward;
		if ( not r ) then return; end
		GameTooltip:SetOwner(self, "ANCHOR_TOP");
		if ( r.rtype == "item" ) then
			GameTooltip:SetHyperlink("item:"..r.rid);
		else
			GameTooltip:SetText(r.desc, 1, 1, 1);
		end
		GameTooltip:Show();
	end);
	c:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	cards[i] = c;
	return c;
end

local function ScopeLabel(r)
	if ( r.scope == "overall" ) then return "Complete the whole log"; end
	if ( r.scope == "tab" ) then return "Complete all "..(KINDS[r.kind] and KINDS[r.kind].label or "entries"); end
	local label = r.section;
	for _, k in ipairs(IMPLEMENTED) do
		if ( k == r.kind and cache[k] ) then
			for _, s in ipairs(cache[k].sections) do if ( s.key == r.section ) then label = s.label; end end
		end
	end
	return (KINDS[r.kind] and KINDS[r.kind].label or "").." - "..label;
end

local function RefreshRewards()
	local list = {};
	for _, id in ipairs(rewardOrder) do
		local r = rewards[id];
		local relevant;
		if ( r.scope == "overall" ) then relevant = true;
		elseif ( r.scope == "tab" ) then relevant = ( r.kind == state.kind );
		elseif ( r.kind == state.kind ) then relevant = ( state.section == "all" and r.state == 1 ) or ( r.section == state.section );
		end
		if ( relevant ) then list[#list + 1] = r; end
	end
	-- the section's own reward first, then the tab, then the whole log
	local order = { section = 1, tab = 2, overall = 3 };
	sort(list, function(a, b) if ( order[a.scope] ~= order[b.scope] ) then return order[a.scope] < order[b.scope]; end return a.id < b.id; end);
	for i = 1, math.min(#list, 4) do
		local r = list[i];
		local c = Card(i);
		c.reward = r;
		c.icon:SetTexture(RewardIcon(r));
		c.scope:SetText(ScopeLabel(r));
		c.desc:SetText(r.desc);
		if ( r.state == 2 ) then
			c.status:SetText("|cff9d9d9dClaimed|r"); c.claim:Hide(); c.icon:SetDesaturated(true);
		elseif ( r.state == 1 ) then
			c.status:SetText("|cff33ff33Ready!|r"); c.claim:Show(); c.claim:Enable(); c.icon:SetDesaturated(false);
		else
			c.status:SetText("|cffff7777Locked|r"); c.claim:Hide(); c.icon:SetDesaturated(true);
		end
		c:Show();
	end
	for i = #list + 1, #cards do cards[i].reward = nil; cards[i]:Hide(); end
	SetShownCompat(rewardEmpty, #list == 0);
end

-- ---------------------------------------------------------------------------
-- Tabs (retail PanelTabButtonTemplate: uiframe-tab-* atlases, same as Companions)
-- ---------------------------------------------------------------------------

local tabs = {};
local function CreateTab(k, anchorTo, x)
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
	label:SetText(k.label);
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
	function b:SetTabSelected(selected)
		for _, t in ipairs(self.active) do SetShownCompat(t, selected); end
		for _, t in ipairs(self.inactive) do SetShownCompat(t, not selected); end
		self.label:SetFontObject(selected and GameFontHighlightSmall or GameFontNormalSmall);
		self.label:ClearAllPoints();
		self.label:SetPoint("CENTER", 0, selected and 0 or 2);
	end
	if ( k.soon ) then
		label:SetTextColor(0.5, 0.5, 0.5);
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP");
			GameTooltip:SetText(k.label);
			GameTooltip:AddLine("Coming soon.", 0.8, 0.8, 0.8);
			GameTooltip:Show();
		end);
		b:SetScript("OnLeave", function() GameTooltip:Hide(); end);
	else
		b:SetScript("OnClick", function()
			state.kind = k.id; DB.kind = k.id;
			state.section, state.selected, state.search = "all", nil, "";
			searchBox:SetText("");
			RazagathCollection_Refresh(true);
		end);
	end
	b.kind = k.id;
	return b;
end
do
	local prev = frame;
	for i, k in ipairs(KINDS) do
		prev = CreateTab(k, prev, i == 1 and 11 or 4);
		tabs[#tabs + 1] = prev;
	end
end

-- ---------------------------------------------------------------------------
-- Refresh
-- ---------------------------------------------------------------------------

-- The grid is virtual: a recipe tab has thousands of entries, so only the rows that are on screen (plus a spare) get a button, and the buttons are reused as the
-- list scrolls. Nothing is created or talked to the server while scrolling.
local function RenderGrid()
	local rowH = CELL + GAP;
	local first = math.max(0, math.floor((gridScroll:GetVerticalScroll() - 6) / rowH));
	local viewRows = math.ceil((gridScroll:GetHeight() or 400) / rowH) + 2;
	local base = first * COLS;
	local used = 0;
	for j = 1, viewRows * COLS do
		local e = shown[base + j];
		if ( not e ) then break; end
		used = j;
		local cell = Cell(j);
		local col, row = (j - 1) % COLS, first + math.floor((j - 1) / COLS);
		if ( cell.px ~= col or cell.py ~= row ) then
			cell.px, cell.py = col, row;
			cell:ClearAllPoints();
			cell:SetPoint("TOPLEFT", gridChild, "TOPLEFT", 6 + col * rowH, -(6 + row * rowH));
		end
		if ( cell.entry ~= e or cell.stateCollected ~= e.collected ) then
			cell.entry, cell.stateCollected = e, e.collected;
			cell.icon:SetTexture(e.icon);
			cell.icon:SetDesaturated(not e.collected);
			if ( e.collected ) then
				cell.icon:SetVertexColor(1, 1, 1);
				cell.border:SetBackdropBorderColor(1, 0.82, 0);
			else
				cell.icon:SetVertexColor(0.45, 0.45, 0.45);
				cell.border:SetBackdropBorderColor(0.4, 0.4, 0.4);
			end
		end
		SetShownCompat(cell.sel, state.selected == e);
		cell:Show();
	end
	for j = used + 1, #cells do cells[j]:Hide(); end
end
gridScroll:HookScript("OnVerticalScroll", function() if ( frame:IsShown() ) then RenderGrid(); end end);
gridScroll:HookScript("OnSizeChanged", function() if ( frame:IsShown() ) then RenderGrid(); end end);

local function Passes(e)
	if ( state.section ~= "all" and e.section ~= state.section ) then return false; end
	if ( state.filter == "got" and not e.collected ) then return false; end
	if ( state.filter == "missing" and e.collected ) then return false; end
	if ( state.search ~= "" and not strfind(e.lname or (function() e.lname = strlower(e.name or ""); return e.lname; end)(), state.search, 1, true) ) then return false; end
	return true;
end

local function SetBar(bar, label, got, total)
	bar:SetMinMaxValues(0, math.max(total, 1));
	bar:SetValue(got);
	bar.text:SetText(format("%d / %d  (%d%%)", got, total, total > 0 and math.floor(got * 100 / total) or 0));
	bar.label:SetText(label);
end

function RazagathCollection_Refresh(rebuild)
	if ( not frame:IsShown() ) then return; end
	if ( rebuild ) then RebuildAll(type(rebuild) == "number" and rebuild or nil); end
	local c = cache[state.kind];
	entries, sections = c and c.entries or {}, c and c.sections or {};

	-- tabs
	for _, t in ipairs(tabs) do t:SetTabSelected(t.kind == state.kind); end

	-- header: total across every tab that exists, and the section on screen
	local total, got = 0, 0;
	for _, k in ipairs(IMPLEMENTED) do if ( cache[k] and not NOT_IN_TOTAL[k] ) then total = total + cache[k].total; got = got + cache[k].got; end end
	SetBar(totalBar, "Total completion", got, total);

	local present = false;
	for _, s in ipairs(sections) do if ( s.key == state.section ) then present = true; end end
	if ( not present ) then state.section = "all"; end
	local cur = sections[1];
	for _, s in ipairs(sections) do if ( s.key == state.section ) then cur = s; end end
	SetBar(sectionBar, KINDS[state.kind].label..(cur and cur.key ~= "all" and (" - "..cur.label) or " (all sections)"), cur and cur.got or 0, cur and cur.total or 0);

	-- sections
	for i, s in ipairs(sections) do
		local r = SectionRow(i);
		r.key = s.key;
		r.label:SetText(s.label);
		r.count:SetText(format("%d/%d", s.got, s.total));
		if ( s.got == s.total and s.total > 0 ) then r.count:SetTextColor(0.2, 1, 0.2); else r.count:SetTextColor(1, 1, 1); end
		SetShownCompat(r.sel, s.key == state.section);
		r:Show();
	end
	for i = #sections + 1, #secRows do secRows[i]:Hide(); end
	secChild:SetHeight(math.max(10, #sections * SEC_H));

	-- filters
	for _, b in ipairs(filterButtons) do SetShownCompat(b.bg, b.key == state.filter); end

	-- grid
	wipe(shown);
	for _, e in ipairs(entries) do if ( Passes(e) ) then shown[#shown + 1] = e; end end
	gridCount:SetText(format("%d shown", #shown));
	gridChild:SetHeight(math.max(10, math.ceil(#shown / COLS) * (CELL + GAP) + 12));
	RenderGrid();

	-- the selection may have been rebuilt: find its new copy
	if ( state.selected ) then
		local keep;
		for _, e in ipairs(entries) do
			if ( e.name == state.selected.name and e.kind == state.selected.kind and e.id == state.selected.id ) then keep = e; end
		end
		if ( keep ~= state.selected ) then
			if ( keep and keep.cr == state.selected.cr ) then keep.fromOld = true; end
			state.selected = keep;
		end
	end
	RefreshRewards();
	ShowDetail();
end

searchBox:SetScript("OnTextChanged", function(self)
	local t = strlower(self:GetText() or "");
	SetShownCompat(searchHint, t == "" and not self:HasFocus());
	if ( t ~= state.search ) then state.search = t; RazagathCollection_Refresh(false); end
end);
searchBox:SetScript("OnEditFocusGained", function() searchHint:Hide(); end);
searchBox:SetScript("OnEditFocusLost", function(self) SetShownCompat(searchHint, (self:GetText() or "") == ""); end);
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); end);

frame:SetScript("OnShow", function()
	for _, f in ipairs({ bgFrame, leftInset, midInset, rightInset, rewardInset }) do if ( f.TileLayout ) then f.TileLayout(); end end
	RefreshLocal();
	RequestKind(1); RequestKind(2); RequestKind(3); RequestKind(4); RequestKind(5); RequestKind(6);
	state.seq = state.seq + 1;
	SendAddonMessage(PREFIX, format("D;%d", state.seq), "WHISPER", UnitName("player"));
	RequestRewards();
	if ( not state.primed ) then
		-- have the server send the creature data for every mount / pet so the previews are textured (see PrimeCreatures in mod_collection_log.cpp)
		state.primed = true;
		state.seq = state.seq + 1;
		SendAddonMessage(PREFIX, format("P;%d", state.seq), "WHISPER", UnitName("player"));
	end
	RazagathCollection_Refresh(true);
end);

-- server replies + live changes
local ev = CreateFrame("Frame");
ev:RegisterEvent("CHAT_MSG_ADDON");
ev:RegisterEvent("COMPANION_LEARNED");
ev:RegisterEvent("ACHIEVEMENT_EARNED");
ev:SetScript("OnEvent", function(self, event, prefix, message)
	if ( event == "CHAT_MSG_ADDON" ) then
		if ( prefix ~= PREFIX or type(message) ~= "string" ) then return; end
		local t = strsub(message, 1, 1);
		if ( t == "L" or t == "E" ) then
			local _, seq, kind, ids = strsplit(";", message);
			kind = tonumber(kind);
			if ( not kind or not srv[kind] ) then return; end
			if ( t == "L" and ids ) then
				if ( not srvReady[kind.."pending"] ) then srvReady[kind.."pending"] = true; wipe(srv[kind]); end
				for id in string.gmatch(ids, "%d+") do srv[kind][tonumber(id)] = true; end
			else
				srvReady[kind.."pending"] = nil;
				srvReady[kind] = true;
				RazagathCollection_Refresh(kind);
			end
		elseif ( t == "R" ) then
			-- R;seq;id;state;scope;kind;section;rtype;rid;rcount;description
			local _, seq, id, st, scope, kind, section, rtype, rid, rcount, desc = strsplit(";", message);
			id = tonumber(id);
			if ( not id ) then return; end
			if ( tonumber(seq) ~= state.rewardSeq ) then return; end
			if ( not state.rewardsLoading ) then
				state.rewardsLoading = true; wipe(rewards); wipe(rewardOrder);
			end
			rewards[id] = { id = id, state = tonumber(st) or 0, scope = scope, kind = tonumber(kind) or 0, section = section, rtype = rtype,
				rid = tonumber(rid) or 0, rcount = tonumber(rcount) or 1, desc = desc or "" };
			rewardOrder[#rewardOrder + 1] = id;
		elseif ( t == "D" ) then
			-- D;seq;spell=pct|spell=pct|...  (effective chance in percent, already multiplied by the realm discovery rate)
			local _, seq, body = strsplit(";", message);
			for sp, pct in string.gmatch(body or "", "(%d+)=([%d%.]+)") do discChance[tonumber(sp)] = tonumber(pct); end
			if ( frame:IsShown() and state.selected and state.selected.kind == 5 ) then ShowDetail(); end
		elseif ( t == "P" ) then
			-- the creature data has arrived: draw the selected preview again, now with its skin
			if ( frame:IsShown() and model.entry and model:IsShown() ) then StartModel(model.entry); end
		elseif ( t == "X" ) then
			state.rewardsLoading = nil;
			if ( frame:IsShown() ) then RefreshRewards(); end
		elseif ( t == "G" ) then
			local _, seq, id, ok, reason = strsplit(";", message);
			if ( ok ~= "1" and reason ) then UIErrorsFrame:AddMessage("Collection Log: "..reason, 1, 0.3, 0.3); end
			RequestRewards();
		end
	else
		RefreshLocal();
		if ( frame:IsShown() ) then RazagathCollection_Refresh(true); RequestRewards(); end
	end
end);

function RazagathCollection_Toggle()
	if ( frame:IsShown() ) then frame:Hide(); else frame:Show(); end
end

-- ===========================================================================
-- Launcher button: retail's Adventure Guide micro-menu art, docked beside the Mounts & Pets button
-- ===========================================================================

local microButton = CreateFrame("Button", "RazagathCollectionMicroButton", UIParent);
microButton:SetSize(32, 41);
microButton:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -104, 8);
microButton:SetFrameStrata("MEDIUM");
microButton:SetMovable(true);
microButton:SetClampedToScreen(true);
SetButtonAtlas(microButton, "Normal", "ui-hud-micromenu-adventureguide-up-2x", nil, true);
SetButtonAtlas(microButton, "Pushed", "ui-hud-micromenu-adventureguide-down-2x", nil, true);
SetButtonAtlas(microButton, "Highlight", "ui-hud-micromenu-adventureguide-mouseover-2x", "ADD", true);
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
	if ( x and y ) then DB.microPos = { x, y }; end
end);
microButton:SetScript("OnClick", function() RazagathCollection_Toggle(); end);
microButton:SetScript("OnEnter", function(self)
	GameTooltip:SetOwner(self, "ANCHOR_LEFT");
	GameTooltip:SetText("Collection Log");
	GameTooltip:AddLine("Mounts, pets, achievements and more - account-wide.", 0.8, 0.8, 0.8, 1);
	GameTooltip:AddLine("Click to open. Shift-drag to move.", 0.6, 0.6, 0.6);
	GameTooltip:Show();
end);
microButton:SetScript("OnLeave", function() GameTooltip:Hide(); end);

BINDING_HEADER_RAZAGATHCOLLECTION = "Razagath Collection Log";
BINDING_NAME_RAZAGATHCOLLECTION_TOGGLE = "Toggle Collection Log";

SLASH_RAZAGATHCOLLECTION1 = "/clog";
SLASH_RAZAGATHCOLLECTION2 = "/collection";
SlashCmdList["RAZAGATHCOLLECTION"] = RazagathCollection_Toggle;

local setup = CreateFrame("Frame");
setup:RegisterEvent("PLAYER_LOGIN");
setup:SetScript("OnEvent", function()
	RazagathCompanionsDB = RazagathCompanionsDB or {};
	RazagathCompanionsDB.log = RazagathCompanionsDB.log or {};
	DB = RazagathCompanionsDB.log;                       -- the real (saved) table, not the one created before the saved variables were loaded
	state.kind = DB.kind or state.kind;
	local pos = DB.microPos;
	if ( pos ) then
		microButton:ClearAllPoints();
		microButton:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", pos[1], pos[2]);
	end
	RefreshLocal();
end);

-- shared frame helpers for the other Razagath windows (Wardrobe draws with the same chrome / insets)
RazagathUIKit = { TileBackground = TileBackground, CreateInset = CreateInset, SetAtlas = SetAtlas, SetButtonAtlas = SetButtonAtlas };
