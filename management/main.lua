-- management/main.lua
-- Bank management console with SGL interface

local sgl = require("/lib/sgl/sgl")
local config = require("/config")
local network = require("/lib/network")
local crypto = require("/lib/crypto")

-- Initialize config
config.init()
config.load()

-- State
local authenticated = false
local managementToken = nil
local statusMessage = ""
local messageColor = colors.white
local catalogData = {}
local priceItemList = nil
local priceSelectedIndex = nil

-- Initialize modem
local modem = network.init(config.management.port)

-- Create application
local app = sgl.createApplication("CC-Bank Management Console")

-- Create root panel
local root = sgl.Panel:new(1, 1, 51, 19)
root:setTitle("CC-Bank Management")
root:setBorder(true)

-- Set root before adding children
app:setRoot(root)

-- Utility function to show message
local function showMessage(message, isError)
    statusMessage = message
    messageColor = isError and colors.red or colors.green
end

-- Utility function to communicate with server
local function sendToServer(msgType, data)
    local message = network.createMessage(msgType, data, managementToken)
    network.broadcast(modem, config.server.port, message)
    
    -- Use longer timeout (15 seconds) for shop catalog operations which may need to scan
    local timeout = (msgType == network.MSG.SHOP_GET_CATALOG or msgType == network.MSG.SHOP_RESCAN) and 15 or 5
    local response, err = network.receive(config.management.port, timeout)
    if not response then
        return nil, err or "No response from server"
    end
    
    if response.type == network.MSG.ERROR then
        return nil, response.data.message or "Unknown error"
    end
    
    return response.data, nil
end

-- Utility function to show screen
local function showScreen(screenName)
    for i = 1, #root.children do
        local child = root.children[i]
        if child.data and child.data.isScreen then
            child:setVisible(child.data.screenName == screenName)
        end
    end
    
    -- Refresh data when showing certain screens
    if screenName == "listAccounts" and refreshAccountList then
        refreshAccountList()
    elseif screenName == "listItems" and refreshItemList then
        refreshItemList()
    elseif screenName == "shopCatalog" and refreshCatalog then
        refreshCatalog()
    elseif screenName == "setPrice" and refreshCatalog then
        -- Ensure we have latest catalog for set-price selection
        refreshCatalog()
        -- populate the set-price list widget if present
        if priceItemList and catalogData then
            local listItems = {}
            for _, it in ipairs(catalogData) do
                local priceText = it.price and it.price > 0 and ("$" .. it.price) or "[No price]"
                table.insert(listItems, string.format("%s - %s (x%d)", it.displayName, priceText, it.stock))
            end
            if #listItems == 0 then
                priceItemList.items = {"No items in STORAGE chests"}
            else
                priceItemList.items = listItems
            end
        end
    elseif screenName == "stats" and refreshStats then
        refreshStats()
    end
    
    root:markDirty()
end

-- First run setup screen
local setupScreen = sgl.Panel:new(2, 2, 47, 15)
setupScreen:setBorder(false)
setupScreen:setVisible(false)
setupScreen.data = {isScreen = true, screenName = "setup"}
root:addChild(setupScreen)

local label1 = sgl.Label:new(2, 2, "Create Master Password", 43)
label1.style.fgColor = colors.yellow
setupScreen:addChild(label1)

local label2 = sgl.Label:new(2, 4, "Password:", 43)
setupScreen:addChild(label2)

local passwordInput = sgl.Input:new(2, 5, 40, 1)
passwordInput:setMasked(true)
setupScreen:addChild(passwordInput)

local label3 = sgl.Label:new(2, 7, "Confirm Password:", 43)
setupScreen:addChild(label3)

local confirmInput = sgl.Input:new(2, 8, 40, 1)
confirmInput:setMasked(true)
setupScreen:addChild(confirmInput)

local statusLabel = sgl.Label:new(2, 10, "", 43)
statusLabel.style.fgColor = colors.red
setupScreen:addChild(statusLabel)

local saveBtn = sgl.Button:new(10, 12, 25, 2, "Save & Continue")
saveBtn.style.bgColor = colors.green
saveBtn.onClick = function()
    local pass = passwordInput:getText()
    local confirm = confirmInput:getText()
    
    if pass ~= confirm then
        statusLabel:setText("Passwords do not match")
        statusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    if #pass < 8 then
        statusLabel:setText("Password too short (min 8 chars)")
        statusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    local passData = crypto.hashPassword(pass)
    -- Encode salt as base64 for safe JSON storage
    config.management.masterPasswordHash = passData.hash
    config.management.masterPasswordSalt = crypto.base64Encode(passData.salt)
    config.save()
    
    statusLabel:setText("Setup complete! Proceeding to login...")
    statusLabel.style.fgColor = colors.green
    root:markDirty()
    sleep(1)
    showScreen("login")
