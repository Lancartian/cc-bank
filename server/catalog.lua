-- server/catalog.lua
-- Shop item catalog management

local config = require("/config")

local catalog = {}

-- Catalog database
local catalogDB = {}  -- itemName -> {price, category, description}
local DATA_FILE = "/data/catalog.json"

-- Load catalog from file
function catalog.load()
    if fs.exists(DATA_FILE) then
        local file = fs.open(DATA_FILE, "r")
        if file then
            local content = file.readAll()
            file.close()
            catalogDB = textutils.unserialiseJSON(content) or {}
            return true
        end
    end
    catalogDB = {}
    return true
end

-- Save catalog to file
function catalog.save()
    local file = fs.open(DATA_FILE, "w")
    if file then
        file.write(textutils.serialiseJSON(catalogDB))
        file.close()
        return true
    end
    return false
end

-- Add or update item in catalog
function catalog.setItem(itemName, price, category, description)
    if not itemName or not price then
        return false, "item_name_and_price_required"
    end
    
    if price < 0 then
        return false, "price_must_be_positive"
    end
    
    catalogDB[itemName] = {
        name = itemName,
        price = price,
        category = category or "General",
        description = description or "",
        updated = os.epoch("utc")
    }
    
    catalog.save()
    return true, nil
end

-- Remove item from catalog
function catalog.removeItem(itemName)
    if catalogDB[itemName] then
        catalogDB[itemName] = nil
        catalog.save()
        return true
    end
    return false, "item_not_found"
end

-- Get item info
function catalog.getItem(itemName)
    return catalogDB[itemName]
end

-- Get all items
function catalog.getAllItems()
    local items = {}
    for name, data in pairs(catalogDB) do
        table.insert(items, data)
    end
    return items
end

-- Get items by category
function catalog.getItemsByCategory(category)
    local items = {}
    for name, data in pairs(catalogDB) do
        if data.category == category then
            table.insert(items, data)
        end
    end
    return items
end

-- Get all categories
function catalog.getCategories()
    local categories = {}
    local seen = {}
    
    for name, data in pairs(catalogDB) do
        if data.category and not seen[data.category] then
            table.insert(categories, data.category)
            seen[data.category] = true
        end
    end
    
    table.sort(categories)
    return categories
end

-- Search items by name or description
function catalog.search(query)
    local results = {}
    local queryLower = string.lower(query)
    
    for name, data in pairs(catalogDB) do
        local nameLower = string.lower(data.name)
        local descLower = string.lower(data.description or "")
        
        if string.find(nameLower, queryLower, 1, true) or 
           string.find(descLower, queryLower, 1, true) then
            table.insert(results, data)
        end
    end
    
    return results
end

-- Get catalog statistics
function catalog.getStats()
    local totalItems = 0
    local categories = {}
    
    for name, data in pairs(catalogDB) do
        totalItems = totalItems + 1
        local cat = data.category or "Uncategorized"
        categories[cat] = (categories[cat] or 0) + 1
    end
    
    return {
        totalItems = totalItems,
        categories = categories
    }
end

return catalog
