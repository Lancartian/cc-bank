-- atm/main.lua
-- ATM Frontend Client with SGL interface

local sgl = require("/lib/sgl/sgl")
local config = require("/config")
local network = require("/lib/network")
local crypto = require("/lib/crypto")

-- Initialize config
config.init()
config.load()

-- ATM State
local currentScreen = "welcome"
local sessionToken = nil
local accountNumber = nil
local username = nil
local balance = 0
local statusMessage = ""
local messageColor = colors.white

-- Initialize modem
local modem = network.init(config.atm.port)

-- ATM ID, frequency, and authorization token
local atmID = config.atm.id or os.getComputerID()
local frequency = config.atm.frequency or 0
local authToken = config.atm.authToken  -- Must be set by administrator
local encryptionKey = nil  -- Received from server on registration

print("CC-Bank ATM v1.0")
print("ATM ID: " .. atmID)
print("Frequency: " .. frequency)

if not authToken then
    print("WARNING: No authorization token configured!")
    print("Contact administrator to authorize this ATM")
end

-- Register with server (requires authorization)
local function registerATM()
    if not authToken then
        print("ERROR: No authorization token configured")
        return false
    end
    
    local message = network.createMessage(network.MSG.ATM_REGISTER, {
        atmID = atmID,
        frequency = frequency,
        authToken = authToken
    })
    
    network.broadcast(modem, config.server.port, message)
    
    local response, err = network.receive(config.atm.port, 5)
    if response and response.type == network.MSG.SUCCESS then
        print("Registered with server")
        -- Store encryption key from server
        if response.data.encryptionKey then
            encryptionKey = response.data.encryptionKey
        end
        return true
    else
        print("Failed to register: " .. tostring(err))
        return false
    end
end

-- Send status ping
local function sendStatusPing()
    local message = network.createMessage(network.MSG.ATM_STATUS, {
        atmID = atmID
    })
    network.broadcast(modem, config.server.port, message)
end

-- Communicate with server
local function sendToServer(msgType, data, useToken)
    local message
    if useToken and sessionToken then
        message = network.createMessage(msgType, data, sessionToken)
    else
        message = network.createMessage(msgType, data)
    end
    
    network.broadcast(modem, config.server.port, message)
    
    local response, err = network.receive(config.atm.port, 5)
    if not response then
        return nil, err or "No response from server"
    end
    
    if response.type == network.MSG.ERROR then
        return nil, response.data.message or "Unknown error"
    end
    
    return response.data, nil
end

-- Show message helper
local function showMessage(message, isError)
    statusMessage = message
    messageColor = isError and colors.red or colors.green
end

-- Create application
local app = sgl.createApplication(config.atm.displayName)

-- Screens
local screens = {}

-- Welcome screen
function screens.welcome()
    local welcomePanel = sgl.Panel:new(1, 1, 51, 19)
    welcomePanel:setTitle(config.atm.displayName)
    
    local titleLabel = sgl.Label:new(5, 4, config.atm.welcomeMessage)
    titleLabel.style.fgColor = colors.yellow
    welcomePanel:addChild(titleLabel)
    
    local infoLabel = sgl.Label:new(8, 7, "Secure Banking Services")
    infoLabel.style.fgColor = colors.lightBlue
    welcomePanel:addChild(infoLabel)
    
    local startBtn = sgl.Button:new(10, 10, 30, 3, "Touch to Begin")
    startBtn.style.bgColor = colors.green
    startBtn.onClick = function()
        currentScreen = "login"
        screens.login()
    end
    welcomePanel:addChild(startBtn)
    
    local atmInfo = sgl.Label:new(2, 17, "ATM ID: " .. atmID)
    atmInfo.style.fgColor = colors.gray
    welcomePanel:addChild(atmInfo)
    
    app:setRoot(welcomePanel)
end

