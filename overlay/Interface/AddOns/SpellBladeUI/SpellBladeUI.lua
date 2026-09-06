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

-- Dungeon Finder role buttons -------------------------------------------------
--  The stock 3.3.5a client's GetAvailableRoles() has no case for class 10, so
--  LFG_UpdateAvailableRoles() permanently disables every role button - and
--  SetLFGRoles() refuses class-10 roles too, so the stock mechanism is dead.
--  Instead: re-enable Healer + DPS (a Spellblade is a Shaman underneath - heals
--  or does damage, never tanks), track the checked state ourselves, and push the
--  choice to the server with the .lfgrole command (mod-razagath-classes) over
--  the addon-command channel. The server queues the Spellblade with that role.
local IsSpellblade = function() return select(2, UnitClass("player")) == TOKEN end

local roleWanted = { HEALER = true, DAMAGER = true }   -- default: both, matchmaker picks
local cmdSeq = 0

local function PushRoleToServer()
    local arg = (roleWanted.HEALER and roleWanted.DAMAGER) and "both"
             or roleWanted.HEALER and "heal"
             or roleWanted.DAMAGER and "dps"
             or "both"
    cmdSeq = (cmdSeq % 9999) + 1
    SendAddonMessage("AzerothCore", string.format("i%04dlfgrole %s", cmdSeq, arg), "WHISPER", UnitName("player"))
end

local ROLE_KEYS = { { LFDQueueFrameRoleButtonHealer, "HEALER" }, { LFDQueueFrameRoleButtonDPS, "DAMAGER" } }

local function SpellBladeRefreshLFGRoles()
    if not IsSpellblade() then return end
    for _, rk in ipairs(ROLE_KEYS) do
        local b, key = rk[1], rk[2]
        if b and type(LFG_EnableRoleButton) == "function" then
            LFG_EnableRoleButton(b)
            b.checkButton:SetChecked(roleWanted[key])
            if not b.__sbHooked then
                b.__sbHooked = true
                b.checkButton.onClick = function(self)
                    roleWanted[key] = not roleWanted[key]
                    if not roleWanted.HEALER and not roleWanted.DAMAGER then
                        roleWanted[key] = true            -- never leave zero roles selected
                    end
                    self:SetChecked(roleWanted[key])
                    PushRoleToServer()
                end
            end
        end
    end
    -- the role-check popup (premade groups) - just enable, server assigns
    for _, b in ipairs({ LFDRoleCheckPopupRoleButtonHealer, LFDRoleCheckPopupRoleButtonDPS,
                         LFRQueueFrameRoleButtonHealer, LFRQueueFrameRoleButtonDPS }) do
        if b and type(LFG_EnableRoleButton) == "function" then LFG_EnableRoleButton(b) end
    end
end

-- the server tells us the stored choice on login (and after every .lfgrole)
local sbMsgFrame = CreateFrame("Frame")
sbMsgFrame:RegisterEvent("CHAT_MSG_ADDON")
sbMsgFrame:SetScript("OnEvent", function(_, _, prefix, message)
    if prefix ~= "SpellBladeLFG" then return end
    local mask = tonumber((message or ""):match("^ROLE (%d+)$"))
    if not mask then return end
    roleWanted.HEALER  = bit.band(mask, 0x04) ~= 0
    roleWanted.DAMAGER = bit.band(mask, 0x08) ~= 0
    if not roleWanted.HEALER and not roleWanted.DAMAGER then
        roleWanted.HEALER, roleWanted.DAMAGER = true, true
    end
    SpellBladeRefreshLFGRoles()
end)

if type(hooksecurefunc) == "function" and type(LFG_UpdateAvailableRoles) == "function" then
    hooksecurefunc("LFG_UpdateAvailableRoles", SpellBladeRefreshLFGRoles)
    SpellBladeRefreshLFGRoles()
end

-- Queue via the server -------------------------------------------------------
--  The client's JoinLFG() refuses to send CMSG_LFG_JOIN when it has no role,
--  and class 10 can never give it one. So for a Spellblade we send the selected
--  dungeon ids to the server (.sbqueue) and let core's LFGMgr queue us with the
--  role picked above. The server's own LFG update packets make the client UI
--  show "in queue" as normal; leaving the queue still works client-side.
local function SpellBladeServerQueue()
    local ids = {}
    if LFDQueueFrame and type(LFDQueueFrame.type) == "number" then
        ids[#ids + 1] = LFDQueueFrame.type
    elseif LFDQueueFrame and LFDQueueFrame.type == "specific" then
        local pools = { LFDDungeonList, LFDHiddenByCollapseList }
        for _, pool in ipairs(pools) do
            for _, id in pairs(pool or {}) do
                if not LFGIsIDHeader(id) and LFGEnabledList and LFGEnabledList[id]
                   and not (LFGLockList and LFGLockList[id]) then
                    ids[#ids + 1] = id
                end
            end
        end
    end
    if #ids == 0 then
        UIErrorsFrame:AddMessage(ERR_LFG_NO_DUNGEONS or "Select a dungeon first.", 1.0, 0.1, 0.1, 1.0)
        return
    end
    cmdSeq = (cmdSeq % 9999) + 1
    SendAddonMessage("AzerothCore", string.format("i%04dsbqueue %s", cmdSeq, table.concat(ids, ",")), "WHISPER", UnitName("player"))
end

if type(LFDQueueFrame_Join) == "function" then
    local stock_LFDQueueFrame_Join = LFDQueueFrame_Join
    LFDQueueFrame_Join = function(...)
        if IsSpellblade() then
            SpellBladeServerQueue()
            return
        end
        return stock_LFDQueueFrame_Join(...)
    end
end

-- Safety net: the ready-check popup hard-errors on any role string it doesn't
-- know ("Unknown role: ..."). Fall back to a DPS icon instead of throwing.
if type(GetTexCoordsForRole) == "function" then
    local stock_GetTexCoordsForRole = GetTexCoordsForRole
    GetTexCoordsForRole = function(role)
        if role ~= "TANK" and role ~= "HEALER" and role ~= "DAMAGER" and role ~= "GUIDE" then
            role = "DAMAGER"
        end
        return stock_GetTexCoordsForRole(role)
    end
end
