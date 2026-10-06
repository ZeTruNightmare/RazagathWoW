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

-- hover label
WorldMapButton:HookScript("OnUpdate", function(self)
    if self:IsMouseOver() and OverPeninsula() then
        WorldMapFrame.areaName = GIL
        WorldMapFrameAreaLabel:SetText(GIL)
        if WorldMapFrameAreaDescription then WorldMapFrameAreaDescription:SetText("") end
        WorldMapHighlight:Hide()
    elseif self:IsMouseOver() and OverCity() then
        WorldMapFrame.areaName = CITY
        WorldMapFrameAreaLabel:SetText(CITY)
        if WorldMapFrameAreaDescription then WorldMapFrameAreaDescription:SetText("") end
        WorldMapHighlight:Hide()
    end
end)

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