-- Login screen
function screens.login()
    local loginPanel = sgl.Panel:new(1, 1, 51, 19)
    loginPanel:setTitle("Login")
    
    local usernameLabel = sgl.Label:new(2, 2, "Username:")
    loginPanel:addChild(usernameLabel)
    
    local usernameInput = sgl.Input:new(2, 3, 45)
    loginPanel:addChild(usernameInput)
    
    local passwordLabel = sgl.Label:new(2, 5, "Password:")
    loginPanel:addChild(passwordLabel)
    
    local passwordInput = sgl.Input:new(2, 6, 45)
    passwordInput:setMasked(true)
    loginPanel:addChild(passwordInput)
    
    local loginBtn = sgl.Button:new(10, 9, 30, 3, "Login")
    loginBtn.style.bgColor = colors.green
    loginBtn.onClick = function()
        local user = usernameInput:getText()
        local pass = passwordInput:getText()
        
        if user == "" or pass == "" then
            showMessage("Please enter username and password", true)
            return
        end
        
        showMessage("Authenticating...", false)
        
        -- Create encrypted authentication request
        local message = network.createMessage(network.MSG.AUTH_REQUEST, {
            username = user,
            password = pass
        }, nil, encryptionKey)
        
        network.broadcast(modem, config.server.port, message)
        
        local response, err = network.receive(config.atm.port, 5)
        if not response then
            showMessage("Connection error: " .. tostring(err), true)
            return
        end
        
        if response.type == network.MSG.ERROR then
            showMessage("Login failed: " .. tostring(response.data.message), true)
            passwordInput:setText("")
            return
        end
        
        -- Decrypt response
        local success, data = network.verifyMessage(response, encryptionKey, encryptionKey)
        if not success then
            showMessage("Security error", true)
            return
        end
        
        local response = data or response.data
        
        if response and response.success then
            sessionToken = response.token
            accountNumber = response.accountNumber
            username = response.username
            balance = response.balance
            
            currentScreen = "menu"
            screens.menu()
        else
            showMessage("Login failed: " .. tostring(err), true)
            passwordInput:setText("")
        end
    end
    loginPanel:addChild(loginBtn)
    
    local cancelBtn = sgl.Button:new(10, 13, 30, 2, "Cancel")
    cancelBtn.onClick = function()
        currentScreen = "welcome"
        screens.welcome()
    end
    loginPanel:addChild(cancelBtn)
    
    if statusMessage ~= "" then
        local msgLabel = sgl.Label:new(2, 16, statusMessage)
        msgLabel.style.fgColor = messageColor
        loginPanel:addChild(msgLabel)
    end
    
    app:setRoot(loginPanel)
    app:setFocus(usernameInput)
end

-- Main menu screen
function screens.menu()
    local menuPanel = sgl.Panel:new(1, 1, 51, 19)
    menuPanel:setTitle("Main Menu")
    
    local welcomeLabel = sgl.Label:new(2, 2, "Welcome, " .. username)
    welcomeLabel.style.fgColor = colors.yellow
    menuPanel:addChild(welcomeLabel)
    
    local balanceLabel = sgl.Label:new(2, 3, "Balance: " .. balance .. " " .. config.currency.displayNamePlural)
    balanceLabel.style.fgColor = colors.lightBlue
    menuPanel:addChild(balanceLabel)
    
    local btnWidth = 40
    local btnHeight = 2
    local btnX = 6
    
    local checkBalanceBtn = sgl.Button:new(btnX, 6, btnWidth, btnHeight, "Check Balance")
    checkBalanceBtn.onClick = function()
        screens.checkBalance()
    end
    menuPanel:addChild(checkBalanceBtn)
    
    local withdrawBtn = sgl.Button:new(btnX, 9, btnWidth, btnHeight, "Withdraw")
    withdrawBtn.onClick = function()
        screens.withdraw()
    end
    menuPanel:addChild(withdrawBtn)
    
    local depositBtn = sgl.Button:new(btnX, 12, btnWidth, btnHeight, "Deposit")
    depositBtn.onClick = function()
        screens.deposit()
    end
    menuPanel:addChild(depositBtn)
    
    local transferBtn = sgl.Button:new(btnX, 15, btnWidth, btnHeight, "Transfer")
    transferBtn.onClick = function()
        screens.transfer()
    end
    menuPanel:addChild(transferBtn)
    
    local logoutBtn = sgl.Button:new(2, 18, 15, 1, "Logout")
    logoutBtn.style.bgColor = colors.red
    logoutBtn.onClick = function()
        sessionToken = nil
        accountNumber = nil
        username = nil
        balance = 0
        currentScreen = "welcome"
        screens.welcome()
    end
    menuPanel:addChild(logoutBtn)
    
    app:setRoot(menuPanel)
end

