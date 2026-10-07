-- Razagath: joins the two realm-wide chat channels a few seconds after every login.
--   Global-All      everyone (Horde, Alliance, playerbots)
--   Global-Players  real players only (the server keeps bots out of it)
--
-- Why the CLIENT does it: the 3.3.5 client ignores a server-initiated "you joined" for a custom channel (only the built-in zone channels like General/Trade
-- are accepted that way), so the server-side join left both channels invisible and un-typeable. A join the client asks for itself (what /join does) is
-- accepted normally, so the add-on just runs the equivalent of "/join Global-All" and "/join Global-Players".
-- Type /leave <name> to leave one; it comes back on the next login. Set RAZAGATH_GLOBALCHANNELS_OFF = true in a macro/add-on to skip it.

local CHANNELS = { "Global-All", "Global-Players" }
local FIRST_DELAY = 4      -- seconds after entering the world (lets the zone channels settle first)
local RETRY_DELAY = 3
local MAX_TRIES = 4

local f = CreateFrame("Frame")
local timer, tries = nil, 0

local function JoinMissing()
    local missing = false
    for _, name in ipairs(CHANNELS) do
        if GetChannelName(name) == 0 then
            JoinChannelByName(name, nil, DEFAULT_CHAT_FRAME:GetID(), 0)
            missing = true
        end
    end
    return missing
end

f:SetScript("OnUpdate", function(self, elapsed)
    if not timer then return end
    timer = timer - elapsed
    if timer > 0 then return end
    tries = tries + 1
    -- the first pass joins, later passes only re-check that the join took (stops once both are listed)
    if JoinMissing() and tries < MAX_TRIES then
        timer = RETRY_DELAY
    else
        timer = nil
    end
end)

f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:SetScript("OnEvent", function(self, event)
    -- once per login (this event also fires on every loading screen) so a /leave sticks until the next login
    self:UnregisterEvent("PLAYER_ENTERING_WORLD")
    if RAZAGATH_GLOBALCHANNELS_OFF then return end
    timer = FIRST_DELAY
end)
