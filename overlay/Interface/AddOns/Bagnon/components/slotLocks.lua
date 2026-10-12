--[[
	slotLocks.lua
		Razagath addition: lock individual bag/bank slots so the Sort button leaves them alone (nothing is moved out of a
		locked slot, and nothing is moved into it - empty slots can be locked too, to keep a gap or a reserved spot).

		Locks are remembered per character in the BagnonLockedSlots saved variable, keyed by "bag:slot" (a position, not an
		item).  A small "lock mode" toggle button in the window title bar turns on slot clicking: while it is on, left-clicking
		a slot locks/unlocks it instead of picking the item up.
--]]

local Bagnon = LibStub('AceAddon-3.0'):GetAddon('Bagnon')
local Locks = {}
Bagnon.SlotLocks = Locks

Locks.mode = false

--saved variables are loaded after the add-on's files run, so never touch the table at load time
local function DB()
	if not BagnonLockedSlots then
		BagnonLockedSlots = {}
	end
	return BagnonLockedSlots
end

--only real bags/bank bags can be sorted, so only those can be locked (not the keyring)
function Locks:IsLockableBag(bag)
	return bag == BACKPACK_CONTAINER or bag == BANK_CONTAINER
		or (bag > 0 and bag <= NUM_BAG_SLOTS + NUM_BANKBAGSLOTS)
end

function Locks:IsLocked(bag, slot)
	return DB()[bag .. ':' .. slot] and true or false
end

function Locks:Toggle(bag, slot)
	local key = bag .. ':' .. slot
	local db = DB()
	if db[key] then
		db[key] = nil
	else
		db[key] = true
	end
	Bagnon.Callbacks:SendMessage('SLOT_LOCK_UPDATE')
end

function Locks:IsMode()
	return Locks.mode
end

function Locks:SetMode(on)
	on = on and true or false
	if Locks.mode ~= on then
		Locks.mode = on
		Bagnon.Callbacks:SendMessage('SLOT_LOCK_MODE')
	end
end


--[[ The lock-mode toggle button (title bar, next to Sort) ]]--

local LockButton = Bagnon.Classy:New('CheckButton')
Bagnon.LockButton = LockButton

local SIZE = 20
local NORMAL_TEXTURE_SIZE = 64 * (SIZE/36)

function LockButton:New(frameID, parent)
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
	icon:SetTexture([[Interface\Icons\INV_Misc_Key_04]])

	b:SetScript('OnClick', b.OnClick)
	b:SetScript('OnEnter', b.OnEnter)
	b:SetScript('OnLeave', b.OnLeave)
	b:SetScript('OnShow', b.OnShow)
	b:SetScript('OnHide', b.OnHide)

	return b
end

function LockButton:SLOT_LOCK_MODE()
	self:Update()
end

function LockButton:OnShow()
	self:RegisterMessage('SLOT_LOCK_MODE')
	self:Update()
end

function LockButton:OnHide()
	self:UnregisterAllMessages()
	--closing the window ends lock mode (the window re-lays-out its buttons by hiding/showing them, which must not count)
	local parent = self:GetParent()
	if parent and not parent:IsShown() then
		Locks:SetMode(false)
	end
end

function LockButton:Update()
	self:SetChecked(Locks:IsMode())
end

function LockButton:OnClick()
	Locks:SetMode(not Locks:IsMode())
	self:Update()
end

function LockButton:OnEnter()
	if self:GetRight() > (GetScreenWidth() / 2) then
		GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
	else
		GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
	end
	GameTooltip:SetText('Lock Slots')
	GameTooltip:AddLine('Turn this on, then click slots to lock or unlock them. Locked slots (shown with a padlock) are skipped by Sort: nothing is moved out of them or into them.', 1, 1, 1, true)
	GameTooltip:Show()
end

function LockButton:OnLeave()
	GameTooltip:Hide()
end
