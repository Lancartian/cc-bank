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

local currencyBtn = sgl.Button:new(btnX, btnY + 3, btnWidth, btnHeight, "Mint Currency")
currencyBtn.onClick = function()
    showScreen("currency")
end
mainScreen:addChild(currencyBtn)

local statsBtn = sgl.Button:new(btnX, btnY + 6, btnWidth, btnHeight, "View Statistics")
statsBtn.onClick = function()
    showScreen("stats")
end
mainScreen:addChild(statsBtn)

local atmBtn = sgl.Button:new(btnX, btnY + 9, btnWidth, btnHeight, "ATM Management")
atmBtn.onClick = function()
    showScreen("atm")
end
mainScreen:addChild(atmBtn)

local exitBtn = sgl.Button:new(btnX, btnY + 12, btnWidth, btnHeight, "Exit")
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
local currencyScreen = sgl.Panel:new(2, 2, 47, 15)
currencyScreen:setBorder(false)
currencyScreen:setVisible(false)
currencyScreen.data = {isScreen = true, screenName = "currency"}
root:addChild(currencyScreen)

local currencyTitle = sgl.Label:new(10, 1, "Currency Minting", 43)
currencyTitle.style.fgColor = colors.yellow
currencyScreen:addChild(currencyTitle)

local currencyInfo = sgl.Label:new(2, 3, "Name books with denomination", 43)
currencyScreen:addChild(currencyInfo)

local currencyInfo2 = sgl.Label:new(2, 4, "(e.g. '1 Token', '5 Credits')", 43)
currencyScreen:addChild(currencyInfo2)

local currencyStatusLabel = sgl.Label:new(2, 6, "", 43)
currencyScreen:addChild(currencyStatusLabel)

local mintBtn = sgl.Button:new(8, 9, 30, 3, "Process Mint Chest")
mintBtn.style.bgColor = colors.green
mintBtn.onClick = function()
    currencyStatusLabel:setText("Processing...")
    currencyStatusLabel.style.fgColor = colors.white
    root:markDirty()
    
    local result, err = sendToServer(network.MSG.CURRENCY_MINT, {
        autoSort = true
    })
    
    if result then
        local msg = "Minted " .. result.totalAmount .. " Credits"
        if result.processedCount then
            msg = msg .. " (" .. result.processedCount .. " books)"
        end
        currencyStatusLabel:setText(msg)
        currencyStatusLabel.style.fgColor = colors.green
    else
        currencyStatusLabel:setText("Error: " .. tostring(err))
        currencyStatusLabel.style.fgColor = colors.red
    end
    root:markDirty()
end
currencyScreen:addChild(mintBtn)

local currencyBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
currencyBackBtn.onClick = function()
    showScreen("main")
end
currencyScreen:addChild(currencyBackBtn)

-- Stats screen
local statsScreen = sgl.Panel:new(2, 2, 47, 15)
statsScreen:setBorder(false)
statsScreen:setVisible(false)
statsScreen.data = {isScreen = true, screenName = "stats"}
root:addChild(statsScreen)

local statsTitle = sgl.Label:new(10, 1, "System Statistics", 43)
statsTitle.style.fgColor = colors.yellow
statsScreen:addChild(statsTitle)

local stat1 = sgl.Label:new(2, 3, "Total Accounts: 0", 43)
statsScreen:addChild(stat1)

local stat2 = sgl.Label:new(2, 4, "Total Transactions: 0", 43)
statsScreen:addChild(stat2)

local stat3 = sgl.Label:new(2, 5, "Currency Supply: 0 Credits", 43)
statsScreen:addChild(stat3)

local statsBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
statsBackBtn.onClick = function()
    showScreen("main")
end
statsScreen:addChild(statsBackBtn)

-- ATM Management screen
local atmScreen = sgl.Panel:new(2, 2, 47, 15)
atmScreen:setBorder(false)
atmScreen:setVisible(false)
atmScreen.data = {isScreen = true, screenName = "atm"}
root:addChild(atmScreen)

local atmTitle = sgl.Label:new(10, 1, "ATM Management", 43)
atmTitle.style.fgColor = colors.yellow
atmScreen:addChild(atmTitle)

local authorizeBtn = sgl.Button:new(3, 3, 18, 2, "Authorize ATM")
authorizeBtn.onClick = function()
    showScreen("authorizeATM")
end
atmScreen:addChild(authorizeBtn)

local listATMBtn = sgl.Button:new(23, 3, 18, 2, "List ATMs")
listATMBtn.onClick = function()
    showScreen("listATMs")
end
atmScreen:addChild(listATMBtn)

local atmBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
atmBackBtn.onClick = function()
    showScreen("main")
end
atmScreen:addChild(atmBackBtn)

-- Authorize ATM screen
local authorizeATMScreen = sgl.Panel:new(2, 2, 47, 15)
authorizeATMScreen:setBorder(false)
authorizeATMScreen:setVisible(false)
authorizeATMScreen.data = {isScreen = true, screenName = "authorizeATM"}
root:addChild(authorizeATMScreen)

local authTitle = sgl.Label:new(10, 1, "Authorize ATM", 43)
authTitle.style.fgColor = colors.yellow
authorizeATMScreen:addChild(authTitle)

local idLabel = sgl.Label:new(2, 3, "ATM ID:", 43)
local idLabel = sgl.Label:new(2, 3, "ATM ID (1-16):", 43)
authorizeATMScreen:addChild(idLabel)

local idInput = sgl.Input:new(2, 4, 40, 1)
authorizeATMScreen:addChild(idInput)

local authInfoLabel = sgl.Label:new(2, 6, "Set void chest frequency in-game", 43)
authInfoLabel.style.fgColor = colors.gray
authorizeATMScreen:addChild(authInfoLabel)

local authStatusLabel = sgl.Label:new(2, 8, "", 43)
authorizeATMScreen:addChild(authStatusLabel)

local authTokenLabel = sgl.Label:new(2, 10, "", 43)
authTokenLabel.style.fgColor = colors.yellow
authorizeATMScreen:addChild(authTokenLabel)

local authBtn = sgl.Button:new(10, 12, 25, 2, "Authorize")
authBtn.style.bgColor = colors.green
authBtn.onClick = function()
    local atmID = idInput:getText()
    
    if atmID == "" then
        authStatusLabel:setText("Please enter ATM ID")
        authStatusLabel.style.fgColor = colors.red
        authTokenLabel:setText("")
        root:markDirty()
        return
    end
    
    local atmNum = tonumber(atmID)
    if not atmNum or atmNum < 1 or atmNum > 16 then
        authStatusLabel:setText("ATM ID must be between 1 and 16")
        authStatusLabel.style.fgColor = colors.red
        authTokenLabel:setText("")
        root:markDirty()
        return
    end
    
    local token = crypto.generateToken()
    config.management.authorizedATMs[atmID] = {
        token = token,
        authorized = os.epoch("utc")
    }
    config.save()
    
    authStatusLabel:setText("Authorized! Enter on ATM:")
    authStatusLabel.style.fgColor = colors.green
    authTokenLabel:setText("ID: " .. atmID .. " Token: " .. token)
    print("\n========================================")
    print("ATM #" .. atmID .. " Authorization")
    print("========================================")
    print("Token: " .. token)
    print("========================================\n")
    root:markDirty()
end
authorizeATMScreen:addChild(authBtn)

local authBackBtn = sgl.Button:new(25, 12, 15, 2, "Back")
authBackBtn.onClick = function()
    showScreen("atm")
end
authorizeATMScreen:addChild(authBackBtn)

-- List ATMs screen
local listATMsScreen = sgl.Panel:new(2, 2, 47, 15)
listATMsScreen:setBorder(false)
listATMsScreen:setVisible(false)
listATMsScreen.data = {isScreen = true, screenName = "listATMs"}
root:addChild(listATMsScreen)

local listATMTitle = sgl.Label:new(10, 1, "Authorized ATMs", 43)
listATMTitle.style.fgColor = colors.yellow
listATMsScreen:addChild(listATMTitle)

-- ATM list would be dynamically populated here
local noATMLabel = sgl.Label:new(2, 3, "No ATMs authorized yet", 43)
noATMLabel.style.fgColor = colors.gray
listATMsScreen:addChild(noATMLabel)

local listATMBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
listATMBackBtn.onClick = function()
    showScreen("atm")
end
listATMsScreen:addChild(listATMBackBtn)

-- Create Account screen
local createAccountScreen = sgl.Panel:new(2, 2, 47, 15)
createAccountScreen:setBorder(false)
createAccountScreen:setVisible(false)
createAccountScreen.data = {isScreen = true, screenName = "createAccount"}
root:addChild(createAccountScreen)

local createAccTitle = sgl.Label:new(10, 1, "Create New Account", 43)
createAccTitle.style.fgColor = colors.yellow
createAccountScreen:addChild(createAccTitle)

local createAccBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
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

local listAccBackBtn = sgl.Button:new(3, 13, 15, 2, "Back")
listAccBackBtn.onClick = function()
    showScreen("accounts")
end
listAccountsScreen:addChild(listAccBackBtn)

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
