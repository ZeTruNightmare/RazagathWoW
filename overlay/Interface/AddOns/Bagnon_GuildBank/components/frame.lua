--[[
	frame.lua
		A specialized version of the bagnon frame for guild banks
--]]

local Bagnon = LibStub('AceAddon-3.0'):GetAddon('Bagnon')
local Frame = Bagnon.Classy:New('Frame', Bagnon.Frame)
Frame:Hide()
Bagnon.GuildFrame = Frame


--[[
	Events
--]]

function Frame:OnShow()
	PlaySound('GuildVaultOpen')

	self:UpdateEvents()
	self:UpdateLook()
end

function Frame:OnHide()
--	GuildBankPopupFrame:Hide()
	StaticPopup_Hide('GUILDBANK_WITHDRAW')
	StaticPopup_Hide('GUILDBANK_DEPOSIT')
	StaticPopup_Hide('CONFIRM_BUY_GUILDBANK_TAB')
	CloseGuildBankFrame()
	PlaySound('GuildVaultClose')

	self:UpdateEvents()

	--fix issue where a frame is hidden, but not via bagnon controlled methods (ie, close on escape)
	if self:IsFrameShown() then
		self:HideFrame()
	end
end


--[[
	Actions
--]]

function Frame:CreateItemFrame()
	local f = Bagnon.GuildItemFrame:New(self:GetFrameID(), self)
	self.itemFrame = f
	return f
end

function Frame:CreateBagFrame()
	local f = Bagnon.GuildTabFrame:New(self:GetFrameID(), self)
	self.bagFrame = f
	return f
end

function Frame:CreateMoneyFrame()
	local f = Bagnon.GuildMoneyFrame:New(self:GetFrameID(), self)
	self.moneyFrame = f
	return f
end

function Frame:HasBagFrame()
	return true
end

function Frame:IsBagFrameShown()
	return true
end

function Frame:HasBagToggle()
	return false
end

function Frame:HasPlayerSelector()
	return false
end


--[[
	Razagath: "Buy Tab" button for the guild leader (the stock guild bank has a purchase panel; this window had none,
	so unbought tabs just read "Unavailable")
--]]

local function BuyButton_OnClick()
	PlaySound('igMainMenuOption')
	StaticPopup_Show('CONFIRM_BUY_GUILDBANK_TAB')
end

local function BuyButton_OnEnter(self)
	GameTooltip:SetOwner(self, 'ANCHOR_TOP')
	GameTooltip:SetText(BUY_GUILDBANK_TAB)
	local cost = GetGuildBankTabCost()
	if cost then
		SetTooltipMoney(GameTooltip, cost)
	end
	GameTooltip:Show()
end

local function BuyButton_OnLeave()
	GameTooltip:Hide()
end

local function BuyButton_OnEvent(self)
	self:GetParent():UpdateBuyButton()
end

function Frame:CreateBuyButton()
	local b = CreateFrame('Button', nil, self, 'UIPanelButtonTemplate')
	b:SetWidth(84)
	b:SetHeight(22)
	b:SetText('Buy Tab')
	b:SetPoint('BOTTOMLEFT', self, 'BOTTOMLEFT', 8, 9)

	b:SetScript('OnClick', BuyButton_OnClick)
	b:SetScript('OnEnter', BuyButton_OnEnter)
	b:SetScript('OnLeave', BuyButton_OnLeave)
	b:SetScript('OnEvent', BuyButton_OnEvent)
	b:RegisterEvent('GUILDBANK_UPDATE_TABS')
	b:RegisterEvent('GUILDBANK_UPDATE_MONEY')
	b:RegisterEvent('PLAYER_MONEY')
	b:RegisterEvent('PLAYER_GUILD_UPDATE')

	self.buyButton = b
	return b
end

function Frame:UpdateBuyButton()
	local b = self.buyButton or self:CreateBuyButton()
	local cost = IsGuildLeader() and GetGuildBankTabCost()

	if cost then
		b:Show()
		if GetMoney() >= cost or (GetMoney() + GetGuildBankMoney()) >= cost then
			b:Enable()
		else
			b:Disable()		--not enough gold (same rule as the stock window)
		end
	else
		b:Hide()
	end
end

function Frame:PlaceMoneyFrame()
	self:UpdateBuyButton()
	return self.super.PlaceMoneyFrame(self)
end