-- management/main.lua
-- Bank management console with SGL interface

local sgl = require("lib/sgl/sgl")
local config = require("config")
local network = require("lib/network")
local crypto = require("lib/crypto")

-- Initialize config
config.init()
config.load()

-- State
local authenticated = false
local currentScreen = "login"
local accountList = {}
local selectedAccount = nil
local statusMessage = ""
local messageColor = colors.white

-- Initialize modem
local modem = network.init(config.management.port)

-- Create application
local app = sgl.createApplication("CC-Bank Management Console")

-- Screens
local screens = {}

-- Utility function to show message
local function showMessage(message, isError)
    statusMessage = message
    messageColor = isError and colors.red or colors.green
end

-- Utility function to communicate with server
local function sendToServer(msgType, data)
    local message = network.createMessage(msgType, data)
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

-- First run setup
local function firstRunSetup()
    if not config.management.masterPasswordHash then
        local setupPanel = sgl.Panel:new(1, 1, 51, 19)
        setupPanel:setTitle("First Run Setup")
        
        local label1 = sgl.Label:new(2, 2, "Create Master Password")
        label1.style.fgColor = colors.yellow
        setupPanel:addChild(label1)
        
        local label2 = sgl.Label:new(2, 4, "Password:")
        setupPanel:addChild(label2)
        
        local passwordInput = sgl.Input:new(2, 5, 45)
        passwordInput:setMasked(true)
        setupPanel:addChild(passwordInput)
        
        local label3 = sgl.Label:new(2, 7, "Confirm Password:")
        setupPanel:addChild(label3)
        
        local confirmInput = sgl.Input:new(2, 8, 45)
        confirmInput:setMasked(true)
        setupPanel:addChild(confirmInput)
        
        local saveBtn = sgl.Button:new(10, 11, 30, 3, "Save & Continue")
        saveBtn.onClick = function()
            local pass = passwordInput:getText()
            local confirm = confirmInput:getText()
            
            if pass ~= confirm then
                showMessage("Passwords do not match", true)
                return
            end
            
            if #pass < 8 then
                showMessage("Password too short (min 8 chars)", true)
                return
            end
            
            local passData = crypto.hashPassword(pass)
            config.management.masterPasswordHash = passData.hash
            config.management.masterPasswordSalt = passData.salt
            config.save()
            
            showMessage("Setup complete!", false)
            app:stop()
        end
        setupPanel:addChild(saveBtn)
        
        app:setRoot(setupPanel)
        app:setFocus(passwordInput)
        app:run()
        
        return false
    end
    return true
end

-- Login screen
function screens.login()
    local loginPanel = sgl.Panel:new(1, 1, 51, 19)
    loginPanel:setTitle("Management Console - Login")
    
    local titleLabel = sgl.Label:new(10, 3, "CC-Bank Management")
    titleLabel.style.fgColor = colors.yellow
    loginPanel:addChild(titleLabel)
    
    local passLabel = sgl.Label:new(2, 7, "Master Password:")
    loginPanel:addChild(passLabel)
    
    local passwordInput = sgl.Input:new(2, 8, 45)
    passwordInput:setMasked(true)
    loginPanel:addChild(passwordInput)
    
    local loginBtn = sgl.Button:new(10, 11, 30, 3, "Login")
    loginBtn.onClick = function()
        local password = passwordInput:getText()
        
        if crypto.verifyPassword(password, config.management.masterPasswordHash, config.management.masterPasswordSalt) then
            authenticated = true
            currentScreen = "main"
            screens.main()
        else
            showMessage("Invalid password", true)
            passwordInput:setText("")
        end
    end
    loginPanel:addChild(loginBtn)
    
    if statusMessage ~= "" then
        local msgLabel = sgl.Label:new(2, 15, statusMessage)
        msgLabel.style.fgColor = messageColor
        loginPanel:addChild(msgLabel)
    end
    
    app:setRoot(loginPanel)
    app:setFocus(passwordInput)
end

