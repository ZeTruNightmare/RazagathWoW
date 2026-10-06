-- The 3.3.5 client lists Gilneas (our imported zone) as a fifth "continent". Some map add-ons read GetMapContinents() while they load and assume the stock four
-- (LibTourist-3.0, used by Cromulent, dies with "attempt to index field '?'" and the add-on stays broken). This add-on's folder name starts with "!" so it loads before
-- all of them: until PLAYER_LOGIN (when every add-on has finished loading) GetMapContinents() hides Gilneas; afterwards the real function is put back, so Razagath's own
-- Gilneas map code (which needs the fifth continent) and the world map itself are unaffected.
local GIL = "Gilneas"
local orig = GetMapContinents
if type(orig) ~= "function" then return end
local function filtered(...)
    local all = { orig(...) }
    local out, n = {}, 0
    for i = 1, #all do
        if all[i] ~= GIL then n = n + 1; out[n] = all[i] end
    end
    return unpack(out, 1, n)
end
GetMapContinents = filtered

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function(self)
    if GetMapContinents == filtered then GetMapContinents = orig end
    self:UnregisterAllEvents()
end)