end
setupScreen:addChild(saveBtn)

-- Login screen
local loginScreen = sgl.Panel:new(2, 2, 47, 15)
loginScreen:setBorder(false)
loginScreen:setVisible(false)
loginScreen.data = {isScreen = true, screenName = "login"}
root:addChild(loginScreen)

local titleLabel = sgl.Label:new(10, 2, "CC-Bank Management", 43)
titleLabel.style.fgColor = colors.yellow
loginScreen:addChild(titleLabel)

local passLabel = sgl.Label:new(2, 5, "Master Password:", 43)
loginScreen:addChild(passLabel)

local loginPasswordInput = sgl.Input:new(2, 6, 40, 1)
loginPasswordInput:setMasked(true)
loginScreen:addChild(loginPasswordInput)

local loginStatusLabel = sgl.Label:new(2, 8, "", 43)
loginScreen:addChild(loginStatusLabel)

local loginBtn = sgl.Button:new(10, 10, 25, 2, "Login")
loginBtn.style.bgColor = colors.green
loginBtn.onClick = function()
    local password = loginPasswordInput:getText()
    
    if password == "" then
        loginStatusLabel:setText("Please enter password")
        loginStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    -- Reload config to ensure we have latest hash
    config.load()
    
    -- Decode salt from base64
    local salt = crypto.base64Decode(config.management.masterPasswordSalt)
    
    local ok, saltDecoded = pcall(function() return crypto.base64Decode(config.management.masterPasswordSalt) end)
    if not ok or not saltDecoded then
        saltDecoded = config.management.masterPasswordSalt
    end

    if crypto.verifyPassword(password, config.management.masterPasswordHash, saltDecoded) then
        authenticated = true
        
        -- Authenticate with server to get management session token
        local authMessage = network.createMessage(network.MSG.MGMT_LOGIN, {
            password = password
        })
        network.broadcast(modem, config.server.port, authMessage)
        
        local response, err = network.receive(config.management.port, 5)
        
        if not response then
            authenticated = false
            loginStatusLabel:setText("No response from server: " .. tostring(err))
            loginStatusLabel.style.fgColor = colors.red
            loginPasswordInput:setText("")
            root:markDirty()
            return
        end
        
        if response.type == network.MSG.ERROR then
            authenticated = false
            loginStatusLabel:setText("Auth error: " .. tostring(response.data.message))
            loginStatusLabel.style.fgColor = colors.red
            loginPasswordInput:setText("")
            root:markDirty()
            return
        end
        
        if response.type == network.MSG.SUCCESS and response.data and response.data.token then
            managementToken = response.data.token
            
            loginPasswordInput:setText("")  -- Clear on success
            loginStatusLabel:setText("")
            loginStatusLabel.style.fgColor = colors.white
            
            -- Clear focus before transitioning
            app:setFocus(nil)
            showScreen("main")
        else
            -- Local auth passed but server auth failed
            authenticated = false
            loginStatusLabel:setText("Server authentication failed")
            loginStatusLabel.style.fgColor = colors.red
            loginPasswordInput:setText("")
            root:markDirty()
        end
    else
        loginStatusLabel:setText("Invalid password")
        loginStatusLabel.style.fgColor = colors.red
        loginPasswordInput:setText("")  -- Clear on failure
        root:markDirty()
    end
end
loginScreen:addChild(loginBtn)

-- Main menu screen
local mainScreen = sgl.Panel:new(2, 2, 47, 15)
mainScreen:setBorder(false)
mainScreen:setVisible(false)
mainScreen.data = {isScreen = true, screenName = "main"}
root:addChild(mainScreen)

local mainTitle = sgl.Label:new(15, 1, "Main Menu", 43)
mainTitle.style.fgColor = colors.yellow
mainScreen:addChild(mainTitle)

local btnWidth = 40
local btnHeight = 2
local btnX = 3
local btnY = 3

local accountsBtn = sgl.Button:new(btnX, btnY, btnWidth, btnHeight, "Manage Accounts")
accountsBtn.onClick = function()
    showScreen("accounts")
end
mainScreen:addChild(accountsBtn)

local shopBtn = sgl.Button:new(btnX, btnY + 3, btnWidth, btnHeight, "Shop Management")
shopBtn.onClick = function()
    showScreen("shop")
end
mainScreen:addChild(shopBtn)

