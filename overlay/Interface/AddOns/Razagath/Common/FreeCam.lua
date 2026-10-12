-- Razagath free camera for 3D views (the same controls as MogIt's preview):
--     left-drag   sideways = rotate, up / down = zoom
--     right-drag  move the picture
--     mouse wheel zoom
-- RazagathFreeCam(model [, defaults]) turns any Model / PlayerModel / DressUpModel frame into one of these. The view lives in model.view (depth, x, y, face) and is
-- applied with SetPosition(depth, x, y) + SetFacing(face) - nothing else is touched while dragging, because re-setting scale / portrait zoom resets the camera.
--
-- The game throws a model's camera away whenever the model is (re)loaded, so after anything that changes what is shown (SetCreature, SetUnit, TryOn ...) call
-- model:Settle(): the view is re-applied every frame for a moment until the new model has really loaded.
--     model:ApplyView()  model:ResetView()  model:Settle([seconds])      model.autoRotate = -1 | 0 | 1 spins it (used by rotate buttons)

local SENSITIVITY = 50;       -- MogIt's value
local WHEEL_STEP = 0.6;

local mover = CreateFrame("Frame");
mover:Hide();
mover:SetScript("OnUpdate", function(self)
	local model = self.model;
	if ( not model ) then self:Hide(); return; end
	local cx, cy = GetCursorPosition();
	local dX, dY = (cx - self.px) / SENSITIVITY, (cy - self.py) / SENSITIVITY;
	local v = model.view;
	if ( self.btn == "LeftButton" ) then
		v.depth = v.depth + dY;
		v.face = v.face + dX;
	else
		v.x = v.x + dX;
		v.y = v.y + dY;
	end
	self.px, self.py = cx, cy;
	model:ApplyView();
end);

function RazagathFreeCam(model, defaults)
	defaults = defaults or {};
	model.viewDefault = { depth = defaults.depth or 0, x = defaults.x or 0, y = defaults.y or 0, face = defaults.face or 0 };
	model.view = { depth = model.viewDefault.depth, x = model.viewDefault.x, y = model.viewDefault.y, face = model.viewDefault.face };
	model.autoRotate = 0;

	function model:ApplyView()
		local v = self.view;
		self:SetPosition(v.depth, v.x, v.y);
		self:SetFacing(v.face);
	end
	function model:ResetView()
		local d = self.viewDefault;
		self.view.depth, self.view.x, self.view.y, self.view.face = d.depth, d.x, d.y, d.face;
		self:ApplyView();
	end
	function model:Settle(seconds)
		self.settle = seconds or 0.8;
	end

	model:EnableMouse(true);
	model:EnableMouseWheel(true);
	model:RegisterForDrag("LeftButton", "RightButton");
	model:SetScript("OnDragStart", function(self, button)
		mover.model, mover.btn = self, button;
		mover.px, mover.py = GetCursorPosition();
		mover:Show();
	end);
	model:SetScript("OnDragStop", function() mover:Hide(); end);
	model:SetScript("OnMouseWheel", function(self, delta)
		self.view.depth = self.view.depth + (delta > 0 and WHEEL_STEP or -WHEEL_STEP);
		self:ApplyView();
	end);

	-- a child frame ticks the settling + the spin, so the owner keeps its own OnUpdate untouched
	local ticker = CreateFrame("Frame", nil, model);
	ticker:SetScript("OnUpdate", function(self, elapsed)
		local m = self:GetParent();
		if ( m.settle and m.settle > 0 ) then
			m.settle = m.settle - elapsed;
			m:ApplyView();
		end
		if ( m.autoRotate ~= 0 ) then
			m.view.face = m.view.face + m.autoRotate * 2 * elapsed;
			m:ApplyView();
		end
	end);
	return model;
end
