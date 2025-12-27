-- server/shop_catalog.lua
-- Automatic shop catalog system inspired by CC-STR storage system
-- Scans STORAGE chests to build catalog automatically

local textutils = textutils
local fs = fs

local catalog = {}

-- State
local itemCatalog = {}  -- {itemName = {displayName, totalStock, price, locations = {chestName = count}}}
local cacheValid = false
local lastScanTime = 0
local isScanning = false  -- Prevent concurrent scans
local CACHE_FILE = "shop_catalog_cache.dat"

-- Dependencies (lazy loaded to avoid circular dependencies)
local networkStorage = nil

-- Get network storage module
local function getNetworkStorage()
    if not networkStorage then
        networkStorage = require("/server/network_storage")
    end
    return networkStorage
end

-- Save cache to disk
local function saveCache()
    local file = fs.open(CACHE_FILE, "w")
    if file then
        file.write(textutils.serialize({
            itemCatalog = itemCatalog,
            lastScanTime = os.epoch("utc")
        }))
        file.close()
        return true
    end
    return false
end

-- Load cache from disk
local function loadCache()
    if not fs.exists(CACHE_FILE) then
        return false
    end
    
    local file = fs.open(CACHE_FILE, "r")
    if file then
        local content = file.readAll()
        file.close()
        
        local success, data = pcall(textutils.unserialize, content)
        if success and data then
            itemCatalog = data.itemCatalog or {}
            lastScanTime = data.lastScanTime or 0
            cacheValid = true
            return true
        end
    end
    return false
end

-- Initialize catalog system
function catalog.initialize()
    local storage = getNetworkStorage()
    
    -- Try to load cached data first
    if loadCache() then
        -- Quick validation: check if we still have the expected storage chests
        local storageChests = storage.getStorageChests()
        if #storageChests > 0 then
            -- Cache is potentially valid
            print("[SHOP CATALOG] Loaded from cache: " .. catalog.getItemCount() .. " items")
            return true
        end
    end
    
    -- Cache not available or invalid, do full scan
    print("[SHOP CATALOG] Cache invalid, performing full scan")
    local success, result = pcall(catalog.rescan)
    
    if not success then
        print("[SHOP CATALOG] Error during scan: " .. tostring(result))
        isScanning = false  -- Reset flag on error
        return false
    end
    
    return result
end