local statsBtn = sgl.Button:new(btnX, btnY + 6, btnWidth, btnHeight, "View Statistics")
statsBtn.onClick = function()
    showScreen("stats")
end
mainScreen:addChild(statsBtn)

local exitBtn = sgl.Button:new(btnX, btnY + 9, btnWidth, btnHeight, "Exit")
exitBtn.style.bgColor = colors.red
exitBtn.onClick = function()
    app:stop()
end
mainScreen:addChild(exitBtn)

-- Accounts screen
local accountsScreen = sgl.Panel:new(2, 2, 47, 15)
accountsScreen:setBorder(false)
accountsScreen:setVisible(false)
accountsScreen.data = {isScreen = true, screenName = "accounts"}
root:addChild(accountsScreen)

local accountsTitle = sgl.Label:new(10, 1, "Account Management", 43)
accountsTitle.style.fgColor = colors.yellow
accountsScreen:addChild(accountsTitle)

local createAccBtn = sgl.Button:new(3, 3, 18, 2, "Create Account")
createAccBtn.onClick = function()
    showScreen("createAccount")
end
accountsScreen:addChild(createAccBtn)

local listAccBtn = sgl.Button:new(23, 3, 18, 2, "List Accounts")
listAccBtn.onClick = function()
    showScreen("listAccounts")
end
accountsScreen:addChild(listAccBtn)

local unlockAccBtn = sgl.Button:new(3, 6, 38, 2, "Unlock Account")
unlockAccBtn.style.bgColor = colors.orange
unlockAccBtn.onClick = function()
    showScreen("unlockAccount")
end
accountsScreen:addChild(unlockAccBtn)

local resetPassBtn = sgl.Button:new(3, 9, 38, 2, "Reset Account Password")
resetPassBtn.style.bgColor = colors.blue
resetPassBtn.onClick = function()
    showScreen("resetPassword")
end
accountsScreen:addChild(resetPassBtn)

local accountsBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
accountsBackBtn.onClick = function()
    showScreen("main")
end
accountsScreen:addChild(accountsBackBtn)

-- Currency screen
-- Shop Management screen
local shopScreen = sgl.Panel:new(2, 2, 47, 15)
shopScreen:setBorder(false)
shopScreen:setVisible(false)
shopScreen.data = {isScreen = true, screenName = "shop"}
root:addChild(shopScreen)

local shopTitle = sgl.Label:new(10, 1, "Shop Management", 43)
shopTitle.style.fgColor = colors.yellow
shopScreen:addChild(shopTitle)

local viewCatalogBtn = sgl.Button:new(3, 3, 38, 2, "View Shop Catalog")
viewCatalogBtn.onClick = function()
    showScreen("shopCatalog")
end
shopScreen:addChild(viewCatalogBtn)

local setPricesBtn = sgl.Button:new(3, 6, 38, 2, "Set Item Prices")
setPricesBtn.onClick = function()
    showScreen("setPrice")
end
shopScreen:addChild(setPricesBtn)

local rescanBtn = sgl.Button:new(3, 9, 38, 2, "Rescan STORAGE Chests")
rescanBtn.style.bgColor = colors.orange
rescanBtn.onClick = function()
    showScreen("rescanStorage")
end
shopScreen:addChild(rescanBtn)

local shopBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
shopBackBtn.onClick = function()
    showScreen("main")
end
shopScreen:addChild(shopBackBtn)

-- Shop Catalog View screen (similar to inventory view in storage system)
local shopCatalogScreen = sgl.Panel:new(2, 2, 47, 15)
shopCatalogScreen:setBorder(false)
shopCatalogScreen:setVisible(false)
shopCatalogScreen.data = {isScreen = true, screenName = "shopCatalog"}
root:addChild(shopCatalogScreen)

local shopCatalogTitle = sgl.Label:new(10, 1, "Shop Catalog", 43)
shopCatalogTitle.style.fgColor = colors.yellow
shopCatalogScreen:addChild(shopCatalogTitle)

local catalogInfoLabel = sgl.Label:new(2, 2, "", 43)
catalogInfoLabel.style.fgColor = colors.gray
shopCatalogScreen:addChild(catalogInfoLabel)

-- Use a scrollable list for shop catalog
local catalogListWidget = sgl.List:new(2, 3, 43, 9)
shopCatalogScreen:addChild(catalogListWidget)

