-- lib/utils.lua
-- Utility functions for CC-Bank

local utils = {}

-- Format number with commas
function utils.formatNumber(num)
    local formatted = tostring(num)
    local k
    
    while true do
        formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
        if k == 0 then
            break
        end
    end
    
    return formatted
end

-- Format currency
function utils.formatCurrency(amount, displayName)
    displayName = displayName or "Credits"
    return utils.formatNumber(amount) .. " " .. displayName
end

-- Validate account number
function utils.validateAccountNumber(accountNumber)
    if type(accountNumber) ~= "string" then
        return false
    end
    
    if #accountNumber ~= 10 then
        return false
    end
    
    return string.match(accountNumber, "^%d+$") ~= nil
end

-- Validate username
function utils.validateUsername(username)
    if type(username) ~= "string" then
        return false
    end
    
    if #username < 3 or #username > 16 then
        return false
    end
    
    return string.match(username, "^[a-zA-Z0-9_]+$") ~= nil
end

-- Sanitize input
function utils.sanitize(input)
    if type(input) ~= "string" then
        return ""
    end
    
    -- Remove control characters
    return string.gsub(input, "%c", "")
end

-- Deep copy table
function utils.deepCopy(orig)
    local orig_type = type(orig)
    local copy
    
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[utils.deepCopy(orig_key)] = utils.deepCopy(orig_value)
        end
        setmetatable(copy, utils.deepCopy(getmetatable(orig)))
    else
        copy = orig
    end
    
    return copy
end

-- Check if peripheral exists
function utils.findPeripheral(peripheralType)
    return peripheral.find(peripheralType)
end

-- Wrap peripheral with error handling
function utils.wrapPeripheral(side)
    if not peripheral.isPresent(side) then
        return nil, "No peripheral on " .. side
    end
    
    return peripheral.wrap(side), nil
end

-- Safe JSON serialization
function utils.toJSON(data)
    local success, result = pcall(textutils.serialiseJSON, data)
    if success then
        return result, nil
    else
        return nil, result
    end
end

-- Safe JSON deserialization
function utils.fromJSON(json)
    local success, result = pcall(textutils.unserialiseJSON, json)
    if success then
        return result, nil
    else
        return nil, result
    end
end

-- Generate random string
function utils.randomString(length)
    local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
    local result = {}
    
    for i = 1, length do
        local index = math.random(1, #chars)
        result[i] = string.sub(chars, index, index)
    end
    
    return table.concat(result)
end

-- Time formatting
function utils.formatTime(epochTime)
    if not epochTime then
        return "Never"
    end
    
    local seconds = math.floor(epochTime / 1000)
    return os.date("%Y-%m-%d %H:%M:%S", seconds)
end

-- Duration formatting
function utils.formatDuration(milliseconds)
    local seconds = math.floor(milliseconds / 1000)
    local minutes = math.floor(seconds / 60)
    local hours = math.floor(minutes / 60)
    local days = math.floor(hours / 24)
    
    if days > 0 then
        return string.format("%dd %dh", days, hours % 24)
    elseif hours > 0 then
        return string.format("%dh %dm", hours, minutes % 60)
    elseif minutes > 0 then
        return string.format("%dm %ds", minutes, seconds % 60)
    else
        return string.format("%ds", seconds)
    end
end

-- Pagination helper
function utils.paginate(items, page, itemsPerPage)
    page = page or 1
    itemsPerPage = itemsPerPage or 10
    
    local totalPages = math.ceil(#items / itemsPerPage)
    local startIdx = ((page - 1) * itemsPerPage) + 1
    local endIdx = math.min(startIdx + itemsPerPage - 1, #items)
    
    local pageItems = {}
    for i = startIdx, endIdx do
        table.insert(pageItems, items[i])
    end
    
    return {
        items = pageItems,
        page = page,
        totalPages = totalPages,
        totalItems = #items,
        hasNext = page < totalPages,
        hasPrev = page > 1
    }
end

-- Center text
function utils.centerText(text, width)
    local padding = math.floor((width - #text) / 2)
    return string.rep(" ", padding) .. text
end

-- Truncate text
function utils.truncate(text, maxLength, suffix)
    suffix = suffix or "..."
    
    if #text <= maxLength then
        return text
    end
    
    return string.sub(text, 1, maxLength - #suffix) .. suffix
end

-- Wrap text to fit width
function utils.wrapText(text, width)
    local lines = {}
    local currentLine = ""
    
    for word in string.gmatch(text, "%S+") do
        if #currentLine + #word + 1 > width then
            if currentLine ~= "" then
                table.insert(lines, currentLine)
            end
            currentLine = word
        else
            if currentLine == "" then
                currentLine = word
            else
                currentLine = currentLine .. " " .. word
            end
        end
    end
    
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end
    
    return lines
end

-- Check if string contains
function utils.contains(str, substr)
    return string.find(str, substr, 1, true) ~= nil
end

-- Split string
function utils.split(str, delimiter)
    local result = {}
    local pattern = "(.-)" .. delimiter
    local lastEnd = 1
    local s, e, cap = string.find(str, pattern, 1)
    
    while s do
        if s ~= 1 or cap ~= "" then
            table.insert(result, cap)
        end
        lastEnd = e + 1
        s, e, cap = string.find(str, pattern, lastEnd)
    end
    
    if lastEnd <= #str then
        cap = string.sub(str, lastEnd)
        table.insert(result, cap)
    end
    
    return result
end

-- Trim string
function utils.trim(str)
    return string.match(str, "^%s*(.-)%s*$")
end

return utils
