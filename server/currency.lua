-- server/currency.lua
-- Physical currency management with NBT-based verification

local crypto = require("/lib/crypto")
local config = require("/config")
local networkStorage = require("/server/network_storage")

local currency = {}

-- Currency database (NBT hash -> amount)
local currencyDB = {}

-- Load currency database
function currency.load()
    if fs.exists(config.server.currencyFile) then
        local file = fs.open(config.server.currencyFile, "r")
        if file then
            local content = file.readAll()
            file.close()
            currencyDB = textutils.unserialiseJSON(content) or {}
            return true
        end
    end
    return false
end

-- Save currency database
function currency.save()
    local file = fs.open(config.server.currencyFile, "w")
    if file then
        file.write(textutils.serialiseJSON(currencyDB))
        file.close()
        return true
    end
    return false
end

-- Parse denomination from book display name
local function parseDenomination(displayName)
    if not displayName then return nil end
    
    -- Try to extract number from the beginning of the name
    -- Matches: "1 Token", "5 Credits", "10 Credit", "100", etc.
    local num = string.match(displayName, "^(%d+)")
    if num then
        return tonumber(num)
    end
    
    return nil
end

-- Mint new currency from items in mint chest, automatically sorting by book names
function currency.mintAndSort()
    -- Get mintable items from network storage
    local mintableItems, err = networkStorage.getMintableItems()
    if not mintableItems then
        return nil, err or "no_mint_chest"
    end
    
    local mintedByDenom = {}  -- Track minted items by denomination
    local totalAmount = 0
    local processedCount = 0
    
    -- Process each item in mint chest
    for _, item in ipairs(mintableItems) do
        -- Parse denomination from display name
        local denomination = parseDenomination(item.displayName)
        
        if denomination then
            -- Use the NBT hash as unique currency ID
            local nbtHash = item.nbt
            local currencyID = config.currency.nbtPrefix .. nbtHash
            
            -- Register in database if not already registered
            local itemValue = item.count * denomination
            
            if not currencyDB[currencyID] then
                currencyDB[currencyID] = {
                    id = currencyID,
                    nbtHash = nbtHash,
                    denomination = denomination,
                    itemCount = item.count,
                    value = itemValue,
                    minted = os.epoch("utc"),
                    valid = true
                }
                
                -- Track for sorting
                if not mintedByDenom[denomination] then
                    mintedByDenom[denomination] = {}
                end
                
                table.insert(mintedByDenom[denomination], {
                    id = currencyID,
                    value = itemValue,
                    slot = item.slot,
                    count = item.count
                })
                
                totalAmount = totalAmount + itemValue
                processedCount = processedCount + 1
            end
        end
    end
    
    -- Now sort the items into denomination chests
    local sortResults = {}
    for denom, items in pairs(mintedByDenom) do
        local moved, err = networkStorage.sortBillsToDenomChest(denom, items)
        if moved then
            sortResults[denom] = moved
        else
            sortResults[denom] = {error = err}
        end
    end
    
    currency.save()
    
    return {
        totalAmount = totalAmount,
        processedCount = processedCount,
        mintedByDenom = mintedByDenom,
        sortResults = sortResults
    }, nil
end

-- Mint new currency from items in mint chest (legacy function)
function currency.mint(amount, denomination)
    denomination = denomination or 1
    
    -- Get mintable items from network storage
    local mintableItems, err = networkStorage.getMintableItems()
    if not mintableItems then
        return nil, err or "no_mint_chest"
    end
    
    local mintedItems = {}
    local totalAmount = 0
    
    -- Process each item in mint chest
    for _, item in ipairs(mintableItems) do
        if totalAmount >= amount then
            break
        end
        
        -- Use the NBT hash as unique currency ID
        -- This hash represents the signed book's unique signature
        local nbtHash = item.nbt  -- Already a hash string from CC:Tweaked
        local currencyID = config.currency.nbtPrefix .. nbtHash
        
        -- Register in database if not already registered
        local itemValue = item.count * denomination
        
        if not currencyDB[currencyID] then
            currencyDB[currencyID] = {
                id = currencyID,
                nbtHash = nbtHash,
                denomination = denomination,
                itemCount = item.count,
                value = itemValue,
                minted = os.epoch("utc"),
                valid = true
            }
            
            table.insert(mintedItems, {
                id = currencyID,
                value = itemValue,
                slot = item.slot
            })
            
            totalAmount = totalAmount + itemValue
        end
    end
    
    currency.save()
    
    return {
        totalAmount = totalAmount,
        items = mintedItems,
        count = #mintedItems
    }, nil