local function refreshCatalog()
    catalogInfoLabel:setText("Loading...")
    root:markDirty()
    
    local result, err = sendToServer(network.MSG.SHOP_GET_CATALOG, {})
    
    if result and result.items then
        catalogInfoLabel:setText(string.format("Items: %d | Total Stock: %d", 
            result.totalItems or 0, result.totalStock or 0))
        catalogInfoLabel.style.fgColor = colors.gray
        local listItems = {}
        -- store raw catalog data for other screens (set-price)
        catalogData = result.items or {}
        for _, item in ipairs(result.items) do
            local priceText = item.price and item.price > 0 and ("$" .. item.price) or "[No price]"
            table.insert(listItems, string.format("%s - %s (x%d)", item.displayName, priceText, item.stock))
        end
        if #listItems == 0 then
            catalogListWidget.items = {"No items in STORAGE chests"}
        else
            catalogListWidget.items = listItems
        end
    else
        catalogInfoLabel:setText("Error: " .. tostring(err))
        catalogInfoLabel.style.fgColor = colors.red
    end
    root:markDirty()
end

local catalogBackBtn = sgl.Button:new(3, 14, 15, 1, "Back")
catalogBackBtn.onClick = function()
    showScreen("shop")
end
shopCatalogScreen:addChild(catalogBackBtn)

local catalogRefreshBtn = sgl.Button:new(20, 14, 20, 1, "Refresh")
catalogRefreshBtn.onClick = function()
    refreshCatalog()
end
shopCatalogScreen:addChild(catalogRefreshBtn)

-- Set Price screen
local setPriceScreen = sgl.Panel:new(2, 2, 47, 15)
setPriceScreen:setBorder(false)
setPriceScreen:setVisible(false)
setPriceScreen.data = {isScreen = true, screenName = "setPrice"}
root:addChild(setPriceScreen)

local setPriceTitle = sgl.Label:new(10, 1, "Set Item Price", 43)
setPriceTitle.style.fgColor = colors.yellow
setPriceScreen:addChild(setPriceTitle)

local priceItemLabel = sgl.Label:new(2, 3, "Select Item (from catalog):", 43)
priceItemLabel.style.fgColor = colors.gray
setPriceScreen:addChild(priceItemLabel)

-- Use a list to select item (stores index into catalogData)
priceItemList = sgl.List:new(2, 4, 40, 4)
priceItemList.onSelectionChanged = function(index, text)
    priceSelectedIndex = index
end
setPriceScreen:addChild(priceItemList)

local newPriceLabel = sgl.Label:new(2, 8, "New Price:", 43)
setPriceScreen:addChild(newPriceLabel)

local newPriceInput = sgl.Input:new(2, 9, 40, 1)
setPriceScreen:addChild(newPriceInput)

local setPriceStatusLabel = sgl.Label:new(2, 11, "", 43)
setPriceScreen:addChild(setPriceStatusLabel)

local setPriceBtn = sgl.Button:new(10, 12, 25, 2, "Set Price")
setPriceBtn.style.bgColor = colors.green
setPriceBtn.onClick = function()
    local price = tonumber(newPriceInput:getText())
    if not price or price < 0 then
        setPriceStatusLabel:setText("Invalid price")
        setPriceStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end

    if not priceSelectedIndex or not catalogData or not catalogData[priceSelectedIndex] then
        setPriceStatusLabel:setText("Please select an item from the list")
        setPriceStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end

    local itemName = catalogData[priceSelectedIndex].name
    
    setPriceStatusLabel:setText("Updating price...")
    setPriceStatusLabel.style.fgColor = colors.white
    root:markDirty()
    
    local result, err = sendToServer(network.MSG.SHOP_SET_PRICE, {
        itemName = itemName,
        price = price
    })
    
    if result then
        setPriceStatusLabel:setText("Price updated successfully!")
        setPriceStatusLabel.style.fgColor = colors.green
        priceSelectedIndex = nil
        newPriceInput:setText("")
        -- Refresh catalog and repopulate set-price list so updated prices are shown
        refreshCatalog()
        if priceItemList and catalogData then
            local listItems = {}
            for _, it in ipairs(catalogData) do
                local priceText = it.price and it.price > 0 and ("$" .. it.price) or "[No price]"
                table.insert(listItems, string.format("%s - %s (x%d)", it.displayName, priceText, it.stock))
            end
            priceItemList.items = #listItems == 0 and {"No items in STORAGE chests"} or listItems
        end
    else
        setPriceStatusLabel:setText("Error: " .. tostring(err))
        setPriceStatusLabel.style.fgColor = colors.red
    end
    root:markDirty()
end
setPriceScreen:addChild(setPriceBtn)

