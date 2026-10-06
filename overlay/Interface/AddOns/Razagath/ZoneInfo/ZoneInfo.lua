-- ZoneInfo.lua - zone levels and instances on the world map (what the Cromulent add-on does), built into Razagath so every player gets it.
-- Data: the MIT-licensed LibTourist-3.0 (levels, factions, instances of every zone) + LibBabble-Zone-3.0, embedded under ZoneInfo\Libs. The display code below is our own.
-- Hovering a zone on the world map shows its name in the faction colour with the level range ("Elwynn Forest [1-10]") and, under it, the instances inside it.
-- If Cromulent is loaded it already does all of this for the stock zones, so this file does nothing then (and GilneasMap writes the Gilneas level itself).
-- Gilneas (our imported zone) is not in LibTourist, so it is answered like Elwynn Forest: a level 1-10 Alliance starter zone with no instances,
-- and with Elwynn's fishing level (the server fishes Gilneas like Elwynn Forest and Gilneas City like Stormwind City, both minimum 1).
local ok, err = pcall(function()
    if IsAddOnLoaded("Cromulent") then return end
    local T = LibStub and LibStub("LibTourist-3.0", true)
    if not T or not T.GetLevel then return end
    RazagathZoneInfoActive = true

    -- Gilneas / Gilneas City behave like Elwynn Forest (level, faction, continent) minus instances
    local ALIAS = { ["Gilneas"] = true, ["Gilneas City"] = true }
    local model = "Elwynn Forest"
    local BZ = LibStub("LibBabble-Zone-3.0", true)
    if BZ and BZ.GetLookupTable then
        local lt = BZ:GetLookupTable()
        if lt and lt[model] then model = lt[model] end
    end
    if not T.__razGilneas then
        T.__razGilneas = true
        for _, fn in ipairs({ "GetLevel", "GetLevelColor", "GetFactionColor", "IsZone", "IsZoneOrInstance", "IsAlliance", "IsHostile", "IsContested", "GetContinent", "GetFishingLevel" }) do
            local orig = T[fn]
            if type(orig) == "function" then
                T[fn] = function(self, zone, ...)
                    if ALIAS[zone] then zone = model end
                    return orig(self, zone, ...)
                end
            end
        end
        local function Override(fn, value)
            local orig = T[fn]
            if type(orig) ~= "function" then return end
            T[fn] = function(self, zone, ...)
                if ALIAS[zone] then return value end
                return orig(self, zone, ...)
            end
        end
        Override("DoesZoneHaveInstances", false)
        Override("IsInstance", false)
        Override("GetInstanceGroupSize", 0)
        Override("GetComplex", nil)
        local origIter = T.IterateZoneInstances
        if type(origIter) == "function" then
            T.IterateZoneInstances = function(self, zone, ...)
                if ALIAS[zone] then return function() return nil end end
                return origIter(self, zone, ...)
            end
        end
    end

    -- instance list, drawn under the zone label
    local info = WorldMapButton:CreateFontString(nil, "OVERLAY", "GameFontNormal")      -- 12 pt (the small variant is 10 pt and hard to read)
    info:SetPoint("TOP", WorldMapFrameAreaDescription or WorldMapFrameAreaLabel, "BOTTOM", 0, -2)
    info:SetJustifyH("CENTER")
    local lines, lastZone = {}, nil

    local function Clean(s) return (s:gsub(" |cff.+$", "")) end

    -- the player's current Fishing skill rank (nil when they do not have the skill)
    local fishingName = GetSpellInfo(7620) or "Fishing"
    local function FishingRank()
        for i = 1, GetNumSkillLines() do
            local skillName, isHeader, _, skillRank = GetSkillLineInfo(i)
            if not isHeader and skillName == fishingName then return skillRank end
        end
    end

    WorldMapButton:HookScript("OnUpdate", function()
        local label = WorldMapFrameAreaLabel:GetText()
        local zone = (label and label ~= "") and Clean(label) or nil
        -- the whole-world map hovers Kalimdor / Eastern Kingdoms: leave those alone
        if GetCurrentMapContinent() == 0 then
            local c1, c2 = GetMapContinents()
            if zone == c1 or zone == c2 then info:SetText(""); lastZone = nil; return end
        end
        if not zone or not T:IsZoneOrInstance(zone) then zone = WorldMapFrame.areaName end
        if not zone or not (T:IsZoneOrInstance(zone) or T:DoesZoneHaveInstances(zone)) then info:SetText(""); lastZone = nil; return end
        -- name colour = faction, plus [low-high] in the level colour
        WorldMapFrameAreaLabel:SetTextColor(T:GetFactionColor(zone))
        local low, high = T:GetLevel(zone)
        if low and high and low > 0 and high > 0 then
            local r, g, b = T:GetLevelColor(zone)
            local levels = (low == high) and string.format(" |cff%02x%02x%02x[%d]|r", r * 255, g * 255, b * 255, high)
                                         or string.format(" |cff%02x%02x%02x[%d-%d]|r", r * 255, g * 255, b * 255, low, high)
            local size = T:GetInstanceGroupSize(zone)
            local sizeText = (size and size > 0) and string.format(" %d-man", size) or ""
            WorldMapFrameAreaLabel:SetText(Clean(WorldMapFrameAreaLabel:GetText() or zone) .. levels .. sizeText)
        end
        -- instances inside this zone + the minimum fishing skill of the zone (only shown to players who have Fishing); cached so it is only rebuilt when the zone changes
        if lastZone ~= zone then
            lastZone = zone
            wipe(lines)
            if T:DoesZoneHaveInstances(zone) then
                lines[1] = "|cffffff00Instances:|r"
                for inst in T:IterateZoneInstances(zone) do
                    local complex = T:GetComplex(inst)
                    local ilow, ihigh = T:GetLevel(inst)
                    local fr, fg, fb = T:GetFactionColor(inst)
                    local lr, lg, lb = T:GetLevelColor(inst)
                    local gs = T:GetInstanceGroupSize(inst)
                    local name = complex and (complex .. " - " .. inst) or inst
                    local lv = (ilow == ihigh) and string.format("%d", ihigh) or string.format("%d-%d", ilow, ihigh)
                    lines[#lines + 1] = string.format("|cff%02x%02x%02x%s|r |cff%02x%02x%02x[%s]|r%s", fr * 255, fg * 255, fb * 255, name, lr * 255, lg * 255, lb * 255, lv,
                                                       (gs and gs > 0) and string.format(" %d-man", gs) or "")
                end
            end
            local minFish = T.GetFishingLevel and T:GetFishingLevel(zone)
            local rank = minFish and FishingRank()
            if minFish and rank then
                local r, g, b = 1, 0, 0                                      -- red = your skill is too low, green = high enough
                if minFish < rank then r, g, b = 0, 1, 0 end
                lines[#lines + 1] = string.format("|cffffff00%s|r |cff%02x%02x%02x[%d]|r", fishingName, r * 255, g * 255, b * 255, minFish)
            end
            info:SetText(table.concat(lines, "\n"))
        end
    end)
end)
if not ok then DEFAULT_CHAT_FRAME:AddMessage("|cffff8800Razagath ZoneInfo:|r " .. tostring(err)) end
