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

local DEFAULTS = {
    enabled = true,
    trinketSlot = 14,            -- 13 = top trinket, 14 = bottom trinket
    sets = {
        mount = { [14] = "Carrot on a Stick" },
        swim = { [15] = "Cloak of Hermitic Bliss" },
    },
    saved = {},                  -- [slot] = link of the normal item we replaced
}

local SLOT_NAMES = {
    [1] = "Head", [2] = "Neck", [3] = "Shoulder", [4] = "Shirt", [5] = "Chest",
    [6] = "Waist", [7] = "Legs", [8] = "Feet", [9] = "Wrist", [10] = "Hands",
    [11] = "Ring 1", [13] = "Trinket 1", [14] = "Trinket 2", [15] = "Back",
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
local raw = { mount = false, swim = false }     -- what the game says right now
local stable = { mount = false, swim = false }  -- what we act on (debounced)
local since = { mount = 0, swim = 0 }
local nextTry = {}
local lastBagWarning = 0

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage(PREFIX .. msg)
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
            Print("bags are full, so I can't take off " .. (EquippedName(slot) or "that item") .. " yet.")
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

-- Setup and events ---------------------------------------------------------------
local function InitDB()
    CarrotCloakDB = CarrotCloakDB or {}
    db = CarrotCloakDB
    if db.enabled == nil then db.enabled = DEFAULTS.enabled end
    if db.trinketSlot ~= 13 and db.trinketSlot ~= 14 then db.trinketSlot = DEFAULTS.trinketSlot end
    if type(db.saved) ~= "table" then db.saved = {} end
    -- The default items are only filled in on first run, so removed items stay removed.
    if type(db.sets) ~= "table" then
        db.sets = {
            mount = { [14] = DEFAULTS.sets.mount[14] },
            swim = { [15] = DEFAULTS.sets.swim[15] },
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

-- Slash commands -----------------------------------------------------------------
local function ListSets()
    Print(db.enabled and "ON" or "OFF (type /cc on to turn it back on)")
    for _, key in ipairs({ "mount", "swim" }) do
        local label = key == "mount" and "While mounted" or "While swimming"
        local any = false
        for slot, name in pairs(db.sets[key]) do
            any = true
            Print(("  %s: %s (%s)"):format(label, name, SLOT_NAMES[slot] or ("slot " .. slot)))
        end
        if not any then Print("  " .. label .. ": nothing") end
    end
end

local function AddItem(key, text)
    if text == "" then
        Print("shift-click the item after the command, e.g. /cc " .. key .. " [Item Name]")
        return
    end
    local name, _, _, _, _, _, _, _, equipLoc = GetItemInfo(text)
    if not name then
        Print("I don't recognise that item. Shift-click it from your bags into the chat box instead of typing the name.")
        return
    end
    local slot = equipLoc == "INVTYPE_TRINKET" and db.trinketSlot or EQUIPLOC_TO_SLOT[equipLoc]
    if not slot then
        Print(name .. " can't be used: weapons, off-hands and non-gear items are not supported.")
        return
    end
    -- Links carry the full name (e.g. "of the Whale"), which is what we match on.
    name = NameFromLink(text) or name
    local old = db.sets[key][slot]
    if old and old ~= name and EquippedName(slot) == old then
        Print("take off " .. old .. " first (dismount or leave the water), then replace it.")
        return
    end
    db.sets[key][slot] = name
    local label = key == "mount" and "mounted" or "swimming"
    if old and old ~= name then
        Print(("%s replaces %s as your %s %s item."):format(name, old, label, SLOT_NAMES[slot]))
    else
        Print(("%s will be equipped while %s (%s)."):format(name, label, SLOT_NAMES[slot]))
    end
end

local function RemoveItem(text)
    local target = (NameFromLink(text) or text):lower()
    local found = false
    for _, set in pairs(db.sets) do
        for slot, name in pairs(set) do
            if name:lower() == target then
                if EquippedName(slot) == name then
                    Print("take off " .. name .. " first (dismount or leave the water), then remove it.")
                    return
                end
                set[slot] = nil
                found = true
            end
        end
    end
    Print(found and ("removed " .. target .. ".") or ("couldn't find \"" .. text .. "\" in either list. Type /cc to see them."))
end

local function SetTrinketSlot(text)
    local new = tonumber(text)
    if new == 1 then new = 13 elseif new == 2 then new = 14 end
    if new ~= 13 and new ~= 14 then
        Print("use /cc trinket 1 (top trinket) or /cc trinket 2 (bottom trinket).")
        return
    end
    local old = db.trinketSlot
    if new == old then
        Print("already using " .. SLOT_NAMES[new] .. ".")
        return
    end
    for _, set in pairs(db.sets) do
        if set[old] and EquippedName(old) == set[old] then
            Print("dismount or leave the water first, then change the trinket slot.")
            return
        end
    end
    for _, set in pairs(db.sets) do
        set[new], set[old] = set[old], nil
    end
    db.saved[old], db.saved[new] = nil, nil
    db.trinketSlot = new
    Print("riding and swimming trinkets now use " .. SLOT_NAMES[new] .. ".")
end

SLASH_CARROTCLOAK1 = "/carrotcloak"
SLASH_CARROTCLOAK2 = "/cc"
SlashCmdList["CARROTCLOAK"] = function(msg)
    if not db then return end
    local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = cmd:lower()
    if cmd == "on" or cmd == "off" then
        db.enabled = (cmd == "on")
        Print(db.enabled and "ON." or "OFF. I won't touch your gear until you type /cc on.")
    elseif cmd == "mount" or cmd == "swim" then
        AddItem(cmd, rest)
    elseif cmd == "remove" then
        RemoveItem(rest)
    elseif cmd == "trinket" then
        SetTrinketSlot(rest)
    elseif cmd == "" or cmd == "list" or cmd == "status" then
        ListSets()
    else
        Print("commands:")
        Print("  /cc - show what is set up")
        Print("  /cc on, /cc off - turn the addon on or off")
        Print("  /cc mount [item] - equip this item while mounted")
        Print("  /cc swim [item] - equip this item while swimming")
        Print("  /cc remove [item] - stop managing this item")
        Print("  /cc trinket 1 or 2 - which trinket slot to use (1 = top, 2 = bottom)")
    end
end
