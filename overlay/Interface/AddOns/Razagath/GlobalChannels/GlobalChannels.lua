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

-- Joining a channel does NOT tick it in the chat frame's own channel filter (Chat Settings -> Global Channels) for a character whose chat window was set up before the
-- channel existed - its messages are then silently hidden (found on live 2026-10-07: the channels were listed and joined but nothing could be seen). So, ONCE per character
-- and channel, add it to the main chat window ourselves. The flag is saved per character (RazagathGlobalChannelsChar), so a player who later unticks a channel keeps it unticked.
local function EnsureChatFrame()
    RazagathGlobalChannelsChar = RazagathGlobalChannelsChar or {}
    local done = RazagathGlobalChannelsChar
    for _, name in ipairs(CHANNELS) do
        if not done[name] and GetChannelName(name) ~= 0 then
            local present = false
            for _, c in ipairs(DEFAULT_CHAT_FRAME.channelList or {}) do
                if c == name then present = true break end
            end
            if not present and ChatFrame_AddChannel then pcall(ChatFrame_AddChannel, DEFAULT_CHAT_FRAME, name) end   -- pcall: this must never be able to throw
            done[name] = true
        end
    end
end

f:SetScript("OnUpdate", function(self, elapsed)
    if not timer then return end
    timer = timer - elapsed
    if timer > 0 then return end
    tries = tries + 1
    -- the first pass joins, later passes only re-check that the join took (stops once both are listed)
    local missing = JoinMissing()
    EnsureChatFrame()
    if missing and tries < MAX_TRIES then
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