-- Scan all STORAGE chests and build catalog
function catalog.rescan()
    if isScanning then
        print("[SHOP CATALOG] Scan already in progress, skipping")
        return false
    end
    
    isScanning = true
    print("[SHOP CATALOG] Starting rescan...")
    itemCatalog = {}
    local storage = getNetworkStorage()
    
    -- Get all STORAGE chests from network_storage
    local storageChests = storage.getStorageChests()
    print("[SHOP CATALOG] Found " .. #storageChests .. " STORAGE chests")
    
    if #storageChests == 0 then
        -- No storage chests found, but this is OK - empty catalog
        print("[SHOP CATALOG] No STORAGE chests found, creating empty catalog")
        cacheValid = true
        lastScanTime = os.epoch("utc")
        saveCache()
        return true
    end
    
    -- Scan each STORAGE chest
    for chestIndex, chestInfo in ipairs(storageChests) do
        print("[SHOP CATALOG] Scanning chest " .. chestIndex .. "/" .. #storageChests .. ": " .. chestInfo.name)
        local chest = chestInfo.peripheral  -- Already wrapped
        if chest and chest.list then
            local success, items = pcall(function() return chest.list() end)
            
            -- Check if list() succeeded and returned valid data
            if success and items and type(items) == "table" then
                local itemCount = 0
                for slot, item in pairs(items) do
                    -- Validate item data
                    if item and item.name and item.count then
                        itemCount = itemCount + 1
                        local shouldSkip = false
                        
                        -- Skip STORAGE marker papers specifically
                        if item.name == "minecraft:paper" then
                            local detailSuccess, detail = pcall(function() return chest.getItemDetail(slot) end)
                            if detailSuccess and detail and detail.displayName and detail.displayName == "STORAGE" then
                                shouldSkip = true
                            end
                        end
                        
                        if not shouldSkip then
                            -- Initialize item entry if needed
                            if not itemCatalog[item.name] then
                                itemCatalog[item.name] = {
                                    name = item.name,
                                    displayName = nil,
                                    totalStock = 0,
                                    price = 0,  -- Default price, can be set by management console
                                    locations = {}
                                }
                            end
                            
                            -- Add to total stock
                            itemCatalog[item.name].totalStock = itemCatalog[item.name].totalStock + item.count
                            
                            -- Track location (use string name as key)
                            if not itemCatalog[item.name].locations[chestInfo.name] then
                                itemCatalog[item.name].locations[chestInfo.name] = 0
                            end
                            itemCatalog[item.name].locations[chestInfo.name] = 
                                itemCatalog[item.name].locations[chestInfo.name] + item.count
                        end
                    end
                end
                print("[SHOP CATALOG] Scanned " .. itemCount .. " items from " .. chestInfo.name)
            else
                print("[SHOP CATALOG] Failed to list items from " .. chestInfo.name)
            end
        end
    end
    
    -- Get display names for items
    print("[SHOP CATALOG] Fetching display names for " .. catalog.getItemCount() .. " unique items")
    for itemName, itemData in pairs(itemCatalog) do
        -- Try to get detailed info from first location
        for chestName, _ in pairs(itemData.locations) do
            -- Validate chestName is a string
            if type(chestName) == "string" then
                -- chestName is already a string peripheral name
                local wrapSuccess, chest = pcall(function() return peripheral.wrap(chestName) end)
                if wrapSuccess and chest and chest.list then
                    local listSuccess, items = pcall(function() return chest.list() end)
                    -- Check if list() returned valid data
                    if listSuccess and items and type(items) == "table" then
                        for slot, item in pairs(items) do
                            if item and item.name == itemName then
                                local detailSuccess, detail = pcall(function() return chest.getItemDetail(slot) end)
                                if detailSuccess and detail and detail.displayName then
                                    itemData.displayName = detail.displayName
                                    break
                                end
                            end
                        end
                    end
                end
            end
            if itemData.displayName then
                break
            end
        end
    end
    
    -- Mark cache as valid and save to disk
    print("[SHOP CATALOG] Scan complete. Items: " .. catalog.getItemCount() .. ", Stock: " .. catalog.getTotalStock())
    cacheValid = true
    lastScanTime = os.epoch("utc")
    isScanning = false
    saveCache()
    
    return true
end

-- Get all catalog items
function catalog.getAll()
    -- Don't try to initialize if already scanning
    if not cacheValid and not isScanning then
        print("[SHOP CATALOG] Cache not valid, attempting initialization")
        catalog.initialize()
    end
    
    local items = {}
    for itemName, itemData in pairs(itemCatalog) do
        table.insert(items, {
            name = itemName,
            displayName = itemData.displayName or itemName,
            stock = itemData.totalStock,
            price = itemData.price
        })
    end
    
    -- Sort by display name
    table.sort(items, function(a, b)
        return a.displayName < b.displayName
    end)
    
    return items
end

-- Search catalog items
function catalog.search(searchTerm)
    local results = {}
    local searchLower = string.lower(searchTerm)
    
    for itemName, itemData in pairs(itemCatalog) do
        local itemNameLower = string.lower(itemName)
        local displayNameLower = itemData.displayName and string.lower(itemData.displayName) or ""
        
        -- Check if search term matches
        if string.find(itemNameLower, searchLower, 1, true) or 
           string.find(displayNameLower, searchLower, 1, true) then
            
            table.insert(results, {
                name = itemName,
                displayName = itemData.displayName or itemName,
                stock = itemData.totalStock,
                price = itemData.price
            })
        end
    end
    
    -- Sort by display name
    table.sort(results, function(a, b)
        return a.displayName < b.displayName
    end)
    
    return results
end

-- Get item by name
function catalog.getItem(itemName)
    if itemCatalog[itemName] then
        return {
            name = itemName,
            displayName = itemCatalog[itemName].displayName or itemName,
            stock = itemCatalog[itemName].totalStock,
            price = itemCatalog[itemName].price,
            locations = itemCatalog[itemName].locations
        }
    end
    return nil
end

-- Set price for an item
function catalog.setPrice(itemName, price)
    if itemCatalog[itemName] and price >= 0 then
        itemCatalog[itemName].price = price
        saveCache()
        return true
    end
    return false
end

-- Set display name for an item (custom rename)
function catalog.setDisplayName(itemName, displayName)
    if itemCatalog[itemName] and displayName and displayName ~= "" then
        itemCatalog[itemName].displayName = displayName
        saveCache()
        return true
    end
    return false
end

-- Check if item is in stock with enough quantity
function catalog.checkStock(itemName, quantity)
    if not itemCatalog[itemName] then
        return false, "Item not found"
    end
    
    if itemCatalog[itemName].totalStock < quantity then
        return false, "Insufficient stock"
    end
    
    return true
end

-- Get total number of unique items
function catalog.getItemCount()
    local count = 0
    for _ in pairs(itemCatalog) do
        count = count + 1
    end
    return count
end

-- Get total stock across all items
function catalog.getTotalStock()
    local total = 0
    for _, itemData in pairs(itemCatalog) do
        total = total + itemData.totalStock
    end
    return total
end

-- Get last scan time
function catalog.getLastScanTime()
    return lastScanTime
end

-- Check if cache is valid
function catalog.isCacheValid()
    return cacheValid
end

-- Invalidate cache (for external use)
function catalog.invalidateCache()
    cacheValid = false
end

return catalog
