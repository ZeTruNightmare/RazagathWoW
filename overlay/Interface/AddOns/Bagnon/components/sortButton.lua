--[[
	sortButton.lua
		Razagath addition: a "sort items" button for the inventory and bank windows, plus the sorter itself.

		3.3.5a has no sort API, so we do it the way BankStack/Tidy Bags do: plan one move at a time, perform it
		with two PickupContainerItem calls (pick up, drop = server-side swap/merge), wait for the item locks to
		clear, then re-plan from the real bag state.  Because the plan is rebuilt from the live contents before
		every move, it is safe if the player or the server changes something in between.
--]]

local Bagnon = LibStub('AceAddon-3.0'):GetAddon('Bagnon')


--[[ The sorter ]]--

local Sorter = {}
Bagnon.Sorter = Sorter

local TICK = 0.08            --seconds between steps
local MAX_MOVES = 800        --safety net
local STUCK_SECONDS = 4      --give up if the cursor/locks never clear

local PREFIX = '|cff33ff99Bagnon:|r '
local function Say(msg)
	DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
end

--localized item class names in a sensible display order
local classRank = {}
do
	local classes = {GetAuctionItemClasses()}
	for i, name in ipairs(classes) do
		classRank[name] = i
	end
end

local infoCache = {}
local function GetInfo(link)
	local info = infoCache[link]
	if info then
		return info
	end

	local name, _, quality, ilvl, _, itemType, subType, stack, equipLoc = GetItemInfo(link)
	if not name then
		--the client doesn't know this item yet; use what the link tells us, and don't cache it
		return {
			name = link:match('%[(.-)%]') or link,
			quality = 1, ilvl = 0, rank = 99, subType = '', equipLoc = '', stack = 1
		}
	end

	info = {
		name = name,
		quality = quality or 1,
		ilvl = ilvl or 0,
		subType = subType or '',
		equipLoc = equipLoc or '',
		stack = stack or 1,
	}
	if info.quality == 0 then
		info.rank = 100                                  --junk goes last
	else
		info.rank = classRank[itemType or ''] or 98
	end
	infoCache[link] = info
	return info
end

local function Less(a, b)
	local x, y = a.info, b.info
	if x.rank ~= y.rank then return x.rank < y.rank end
	if x.subType ~= y.subType then return x.subType < y.subType end
	if x.equipLoc ~= y.equipLoc then return x.equipLoc < y.equipLoc end
	if x.quality ~= y.quality then return x.quality > y.quality end
	if x.ilvl ~= y.ilvl then return x.ilvl > y.ilvl end
	if x.name ~= y.name then return x.name < y.name end
	if a.link ~= b.link then return a.link < b.link end
	return a.count > b.count
end

--the bags that belong to a window, grouped by bag family (ammo pouches, herb bags, ... only hold their own kind)
local function BuildGroups(frameID)
	local bags
	if frameID == 'bank' then
		bags = {BANK_CONTAINER}
		for bag = NUM_BAG_SLOTS + 1, NUM_BAG_SLOTS + NUM_BANKBAGSLOTS do
			table.insert(bags, bag)
		end
	else
		bags = {}
		for bag = 0, NUM_BAG_SLOTS do
			table.insert(bags, bag)
		end
	end

	local groups, byFamily = {}, {}
	for _, bag in ipairs(bags) do
		local size = GetContainerNumSlots(bag)
		if size and size > 0 then
			local _, family = GetContainerNumFreeSlots(bag)
			family = family or 0
			local group = byFamily[family]
			if not group then
				group = {}
				byFamily[family] = group
				table.insert(groups, group)
			end
			for slot = 1, size do
				table.insert(group, {bag, slot})
			end
		end
	end
	return groups
end

