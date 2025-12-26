-- server/network_storage.lua
-- Peripheral network storage management for currency chests

local config = require("/config")

local networkStorage = {}

-- Storage state
local mintChest = nil
local outputChest = nil
local auxiliaryChest = nil  -- Receives books from deposit void chests
local denominationChests = {}  -- Indexed by denomination value
local voidChests = {}  -- Indexed by ATM ID
local allChests = {}  -- All registered chests

-- Marker names for special chests
local MINT_MARKER = "MINT"
local OUTPUT_MARKER = "OUTPUT"
local AUXILIARY_MARKER = "AUXILIARY"

-- Get all peripheral names excluding directly attached ones
-- If a chest is both directly attached AND on network, only return the network instance
local function getNetworkPeripherals()
    local allPeripherals = peripheral.getNames()
    local directSides = {left = true, right = true, top = true, bottom = true, front = true, back = true}
    local networkPeripherals = {}
    local processedChests = {}  -- Track chests we've already seen
    
    -- First pass: collect all network peripherals and track their types
    for _, name in ipairs(allPeripherals) do
        -- Check if peripheral is on network (contains underscore in name)
        -- Network peripherals: "chest_0", "minecraft:chest_1", etc.
        if string.find(name, "_") then
            if peripheral.hasType(name, "inventory") then
                -- Track this chest's type to check for duplicates
                local inv = peripheral.wrap(name)
                if inv and inv.size then
                    -- Use size and first few slots as a fingerprint
                    local fingerprint = tostring(inv.size())
                    local items = inv.list()
                    local itemCount = 0
                    for _ in pairs(items) do
                        itemCount = itemCount + 1
                    end
                    fingerprint = fingerprint .. "_" .. itemCount
                    
                    processedChests[fingerprint] = name
                end
            end
            table.insert(networkPeripherals, name)
        end
    end
    
    -- Second pass: check if any directly attached chests are duplicates
    local directDuplicates = {}
    for _, name in ipairs(allPeripherals) do
        if directSides[name] and peripheral.hasType(name, "inventory") then
            local inv = peripheral.wrap(name)
            if inv and inv.size then
                local fingerprint = tostring(inv.size())
                local items = inv.list()
                local itemCount = 0
                for _ in pairs(items) do
                    itemCount = itemCount + 1
                end
                fingerprint = fingerprint .. "_" .. itemCount
                
                -- If we've seen this chest on the network, mark it as a duplicate
                if processedChests[fingerprint] then
                    directDuplicates[name] = processedChests[fingerprint]
                end
            end
        end
    end
    
    -- Log any duplicates found
    for directName, networkName in pairs(directDuplicates) do
        print("  Note: Chest '" .. directName .. "' is both directly attached and on network")
        print("        Using network instance: " .. networkName)
    end
    
    return networkPeripherals
end

-- Check if chest has a marker item with specific name
local function hasMarker(chest, markerName)
    if not chest or not chest.list then
        return false
    end
    
    local items = chest.list()
    for slot, item in pairs(items) do
        -- Check if it's paper
        if string.find(item.name, "paper") then
            local detail = chest.getItemDetail(slot)
            if detail and detail.displayName then
                -- Check if display name matches marker
                if string.find(string.upper(detail.displayName), string.upper(markerName)) then
                    return true, slot
                end
            end
        end
    end
    
    return false
end

-- Check if chest is denomination chest by checking for denomination markers
-- Searches for numbers in the display name and matches against valid denominations
local function getDenominationFromChest(chest)
    if not chest or not chest.list then
        return nil
    end
    
    local items = chest.list()
    for slot, item in pairs(items) do
        if string.find(item.name, "paper") then
            local detail = chest.getItemDetail(slot)
            if detail and detail.displayName then
                local displayName = detail.displayName
                
                -- Skip if this is an ATM chest (contains "ATM" keyword)
                if string.find(string.upper(displayName), "ATM") then
                    return nil
                end
                
                -- Skip if this is MINT or OUTPUT
                local upper = string.upper(displayName)
                if string.find(upper, "MINT") or string.find(upper, "OUTPUT") then
                    return nil
                end
                
                -- Extract all numbers from the display name
                -- This allows flexible naming like "100 dollar bill", "my 50 note", "5credits", etc.
                for number in string.gmatch(displayName, "%d+") do
                    local value = tonumber(number)
                    
                    -- Check if this number matches a valid denomination
                    for _, denom in ipairs(config.currency.denominations) do
                        if value == denom.value then
                            return denom.value, slot
                        end
                    end
                end
            end
        end
    end
    
    return nil
