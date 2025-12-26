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
    
    local response, err = network.receive(config.management.port, 5)
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
    
    if crypto.verifyPassword(password, config.management.masterPasswordHash, salt) then
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

local addItemBtn = sgl.Button:new(3, 3, 18, 2, "Add Item")
addItemBtn.onClick = function()
    showScreen("addItem")
end
shopScreen:addChild(addItemBtn)

local listItemsBtn = sgl.Button:new(23, 3, 18, 2, "List Items")
listItemsBtn.onClick = function()
    showScreen("listItems")
end
shopScreen:addChild(listItemsBtn)

local shopBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
shopBackBtn.onClick = function()
    showScreen("main")
end
shopScreen:addChild(shopBackBtn)

-- Add Item screen
local addItemScreen = sgl.Panel:new(2, 2, 47, 15)
addItemScreen:setBorder(false)
addItemScreen:setVisible(false)
addItemScreen.data = {isScreen = true, screenName = "addItem"}
root:addChild(addItemScreen)

local addItemTitle = sgl.Label:new(10, 1, "Add Shop Item", 43)
addItemTitle.style.fgColor = colors.yellow
addItemScreen:addChild(addItemTitle)

local nameLabel = sgl.Label:new(2, 3, "Item Name:", 43)
addItemScreen:addChild(nameLabel)

local nameInput = sgl.Input:new(2, 4, 40, 1)
addItemScreen:addChild(nameInput)

local priceLabel = sgl.Label:new(2, 5, "Price:", 43)
addItemScreen:addChild(priceLabel)

local priceInput = sgl.Input:new(2, 6, 40, 1)
addItemScreen:addChild(priceInput)

local categoryLabel = sgl.Label:new(2, 7, "Category:", 43)
addItemScreen:addChild(categoryLabel)

local categoryInput = sgl.Input:new(2, 8, 40, 1)
addItemScreen:addChild(categoryInput)

local descLabel = sgl.Label:new(2, 9, "Description:", 43)
addItemScreen:addChild(descLabel)

local descInput = sgl.Input:new(2, 10, 40, 1)
addItemScreen:addChild(descInput)

local addStatusLabel = sgl.Label:new(2, 11, "", 43)
addItemScreen:addChild(addStatusLabel)

local addBtn = sgl.Button:new(10, 12, 25, 2, "Add Item")
addBtn.style.bgColor = colors.green
addBtn.onClick = function()
    local itemName = nameInput:getText()
    local itemPrice = tonumber(priceInput:getText())
    local itemCategory = categoryInput:getText()
    local itemDesc = descInput:getText()
    
    if itemName == "" or not itemPrice or itemPrice <= 0 then
        addStatusLabel:setText("Invalid name or price")
        addStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    addStatusLabel:setText("Adding...")
    addStatusLabel.style.fgColor = colors.white
    root:markDirty()
    
    local result, err = sendToServer(network.MSG.SHOP_MANAGE, {
        action = "add",
        itemName = itemName,
        price = itemPrice,
        category = itemCategory,
        description = itemDesc
    })
    
    if result then
        addStatusLabel:setText("Item added successfully")
        addStatusLabel.style.fgColor = colors.green
        nameInput:setText("")
        priceInput:setText("")
        categoryInput:setText("")
        descInput:setText("")
    else
        addStatusLabel:setText("Error: " .. tostring(err))
        addStatusLabel.style.fgColor = colors.red
    end
    root:markDirty()
end
addItemScreen:addChild(addBtn)

local addItemBackBtn = sgl.Button:new(3, 14, 15, 1, "Back")
addItemBackBtn.onClick = function()
    showScreen("shop")
end
addItemScreen:addChild(addItemBackBtn)

-- List Items screen
local listItemsScreen = sgl.Panel:new(2, 2, 47, 15)
listItemsScreen:setBorder(false)
listItemsScreen:setVisible(false)
listItemsScreen.data = {isScreen = true, screenName = "listItems"}
root:addChild(listItemsScreen)

local listItemsTitle = sgl.Label:new(10, 1, "Shop Items", 43)
listItemsTitle.style.fgColor = colors.yellow
listItemsScreen:addChild(listItemsTitle)

local itemListLabels = {}
for i = 1, 10 do
    local label = sgl.Label:new(2, 2 + i, "", 43)
    label.style.fgColor = colors.white
    listItemsScreen:addChild(label)
    itemListLabels[i] = label
end

local function refreshItemList()
    local result, err = sendToServer(network.MSG.SHOP_BROWSE, {})
    
    if result and result.items then
        local items = result.items
        for i = 1, 10 do
            if items[i] then
                itemListLabels[i]:setText(items[i].displayName .. " - $" .. items[i].price)
            else
                itemListLabels[i]:setText("")
            end
        end
        
        if #items == 0 then
            itemListLabels[1]:setText("No items in catalog")
            itemListLabels[1].style.fgColor = colors.gray
        end
    else
        itemListLabels[1]:setText("Error loading items")
        itemListLabels[1].style.fgColor = colors.red
    end
    root:markDirty()
end

local listItemsBackBtn = sgl.Button:new(3, 14, 15, 1, "Back")
listItemsBackBtn.onClick = function()
    showScreen("shop")
end
listItemsScreen:addChild(listItemsBackBtn)

local listItemsRefreshBtn = sgl.Button:new(20, 14, 20, 1, "Refresh")
listItemsRefreshBtn.onClick = function()
    refreshItemList()
end
listItemsScreen:addChild(listItemsRefreshBtn)

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

local accountListLabels = {}
for i = 1, 10 do
    local label = sgl.Label:new(2, 2 + i, "", 43)
    label.style.fgColor = colors.white
    listAccountsScreen:addChild(label)
    accountListLabels[i] = label
end

-- Function to refresh account list
local function refreshAccountList()
    local result, err = sendToServer(network.MSG.ACCOUNT_LIST, {})
    
    if result and result.accounts then
        for i = 1, 10 do
            if result.accounts[i] then
                local acc = result.accounts[i]
                accountListLabels[i]:setText(acc.username .. " (#" .. acc.accountNumber .. ") - " .. acc.balance .. " Credits")
                accountListLabels[i].style.fgColor = colors.white
            else
                accountListLabels[i]:setText("")
            end
        end
        
        if #result.accounts == 0 then
            accountListLabels[1]:setText("No accounts found")
            accountListLabels[1].style.fgColor = colors.gray
        end
    else
        accountListLabels[1]:setText("Error loading accounts")
        accountListLabels[1].style.fgColor = colors.red
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

app:run()

-- Cleanup
term.clear()
term.setCursorPos(1, 1)
print("Management console closed!")
