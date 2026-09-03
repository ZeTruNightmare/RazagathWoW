--[[  Spell Blade UI  ------------------------------------------------------
  CLASS_SPELL_BLADE (10) is a real server class, but the stock 3.3.5a client
  has no entry for it in the FrameXML class tables. That makes any frame that
  looks a class up by token error on nil - most visibly the /who list
  (RAID_CLASS_COLORS[token].r), party/raid frames, the character sheet, and
  unit tooltips.

  This addon registers "SPELLBLADE" in every one of those tables at load. It
  can't ship as Interface\FrameXML\Constants.lua (ChromieCraft's client rejects
  glue/frame overrides) - an ordinary AddOn is the supported way in.
------------------------------------------------------------------------- ]]

local TOKEN = "SPELLBLADE"
local NAME  = "Spellblade"
local R, G, B = 126/255, 0/255, 199/255          -- #7E00C7

-- localized name (male + female)
for _, tbl in ipairs({ LOCALIZED_CLASS_NAMES_MALE, LOCALIZED_CLASS_NAMES_FEMALE }) do
    if tbl and not tbl[TOKEN] then tbl[TOKEN] = NAME end
end

-- class colour (used by /who, party frames, chat, LFG, tooltips, ...)
if RAID_CLASS_COLORS and not RAID_CLASS_COLORS[TOKEN] then
    RAID_CLASS_COLORS[TOKEN] = { r = R, g = G, b = B,
        colorStr = string.format("ff%02x%02x%02x", R * 255, G * 255, B * 255) }
end
if CUSTOM_CLASS_COLORS and not CUSTOM_CLASS_COLORS[TOKEN] then
    CUSTOM_CLASS_COLORS[TOKEN] = RAID_CLASS_COLORS[TOKEN]
end

-- class-icon atlas coords (row 4, col 1 of UI-CharacterCreate-Classes.blp,
-- which patch-enUS-Z.MPQ paints with the Spell Blade sword)
if CLASS_ICON_TCOORDS and not CLASS_ICON_TCOORDS[TOKEN] then
    CLASS_ICON_TCOORDS[TOKEN] = { 0, 0.25, 0.75, 1.0 }
end

-- sort order (class-grouped tooltips / raid sorting)
if CLASS_SORT_ORDER then
    local seen = false
    for _, v in ipairs(CLASS_SORT_ORDER) do if v == TOKEN then seen = true; break end end
    if not seen then
        table.insert(CLASS_SORT_ORDER, TOKEN)
        if CLASS_SORT_ORDER[TOKEN] == nil then CLASS_SORT_ORDER[TOKEN] = #CLASS_SORT_ORDER end
    end
end

if not _G["CLASS_" .. TOKEN] then
    _G["CLASS_" .. TOKEN] = NAME
end