-- Refresh button for set-price list
local priceRefreshBtn = sgl.Button:new(43, 4, 6, 1, "Refresh")
priceRefreshBtn.onClick = function()
    -- Refresh catalog and repopulate list
    refreshCatalog()
    if priceItemList and catalogData then
        local listItems = {}
        for _, it in ipairs(catalogData) do
            local priceText = it.price and it.price > 0 and ("$" .. it.price) or "[No price]"
            table.insert(listItems, string.format("%s - %s (x%d)", it.displayName, priceText, it.stock))
        end
        priceItemList.items = #listItems == 0 and {"No items in STORAGE chests"} or listItems
    end
    root:markDirty()
end
setPriceScreen:addChild(priceRefreshBtn)

local setPriceBackBtn = sgl.Button:new(3, 14, 15, 1, "Back")
setPriceBackBtn.onClick = function()
    showScreen("shop")
end
setPriceScreen:addChild(setPriceBackBtn)

-- Rescan Storage screen
local rescanStorageScreen = sgl.Panel:new(2, 2, 47, 15)
rescanStorageScreen:setBorder(false)
rescanStorageScreen:setVisible(false)
rescanStorageScreen.data = {isScreen = true, screenName = "rescanStorage"}
root:addChild(rescanStorageScreen)

local rescanTitle = sgl.Label:new(10, 1, "Rescan STORAGE Chests", 43)
rescanTitle.style.fgColor = colors.yellow
rescanStorageScreen:addChild(rescanTitle)

local rescanInfo = sgl.Label:new(2, 3, "Scans all STORAGE chests and updates catalog", 43)
rescanInfo.style.fgColor = colors.gray
rescanStorageScreen:addChild(rescanInfo)

local rescanStatusLabel = sgl.Label:new(2, 5, "", 43)
rescanStorageScreen:addChild(rescanStatusLabel)

local rescanBtn = sgl.Button:new(10, 7, 27, 3, "Rescan Now")
rescanBtn.style.bgColor = colors.orange
rescanBtn.onClick = function()
    rescanStatusLabel:setText("Scanning...")
    rescanStatusLabel.style.fgColor = colors.white
    root:markDirty()
    
    local result, err = sendToServer(network.MSG.SHOP_RESCAN, {})
    
    if result then
        local msg = string.format("Found %d items (%d total stock)",
            result.totalItems or 0, result.totalStock or 0)
        rescanStatusLabel:setText(msg)
        rescanStatusLabel.style.fgColor = colors.green
    else
        rescanStatusLabel:setText("Error: " .. tostring(err))
        rescanStatusLabel.style.fgColor = colors.red
    end
    root:markDirty()
end
rescanStorageScreen:addChild(rescanBtn)

local rescanBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
rescanBackBtn.onClick = function()
    showScreen("shop")
end
rescanStorageScreen:addChild(rescanBackBtn)

-- Process Items screen (kept for moving items from INPUT to STORAGE)
local processItemsScreen = sgl.Panel:new(2, 2, 47, 15)
processItemsScreen:setBorder(false)
processItemsScreen:setVisible(false)
processItemsScreen.data = {isScreen = true, screenName = "processItems"}
root:addChild(processItemsScreen)

local processTitle = sgl.Label:new(10, 1, "Process INPUT Chests", 43)
processTitle.style.fgColor = colors.yellow
processItemsScreen:addChild(processTitle)

local processInfo = sgl.Label:new(2, 3, "Move items from INPUT to STORAGE", 43)
processInfo.style.fgColor = colors.gray
processItemsScreen:addChild(processInfo)

local processStatusLabel = sgl.Label:new(2, 5, "", 43)
processItemsScreen:addChild(processStatusLabel)

local processStartBtn = sgl.Button:new(10, 7, 27, 3, "Process Now")
processStartBtn.style.bgColor = colors.green
processStartBtn.onClick = function()
    processStatusLabel:setText("Processing...")
    processStatusLabel.style.fgColor = colors.white
    root:markDirty()
    
    local result, err = sendToServer(network.MSG.SHOP_MANAGE, {
        action = "process"
    })
    
    if result then
        local msg = "Processed " .. (result.itemsProcessed or 0) .. " item stacks"
        if result.uniqueTypes then
            msg = msg .. " (" .. result.uniqueTypes .. " types)"
        end
        processStatusLabel:setText(msg)
        processStatusLabel.style.fgColor = colors.green
    else
        processStatusLabel:setText("Error: " .. tostring(err))
        processStatusLabel.style.fgColor = colors.red
    end
    root:markDirty()
end
processItemsScreen:addChild(processStartBtn)

local processBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
processBackBtn.onClick = function()
    showScreen("shop")
end
processItemsScreen:addChild(processBackBtn)

-- Stats screen
local statsScreen = sgl.Panel:new(2, 2, 47, 15)
statsScreen:setBorder(false)
statsScreen:setVisible(false)
statsScreen.data = {isScreen = true, screenName = "stats"}
root:addChild(statsScreen)

local statsTitle = sgl.Label:new(10, 1, "System Statistics", 43)
statsTitle.style.fgColor = colors.yellow
statsScreen:addChild(statsTitle)

local stat1 = sgl.Label:new(2, 3, "Loading...", 43)
statsScreen:addChild(stat1)

local stat2 = sgl.Label:new(2, 5, "", 43)
statsScreen:addChild(stat2)

local stat3 = sgl.Label:new(2, 7, "", 43)
statsScreen:addChild(stat3)

local stat4 = sgl.Label:new(2, 9, "", 43)
statsScreen:addChild(stat4)

local statsStatusLabel = sgl.Label:new(2, 11, "", 43)
statsStatusLabel.style.fgColor = colors.gray
statsScreen:addChild(statsStatusLabel)

-- Function to refresh statistics
local function refreshStats()
    stat1:setText("Loading statistics...")
    stat1.style.fgColor = colors.white
    stat2:setText("")
    stat3:setText("")
    stat4:setText("")
    statsStatusLabel:setText("")
    root:markDirty()
    
    -- Get account list
    local result, err = sendToServer(network.MSG.ACCOUNT_LIST, {})
    
    if result and result.accounts then
        local totalAccounts = result.count or #result.accounts
        local totalBalance = 0
        local lockedCount = 0
        
        for _, acc in ipairs(result.accounts) do
            totalBalance = totalBalance + (acc.balance or 0)
            if acc.locked then
                lockedCount = lockedCount + 1
            end
        end
        
        stat1:setText("Total Accounts: " .. totalAccounts)
        stat1.style.fgColor = colors.white
        stat2:setText("Total Balance: " .. totalBalance .. " Credits")
        stat2.style.fgColor = colors.white
        stat3:setText("Locked Accounts: " .. lockedCount)
        stat3.style.fgColor = lockedCount > 0 and colors.yellow or colors.white
        stat4:setText("")
        stat4.style.fgColor = colors.white
        
        statsStatusLabel:setText("Last updated: " .. os.date("%H:%M:%S"))
        statsStatusLabel.style.fgColor = colors.gray
    else
        stat1:setText("Error loading statistics")
        stat1.style.fgColor = colors.red
        stat2:setText("")
        stat3:setText("")
        stat4:setText("")
        statsStatusLabel:setText(tostring(err))
        statsStatusLabel.style.fgColor = colors.red
    end
    root:markDirty()
end

local statsRefreshBtn = sgl.Button:new(20, 13, 20, 2, "Refresh")
statsRefreshBtn.onClick = function()
    refreshStats()
end
statsScreen:addChild(statsRefreshBtn)

local statsBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
statsBackBtn.onClick = function()
    showScreen("main")
end
statsScreen:addChild(statsBackBtn)

-- ATM Management screen
-- Create Account screen
local createAccountScreen = sgl.Panel:new(2, 2, 47, 15)
createAccountScreen:setBorder(false)
createAccountScreen:setVisible(false)
createAccountScreen.data = {isScreen = true, screenName = "createAccount"}
root:addChild(createAccountScreen)

local createAccTitle = sgl.Label:new(10, 1, "Create New Account", 43)
createAccTitle.style.fgColor = colors.yellow
createAccountScreen:addChild(createAccTitle)

local usernameLabel = sgl.Label:new(2, 3, "Username:", 43)
createAccountScreen:addChild(usernameLabel)

local usernameInput = sgl.Input:new(2, 4, 40, 1)
createAccountScreen:addChild(usernameInput)

local passwordLabel = sgl.Label:new(2, 6, "Password:", 43)
createAccountScreen:addChild(passwordLabel)

local passwordInput = sgl.Input:new(2, 7, 40, 1)
passwordInput:setMasked(true)
createAccountScreen:addChild(passwordInput)

local balanceLabel = sgl.Label:new(2, 9, "Initial Balance:", 43)
createAccountScreen:addChild(balanceLabel)

local balanceInput = sgl.Input:new(2, 10, 40, 1)
balanceInput:setText("0")
createAccountScreen:addChild(balanceInput)

local createAccStatusLabel = sgl.Label:new(2, 12, "", 43)
createAccountScreen:addChild(createAccStatusLabel)

