-- CarrotCloak
-- Equips "mounted" items while you are mounted and "swimming" items while you
-- are swimming, and puts your normal gear back afterwards.
--
-- How it stays out of trouble: nothing is ever "queued" as a one-shot action.
-- A few times a second the addon compares what you SHOULD be wearing with what
-- you ARE wearing and fixes any difference. If a swap is not possible right now
-- (combat, dead, casting), it simply waits and fixes it the moment it can, so
-- gear cannot get stuck on or off.

local PREFIX = "|cff33ff99CarrotCloak|r: "
local EMPTY = "EMPTY"            -- marker: the slot was empty before we used it
local TICK = 0.2                 -- seconds between checks
local RETRY = 1.0                -- seconds to wait before retrying a slot
local ON_DELAY = 0.2             -- state must hold this long before gear goes on
local OFF_DELAY = { mount = 0.3, swim = 1.5 } -- ...and this long before it comes off

local DEFAULT_MOUNT_ITEM = "Carrot on a Stick"        -- trinket
local DEFAULT_SWIM_ITEM = "Cloak of Hermitic Bliss"   -- back

local SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands",
    [11] = "Ring 1", [13] = "Top trinket", [14] = "Bottom trinket", [15] = "Back",
    [19] = "Tabard",
}

-- Weapons and off-hands are left out on purpose: a two-hander displaces two
-- items at once and that is the easiest way to end up with gear stuck in bags.
local EQUIPLOC_TO_SLOT = {
    INVTYPE_HEAD = 1, INVTYPE_NECK = 2, INVTYPE_SHOULDER = 3, INVTYPE_BODY = 4,
    INVTYPE_CHEST = 5, INVTYPE_ROBE = 5, INVTYPE_WAIST = 6, INVTYPE_LEGS = 7,
    INVTYPE_FEET = 8, INVTYPE_WRIST = 9, INVTYPE_HAND = 10, INVTYPE_FINGER = 11,
    INVTYPE_CLOAK = 15, INVTYPE_TABARD = 19,
}

local SECTIONS = {
    { key = "mount", title = "While mounted", word = "mounted" },
    { key = "swim", title = "While swimming", word = "swimming" },
}

-- API differences between client versions --------------------------------------
local Cont = C_Container or {}
local GetContainerNumSlots = Cont.GetContainerNumSlots or GetContainerNumSlots
local GetContainerItemLink = Cont.GetContainerItemLink or GetContainerItemLink
local GetContainerNumFreeSlots = Cont.GetContainerNumFreeSlots or GetContainerNumFreeSlots
local ContainerIDToInventoryID = Cont.ContainerIDToInventoryID or ContainerIDToInventoryID
local GetItemInfo = GetItemInfo or (C_Item and C_Item.GetItemInfo)
local EquipItemByName = EquipItemByName or (C_Item and C_Item.EquipItemByName)
local CastInfo = UnitCastingInfo or CastingInfo
local ChannelInfo = UnitChannelInfo or ChannelInfo
local LAST_BAG = NUM_BAG_SLOTS or 4

local db
local ui                                        -- the settings window (built on first open)
local minimapButton
local raw = { mount = false, swim = false }     -- what the game says right now
local stable = { mount = false, swim = false }  -- what we act on (debounced)
local since = { mount = 0, swim = 0 }
local nextTry = {}
local lastBagWarning = 0

