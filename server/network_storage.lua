-- server/network_storage.lua
-- Peripheral network storage management for shop items and delivery

local config = require("/config")

local networkStorage = {}

-- Storage state
local storageChests = {}  -- Multiple chests labeled "STORAGE" for shop items
local inputChests = {}    -- Chests labeled "INPUT" for items to be processed
local voidChests = {}  -- User void chests for delivery
local allChests = {}  -- All registered chests

-- Marker names for special chests
local STORAGE_MARKER = "STORAGE"
local INPUT_MARKER = "INPUT"

-- Get all peripheral names excluding directly attached ones
local function getNetworkPeripherals()
    local allPeripherals = peripheral.getNames()
    local directSides = {left = true, right = true, top = true, bottom = true, front = true, back = true}
    local networkPeripherals = {}
    
    for _, name in ipairs(allPeripherals) do
        if not directSides[name] then
            table.insert(networkPeripherals, name)
        end
    end
    
    return networkPeripherals
end

-- Check if a chest has a marker paper in it
local function getChestMarker(chest)
    local items = chest.list()
    
    for slot, item in pairs(items) do
        -- Look for renamed paper items
        if item.name == "minecraft:paper" then
            local detail = chest.getItemDetail(slot)
            if detail and detail.displayName then
                return detail.displayName, slot
            end
        end
    end
    
    return nil, nil
end

-- Helper to count table entries
local function tableCount(t)
    local count = 0
    for _ in pairs(t) do count = count + 1 end
    return count
end