local createAccBtn = sgl.Button:new(10, 13, 25, 1, "Create Account")
createAccBtn.style.bgColor = colors.green
createAccBtn.onClick = function()
    local user = usernameInput:getText()
    local pass = passwordInput:getText()
    local bal = tonumber(balanceInput:getText()) or 0
    
    if user == "" or pass == "" then
        createAccStatusLabel:setText("Username and password required")
        createAccStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    createAccStatusLabel:setText("Creating account...")
    createAccStatusLabel.style.fgColor = colors.white
    root:markDirty()
    
    local result, err = sendToServer(network.MSG.ACCOUNT_CREATE, {
        username = user,
        password = pass,
        initialBalance = bal
    })
    
    if result then
        createAccStatusLabel:setText("Account created! #" .. tostring(result.accountNumber))
        createAccStatusLabel.style.fgColor = colors.green
        usernameInput:setText("")
        passwordInput:setText("")
        balanceInput:setText("0")
    else
        createAccStatusLabel:setText("Error: " .. tostring(err))
        createAccStatusLabel.style.fgColor = colors.red
    end
    root:markDirty()
end
createAccountScreen:addChild(createAccBtn)

local createAccBackBtn = sgl.Button:new(3, 14, 15, 1, "Back")
createAccBackBtn.onClick = function()
    showScreen("accounts")
end
createAccountScreen:addChild(createAccBackBtn)

-- List Accounts screen
local listAccountsScreen = sgl.Panel:new(2, 2, 47, 15)
listAccountsScreen:setBorder(false)
listAccountsScreen:setVisible(false)
listAccountsScreen.data = {isScreen = true, screenName = "listAccounts"}
root:addChild(listAccountsScreen)

local listAccTitle = sgl.Label:new(10, 1, "Account List", 43)
listAccTitle.style.fgColor = colors.yellow
listAccountsScreen:addChild(listAccTitle)

-- Use a scrollable list for accounts
local accountListWidget = sgl.List:new(2, 3, 43, 10)
listAccountsScreen:addChild(accountListWidget)

-- Function to refresh account list
local function refreshAccountList()
    local result, err = sendToServer(network.MSG.ACCOUNT_LIST, {})
    
    if result and result.accounts then
        local items = {}
        for _, acc in ipairs(result.accounts) do
            local lockStatus = acc.locked and " [LOCKED]" or ""
            table.insert(items, acc.username .. " (#" .. acc.accountNumber .. ") - " .. acc.balance .. " Credits" .. lockStatus)
        end
        if #items == 0 then
            accountListWidget.items = {"No accounts found"}
            accountListWidget.style = accountListWidget.style or {}
        else
            accountListWidget.items = items
        end
    else
        accountListWidget.items = {"Error loading accounts: " .. tostring(err)}
    end
    root:markDirty()
end

local listAccBackBtn = sgl.Button:new(3, 14, 15, 1, "Back")
listAccBackBtn.onClick = function()
    showScreen("accounts")
end
listAccountsScreen:addChild(listAccBackBtn)

local listAccRefreshBtn = sgl.Button:new(20, 14, 20, 1, "Refresh")
listAccRefreshBtn.onClick = function()
    refreshAccountList()
end
listAccountsScreen:addChild(listAccRefreshBtn)

-- Unlock Account screen
local unlockAccountScreen = sgl.Panel:new(2, 2, 47, 15)
unlockAccountScreen:setBorder(false)
unlockAccountScreen:setVisible(false)
unlockAccountScreen.data = {isScreen = true, screenName = "unlockAccount"}
root:addChild(unlockAccountScreen)

local unlockAccTitle = sgl.Label:new(10, 1, "Unlock Account", 43)
unlockAccTitle.style.fgColor = colors.yellow
unlockAccountScreen:addChild(unlockAccTitle)

local unlockAccNumLabel = sgl.Label:new(3, 4, "Username:", 20)
unlockAccountScreen:addChild(unlockAccNumLabel)

local unlockAccNumInput = sgl.Input:new(3, 5, 25, 1)
unlockAccountScreen:addChild(unlockAccNumInput)

local unlockAccStatusLabel = sgl.Label:new(3, 7, "", 43)
unlockAccountScreen:addChild(unlockAccStatusLabel)