-- Check balance screen
function screens.checkBalance()
    local balancePanel = sgl.Panel:new(1, 1, 51, 19)
    balancePanel:setTitle("Balance Check")
    
    local titleLabel = sgl.Label:new(2, 2, "Current Balance")
    titleLabel.style.fgColor = colors.yellow
    balancePanel:addChild(titleLabel)
    
    -- Fetch latest balance
    local response, err = sendToServer(network.MSG.BALANCE_CHECK, {}, true)
    
    if response then
        balance = response.balance
        
        local balanceLabel = sgl.Label:new(2, 5, tostring(balance) .. " " .. config.currency.displayNamePlural)
        balanceLabel.style.fgColor = colors.green
        local termW = term.getSize()
        balanceLabel.style.fontSize = 2  -- Larger text if supported
        balancePanel:addChild(balanceLabel)
        
        local accountLabel = sgl.Label:new(2, 8, "Account: " .. accountNumber)
        balancePanel:addChild(accountLabel)
    else
        local errorLabel = sgl.Label:new(2, 5, "Error: " .. tostring(err))
        errorLabel.style.fgColor = colors.red
        balancePanel:addChild(errorLabel)
    end
    
    local backBtn = sgl.Button:new(15, 15, 20, 3, "Back to Menu")
    backBtn.onClick = function()
        screens.menu()
    end
    balancePanel:addChild(backBtn)
    
    app:setRoot(balancePanel)
end

-- Withdraw screen
function screens.withdraw()
    local withdrawPanel = sgl.Panel:new(1, 1, 51, 19)
    withdrawPanel:setTitle("Withdraw")
    
    local titleLabel = sgl.Label:new(2, 2, "Withdrawal")
    titleLabel.style.fgColor = colors.yellow
    withdrawPanel:addChild(titleLabel)
    
    local balanceLabel = sgl.Label:new(2, 4, "Available: " .. balance .. " " .. config.currency.displayNamePlural)
    withdrawPanel:addChild(balanceLabel)
    
    local amountLabel = sgl.Label:new(2, 6, "Amount to withdraw:")
    withdrawPanel:addChild(amountLabel)
    
    local amountInput = sgl.Input:new(2, 7, 45)
    withdrawPanel:addChild(amountInput)
    
    local withdrawBtn = sgl.Button:new(10, 10, 30, 3, "Withdraw")
    withdrawBtn.style.bgColor = colors.orange
    withdrawBtn.onClick = function()
        local amount = tonumber(amountInput:getText())
        
        if not amount or amount <= 0 then
            showMessage("Invalid amount", true)
            return
        end
        
        if amount > balance then
            showMessage("Insufficient funds", true)
            return
        end
        
        if amount > config.atm.maxWithdrawal then
            showMessage("Exceeds withdrawal limit", true)
            return
        end
        
        showMessage("Processing...", false)
        
        local response, err = sendToServer(network.MSG.WITHDRAW, {
            amount = amount,
            atmID = atmID
        }, true)
        
        if response then
            balance = response.newBalance
            showMessage("Withdrawal successful!", false)
            
            -- Wait for currency to be dispensed
            sleep(2)
            screens.menu()
        else
            showMessage("Withdrawal failed: " .. tostring(err), true)
        end
    end
    withdrawPanel:addChild(withdrawBtn)
    
    local cancelBtn = sgl.Button:new(10, 14, 30, 2, "Cancel")
    cancelBtn.onClick = function()
        screens.menu()
    end
    withdrawPanel:addChild(cancelBtn)
    
    if statusMessage ~= "" then
        local msgLabel = sgl.Label:new(2, 17, statusMessage)
        msgLabel.style.fgColor = messageColor
        withdrawPanel:addChild(msgLabel)
    end
    
    app:setRoot(withdrawPanel)
    app:setFocus(amountInput)
end