end

-- Check if chest is a void chest for a specific ATM by checking for ATM number markers
-- Searches for numbers prefixed with "ATM" in the display name
local function getATMNumberFromChest(chest)
    if not chest or not chest.list then
        return nil
    end
    
    local items = chest.list()
    for slot, item in pairs(items) do
        if string.find(item.name, "paper") then
            local detail = chest.getItemDetail(slot)
            if detail and detail.displayName then
                local displayName = string.upper(detail.displayName)
                
                -- Look for "ATM" followed by a number
                -- Examples: "ATM1", "ATM 1", "atm_1", "This is ATM 5"
                local atmNumber = string.match(displayName, "ATM[%s_%-]*(%d+)")
                if atmNumber then
                    local atmID = tonumber(atmNumber)
                    if atmID and atmID >= 1 and atmID <= 16 then
                        return atmID, slot
                    end
                end
            end
        end
    end
    
    return nil
end

-- Scan network for chests and register them
function networkStorage.scanNetwork()
    print("Scanning peripheral network...")
    
    -- Reset storage state
    mintChest = nil
    outputChest = nil
    auxiliaryChest = nil
    denominationChests = {}
    voidChests = {}
    allChests = {}
    
    local peripherals = getNetworkPeripherals()
    local foundChests = 0
    
    for _, peripheralName in ipairs(peripherals) do
        if peripheral.hasType(peripheralName, "inventory") then
            local chest = peripheral.wrap(peripheralName)
            
            if chest then
                table.insert(allChests, {
                    name = peripheralName,
                    peripheral = chest,
                    size = chest.size()
                })
                foundChests = foundChests + 1
                
                -- Check for MINT marker
                local isMint, markerSlot = hasMarker(chest, MINT_MARKER)
                if isMint then
                    mintChest = {
                        name = peripheralName,
                        peripheral = chest,
                        markerSlot = markerSlot
                    }
                    print("  Found MINT chest: " .. peripheralName)
                end
                
                -- Check for OUTPUT marker
                local isOutput, markerSlot = hasMarker(chest, OUTPUT_MARKER)
                if isOutput then
                    outputChest = {
                        name = peripheralName,
                        peripheral = chest,
                        markerSlot = markerSlot
                    }
                    print("  Found OUTPUT chest: " .. peripheralName)
                end
                
                -- Check for AUXILIARY marker
                local isAuxiliary, markerSlot = hasMarker(chest, AUXILIARY_MARKER)
                if isAuxiliary then
                    auxiliaryChest = {
                        name = peripheralName,
                        peripheral = chest,
                        markerSlot = markerSlot
                    }
                    print("  Found AUXILIARY chest: " .. peripheralName)
                end
                
                -- Check for denomination marker
                local denomValue, markerSlot = getDenominationFromChest(chest)
                if denomValue then
                    -- Support multiple chests per denomination
                    if not denominationChests[denomValue] then
                        denominationChests[denomValue] = {}
                    end
                    table.insert(denominationChests[denomValue], {
                        name = peripheralName,
                        peripheral = chest,
                        denomination = denomValue,
                        markerSlot = markerSlot
                    })
                    print("  Found $" .. denomValue .. " denomination chest: " .. peripheralName)
                end
                
                -- Check for ATM void chest marker
                local atmID, markerSlot = getATMNumberFromChest(chest)
                if atmID then
                    voidChests[atmID] = {
                        name = peripheralName,
                        peripheral = chest,
                        atmID = atmID,
                        markerSlot = markerSlot
                    }
                    print("  Found ATM #" .. atmID .. " void chest: " .. peripheralName)
                end
            end
        end
    end
    
    print("Scan complete. Found " .. foundChests .. " chest(s) on network")
    print("  MINT chest: " .. (mintChest and "YES" or "NO"))
    print("  OUTPUT chest: " .. (outputChest and "YES" or "NO"))
    
    local denomCount = 0
    local denomTypes = 0
    for denomValue, chests in pairs(denominationChests) do
        denomTypes = denomTypes + 1
        denomCount = denomCount + #chests
    end
    print("  Denomination chests: " .. denomCount .. " chest(s) across " .. denomTypes .. " denomination(s)")
    
    local voidCount = 0
    for _ in pairs(voidChests) do
        voidCount = voidCount + 1
    end
    print("  ATM void chests: " .. voidCount)
    
    return foundChests > 0