local unlockAccBtn = sgl.Button:new(3, 9, 20, 2, "Unlock Account")
unlockAccBtn.style.bgColor = colors.orange
unlockAccBtn.onClick = function()
    local username = unlockAccNumInput:getText()
    if not username or username == "" then
        unlockAccStatusLabel:setText("Please enter a username")
        unlockAccStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    local result, err = sendToServer(network.MSG.ACCOUNT_UNLOCK, {
        username = username
    })
    
    if result then
        unlockAccStatusLabel:setText("Account unlocked successfully!")
        unlockAccStatusLabel.style.fgColor = colors.green
        unlockAccNumInput:setText("")
    else
        unlockAccStatusLabel:setText("Error: " .. tostring(err))
        unlockAccStatusLabel.style.fgColor = colors.red
    end
    root:markDirty()
end
unlockAccountScreen:addChild(unlockAccBtn)

local unlockAccBackBtn = sgl.Button:new(3, 12, 15, 1, "Back")
unlockAccBackBtn.onClick = function()
    showScreen("accounts")
end
unlockAccountScreen:addChild(unlockAccBackBtn)

-- Reset Password screen
local resetPasswordScreen = sgl.Panel:new(2, 2, 47, 15)
resetPasswordScreen:setBorder(false)
resetPasswordScreen:setVisible(false)
resetPasswordScreen.data = {isScreen = true, screenName = "resetPassword"}
root:addChild(resetPasswordScreen)

local resetPassTitle = sgl.Label:new(10, 1, "Reset Account Password", 43)
resetPassTitle.style.fgColor = colors.yellow
resetPasswordScreen:addChild(resetPassTitle)

local resetPassUsernameLabel = sgl.Label:new(3, 4, "Username:", 20)
resetPasswordScreen:addChild(resetPassUsernameLabel)

local resetPassUsernameInput = sgl.Input:new(3, 5, 25, 1)
resetPasswordScreen:addChild(resetPassUsernameInput)

local resetPassNewLabel = sgl.Label:new(3, 7, "New Password:", 20)
resetPasswordScreen:addChild(resetPassNewLabel)

local resetPassNewInput = sgl.Input:new(3, 8, 25, 1)
resetPassNewInput:setMasked(true)
resetPasswordScreen:addChild(resetPassNewInput)

local resetPassStatusLabel = sgl.Label:new(3, 10, "", 43)
resetPasswordScreen:addChild(resetPassStatusLabel)

local resetPassBtn = sgl.Button:new(3, 12, 20, 1, "Reset Password")
resetPassBtn.style.bgColor = colors.blue
resetPassBtn.onClick = function()
    local username = resetPassUsernameInput:getText()
    local newPassword = resetPassNewInput:getText()
    
    if not username or username == "" then
        resetPassStatusLabel:setText("Please enter a username")
        resetPassStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    if not newPassword or newPassword == "" then
        resetPassStatusLabel:setText("Please enter a new password")
        resetPassStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    local result, err = sendToServer(network.MSG.ACCOUNT_RESET_PASSWORD, {
        username = username,
        newPassword = newPassword
    })
    
    if result then
        resetPassStatusLabel:setText("Password reset successfully!")
        resetPassStatusLabel.style.fgColor = colors.green
        resetPassUsernameInput:setText("")
        resetPassNewInput:setText("")
    else
        resetPassStatusLabel:setText("Error: " .. tostring(err))
        resetPassStatusLabel.style.fgColor = colors.red
    end
    root:markDirty()
end
resetPasswordScreen:addChild(resetPassBtn)

local resetPassBackBtn = sgl.Button:new(25, 12, 15, 1, "Back")
resetPassBackBtn.onClick = function()
    showScreen("accounts")
end
resetPasswordScreen:addChild(resetPassBackBtn)

-- Determine initial screen and focus
if not config.management.masterPasswordHash then
    -- First run - show setup
    app:setFocus(passwordInput)
    showScreen("setup")
else
    -- Normal run - show login
    app:setFocus(loginPasswordInput)
    showScreen("login")
end

-- Background refresher: when viewing shop catalog or set-price, refresh every 5 seconds
local function managementRefresher()
    while true do
        if root and (root:getChildByData and (root:getChildByData("shopCatalog") or root:getChildByData("setPrice"))) then
            -- If current screen is shopCatalog or setPrice, refresh
            local currentScreen = nil
            for i = 1, #root.children do
                local c = root.children[i]
                if c.data and c.data.isScreen and c.visible then
                    currentScreen = c.data.screenName
                    break
                end
            end
            if currentScreen == "shopCatalog" or currentScreen == "setPrice" then
                pcall(function() refreshCatalog() end)
            end
        end
        sleep(5)
    end
end

parallel.waitForAny(function() app:run() end, managementRefresher)

-- Cleanup
term.clear()
term.setCursorPos(1, 1)
print("Management console closed!")
