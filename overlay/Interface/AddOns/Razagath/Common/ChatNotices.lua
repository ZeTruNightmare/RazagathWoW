-- The 3.3.5a client has no global string for the channel notice the server sends when a player who is not in the Dungeon Finder walks into a capital (Channel.cpp
-- CHAT_NOT_IN_LFG_NOTICE, RestrictedLfgChannel): Blizzard's ChatFrame_MessageEventHandler then calls format(nil, ...) and throws
-- "ChatFrame.lua: bad argument #1 to 'format' (string expected, got nil)". Defining the missing string removes the error (and shows the normal notice).
if not CHAT_NOT_IN_LFG_NOTICE then
    CHAT_NOT_IN_LFG_NOTICE = "|Hchannel:%d|h[%s]|h You must be queued in looking for group before joining this channel."
end
