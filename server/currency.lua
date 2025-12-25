-- server/currency.lua
-- Physical currency management with NBT-based verification

local crypto = require("lib.crypto")
local config = require("config")

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

-- Mint new currency
function currency.mint(amount, denomination)
    denomination = denomination or 1
    
    -- Get chest peripheral
    local chest = peripheral.wrap(config.server.mintChestSide)
    if not chest then
        return nil, "no_chest_found"
    end
    
    local mintedItems = {}
    local totalAmount = 0
    
    -- Find items in chest to mint
    for slot, item in pairs(chest.list()) do
        if item.name == config.currency.itemName and totalAmount < amount then
            -- Get detailed item info including NBT
            local details = chest.getItemDetail(slot)
            
            if details and details.nbt then
                -- Hash the NBT to create unique ID
                local nbtHash = details.nbt
                local currencyID = config.currency.nbtPrefix .. nbtHash
                
                -- Register in database
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
                        slot = slot
                    })
                    
                    totalAmount = totalAmount + itemValue
                end
            end
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
function currency.prepareDispense(amount, atmID)
    -- This function identifies which currency to send to which ATM
    -- The actual physical transfer is done by redstone-controlled void chests
    
    local chest = peripheral.wrap(config.server.mintChestSide)
    if not chest then
        return nil, "no_chest_found"
    end
    
    local selectedItems = {}
    local selectedValue = 0
    
    -- Find valid currency to dispense
    for slot, item in pairs(chest.list()) do
        if item.name == config.currency.itemName and selectedValue < amount then
            local details = chest.getItemDetail(slot)
            
            if details and details.nbt then
                local record, err = currency.verify(details.nbt)
                
                if record then
                    local itemValue = math.min(item.count, math.ceil((amount - selectedValue) / record.denomination)) * record.denomination
                    
                    table.insert(selectedItems, {
                        slot = slot,
                        count = math.min(item.count, math.ceil(itemValue / record.denomination)),
                        value = itemValue
                    })
                    
                    selectedValue = selectedValue + itemValue
                end
            end
        end
    end
    
    if selectedValue < amount then
        return nil, "insufficient_currency"
    end
    
    return {
        atmID = atmID,
        amount = selectedValue,
        items = selectedItems
    }, nil
end

return currency