-- Deposit screen
function screens.deposit()
    local depositPanel = sgl.Panel:new(1, 1, 51, 19)
    depositPanel:setTitle("Deposit")
    
    local titleLabel = sgl.Label:new(2, 2, "Deposit")
    titleLabel.style.fgColor = colors.yellow
    depositPanel:addChild(titleLabel)
    
    local infoLabel = sgl.Label:new(2, 4, "Insert currency into deposit slot")
    depositPanel:addChild(infoLabel)
    
    local amountLabel = sgl.Label:new(2, 7, "Amount to deposit:")
    depositPanel:addChild(amountLabel)
    
    local amountInput = sgl.Input:new(2, 8, 45)
    depositPanel:addChild(amountInput)
    
    local scanBtn = sgl.Button:new(5, 11, 20, 2, "Scan Currency")
    scanBtn.onClick = function()
        -- Scan inserted currency
        showMessage("Scanning currency...", false)
        -- Would verify currency here
    end
    depositPanel:addChild(scanBtn)
    
    local depositBtn = sgl.Button:new(27, 11, 20, 2, "Deposit")
    depositBtn.style.bgColor = colors.green
    depositBtn.onClick = function()
        local amount = tonumber(amountInput:getText())
        
        if not amount or amount <= 0 then
            showMessage("Invalid amount", true)
            return
        end
        
        if amount > config.atm.maxDeposit then
            showMessage("Exceeds deposit limit", true)
            return
        end
        
        showMessage("Processing...", false)
        
        local response, err = sendToServer(network.MSG.DEPOSIT, {
            amount = amount,
            atmID = atmID
        }, true)
        
        if response then
            balance = response.newBalance
            showMessage("Deposit successful!", false)
            sleep(2)
            screens.menu()
        else
            showMessage("Deposit failed: " .. tostring(err), true)
        end
    end
    depositPanel:addChild(depositBtn)
    
    local cancelBtn = sgl.Button:new(10, 14, 30, 2, "Cancel")
    cancelBtn.onClick = function()
        screens.menu()
    end
    depositPanel:addChild(cancelBtn)
    
    if statusMessage ~= "" then
        local msgLabel = sgl.Label:new(2, 17, statusMessage)
        msgLabel.style.fgColor = messageColor
        depositPanel:addChild(msgLabel)
    end
    
    app:setRoot(depositPanel)
    app:setFocus(amountInput)
end

-- Transfer screen
function screens.transfer()
    local transferPanel = sgl.Panel:new(1, 1, 51, 19)
    transferPanel:setTitle("Transfer")
    
    local titleLabel = sgl.Label:new(2, 2, "Transfer Funds")
    titleLabel.style.fgColor = colors.yellow
    transferPanel:addChild(titleLabel)
    
    local balanceLabel = sgl.Label:new(2, 4, "Available: " .. balance .. " " .. config.currency.displayNamePlural)
    transferPanel:addChild(balanceLabel)
    
    local accountLabel = sgl.Label:new(2, 6, "To Account Number:")
    transferPanel:addChild(accountLabel)
    
    local accountInput = sgl.Input:new(2, 7, 45)
    transferPanel:addChild(accountInput)
    
    local amountLabel = sgl.Label:new(2, 9, "Amount:")
    transferPanel:addChild(amountLabel)
    
    local amountInput = sgl.Input:new(2, 10, 45)
    transferPanel:addChild(amountInput)
    
    local transferBtn = sgl.Button:new(10, 13, 30, 3, "Transfer")
    transferBtn.style.bgColor = colors.blue
    transferBtn.onClick = function()
        local toAccount = accountInput:getText()
        local amount = tonumber(amountInput:getText())
        
        if toAccount == "" then
            showMessage("Enter account number", true)
            return
        end
        
        if not amount or amount <= 0 then
            showMessage("Invalid amount", true)
            return
        end
        
        if amount > balance then
            showMessage("Insufficient funds", true)
            return
        end
        
        if amount > config.atm.maxTransfer then
            showMessage("Exceeds transfer limit", true)
            return
        end
        
        showMessage("Processing...", false)
        
        local response, err = sendToServer(network.MSG.TRANSFER, {
            amount = amount,
            toAccount = toAccount
        }, true)
        
        if response then
            balance = response.newBalance
            showMessage("Transfer successful!", false)
            sleep(2)
            screens.menu()
        else
            showMessage("Transfer failed: " .. tostring(err), true)
        end
    end
    transferPanel:addChild(transferBtn)
    
    local cancelBtn = sgl.Button:new(10, 17, 30, 2, "Cancel")
    cancelBtn.onClick = function()
        screens.menu()
    end
    transferPanel:addChild(cancelBtn)
    
    app:setRoot(transferPanel)
    app:setFocus(accountInput)
end

-- Status ping timer
local function startStatusPing()
    while true do
        sendStatusPing()
        sleep(30)  -- Ping every 30 seconds
    end
end

-- Main entry point
local function main()
    -- Register with server
    if not registerATM() then
        print("Failed to register. Check server connection.")
        print("Press any key to retry...")
        os.pullEvent("key")
        os.reboot()
    end
    
    -- Start status ping in background
    parallel.waitForAny(
        function()
            startStatusPing()
        end,
        function()
            -- Start UI
            screens.welcome()
            app:run()
        end
    )
end

-- Run application
main()