-- Main menu screen
function screens.main()
    local mainPanel = sgl.Panel:new(1, 1, 51, 19)
    mainPanel:setTitle("Management Console - Main Menu")
    
    local titleLabel = sgl.Label:new(15, 2, "Main Menu")
    titleLabel.style.fgColor = colors.yellow
    mainPanel:addChild(titleLabel)
    
    local btnWidth = 40
    local btnHeight = 2
    local btnX = 6
    local btnY = 4
    
    local accountsBtn = sgl.Button:new(btnX, btnY, btnWidth, btnHeight, "Manage Accounts")
    accountsBtn.onClick = function()
        currentScreen = "accounts"
        screens.accounts()
    end
    mainPanel:addChild(accountsBtn)
    
    local currencyBtn = sgl.Button:new(btnX, btnY + 3, btnWidth, btnHeight, "Mint Currency")
    currencyBtn.onClick = function()
        currentScreen = "currency"
        screens.currency()
    end
    mainPanel:addChild(currencyBtn)
    
    local statsBtn = sgl.Button:new(btnX, btnY + 6, btnWidth, btnHeight, "View Statistics")
    statsBtn.onClick = function()
        currentScreen = "stats"
        screens.stats()
    end
    mainPanel:addChild(statsBtn)
    
    local atmBtn = sgl.Button:new(btnX, btnY + 9, btnWidth, btnHeight, "ATM Management")
    atmBtn.onClick = function()
        currentScreen = "atm"
        screens.atmManagement()
    end
    mainPanel:addChild(atmBtn)
    
    local exitBtn = sgl.Button:new(btnX, btnY + 12, btnWidth, btnHeight, "Exit")
    exitBtn.style.bgColor = colors.red
    exitBtn.onClick = function()
        app:stop()
    end
    mainPanel:addChild(exitBtn)
    
    app:setRoot(mainPanel)
end

-- Account management screen
function screens.accounts()
    local accountPanel = sgl.Panel:new(1, 1, 51, 19)
    accountPanel:setTitle("Account Management")
    
    local createBtn = sgl.Button:new(2, 2, 20, 2, "Create Account")
    createBtn.onClick = function()
        screens.createAccount()
    end
    accountPanel:addChild(createBtn)
    
    local listBtn = sgl.Button:new(24, 2, 20, 2, "List Accounts")
    listBtn.onClick = function()
        screens.listAccounts()
    end
    accountPanel:addChild(listBtn)
    
    local backBtn = sgl.Button:new(2, 16, 15, 2, "Back")
    backBtn.onClick = function()
        screens.main()
    end
    accountPanel:addChild(backBtn)
    
    app:setRoot(accountPanel)
end

