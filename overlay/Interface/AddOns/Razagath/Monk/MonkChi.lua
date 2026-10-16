-- Monk: the server tells a Monk "Not enough Chi (N needed)." as a system chat line when a finisher is refused (the client has no Chi power, so the stock
-- "Not enough <power>" error can't be used). Chat is easy to miss mid-quest, so show it the way every other cast failure is shown: red text in the middle of the
-- screen (UIErrorsFrame) with the error sound, and swallow the chat line.
local function ChiFilter(self, event, msg)
	if ( msg and string.find(msg, "^Not enough Chi") ) then
		UIErrorsFrame:AddMessage("Not enough Chi", 1.0, 0.1, 0.1, 1.0);
		PlaySound("igPlayerInviteDecline");
		return true;
	end
	return false;
end
ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", ChiFilter);