--reads a group: returns the list of entries (false for an empty slot), and whether anything is still locked
local function Read(slots)
	local cur, locked = {}, false
	for i, s in ipairs(slots) do
		local bag, slot = s[1], s[2]
		local link = GetContainerItemLink(bag, slot)
		if link then
			local _, count, isLocked = GetContainerItemInfo(bag, slot)
			if isLocked then
				locked = true
			end
			count = count or 1
			cur[i] = {
				link = link,
				count = count,
				id = link:match('item:(%d+)') or link,
				info = GetInfo(link),
				sig = link .. '#' .. count,
			}
		else
			cur[i] = false
		end
	end
	return cur, locked
end

--the next move for a group, as indexes into its slot list: src, dst  (nil when the group is done)
local function NextMove(cur)
	local n = #cur

	--1. merge partial stacks of the same item (later stack onto the earlier one)
	local partial = {}
	for i = 1, n do
		local e = cur[i]
		if e and e.info.stack > 1 and e.count < e.info.stack then
			local first = partial[e.id]
			if first then
				return i, first
			end
			partial[e.id] = i
		end
	end

	--2. put the items in order
	local entries = {}
	for i = 1, n do
		if cur[i] then
			table.insert(entries, cur[i])
		end
	end
	table.sort(entries, Less)

	for i = 1, n do
		local want = entries[i] and entries[i].sig
		local have = cur[i] and cur[i].sig
		if want ~= have then
			if not want then
				return nil              --can't happen (items are packed first); never move things to the tail
			end
			for j = i + 1, n do
				local e = cur[j]
				if e and e.sig == want then
					local target = entries[j] and entries[j].sig
					if target ~= e.sig then
						return j, i
					end
				end
			end
		end
	end
	return nil
end


--[[ Runner ]]--

local runner = CreateFrame('Frame')
runner:Hide()

local function Stop(msg)
	runner:Hide()
	Sorter.running = nil
	if msg then
		Say(msg)
	end
	Bagnon.Callbacks:SendMessage('SORT_STATE_CHANGE')
end

function Sorter:IsRunning()
	return self.running ~= nil
end

function Sorter:CanSort(frameID)
	if frameID == 'bank' and not Bagnon.PlayerInfo:AtBank() then
		return false, 'Visit your bank to sort it.'
	end
	return true
end

function Sorter:Toggle(frameID)
	if self.running then
		Stop('Sorting stopped.')
		return
	end

	local ok, err = self:CanSort(frameID)
	if not ok then
		Say(err)
		return
	end
	if CursorHasItem() or SpellIsTargeting() then
		Say('Put down whatever is on your cursor first.')
		return
	end

	self.running = {frameID = frameID, moves = 0, waited = 0, last = nil, repeats = 0}
	runner.elapsed = 0
	runner:Show()
	Bagnon.Callbacks:SendMessage('SORT_STATE_CHANGE')
end

function Sorter:Step()
	local run = self.running
	if not run then
		return
	end

	if run.frameID == 'bank' and not Bagnon.PlayerInfo:AtBank() then
		Stop('Sorting stopped - the bank was closed.')
		return
	end

	local groups = BuildGroups(run.frameID)

	--wait for the previous move to settle
	local anyLocked = CursorHasItem() and true or false
	local reads = {}
	for gi, slots in ipairs(groups) do
		local cur, locked = Read(slots)
		reads[gi] = cur
		anyLocked = anyLocked or locked
	end
	if anyLocked then
		run.waited = run.waited + TICK
		if run.waited > STUCK_SECONDS then
			ClearCursor()
			Stop('Sorting stopped - the items would not move.')
		end
		return
	end
	run.waited = 0

	for gi, slots in ipairs(groups) do
		local src, dst = NextMove(reads[gi])
		if src then
			--no-progress guard: the same move on the same layout again and again means the server refused it
			local parts = {src, dst}
			for _, e in ipairs(reads[gi]) do
				table.insert(parts, e and e.sig or '-')
			end
			local key = table.concat(parts, '|')
			if key == run.last then
				run.repeats = run.repeats + 1
				if run.repeats >= 3 then
					Stop('Sorting stopped - some items could not be moved.')
					return
				end
			else
				run.last = key
				run.repeats = 0
			end

			run.moves = run.moves + 1
			if run.moves > MAX_MOVES then
				Stop('Sorting stopped - too many moves.')
				return
			end

			PickupContainerItem(slots[src][1], slots[src][2])
			PickupContainerItem(slots[dst][1], slots[dst][2])
			return
		end
	end

	local moves = run.moves
	Stop(moves > 0 and 'Sorted.' or 'Already sorted.')
