-- Registers the Gilneas maps and data (Data.lua, generated) with Questie-335's supported extension points. Everything is wrapped in pcall: if Questie changes, this
-- addon degrades to doing nothing instead of breaking Questie.
local D = RazagathQuestieData
if not D then return end
local ok, err = pcall(function()
    if not (QuestieCompat and QuestieCompat.RegisterCorrection and QuestieCompat.UiMapData and QuestieLoader) then return end
    local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
    local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
    -- Questie caches its compiled database; recompile once whenever the generated data changes.
    -- The data version is stamped INSIDE Questie's own saved table (QuestieConfig.global): a SavedVariables table of this addon is loaded AFTER its Lua files run and would
    -- overwrite whatever we set here, so the stamp never persisted and Questie recompiled its whole database on EVERY login (counter was at 198).
    local g = QuestieConfig and QuestieConfig.global
    if g and g.razagathDataVersion ~= D.version then
        g.dbIsCompiled = false
        g.razagathDataVersion = D.version
    end
    -- the two Gilneas maps (Questie mapID = WorldMapArea.dbc id + 1)
    for zone, m in pairs(D.maps) do
        QuestieCompat.UiMapData[m.ui] = {[1] = m.width, [2] = m.height, [3] = m.left, [4] = m.top, mapType = 3, parentMapID = 1415, mapID = m.wma + 1, instance = 654, name = m.name}
        ZoneDB.private.areaIdToUiMapId[zone] = m.ui
        ZoneDB.private.uiMapIdToAreaId[m.ui] = zone
    end
    QuestieCompat.RegisterCorrection("questData", function() return D.quests(QuestieDB.questKeys) end)
    QuestieCompat.RegisterCorrection("npcData", function() return D.npcs(QuestieDB.npcKeys) end)
    QuestieCompat.RegisterCorrection("objectData", function() return D.objects(QuestieDB.objectKeys) end)
    QuestieCompat.RegisterCorrection("itemData", function() return D.items(QuestieDB.itemKeys) end)
end)
if not ok then DEFAULT_CHAT_FRAME:AddMessage("|cffff8800RazagathQuestie:|r " .. tostring(err)) end
-- zone names for the tracker / journey headers (otherwise "Unknown Zone")
pcall(function()
    local l10n = QuestieLoader:ImportModule("l10n")
    if l10n and l10n.zoneLookup then
        l10n.zoneLookup["Razagath Gilneas"] = {[7714] = "Gilneas", [7755] = "Gilneas City"}
    end
end)
-- custom races: Questie-335 does not know the Worgen (race id 12 on this realm), so QuestiePlayer:Initialize died with "playerRaceId (a nil value)" for every Worgen character
-- and Questie did not start at all. Teach it the race, and let the faction-wide "all Alliance / all Horde" race masks include the custom races (Worgen 2048, Goblin 256).
pcall(function()
    if QuestieCompat and QuestieCompat.ChrRaces then
        QuestieCompat.ChrRaces.Worgen = QuestieCompat.ChrRaces.Worgen or 12
        QuestieCompat.ChrRaces.PandarenAlliance = QuestieCompat.ChrRaces.PandarenAlliance or 25   -- the Pandaren race files on this realm (Alliance 25 / Horde 26)
        QuestieCompat.ChrRaces.PandarenHorde = QuestieCompat.ChrRaces.PandarenHorde or 26
    end
    local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
    local _, raceFile = UnitRace("player")
    -- any race file name Questie does not know can only be the Worgen on this realm (Goblin is already in its table)
    if raceFile and QuestieCompat and QuestieCompat.ChrRaces and not QuestieCompat.ChrRaces[raceFile] then QuestieCompat.ChrRaces[raceFile] = 12; raceFile = "Worgen" end
    local masks
    if raceFile == "Worgen" or raceFile == "PandarenAlliance" then masks = {[1101] = true, [3149] = true}
    elseif raceFile == "Goblin" or raceFile == "PandarenHorde" then masks = {[690] = true, [946] = true} end
    if masks and QuestiePlayer and QuestiePlayer.HasRequiredRace then
        local orig = QuestiePlayer.HasRequiredRace
        QuestiePlayer.HasRequiredRace = function(requiredRaces)
            if requiredRaces and masks[requiredRaces] then return true end
            return orig(requiredRaces)
        end
    end
end)

-- custom class: Questie-335 does not know the Monk (class id 12 on this realm; its QuestieCompat.ChrClasses has no MONK row), so QuestiePlayer:Initialize died with
-- "attempt to perform arithmetic on local 'classId' (a nil value)" and Questie did not start for any Monk. Same fix as the Spell Blade (Razagath/SpellBlade/SpellBladeUI.lua):
-- QuestiePlayer caches the ORIGINAL UnitClass, so the id must be in ChrClasses; id 12 = class flag 2048, which no class-restricted quest carries, so no foreign class quests show.
-- Everything that keys off the class TOKEN (townsfolk, comms, tooltips) gets "ROGUE" - the Monk uses the Rogue stat curve and wears leather.
pcall(function()
    local qc = QuestieCompat
    if not qc then return end
    if type(qc.ChrClasses) == "table" and qc.ChrClasses.MONK == nil then qc.ChrClasses.MONK = 12 end
    if type(qc.UnitClass) == "function" and not qc.__rzMonkUnitClass then
        qc.__rzMonkUnitClass = qc.UnitClass
        qc.UnitClass = function(unit)
            local className, classFile, classId = qc.__rzMonkUnitClass(unit)
            if classFile == "MONK" then return className, "ROGUE", 12 end
            return className, classFile, classId
        end
    end
end)