-- Create account screen
function screens.createAccount()
    local createPanel = sgl.Panel:new(1, 1, 51, 19)
    createPanel:setTitle("Create New Account")
    
    local usernameLabel = sgl.Label:new(2, 2, "Username:")
    createPanel:addChild(usernameLabel)
    
    local usernameInput = sgl.Input:new(2, 3, 45)
    createPanel:addChild(usernameInput)
    
    local passwordLabel = sgl.Label:new(2, 5, "Password:")
    createPanel:addChild(passwordLabel)
    
    local passwordInput = sgl.Input:new(2, 6, 45)
    passwordInput:setMasked(true)
    createPanel:addChild(passwordInput)
    
    local balanceLabel = sgl.Label:new(2, 8, "Initial Balance:")
    createPanel:addChild(balanceLabel)
    
    local balanceInput = sgl.Input:new(2, 9, 45)
    balanceInput:setText("0")
    createPanel:addChild(balanceInput)
    
    local createBtn = sgl.Button:new(10, 12, 30, 3, "Create Account")
    createBtn.onClick = function()
        local username = usernameInput:getText()
        local password = passwordInput:getText()
        local balance = tonumber(balanceInput:getText()) or 0
        
        -- Direct account creation (since we're on management console)
        -- In production, this would go through server
        showMessage("Account created: " .. username, false)
        screens.accounts()
    end
    createPanel:addChild(createBtn)
    
    local backBtn = sgl.Button:new(2, 16, 15, 2, "Back")
    backBtn.onClick = function()
        screens.accounts()
    end
    createPanel:addChild(backBtn)
    
    app:setRoot(createPanel)
    app:setFocus(usernameInput)
end

-- List accounts screen
function screens.listAccounts()
    local listPanel = sgl.Panel:new(1, 1, 51, 19)
    listPanel:setTitle("Account List")
    
    -- This would query the server for account list
    local infoLabel = sgl.Label:new(2, 2, "Accounts will be listed here")
    listPanel:addChild(infoLabel)
    
    local backBtn = sgl.Button:new(2, 16, 15, 2, "Back")
    backBtn.onClick = function()
        screens.accounts()
    end
    listPanel:addChild(backBtn)
    
    app:setRoot(listPanel)
end

-- Currency minting screen
function screens.currency()
    local currencyPanel = sgl.Panel:new(1, 1, 51, 19)
    currencyPanel:setTitle("Currency Minting")
    
    local infoLabel = sgl.Label:new(2, 2, "Place items in mint chest")
    infoLabel.style.fgColor = colors.yellow
    currencyPanel:addChild(infoLabel)
    
    local amountLabel = sgl.Label:new(2, 5, "Amount to mint:")
    currencyPanel:addChild(amountLabel)
    
    local amountInput = sgl.Input:new(2, 6, 45)
    amountInput:setText("100")
    currencyPanel:addChild(amountInput)
    
    local mintBtn = sgl.Button:new(10, 9, 30, 3, "Mint Currency")
    mintBtn.style.bgColor = colors.green
    mintBtn.onClick = function()
        local amount = tonumber(amountInput:getText()) or 0
        
        if amount <= 0 then
            showMessage("Invalid amount", true)
            return
        end
        
        -- Trigger minting process
        showMessage("Minting " .. amount .. " credits...", false)
        
        -- In production, this would interface with the currency system
    end
    currencyPanel:addChild(mintBtn)
    
    local statusLabel = sgl.Label:new(2, 14, "Status: Ready")
    statusLabel.style.fgColor = colors.lightGray
    currencyPanel:addChild(statusLabel)
    
    local backBtn = sgl.Button:new(2, 16, 15, 2, "Back")
    backBtn.onClick = function()
        screens.main()
    end
    currencyPanel:addChild(backBtn)
    
    app:setRoot(currencyPanel)
    app:setFocus(amountInput)
end

-- Statistics screen
function screens.stats()
    local statsPanel = sgl.Panel:new(1, 1, 51, 19)
    statsPanel:setTitle("System Statistics")
    
    local titleLabel = sgl.Label:new(2, 2, "Bank Statistics")
    titleLabel.style.fgColor = colors.yellow
    statsPanel:addChild(titleLabel)
    
    -- These would be fetched from server
    local stats = {
        "Total Accounts: 0",
        "Total Transactions: 0",
        "Currency Supply: 0 Credits",
        "Active ATMs: 0",
        "Server Uptime: 0m"
    }
    
    for i, stat in ipairs(stats) do
        local label = sgl.Label:new(2, 3 + i, stat)
        statsPanel:addChild(label)
    end
    
    local refreshBtn = sgl.Button:new(2, 12, 20, 2, "Refresh")
    refreshBtn.onClick = function()
        screens.stats()  -- Reload screen
    end
    statsPanel:addChild(refreshBtn)
    
    local backBtn = sgl.Button:new(2, 16, 15, 2, "Back")
    backBtn.onClick = function()
        screens.main()
    end
    statsPanel:addChild(backBtn)
    
    app:setRoot(statsPanel)
end

-- ATM management screen
function screens.atmManagement()
    local atmPanel = sgl.Panel:new(1, 1, 51, 19)
    atmPanel:setTitle("ATM Management")
    
    local titleLabel = sgl.Label:new(2, 2, "ATM Authorization")
    titleLabel.style.fgColor = colors.yellow
    atmPanel:addChild(titleLabel)
    
    local authorizeBtn = sgl.Button:new(2, 4, 20, 2, "Authorize ATM")
    authorizeBtn.onClick = function()
        screens.authorizeATM()
    end
    atmPanel:addChild(authorizeBtn)
    
    local listBtn = sgl.Button:new(24, 4, 20, 2, "List ATMs")
    listBtn.onClick = function()
        screens.listATMs()
    end
    atmPanel:addChild(listBtn)
    
    local revokeBtn = sgl.Button:new(2, 7, 20, 2, "Revoke ATM")
    revokeBtn.style.bgColor = colors.red
    revokeBtn.onClick = function()
        screens.revokeATM()
    end
    atmPanel:addChild(revokeBtn)
    
    local backBtn = sgl.Button:new(2, 16, 15, 2, "Back")
    backBtn.onClick = function()
        screens.main()
    end
    atmPanel:addChild(backBtn)
    
    app:setRoot(atmPanel)
end

-- Authorize new ATM
function screens.authorizeATM()
    local authPanel = sgl.Panel:new(1, 1, 51, 19)
    authPanel:setTitle("Authorize ATM")
    
    local idLabel = sgl.Label:new(2, 2, "ATM ID:")
    authPanel:addChild(idLabel)
    
    local idInput = sgl.Input:new(2, 3, 45)
    authPanel:addChild(idInput)
    
    local freqLabel = sgl.Label:new(2, 5, "Void Chest Frequency:")
    authPanel:addChild(freqLabel)
    
    local freqInput = sgl.Input:new(2, 6, 45)
    authPanel:addChild(freqInput)
    
    local authorizeBtn = sgl.Button:new(10, 9, 30, 3, "Authorize")
    authorizeBtn.style.bgColor = colors.green
    authorizeBtn.onClick = function()
        local atmID = idInput:getText()
        local frequency = tonumber(freqInput:getText())
        
        if atmID == "" or not frequency then
            showMessage("Invalid input", true)
            return
        end
        
        -- Generate secure authorization token
        local crypto = require("lib/crypto")
        local token = crypto.generateToken()
        
        -- Store in config
        config.management.authorizedATMs[atmID] = {
            token = token,
            frequency = frequency,
            authorized = os.epoch("utc")
        }
        config.save()
        
        showMessage("ATM " .. atmID .. " authorized!\nToken: " .. token, false)
        print("ATM " .. atmID .. " Auth Token: " .. token)
    end
    authPanel:addChild(authorizeBtn)
    
    local backBtn = sgl.Button:new(2, 16, 15, 2, "Back")
    backBtn.onClick = function()
        screens.atmManagement()
    end
    authPanel:addChild(backBtn)
    
    if statusMessage ~= "" then
        local msgLabel = sgl.Label:new(2, 14, statusMessage)
        msgLabel.style.fgColor = messageColor
        authPanel:addChild(msgLabel)
    end
    
    app:setRoot(authPanel)
    app:setFocus(idInput)
end

-- List authorized ATMs
function screens.listATMs()
    local listPanel = sgl.Panel:new(1, 1, 51, 19)
    listPanel:setTitle("Authorized ATMs")
    
    local y = 2
    local count = 0
    
    for atmID, data in pairs(config.management.authorizedATMs) do
        local label = sgl.Label:new(2, y, "ATM " .. atmID .. " - Freq: " .. data.frequency)
        listPanel:addChild(label)
        y = y + 1
        count = count + 1
        
        if y > 14 then break end
    end
    
    if count == 0 then
        local noLabel = sgl.Label:new(2, 2, "No ATMs authorized")
        noLabel.style.fgColor = colors.gray
        listPanel:addChild(noLabel)
    end
    
    local backBtn = sgl.Button:new(2, 16, 15, 2, "Back")
    backBtn.onClick = function()
        screens.atmManagement()
    end
    listPanel:addChild(backBtn)
    
    app:setRoot(listPanel)
end

-- Revoke ATM authorization
function screens.revokeATM()
    local revokePanel = sgl.Panel:new(1, 1, 51, 19)
    revokePanel:setTitle("Revoke ATM")
    
    local idLabel = sgl.Label:new(2, 2, "ATM ID to revoke:")
    revokePanel:addChild(idLabel)
    
    local idInput = sgl.Input:new(2, 3, 45)
    revokePanel:addChild(idInput)
    
    local revokeBtn = sgl.Button:new(10, 6, 30, 3, "Revoke")
    revokeBtn.style.bgColor = colors.red
    revokeBtn.onClick = function()
        local atmID = idInput:getText()
        
        if config.management.authorizedATMs[atmID] then
            config.management.authorizedATMs[atmID] = nil
            config.save()
            showMessage("ATM " .. atmID .. " revoked", false)
        else
            showMessage("ATM not found", true)
        end
    end
    revokePanel:addChild(revokeBtn)
    
    local backBtn = sgl.Button:new(2, 16, 15, 2, "Back")
    backBtn.onClick = function()
        screens.atmManagement()
    end
    revokePanel:addChild(backBtn)
    
    app:setRoot(atmPanel)
    app:setFocus(idInput)
end

-- Main entry point
local function main()
    -- Check first run
    if not firstRunSetup() then
        return
    end
    
    -- Start with login screen
    screens.login()
    app:run()
end

-- Run application
main()