-- Shows a message in chat and at the bottom of the settings window.
local function Notify(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
    if ui then ui.status:SetText(msg) end
end

local function NameFromLink(link)
    return link and link:match("%[(.-)%]")
end

local function EquippedName(slot)
    return NameFromLink(GetInventoryItemLink("player", slot))
end

local function InBags(name)
    if not name then return false end
    for bag = 0, LAST_BAG do
        for i = 1, (GetContainerNumSlots(bag) or 0) do
            if NameFromLink(GetContainerItemLink(bag, i)) == name then
                return true
            end
        end
    end
    return false
end

local function FreeBag()
    for bag = 0, LAST_BAG do
        local free, family = GetContainerNumFreeSlots(bag)
        if free and free > 0 and (not family or family == 0) then
            return bag
        end
    end
end

-- Moves the item in an equipment slot into the bags. Returns true if it tried.
local function PutInBags(slot, now)
    local bag = FreeBag()
    if not bag then
        if now - lastBagWarning > 30 then
            lastBagWarning = now
            Notify("Your bags are full, so I can't take off " .. (EquippedName(slot) or "that item") .. " yet.")
        end
        return false
    end
    PickupInventoryItem(slot)
    if not CursorHasItem() then return false end
    if bag == 0 then
        PutItemInBackpack()
    else
        PutItemInBag(ContainerIDToInventoryID(bag))
    end
    if CursorHasItem() then ClearCursor() end
    return true
end

local function Blocked()
    return InCombatLockdown()
        or UnitAffectingCombat("player")
        or UnitIsDeadOrGhost("player")
        or CursorHasItem()
        or (CastInfo and CastInfo("player"))
        or (ChannelInfo and ChannelInfo("player"))
end

local function UpdateState(key, value, now)
    value = value and true or false
    if value ~= raw[key] then
        raw[key] = value
        since[key] = now
    end
    if stable[key] ~= value then
        local delay = value and ON_DELAY or OFF_DELAY[key]
        if now - since[key] >= delay then
            stable[key] = value
        end
    end
end

-- Returns true if it used the cursor (only one cursor move per pass is safe).
local function ProcessSlot(slot, now, cursorUsed)
    local mountItem, swimItem = db.sets.mount[slot], db.sets.swim[slot]
    local current = EquippedName(slot)
    local currentIsOurs = current ~= nil and (current == mountItem or current == swimItem)

    -- Swimming wins if both want the same slot.
    local want
    if stable.swim and swimItem and (current == swimItem or InBags(swimItem)) then
        want = swimItem
    elseif stable.mount and mountItem and (current == mountItem or InBags(mountItem)) then
        want = mountItem
    end

    if want then
        if current ~= want then
            if not currentIsOurs then
                db.saved[slot] = GetInventoryItemLink("player", slot) or EMPTY
            end
            EquipItemByName(want, slot)
            nextTry[slot] = now + RETRY
        end
    elseif currentIsOurs then
        local saved = db.saved[slot]
        if saved and saved ~= EMPTY and InBags(NameFromLink(saved)) then
            EquipItemByName(saved, slot)
            nextTry[slot] = now + RETRY
        elseif not cursorUsed then
            nextTry[slot] = now + RETRY
            return PutInBags(slot, now)
        end
    else
        db.saved[slot] = nil
    end
    return false
end

local function Evaluate(now)
    if not db or not db.enabled or Blocked() then return end
    local cursorUsed = false
    local seen = {}
    for _, set in pairs(db.sets) do
        for slot in pairs(set) do
            if not seen[slot] then
                seen[slot] = true
                if now >= (nextTry[slot] or 0) and not IsInventoryItemLocked(slot) then
                    if ProcessSlot(slot, now, cursorUsed) then
                        cursorUsed = true
                    end
                end
            end
        end
    end
end

-- Changing the item lists ----------------------------------------------------------
local function AddItem(section, link)
    local name, _, _, _, _, _, _, _, equipLoc = GetItemInfo(link)
    if not name then
        Notify("I couldn't read that item. Try picking it up again.")
        return
    end
    -- Links carry the full name (e.g. "of the Whale"), which is what we match on.
    name = NameFromLink(link) or name
    local slot = equipLoc == "INVTYPE_TRINKET" and db.trinketSlot or EQUIPLOC_TO_SLOT[equipLoc]
    if not slot then
        Notify(name .. " can't be used: weapons, off-hands and non-gear items are not supported.")
        return
    end
    local set = db.sets[section.key]
    local old = set[slot]
    if old and old ~= name and EquippedName(slot) == old then
        Notify("You're wearing " .. old .. " right now. Take it off first, then replace it.")
        return
    end
    set[slot] = name
    if old and old ~= name then
        Notify(("%s replaces %s as your %s item (%s)."):format(name, old, section.word, SLOT_NAMES[slot]))
    else
        Notify(("%s will be equipped while %s (%s)."):format(name, section.word, SLOT_NAMES[slot]))
    end
end

local function RemoveItem(section, slot)
    local set = db.sets[section.key]
    local name = set[slot]
    if not name then return end
    if EquippedName(slot) == name then
        Notify("You're wearing " .. name .. " right now. Dismount or leave the water first, then remove it.")
        return
    end
    set[slot] = nil
    Notify("Removed " .. name .. ".")
end

local function SetTrinketSlot(new)
    local old = db.trinketSlot
    if new == old then return end
    for _, set in pairs(db.sets) do
        -- db.saved[old] means a swap is in progress or active in that slot.
        if db.saved[old] or (set[old] and EquippedName(old) == set[old]) then
            Notify("Dismount or leave the water first, then change the trinket slot.")
            return
        end
    end
    for _, set in pairs(db.sets) do
        set[new], set[old] = set[old], nil
    end
    db.saved[old], db.saved[new] = nil, nil
    db.trinketSlot = new
    Notify("Riding and swimming trinkets now use the " .. SLOT_NAMES[new]:lower() .. " slot.")
end

-- Settings window --------------------------------------------------------------------
local WIDTH, PAD = 340, 18
local INNER = WIDTH - PAD * 2
local Refresh

local function Place(region, y)
    region:ClearAllPoints()
    region:SetPoint("TOPLEFT", ui, "TOPLEFT", PAD, y)
end

local function CreateRow(section)
    local row = CreateFrame("Frame", nil, ui)
    row:SetSize(INNER, 20)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.text:SetPoint("LEFT", 4, 0)
    row.text:SetWidth(INNER - 74)
    row.text:SetJustifyH("LEFT")
    local remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    remove:SetSize(66, 20)
    remove:SetPoint("RIGHT", 0, 0)
    remove:SetText("Remove")
    remove:SetScript("OnClick", function()
        RemoveItem(section, row.slot)
        Refresh()
    end)
    return row
end

Refresh = function()
    if not ui or not db then return end
    ui.enabled:SetChecked(db.enabled)
    ui.minimap:SetChecked(db.minimap)
    ui.trinket:SetText("Trinket slot: " .. (db.trinketSlot == 13 and "top" or "bottom") .. " (click to change)")

    local y = -104
    for _, section in ipairs(SECTIONS) do
        local widgets = ui.sections[section.key]
        Place(widgets.header, y)
        y = y - 18
        Place(widgets.drop, y)
        y = y - 30

        local slots = {}
        for slot in pairs(db.sets[section.key]) do slots[#slots + 1] = slot end
        table.sort(slots)
        for i, slot in ipairs(slots) do
            local row = widgets.rows[i]
            if not row then
                row = CreateRow(section)
                widgets.rows[i] = row
            end
            row.slot = slot
            row.text:SetText(db.sets[section.key][slot] .. "  |cff999999" .. (SLOT_NAMES[slot] or "") .. "|r")
            Place(row, y)
            row:Show()
            y = y - 22
        end
        for i = #slots + 1, #widgets.rows do
            widgets.rows[i]:Hide()
        end
        y = y - 10
    end

    Place(ui.status, y)
    ui:SetHeight(-y + 52)
end

local function OnDropItem(section)
    local kind, _, link = GetCursorInfo()
    if kind ~= "item" or not link then
        Notify("Pick up an item from your bags first, then click this box.")
        return
    end
    ClearCursor()
    AddItem(section, link)
    Refresh()
end

local function CreateCheck(label, x, y, onChange)
    local check = CreateFrame("CheckButton", nil, ui, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", ui, "TOPLEFT", x, y)
    local text = ui:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("LEFT", check, "RIGHT", 2, 0)
    text:SetText(label)
    check:SetScript("OnClick", function(self)
        onChange(self:GetChecked() and true or false)
    end)
    return check
end

local UpdateMinimapButton

local function BuildUI()
    ui = CreateFrame("Frame", "CarrotCloakFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    ui:Hide()
    ui:SetSize(WIDTH, 300)
    ui:SetPoint("CENTER")
    ui:SetFrameStrata("DIALOG")
    ui:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
    ui:EnableMouse(true)
    ui:SetMovable(true)
    ui:SetClampedToScreen(true)
    ui:RegisterForDrag("LeftButton")
    ui:SetScript("OnDragStart", ui.StartMoving)
    ui:SetScript("OnDragStop", ui.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CarrotCloakFrame") -- Escape closes the window

    local title = ui:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -18)
    title:SetText("CarrotCloak")

    local close = CreateFrame("Button", nil, ui, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    ui.enabled = CreateCheck("Enabled", PAD, -42, function(on)
        db.enabled = on
        Notify(on and "Turned on." or "Turned off. I won't touch your gear until you turn me back on.")
    end)
    ui.minimap = CreateCheck("Minimap button", 170, -42, function(on)
        db.minimap = on
        UpdateMinimapButton()
        if not on then Notify("Minimap button hidden. Type /cc to open this window.") end
    end)

    ui.trinket = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
    ui.trinket:SetSize(INNER, 22)
    ui.trinket:SetPoint("TOPLEFT", ui, "TOPLEFT", PAD, -72)
    ui.trinket:SetScript("OnClick", function()
        SetTrinketSlot(db.trinketSlot == 14 and 13 or 14)
        Refresh()
    end)

    ui.sections = {}
    for _, section in ipairs(SECTIONS) do
        local header = ui:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetText(section.title)
        local drop = CreateFrame("Button", nil, ui, "UIPanelButtonTemplate")
        drop:SetSize(INNER, 26)
        drop:SetText("Drop an item here to add it")
        drop:SetScript("OnClick", function() OnDropItem(section) end)
        drop:SetScript("OnReceiveDrag", function() OnDropItem(section) end)
        ui.sections[section.key] = { header = header, drop = drop, rows = {} }
    end

    ui.status = ui:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    ui.status:SetWidth(INNER)
    ui.status:SetJustifyH("LEFT")
    ui.status:SetText("Pick up an item from your bags and click a box to add it.")

    ui:SetScript("OnShow", Refresh)
end

local function ToggleUI()
    if not db then return end
    if not ui then BuildUI() end
    if ui:IsShown() then ui:Hide() else ui:Show() end
end

-- Minimap button ---------------------------------------------------------------------
local function PlaceMinimapButton()
    local angle = math.rad(db.minimapAngle or 215)
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * 80, math.sin(angle) * 80)
end

UpdateMinimapButton = function()
    if not Minimap then return end
    if not db.minimap then
        if minimapButton then minimapButton:Hide() end
        return
    end
    if not minimapButton then
        local b = CreateFrame("Button", "CarrotCloakMinimapButton", Minimap)
        minimapButton = b
        b:SetSize(31, 31)
        b:SetFrameStrata("MEDIUM")
        b:SetFrameLevel(8)
        b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
        local icon = b:CreateTexture(nil, "BACKGROUND")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", 0, 1)
        icon:SetTexture("Interface\\Icons\\INV_Misc_Food_54")
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        local border = b:CreateTexture(nil, "OVERLAY")
        border:SetSize(53, 53)
        border:SetPoint("TOPLEFT", 0, 0)
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

        b:SetScript("OnClick", ToggleUI)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText("CarrotCloak")
            GameTooltip:AddLine("Click to open. Drag to move.", 1, 1, 1)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", function() GameTooltip:Hide() end)

        b:RegisterForDrag("LeftButton")
        b:SetScript("OnDragStart", function(self)
            self:SetScript("OnUpdate", function()
                local mx, my = Minimap:GetCenter()
                local cx, cy = GetCursorPosition()
                local scale = Minimap:GetEffectiveScale()
                db.minimapAngle = math.deg(math.atan2(cy / scale - my, cx / scale - mx))
                PlaceMinimapButton()
            end)
        end)
        b:SetScript("OnDragStop", function(self)
            self:SetScript("OnUpdate", nil)
        end)
    end
    PlaceMinimapButton()
    minimapButton:Show()
end

-- Setup and events -------------------------------------------------------------------
local function InitDB()
    CarrotCloakDB = CarrotCloakDB or {}
    db = CarrotCloakDB
    if db.enabled == nil then db.enabled = true end
    if db.minimap == nil then db.minimap = true end
    if db.trinketSlot ~= 13 and db.trinketSlot ~= 14 then db.trinketSlot = 14 end
    if type(db.saved) ~= "table" then db.saved = {} end
    -- The default items are only filled in on first run, so removed items stay removed.
    if type(db.sets) ~= "table" then
        db.sets = {
            mount = { [14] = DEFAULT_MOUNT_ITEM },
            swim = { [15] = DEFAULT_SWIM_ITEM },
        }
    end
    if type(db.sets.mount) ~= "table" then db.sets.mount = {} end
    if type(db.sets.swim) ~= "table" then db.sets.swim = {} end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("PLAYER_REGEN_ENABLED")

frame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_LOGIN" then
        InitDB()
        UpdateMinimapButton()
    elseif event == "PLAYER_REGEN_ENABLED" then
        -- Combat just ended: fix anything that had to wait, right away.
        for slot in pairs(nextTry) do nextTry[slot] = nil end
        Evaluate(GetTime())
    end
end)

local elapsedTotal = 0
frame:SetScript("OnUpdate", function(_, elapsed)
    elapsedTotal = elapsedTotal + elapsed
    if elapsedTotal < TICK then return end
    elapsedTotal = 0
    local now = GetTime()
    UpdateState("mount", IsMounted(), now)
    UpdateState("swim", IsSwimming(), now)
    Evaluate(now)
end)

-- The only command: open or close the settings window.
SLASH_CARROTCLOAK1 = "/carrotcloak"
SLASH_CARROTCLOAK2 = "/cc"
SlashCmdList["CARROTCLOAK"] = ToggleUI
