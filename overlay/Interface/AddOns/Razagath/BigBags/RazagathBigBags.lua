-- ===========================================================================
--  Raises the stock client's hardcoded 36-slot bag limit (Interface\FrameXML\
--  ContainerFrame.lua: MAX_CONTAINER_ITEMS = 36) so bags bigger than that
--  (the 50-slot Razagath Trunk) actually work, without touching FrameXML
--  itself - this client's anti-tamper check aborts on ANY FrameXML/GlueXML
--  override (see [[chromiecraft-client-gluexml-anti-tamper]] project memory),
--  so this has to be done entirely from an ordinary AddOn instead.
--
--  How the stock 36 cap actually works (confirmed by extracting and reading
--  ContainerFrame.lua/.xml from this client's own MPQs via mpq_extract.pl):
--   - ContainerFrame.xml statically declares exactly 36 "$parentItemN" Button
--     frames per bag window (ContainerFrame1..13), all inheriting the
--     reusable virtual template "ContainerFrameItemButtonTemplate".
--   - ContainerFrame_GenerateFrame (Lua, untouched by this addon) looks each
--     one up by name via getglobal("ContainerFrame"..id.."Item"..i) for
--     i = 1..size, and positions/shows it - it doesn't care how the button
--     came to exist, only that a frame with that exact name is there.
--   - The background art scales the same way, via up to MAX_BG_TEXTURES
--     "$parentBackgroundMiddleN" textures tiled to cover however many rows
--     the bag needs.
--  So the fix is additive: pre-create the missing button/texture frames
--  RazagathBigBags itself needs (37..NEW_MAX_ITEMS, one extra background
--  tile) via CreateFrame using Blizzard's own virtual templates, then raise
--  the two globals that gate the loops. Nothing in FrameXML is replaced.
--
--  IMPORTANT: this only raises the UI/display ceiling. The real number of
--  slots a single bag can hold is separately capped at 36 by the
--  client-server object-update-field protocol itself (CONTAINER_FIELD_SLOT_1
--  .. CONTAINER_END in the server's UpdateFields.h - 2 fixed fields per
--  slot, and the client's compiled networking code expects exactly that
--  layout). Server-side MAX_BAG_SIZE stays 36 - going higher needs a real
--  client binary patch to the object/networking system, not just this
--  addon, and wasn't judged worth the risk. Left in place as harmless
--  headroom in case a future, smaller stretch past 36 is ever worth it.
-- ===========================================================================

local NEW_MAX_ITEMS = 60   -- headroom above the 50-slot Trunk for future tiers
local NEW_BG_TEXTURES = 4  -- MAX_BG_TEXTURES was 2 (covers 12 rows); 4 covers 24

MAX_CONTAINER_ITEMS = NEW_MAX_ITEMS
MAX_BG_TEXTURES = NEW_BG_TEXTURES

for i = 1, NUM_CONTAINER_FRAMES do
    local frame = _G["ContainerFrame" .. i]
    if frame then
        for j = 37, NEW_MAX_ITEMS do
            local name = "ContainerFrame" .. i .. "Item" .. j
            if not _G[name] then
                CreateFrame("Button", name, frame, "ContainerFrameItemButtonTemplate")
            end
        end

        -- Blizzard shipped BackgroundMiddle1 (always used) and a hidden
        -- BackgroundMiddle2 for taller bags. Clone that same pattern for any
        -- extra tiles NEW_BG_TEXTURES needs, each anchored below the last.
        for k = 3, NEW_BG_TEXTURES do
            local name = "ContainerFrame" .. i .. "BackgroundMiddle" .. k
            if not _G[name] then
                local prev = _G["ContainerFrame" .. i .. "BackgroundMiddle" .. (k - 1)]
                local tex = frame:CreateTexture(name, "ARTWORK")
                tex:SetTexture("Interface\\ContainerFrame\\UI-Bag-Components")
                tex:SetWidth(256)
                tex:SetHeight(256)
                tex:SetPoint("TOP", prev, "BOTTOM")
                tex:Hide()
            end
        end
    end
end