end

runner:SetScript('OnUpdate', function(self, elapsed)
	self.elapsed = (self.elapsed or 0) + elapsed
	if self.elapsed >= TICK then
		self.elapsed = 0
		Sorter:Step()
	end
end)


--[[ The button ]]--

local SortButton = Bagnon.Classy:New('CheckButton')
Bagnon.SortButton = SortButton

local SIZE = 20
local NORMAL_TEXTURE_SIZE = 64 * (SIZE/36)

function SortButton:New(frameID, parent)
	local b = self:Bind(CreateFrame('CheckButton', nil, parent))
	b:SetWidth(SIZE)
	b:SetHeight(SIZE)
	b:RegisterForClicks('anyUp')

	local nt = b:CreateTexture()
	nt:SetTexture([[Interface\Buttons\UI-Quickslot2]])
	nt:SetWidth(NORMAL_TEXTURE_SIZE)
	nt:SetHeight(NORMAL_TEXTURE_SIZE)
	nt:SetPoint('CENTER', 0, -1)
	b:SetNormalTexture(nt)

	local pt = b:CreateTexture()
	pt:SetTexture([[Interface\Buttons\UI-Quickslot-Depress]])
	pt:SetAllPoints(b)
	b:SetPushedTexture(pt)

	local ht = b:CreateTexture()
	ht:SetTexture([[Interface\Buttons\ButtonHilight-Square]])
	ht:SetAllPoints(b)
	b:SetHighlightTexture(ht)

	local ct = b:CreateTexture()
	ct:SetTexture([[Interface\Buttons\CheckButtonHilight]])
	ct:SetAllPoints(b)
	ct:SetBlendMode('ADD')
	b:SetCheckedTexture(ct)

	local icon = b:CreateTexture()
	icon:SetAllPoints(b)
	icon:SetTexture([[Interface\Icons\INV_Misc_Gear_01]])
	b.icon = icon

	b.frameID = frameID

	b:SetScript('OnClick', b.OnClick)
	b:SetScript('OnEnter', b.OnEnter)
	b:SetScript('OnLeave', b.OnLeave)
	b:SetScript('OnShow', b.OnShow)
	b:SetScript('OnHide', b.OnHide)

	return b
end

function SortButton:SORT_STATE_CHANGE()
	self:Update()
end

function SortButton:OnShow()
	self:RegisterMessage('SORT_STATE_CHANGE')
	self:Update()
end

function SortButton:OnHide()
	self:UnregisterAllMessages()
end

function SortButton:Update()
	self:SetChecked(Sorter:IsRunning())
end

function SortButton:OnClick()
	Sorter:Toggle(self.frameID)
	self:Update()
end

function SortButton:OnEnter()
	if self:GetRight() > (GetScreenWidth() / 2) then
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
	else
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
	end

	GameTooltip:SetText('Sort Items')
	if Sorter:IsRunning() then
		GameTooltip:AddLine('Click to stop sorting.', 1, 1, 1)
	else
		GameTooltip:AddLine('Stacks items together and orders them by type, quality and name.', 1, 1, 1, true)
		if self.frameID == 'bank' and not Bagnon.PlayerInfo:AtBank() then
			GameTooltip:AddLine('Visit your bank to sort it.', 1, 0.2, 0.2)
		end
	end
	GameTooltip:Show()
end

function SortButton:OnLeave()
	GameTooltip:Hide()
end