end

-- Get mint chest
function networkStorage.getMintChest()
    return mintChest
end

-- Get output chest
function networkStorage.getOutputChest()
    return outputChest
end

-- Get denomination chest for specific value (returns first available)
function networkStorage.getDenominationChest(value)
    local chests = denominationChests[value]
    if chests and #chests > 0 then
        return chests[1]
    end
-- Get auxiliary chest
function networkStorage.getAuxiliaryChest()
    return auxiliaryChest
end

-- Get all chests for a specific denomination
function networkStorage.getDenominationChests(value)
    return denominationChests[value] or {}
end

-- Get all denomination chests
function networkStorage.getAllDenominationChests()
    return denominationChests
end

-- Get void chest for specific ATM ID
function networkStorage.getVoidChest(atmID)
    return voidChests[atmID]
end

-- Get all void chests
function networkStorage.getAllVoidChests()
    return voidChests
end

-- Transfer items from source chest to destination chest
function networkStorage.transferItems(sourceChestInfo, destChestInfo, itemFilter, maxCount)
    if not sourceChestInfo or not destChestInfo then
        return 0, "Invalid chest"
    end
    
    local source = sourceChestInfo.peripheral
    local dest = destChestInfo.peripheral
    
    if not source or not dest then
        return 0, "Chest not accessible"
    end
    
    local transferred = 0
    local items = source.list()
    
    for slot, item in pairs(items) do
        -- Skip marker slots
        if slot ~= sourceChestInfo.markerSlot then
            -- Check if item matches filter
            local matches = true
            if itemFilter then
                if itemFilter.name and item.name ~= itemFilter.name then
                    matches = false
                end
                if itemFilter.nbt then
                    local detail = source.getItemDetail(slot)
                    if not detail or detail.nbt ~= itemFilter.nbt then
                        matches = false
                    end
                end
            end
            
            if matches then
                local count = maxCount and math.min(item.count, maxCount - transferred) or item.count
                
                -- Use pushItems to transfer
                local moved = source.pushItems(destChestInfo.name, slot, count)
                transferred = transferred + moved
                
                if maxCount and transferred >= maxCount then
                    break
                end
            end
        end
    end
    
    return transferred, nil
end

-- Pull specific denomination to output chest
function networkStorage.pullDenominationToOutput(denomination, count)
    local denomChests = denominationChests[denomination]
    
    if not denomChests or #denomChests == 0 then
        return 0, "Denomination chest not found for $" .. denomination
    end
    
    if not outputChest then
        return 0, "Output chest not configured"
    end
    
    -- Transfer currency items from denomination chests to output chest
    -- Pull from multiple chests if needed
    local filter = {
        name = config.currency.itemName
    }
    
    local totalTransferred = 0
    for _, denomChest in ipairs(denomChests) do
        if totalTransferred >= count then
            break
        end
        
        local needed = count - totalTransferred
        local transferred, err = networkStorage.transferItems(denomChest, outputChest, filter, needed)
        
        if transferred and transferred > 0 then
            totalTransferred = totalTransferred + transferred
        end
    end
    
    if totalTransferred < count then
        return totalTransferred, "Only transferred " .. totalTransferred .. " of " .. count .. " items"
    end
    
    return totalTransferred, nil