-- Scan network for chests and register them
function networkStorage.scanNetwork()
    print("Scanning peripheral network...")
    
    -- Reset storage state
    storageChests = {}
    inputChests = {}
    voidChests = {}
    allChests = {}
    
    local peripherals = getNetworkPeripherals()
    local foundChests = 0
    
    for _, peripheralName in ipairs(peripherals) do
        if peripheral.hasType(peripheralName, "inventory") then
            local chest = peripheral.wrap(peripheralName)
            
            if chest and chest.list then
                foundChests = foundChests + 1
                
                -- Check for marker paper
                local marker, markerSlot = getChestMarker(chest)
                
                if marker then
                    local chestInfo = {
                        name = peripheralName,
                        peripheral = chest,
                        marker = marker,
                        markerSlot = markerSlot,
                        size = chest.size()
                    }
                    
                    -- Handle STORAGE chests (multiple allowed)
                    if marker == STORAGE_MARKER then
                        table.insert(storageChests, chestInfo)
                        print("  STORAGE chest: " .. peripheralName)
                    -- Handle INPUT chests (multiple allowed)
                    elseif marker == INPUT_MARKER then
                        table.insert(inputChests, chestInfo)
                        print("  INPUT chest: " .. peripheralName)
                    -- Handle user void chests (username-based)
                    else
                        -- Any other marker is treated as a user void chest
                        voidChests[marker] = chestInfo
                        print("  Void chest for user '" .. marker .. "': " .. peripheralName)
                    end
                    
                    table.insert(allChests, chestInfo)
                end
            end
        end
    end
    
    print("Network scan complete:")
    print("  STORAGE chests: " .. #storageChests)
    print("  INPUT chests: " .. #inputChests)
    print("  Void chests: " .. tableCount(voidChests))
    print("  Total chests: " .. #allChests)
    
    return true
end

-- Get all STORAGE chests
function networkStorage.getStorageChests()
    return storageChests
end

-- Get all INPUT chests
function networkStorage.getInputChests()
    return inputChests
end

-- Process items from INPUT chests into STORAGE (smart organization)
function networkStorage.processInputChests()
    if #inputChests == 0 then
        return 0, "No INPUT chests found"
    end
    
    if #storageChests == 0 then
        return 0, "No STORAGE chests available"
    end
    
    local itemsProcessed = 0
    local itemTypes = {}
    
    -- Process each input chest
    for _, inputChest in ipairs(inputChests) do
        local items = inputChest.peripheral.list()
        
        -- Process each slot in input chest
        for slot, item in pairs(items) do
            if slot ~= inputChest.markerSlot then  -- Skip marker
                local remaining = item.count
                
                -- Phase 1: Try to stack with existing items in STORAGE
                for _, storageChest in ipairs(storageChests) do
                    if remaining <= 0 then break end
                    
                    -- Find existing stacks of same item
                    local storageItems = storageChest.peripheral.list()
                    for storageSlot, storageItem in pairs(storageItems) do
                        if storageSlot ~= storageChest.markerSlot and storageItem.name == item.name and remaining > 0 then
                            -- Try to push to this existing stack
                            local transferred = inputChest.peripheral.pushItems(storageChest.name, slot, remaining, storageSlot)
                            
                            if transferred > 0 then
                                remaining = remaining - transferred
                                if remaining <= 0 then break end
                            end
                        end
                    end
                end
                
                -- Phase 2: If items remain, find empty slots
                if remaining > 0 then
                    for _, storageChest in ipairs(storageChests) do
                        if remaining <= 0 then break end
                        
                        -- Push to any available slot
                        local transferred = inputChest.peripheral.pushItems(storageChest.name, slot, remaining)
                        
                        if transferred > 0 then
                            remaining = remaining - transferred
                            if remaining <= 0 then break end
                        end
                    end
                end
                
                -- Track what we processed
                if remaining < item.count then
                    itemsProcessed = itemsProcessed + 1
                    itemTypes[item.name] = true
                end
            end
        end
    end
    
    local uniqueTypes = 0
    for _ in pairs(itemTypes) do
        uniqueTypes = uniqueTypes + 1
    end
    
    return itemsProcessed, uniqueTypes
end

-- Get void chest for a specific user
function networkStorage.getUserVoidChest(username)
    return voidChests[username]
end

-- Scan all items in STORAGE chests
function networkStorage.scanStorageItems()
    local items = {}
    
    for _, chest in ipairs(storageChests) do
        local chestItems = chest.peripheral.list()
        
        for slot, item in pairs(chestItems) do
            if slot ~= chest.markerSlot then
                local detail = chest.peripheral.getItemDetail(slot)
                
                if detail then
                    local itemKey = item.name
                    
                    if not items[itemKey] then
                        items[itemKey] = {
                            name = item.name,
                            displayName = detail.displayName or item.name,
                            count = 0,
                            locations = {}
                        }
                    end
                    
                    items[itemKey].count = items[itemKey].count + item.count
                    table.insert(items[itemKey].locations, {
                        chest = chest.name,
                        slot = slot,
                        count = item.count
                    })
                end
            end
        end
    end
    
    return items
end

-- Transfer items from STORAGE to user void chest
-- Returns: success, error
function networkStorage.deliverToUser(username, itemName, quantity)
    local voidChest = voidChests[username]
    if not voidChest then
        return false, "user_void_chest_not_found"
    end
    
    local remaining = quantity
    
    -- Search STORAGE chests for the item
    for _, storageChest in ipairs(storageChests) do
        if remaining <= 0 then break end
        
        local items = storageChest.peripheral.list()
        for slot, item in pairs(items) do
            if slot ~= storageChest.markerSlot and item.name == itemName then
                local toTransfer = math.min(remaining, item.count)
                
                -- Transfer to user's void chest
                local transferred = storageChest.peripheral.pushItems(voidChest.name, slot, toTransfer)
                
                if transferred > 0 then
                    remaining = remaining - transferred
                    print("Delivered " .. transferred .. "x " .. itemName .. " to " .. username)
                end
                
                if remaining <= 0 then break end
            end
        end
    end
    
    if remaining > 0 then
        return false, "insufficient_stock"
    end
    
    return true, nil
end

-- Get info about all registered chests
function networkStorage.getChestInfo()
    return {
        storageChests = #storageChests,
        voidChests = tableCount(voidChests),
        totalChests = #allChests
    }
end

-- Initialize network storage
function networkStorage.initialize()
    print("\nInitializing network storage...")
    return networkStorage.scanNetwork()
end

return networkStorage