end

-- Verify currency is authentic
function currency.verify(nbtHash)
    local currencyID = config.currency.nbtPrefix .. nbtHash
    local record = currencyDB[currencyID]
    
    if not record then
        return nil, "currency_not_found"
    end
    
    if not record.valid then
        return nil, "currency_invalid"
    end
    
    return record, nil
end

-- Verify items in a container
function currency.verifyContainer(containerSide)
    local container = peripheral.wrap(containerSide)
    if not container then
        return nil, "no_container_found"
    end
    
    local totalValue = 0
    local verifiedItems = {}
    
    for slot, item in pairs(container.list()) do
        if item.name == config.currency.itemName then
            local details = container.getItemDetail(slot)
            
            if details and details.nbt then
                local record, err = currency.verify(details.nbt)
                
                if record then
                    local itemValue = item.count * record.denomination
                    totalValue = totalValue + itemValue
                    
                    table.insert(verifiedItems, {
                        slot = slot,
                        count = item.count,
                        value = itemValue,
                        denomination = record.denomination
                    })
                end
            end
        end
    end
    
    return {
        totalValue = totalValue,
        items = verifiedItems,
        count = #verifiedItems
    }, nil
end

-- Invalidate currency (mark as spent/destroyed)
function currency.invalidate(nbtHash)
    local currencyID = config.currency.nbtPrefix .. nbtHash
    local record = currencyDB[currencyID]
    
    if not record then
        return false, "currency_not_found"
    end
    
    record.valid = false
    record.invalidated = os.epoch("utc")
    
    currency.save()
    return true, nil
end

-- Get total currency supply
function currency.getTotalSupply()
    local total = 0
    local validCount = 0
    
    for id, record in pairs(currencyDB) do
        if record.valid then
            total = total + record.value
            validCount = validCount + 1
        end
    end
    
    return {
        totalValue = total,
        validCurrency = validCount,
        totalMinted = table.maxn(currencyDB) or 0
    }
end

-- Prepare currency for dispensing to ATM
-- Selects appropriate denominations (bills) and moves them to output chest
function currency.prepareDispense(amount, atmID)
    -- This function calculates which bills are needed and moves them to output chest
    -- The output chest items will then be transferred to the ATM's void chest
    
    local selectedBills = {}
    local selectedValue = 0
    local remaining = amount
    
    -- Build sorted denomination list (prefer large bills if configured)
    local denomList = {}
    for _, denom in ipairs(config.currency.denominations) do
        table.insert(denomList, denom.value)
    end
    
    -- Sort by value (largest first if preferLargeBills, smallest first otherwise)
    table.sort(denomList, function(a, b)
        if config.currency.preferLargeBills then
            return a > b
        else
            return a < b
        end
    end)
    
    -- Calculate how many of each denomination we need
    for _, denom in ipairs(denomList) do
        if remaining <= 0 then break end
        
        local needed = math.floor(remaining / denom)
        if needed > 0 then
            table.insert(selectedBills, {
                denomination = denom,
                count = needed
            })
            selectedValue = selectedValue + (needed * denom)
            remaining = remaining - (needed * denom)
        end
    end
    
    if selectedValue < amount then
        return nil, "insufficient_currency_exact_change"
    end
    
    -- Now transfer the bills to output chest using network storage
    for _, bill in ipairs(selectedBills) do
        local transferred, err = networkStorage.pullDenominationToOutput(bill.denomination, bill.count)
        
        if not transferred or transferred < bill.count then
            return nil, "failed_to_transfer_denomination_" .. bill.denomination .. ": " .. (err or "unknown")
        end
    end
    
    return {
        atmID = atmID,
        amount = selectedValue,
        bills = selectedBills
    }, nil
end

return currency

