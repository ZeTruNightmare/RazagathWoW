-- ---------------------------------------------------------------------------
--  GilneasMap.lua - world-map navigation for the imported Gilneas.
--
--  The 3.3.5 client ties a map to a continent through the WorldMapArea MapID, so Gilneas (its own map 654) is a "continent" to the client even though
--  it should read as a zone of Eastern Kingdoms.  The DBC data therefore stays as it is (Gilneas = continent + zone + city rows) and this file
--  makes the UI behave like a zone of Eastern Kingdoms:
--    * Eastern Kingdoms map: the peninsula west of Silverpine / Hillsbrad is the Gilneas hotspot (hover label + click -> Gilneas zone map)
--    * Gilneas zone map: the walled city is a hotspot (hover label + click -> Gilneas City map)
--    * Silverpine map: clicking "The Greymane Wall" opens Gilneas
--    * right-click: Gilneas City -> Gilneas -> Eastern Kingdoms (never the cosmic map)
--  The hotspot is a hand-placed rectangle in map fractions (the client's own hit regions do not follow the WorldMapArea rectangles).
-- ---------------------------------------------------------------------------
local GIL, CITY, EK, WALL = "Gilneas", "Gilneas City", "Eastern Kingdoms", "The Greymane Wall"
-- peninsula hotspot on the Eastern Kingdoms continent map, as fractions of the map frame (measured from the client's own UpdateMapHighlight sweep)
local HOT = { x1 = 0.355, x2 = 0.435, y1 = 0.460, y2 = 0.545 }

-- walled city on the Gilneas ZONE map (same measuring: fractions of the map frame, from the revealed zone map art)
local CITYHOT = { x1 = 0.545, x2 = 0.715, y1 = 0.385, y2 = 0.635 }

local function Find(list, name)
    for i, n in ipairs(list) do if n == name then return i end end
end
local function ContinentIndex(name) return Find({ GetMapContinents() }, name) end

local function CursorFraction()
    local x, y = GetCursorPosition()
    local s = WorldMapButton:GetEffectiveScale()
    x, y = x / s, y / s
    local cx, cy = WorldMapButton:GetCenter()
    local w, h = WorldMapButton:GetWidth(), WorldMapButton:GetHeight()
    return (x - (cx - w / 2)) / w, (cy + h / 2 - y) / h
end

-- true while the cursor sits on the Gilneas peninsula of the Eastern Kingdoms continent map
local function OverPeninsula()
    local ek = ContinentIndex(EK)
    if not ek or GetCurrentMapContinent() ~= ek or GetCurrentMapZone() ~= 0 then return false end
    local fx, fy = CursorFraction()
    return fx >= HOT.x1 and fx <= HOT.x2 and fy >= HOT.y1 and fy <= HOT.y2
end

-- true while the cursor sits on the walled city of the Gilneas zone map
local function OverCity()
    local gc = ContinentIndex(GIL)
    if not gc or GetCurrentMapContinent() ~= gc then return false end
    local zones = { GetMapZones(gc) }
    if GetCurrentMapZone() ~= Find(zones, GIL) then return false end
    local fx, fy = CursorFraction()
    return fx >= CITYHOT.x1 and fx <= CITYHOT.x2 and fy >= CITYHOT.y1 and fy <= CITYHOT.y2
end

local function OpenCity()
    local gc = ContinentIndex(GIL)
    if not gc then return end
    SetMapZoom(gc, Find({ GetMapZones(gc) }, CITY))
end

local function OpenGilneas()
    local gc = ContinentIndex(GIL)
    if not gc then return end
    SetMapZoom(gc, Find({ GetMapZones(gc) }, GIL))
end

-- Zone-level text, like the zone-info add-on (Cromulent) prints for every other zone: "Gilneas [1-10]", in the faction colour (green = friendly, red = hostile) and the
-- level colour. Gilneas is a level 1-10 Alliance starter zone. Only shown when Cromulent is loaded, so it matches the other zones (players without it see no levels anywhere).
-- Cromulent itself cannot do this for Gilneas (its zone list does not know it, and this label is written after Cromulent has run), so we write it ourselves.
local ZONE_LEVEL = { low = 1, high = 10 }
local function SetZoneLabel(name)
    WorldMapFrame.areaName = name
    WorldMapFrameAreaLabel:SetText(name)
    if WorldMapFrameAreaDescription then WorldMapFrameAreaDescription:SetText("") end
    WorldMapHighlight:Hide()
    if IsAddOnLoaded and IsAddOnLoaded("Cromulent") then
        local friendly = UnitFactionGroup("player") == "Alliance"
        if friendly then WorldMapFrameAreaLabel:SetTextColor(0.1, 1.0, 0.1) else WorldMapFrameAreaLabel:SetTextColor(1.0, 0.1, 0.1) end
        local c = GetQuestDifficultyColor and GetQuestDifficultyColor(ZONE_LEVEL.high) or { r = 1, g = 1, b = 0 }
        WorldMapFrameAreaLabel:SetText(string.format("%s |cff%02x%02x%02x[%d-%d]|r", name, c.r * 255, c.g * 255, c.b * 255, ZONE_LEVEL.low, ZONE_LEVEL.high))
    end
end

-- hover label
WorldMapButton:HookScript("OnUpdate", function(self)
    if self:IsMouseOver() and OverPeninsula() then
        SetZoneLabel(GIL)
    elseif self:IsMouseOver() and OverCity() then
        SetZoneLabel(CITY)
    end
end)

-- The client treats Gilneas as a 5th "continent", so on the cosmic (whole-world) map it also gets an engine hotspot - in the middle of the map over the Maelstrom.
-- Gilneas should only be reachable from the Eastern Kingdoms map: hide that hotspot's highlight / label and swallow clicks on it.
local cosmicOverGilneas = false      -- set every frame from the hover state; read by the click wrapper
local function CosmicGilneasUnderCursor(fx, fy)
    local c = GetCurrentMapContinent()
    if c ~= 0 and c ~= -1 then return false end          -- 0 (this client; -1 on some builds) = the cosmic (whole world) map
    if WorldMapFrame.areaName == GIL then return true end             -- the label the stock OnUpdate has just set for the engine hotspot
    if not fx then fx, fy = CursorFraction() end
    return (UpdateMapHighlight(fx, fy)) == GIL
end
WorldMapButton:HookScript("OnUpdate", function(self)
    cosmicOverGilneas = false
    if self:IsMouseOver() and CosmicGilneasUnderCursor() then
        cosmicOverGilneas = true
        WorldMapHighlight:Hide()
        WorldMapFrame.areaName = nil
        WorldMapFrameAreaLabel:SetText("")
        if WorldMapFrameAreaDescription then WorldMapFrameAreaDescription:SetText("") end
    end
end)
local origProcessMapClick = ProcessMapClick
ProcessMapClick = function(x, y)
    local c = GetCurrentMapContinent()
    if (c == 0 or c == -1) and (cosmicOverGilneas or CosmicGilneasUnderCursor(x, y)) then return end
    return origProcessMapClick(x, y)
end

-- left click: remember what was under the cursor BEFORE the native handler zooms somewhere else, then redirect afterwards
local pending
WorldMapButton:HookScript("OnMouseDown", function(self, button)
    pending = nil
    if button ~= "LeftButton" then return end
    if OverCity() then pending = "city"
    elseif OverPeninsula() or WorldMapFrame.areaName == WALL then pending = "gilneas" end
end)
WorldMapButton:HookScript("OnMouseUp", function(self, button)
    if button == "LeftButton" then
        if pending == "city" then OpenCity() elseif pending == "gilneas" then OpenGilneas() end
    end
    pending = nil
end)

-- zoom out: Gilneas City -> Gilneas -> Eastern Kingdoms
local origZoomOut = WorldMapZoomOutButton_OnClick
local function ZoomOut()
    local gc = ContinentIndex(GIL)
    if gc and GetCurrentMapContinent() == gc then
        local zones = { GetMapZones(gc) }
        local z = GetCurrentMapZone()
        if z > 0 and zones[z] == CITY then
            SetMapZoom(gc, Find(zones, GIL))
        else
            local ek = ContinentIndex(EK)
            if ek then SetMapZoom(ek) end
        end
        return
    end
    return origZoomOut()
end
WorldMapZoomOutButton_OnClick = ZoomOut                    -- used by the right-click path inside WorldMapButton_OnClick
WorldMapZoomOutButton:SetScript("OnClick", ZoomOut)        -- the Zoom Out button itself (the XML bound the original function object)

-- /gilmap : prints what the map thinks is under the cursor (for diagnosing hotspot problems)
SLASH_RAZGILMAP1 = "/gilmap"
SlashCmdList["RAZGILMAP"] = function()
    local fx, fy = CursorFraction()
    DEFAULT_CHAT_FRAME:AddMessage(string.format("|cff66ccffGilneasMap|r continent=%s zone=%s areaName=%s highlight=%s frac=%.3f,%.3f cosmicHidden=%s",
        tostring(GetCurrentMapContinent()), tostring(GetCurrentMapZone()), tostring(WorldMapFrame.areaName), tostring((UpdateMapHighlight(fx, fy))), fx, fy, tostring(cosmicOverGilneas)))
end