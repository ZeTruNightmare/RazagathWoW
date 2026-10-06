-- Registers the Gilneas maps and data (Data.lua, generated) with Questie-335's supported extension points. Everything is wrapped in pcall: if Questie changes, this
-- addon degrades to doing nothing instead of breaking Questie.
local D = RazagathQuestieData
if not D then return end
local ok, err = pcall(function()
    if not (QuestieCompat and QuestieCompat.RegisterCorrection and QuestieCompat.UiMapData and QuestieLoader) then return end
    local QuestieDB = QuestieLoader:ImportModule("QuestieDB")
    local ZoneDB = QuestieLoader:ImportModule("ZoneDB")
    -- Questie caches its compiled database; recompile once whenever the generated data changes
    RazagathQuestieDB = RazagathQuestieDB or {}
    if RazagathQuestieDB.version ~= D.version then
        if QuestieConfig and QuestieConfig.global then QuestieConfig.global.dbIsCompiled = false end
        RazagathQuestieDB.version = D.version
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
    if QuestieCompat and QuestieCompat.ChrRaces then QuestieCompat.ChrRaces.Worgen = QuestieCompat.ChrRaces.Worgen or 12 end
    local QuestiePlayer = QuestieLoader:ImportModule("QuestiePlayer")
    local _, raceFile = UnitRace("player")
    -- any race file name Questie does not know can only be the Worgen on this realm (Goblin is already in its table)
    if raceFile and QuestieCompat and QuestieCompat.ChrRaces and not QuestieCompat.ChrRaces[raceFile] then QuestieCompat.ChrRaces[raceFile] = 12; raceFile = "Worgen" end
    local masks
    if raceFile == "Worgen" then masks = {[1101] = true, [3149] = true} elseif raceFile == "Goblin" then masks = {[690] = true, [946] = true} end
    if masks and QuestiePlayer and QuestiePlayer.HasRequiredRace then
        local orig = QuestiePlayer.HasRequiredRace
        QuestiePlayer.HasRequiredRace = function(requiredRaces)
            if requiredRaces and masks[requiredRaces] then return true end
            return orig(requiredRaces)
        end
    end
end)
