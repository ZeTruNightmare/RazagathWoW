--[[
	currencyFrame.lua
		Razagath addition: shows the currencies you tick "Show on Backpack" for (Character > Currency) inside the
		Bagnon inventory window, next to the money display - the job the stock backpack's token bar used to do.
--]]

local Bagnon = LibStub('AceAddon-3.0'):GetAddon('Bagnon')
local CurrencyFrame = Bagnon.Classy:New('Frame')
CurrencyFrame:Hide()
Bagnon.CurrencyFrame = CurrencyFrame

local NUM_TOKENS = 3        --the client lets you watch at most 3 currencies
local BUTTON_HEIGHT = 16
local ICON_SIZE = 14
local SPACING = 6
local HookWatchChanges

CurrencyFrame.instances = {}


--[[ Constructor ]]--

function CurrencyFrame:New(frameID, parent)
	local f = self:Bind(CreateFrame('Frame', nil, parent))
	f.frameID = frameID
	f.tokens = {}
	f:SetHeight(BUTTON_HEIGHT)
	f:SetWidth(1)

	for i = 1, NUM_TOKENS do
		local b = CreateFrame('Button', nil, f)
		b:SetID(i)
		b:SetHeight(BUTTON_HEIGHT)

		local icon = b:CreateTexture(nil, 'ARTWORK')
		icon:SetWidth(ICON_SIZE)
		icon:SetHeight(ICON_SIZE)
		icon:SetPoint('LEFT', 0, 0)
		b.icon = icon

		local count = b:CreateFontString(nil, 'ARTWORK', 'GameFontHighlightSmall')
		count:SetPoint('LEFT', icon, 'RIGHT', 2, 0)
		b.count = count

		b:SetScript('OnEnter', function(self)
			GameTooltip:SetOwner(self, 'ANCHOR_TOPLEFT')
			GameTooltip:SetBackpackToken(self:GetID())
			GameTooltip:Show()
		end)
		b:SetScript('OnLeave', function()
			GameTooltip:Hide()
		end)

		b:Hide()
		f.tokens[i] = b
	end

	f:SetScript('OnShow', f.OnShow)
	f:SetScript('OnHide', f.OnHide)
	f:SetScript('OnEvent', f.OnEvent)
	f:SetScript('OnUpdate', f.OnUpdate)

	table.insert(self.instances, f)
	HookWatchChanges()

	return f
end


--[[ Events ]]--

function CurrencyFrame:OnShow()
	self:RegisterEvent('BAG_UPDATE')
	self:RegisterEvent('CURRENCY_DISPLAY_UPDATE')
	self:RegisterEvent('PLAYER_MONEY')
	self:RegisterEvent('PLAYER_ENTERING_WORLD')
	self:RegisterEvent('PLAYER_PVP_RANKS_CHANGED')
	self.dirty = true
end

function CurrencyFrame:OnHide()
	self:UnregisterAllEvents()
end

function CurrencyFrame:OnEvent()
	self.dirty = true
end

--updates are batched to one per rendered frame, bag events come in bursts
function CurrencyFrame:OnUpdate()
	if self.dirty then
		self.dirty = nil
		self:Update()
	end
end

--the currency tab's "Show on Backpack" checkbox changes what is watched without necessarily firing an event
local hooked
function HookWatchChanges()
	if hooked then return end
	hooked = true

	local function Refresh()
		for _, f in ipairs(CurrencyFrame.instances) do
			f.dirty = true
		end
	end

	if SetCurrencyBackpack then
		hooksecurefunc('SetCurrencyBackpack', Refresh)
	end
	if BackpackTokenFrame_Update then
		hooksecurefunc('BackpackTokenFrame_Update', Refresh)
	end
end


--[[ Display ]]--

function CurrencyFrame:Update()
	local shown, width = 0, 0
	local prev

	for i = 1, NUM_TOKENS do
		local b = self.tokens[i]
		local name, count, extraCurrencyType, icon = GetBackpackCurrencyInfo(i)

		if name then
			if extraCurrencyType == 1 then			--arena points
				b.icon:SetTexture([[Interface\PVPFrame\PVP-ArenaPoints-Icon]])
				b.icon:SetTexCoord(0, 1, 0, 1)
			elseif extraCurrencyType == 2 then		--honor points
				local faction = UnitFactionGroup('player')
				if faction then
					b.icon:SetTexture([[Interface\TargetingFrame\UI-PVP-]] .. faction)
					b.icon:SetTexCoord(0.03125, 0.59375, 0.03125, 0.59375)
				else
					b.icon:SetTexCoord(0, 1, 0, 1)
				end
			else
				b.icon:SetTexture(icon)
				b.icon:SetTexCoord(0, 1, 0, 1)
			end

			b.count:SetText(count <= 99999 and count or '*')
			b:SetWidth(ICON_SIZE + 2 + b.count:GetStringWidth())

			b:ClearAllPoints()
			if prev then
				b:SetPoint('LEFT', prev, 'RIGHT', SPACING, 0)
				width = width + SPACING
			else
				b:SetPoint('LEFT', self, 'LEFT', 0, 0)
			end
			width = width + b:GetWidth()
			b:Show()

			prev = b
			shown = shown + 1
		else
			b:Hide()
		end
	end

	self.numShown = shown
	self:SetWidth(math.max(width, 1))

	--the window has to re-measure itself when the amount of space we need changes
	if self.lastWidth ~= width then
		self.lastWidth = width
		Bagnon.Callbacks:SendMessage('BAG_FRAME_UPDATE_LAYOUT', self.frameID)
	end
end

--the width the window should reserve for us (0 when nothing is watched)
function CurrencyFrame:GetReservedWidth()
	if self.lastWidth and self.lastWidth > 0 then
		return self.lastWidth + 8
	end
	return 0
end