end

-- Get items in mint chest for minting
function networkStorage.getMintableItems()
    if not mintChest then
        return nil, "Mint chest not configured"
    end
    
    local chest = mintChest.peripheral
    local mintableItems = {}
    
    local items = chest.list()
    for slot, item in pairs(items) do
        -- Skip marker slot
        if slot ~= mintChest.markerSlot and item.name == config.currency.itemName then
            local detail = chest.getItemDetail(slot)
            if detail and detail.nbt then
                table.insert(mintableItems, {
                    slot = slot,
                    name = item.name,
                    count = item.count,
                    nbt = detail.nbt,
                    displayName = detail.displayName
                })
            end
        end
    end
    
    return mintableItems, nil
end

-- Get items in output chest
function networkStorage.getOutputItems()
    if not outputChest then
        return nil, "Output chest not configured"
    end
    
    local chest = outputChest.peripheral
    local outputItems = {}
    
    local items = chest.list()
    for slot, item in pairs(items) do
        -- Skip marker slot
        if slot ~= outputChest.markerSlot then
            local detail = chest.getItemDetail(slot)
            table.insert(outputItems, {
                slot = slot,
                name = item.name,
                count = item.count,
                nbt = detail and detail.nbt,
                displayName = detail and detail.displayName
            })
        end
    end
    
    return outputItems, nil
end

-- Clear output chest (move items back to appropriate denomination chests)
function networkStorage.clearOutputChest()
    if not outputChest then
        return 0, "Output chest not configured"
    end
    
    local cleared = 0
    local items = outputChest.peripheral.list()
    
    for slot, item in pairs(items) do
        if slot ~= outputChest.markerSlot and item.name == config.currency.itemName then
            -- Get item detail to determine denomination
            local detail = outputChest.peripheral.getItemDetail(slot)
            
            if detail and detail.nbt then
                -- Try to find which denomination chest this belongs to
                -- For now, just leave it or implement logic to return to correct chest
                cleared = cleared + item.count
            end
        end
    end
    
    return cleared, nil
end

-- Get network status
function networkStorage.getStatus()
    return {
        mintChest = mintChest ~= nil,
        outputChest = outputChest ~= nil,
        denominationChestCount = (function()
            local count = 0
            for _ in pairs(denominationChests) do count = count + 1 end
            return count
        end)(),
        voidChestCount = (function()
            local count = 0
            for _ in pairs(voidChests) do count = count + 1 end
            return count
        end)(),
        totalChests = #allChests
    }
end

-- Sort bills from mint chest to denomination chests
function networkStorage.sortBillsToDenomChest(denomination, items)
    if not mintChest then
        return nil, "Mint chest not configured"
    end
    
    local targetChests = denominationChests[denomination]
    if not targetChests or #targetChests == 0 then
        return nil, "No chest found for denomination " .. denomination
    end
    
    local mintPeripheral = mintChest.peripheral
    local movedCount = 0
    local totalValue = 0
    
    -- Move each item to denomination chest
    for _, item in ipairs(items) do
        -- Try each denomination chest until we find one with space
        local moved = false
        for _, targetChest in ipairs(targetChests) do
            local targetPeripheral = targetChest.peripheral
            
            -- Try to push the item
            local pushed = mintPeripheral.pushItems(targetChest.name, item.slot)
            if pushed and pushed > 0 then
                movedCount = movedCount + 1
                totalValue = totalValue + item.value
                moved = true
                break
            end
        end
        
        if not moved then
            -- Could not move this item (chests full?)
            return nil, "Could not move all items - denomination chests may be full"
        end
    end
    
    return {
        movedCount = movedCount,
        totalValue = totalValue
    }, nil
end

return networkStorage
