-- atm/main.lua
-- ATM Frontend Client with SGL interface

local sgl = require("/lib/sgl/sgl")
local config = require("/config")
local network = require("/lib/network")
local crypto = require("/lib/crypto")

-- Initialize config
config.init()
config.load()

-- First-run setup if ID or token not configured
if not config.atm.id or not config.atm.authToken then
    term.clear()
    term.setCursorPos(1, 1)
    print(string.rep("=", 50))
    print("FIRST RUN SETUP - ATM Configuration")
    print(string.rep("=", 50))
    print("\nThis ATM needs to be authorized.")
    print("\nSteps:")
    print("1. Login to management console")
    print("2. Go to 'ATM Management' > 'Authorize ATM'")
    print("3. Enter an ATM ID (1-16)")
    print("4. Copy the generated token")
    print("5. Enter the ID and token below")
    print("")
    
    local atmID, authToken
    local valid = false
    
    while not valid do
        write("Enter ATM ID (1-16): ")
        atmID = tonumber(read())
        
        if not atmID or atmID < 1 or atmID > 16 then
            print("ERROR: ATM ID must be between 1 and 16\n")
        else
            write("Enter authorization token: ")
            authToken = read()
            
            if authToken == "" then
                print("ERROR: Token cannot be empty\n")
            else
                valid = true
            end
        end
    end
    
    -- Save configuration
    config.atm.id = atmID
    config.atm.authToken = authToken
    config.save()
    
    print("\n" .. string.rep("=", 50))
    print("Configuration saved!")
    print("ATM will now start...")
    print(string.rep("=", 50))
    sleep(2)
end

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

-- ATM ID and authorization token
local atmID = config.atm.id
local authToken = config.atm.authToken
local encryptionKey = nil  -- Received from server on registration

print("CC-Bank ATM v1.0")
print("ATM ID: " .. atmID)

-- Register with server (requires authorization)
local function registerATM()
    local message = network.createMessage(network.MSG.ATM_REGISTER, {
        atmID = atmID,
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

-- Create root panel
local root = sgl.Panel:new(1, 1, 51, 19)
root:setTitle(config.atm.displayName)
root:setBorder(true)

-- Set root before adding children
app:setRoot(root)

-- Utility function to show screen
local function showScreen(screenName)
    for i = 1, #root.children do
        local child = root.children[i]
        if child.data and child.data.isScreen then
            child:setVisible(child.data.screenName == screenName)
        end
    end
    if screenName == "menu" and updateMenuLabels then
        updateMenuLabels()
    end
    root:markDirty()
end

-- Welcome screen
local welcomeScreen = sgl.Panel:new(2, 2, 47, 15)
welcomeScreen:setBorder(false)
welcomeScreen:setVisible(false)
welcomeScreen.data = {isScreen = true, screenName = "welcome"}
root:addChild(welcomeScreen)
    
local titleLabel = sgl.Label:new(5, 3, config.atm.welcomeMessage, 43)
titleLabel.style.fgColor = colors.yellow
welcomeScreen:addChild(titleLabel)

local infoLabel = sgl.Label:new(8, 6, "Secure Banking Services", 43)
infoLabel.style.fgColor = colors.lightBlue
welcomeScreen:addChild(infoLabel)

local startBtn = sgl.Button:new(8, 9, 30, 3, "Touch to Begin")
startBtn.style.bgColor = colors.green
startBtn.onClick = function()
    currentScreen = "login"
    showScreen("login")
end
welcomeScreen:addChild(startBtn)

local atmInfo = sgl.Label:new(2, 14, "ATM ID: " .. atmID, 43)
atmInfo.style.fgColor = colors.gray
welcomeScreen:addChild(atmInfo)

-- Login screen
local loginScreen = sgl.Panel:new(2, 2, 47, 15)
loginScreen:setBorder(false)
loginScreen:setVisible(false)
loginScreen.data = {isScreen = true, screenName = "login"}
root:addChild(loginScreen)

local usernameLabel = sgl.Label:new(2, 1, "Username:", 43)
loginScreen:addChild(usernameLabel)

local usernameInput = sgl.Input:new(2, 2, 43, 1)
loginScreen:addChild(usernameInput)

local passwordLabel = sgl.Label:new(2, 4, "Password:", 43)
loginScreen:addChild(passwordLabel)

local passwordInput = sgl.Input:new(2, 5, 43, 1)
passwordInput:setMasked(true)
loginScreen:addChild(passwordInput)

local loginStatusLabel = sgl.Label:new(2, 7, "", 43)
loginScreen:addChild(loginStatusLabel)

local loginBtn = sgl.Button:new(8, 9, 30, 2, "Login")
loginBtn.style.bgColor = colors.green
loginBtn.onClick = function()
    local user = usernameInput:getText()
    local pass = passwordInput:getText()
    
    if user == "" or pass == "" then
        loginStatusLabel:setText("Please enter username and password")
        loginStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    loginStatusLabel:setText("Authenticating...")
    loginStatusLabel.style.fgColor = colors.white
    root:markDirty()
    
    -- Create encrypted authentication request
    local message = network.createMessage(network.MSG.AUTH_REQUEST, {
        username = user,
        password = pass
    }, nil, encryptionKey)
    
    network.broadcast(modem, config.server.port, message)
    
    local response, err = network.receive(config.atm.port, 5)
    if not response then
        loginStatusLabel:setText("Connection error: " .. tostring(err))
        loginStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    if response.type == network.MSG.ERROR then
        loginStatusLabel:setText("Login failed: " .. tostring(response.data.message))
        loginStatusLabel.style.fgColor = colors.red
        passwordInput:setText("")
        root:markDirty()
        return
    end
    
    -- Decrypt response
    local success, data = network.verifyMessage(response, encryptionKey, encryptionKey)
    if not success then
        loginStatusLabel:setText("Security error")
        loginStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    local response = data or response.data
    
    if response and response.success then
        sessionToken = response.token
        accountNumber = response.accountNumber
        username = response.username
        balance = response.balance
        
        currentScreen = "menu"
        showScreen("menu")
    else
        loginStatusLabel:setText("Login failed: " .. tostring(err))
        loginStatusLabel.style.fgColor = colors.red
        passwordInput:setText("")
        root:markDirty()
    end
end
loginScreen:addChild(loginBtn)

local cancelBtn = sgl.Button:new(8, 12, 30, 1, "Cancel")
cancelBtn.onClick = function()
    usernameInput:setText("")
    passwordInput:setText("")
    loginStatusLabel:setText("")
    currentScreen = "welcome"
    showScreen("welcome")
end
loginScreen:addChild(cancelBtn)

-- Main menu screen
local menuScreen = sgl.Panel:new(2, 2, 47, 15)
menuScreen:setBorder(false)
menuScreen:setVisible(false)
menuScreen.data = {isScreen = true, screenName = "menu"}
root:addChild(menuScreen)

local welcomeLabel = sgl.Label:new(2, 1, "Welcome", 43)
welcomeLabel.style.fgColor = colors.yellow
menuScreen:addChild(welcomeLabel)

local balanceLabel = sgl.Label:new(2, 2, "Balance: 0", 43)
balanceLabel.style.fgColor = colors.lightBlue
menuScreen:addChild(balanceLabel)

-- Function to update menu labels
local function updateMenuLabels()
    if username then
        welcomeLabel:setText("Welcome, " .. username)
        balanceLabel:setText("Balance: " .. balance .. " " .. config.currency.displayNamePlural)
        root:markDirty()
    end
end
    
local btnWidth = 38
local btnHeight = 2
local btnX = 5

local checkBalanceBtn = sgl.Button:new(btnX, 5, btnWidth, btnHeight, "Check Balance")
checkBalanceBtn.onClick = function()
    -- Fetch latest balance
    local response, err = sendToServer(network.MSG.BALANCE_CHECK, {}, true)
    
    if response then
        balance = response.balance
        balanceDisplayLabel:setText(tostring(balance) .. " " .. config.currency.displayNamePlural)
        balanceDisplayLabel.style.fgColor = colors.green
        accountDisplayLabel:setText("Account: " .. accountNumber)
        accountDisplayLabel.style.fgColor = colors.white
    else
        balanceDisplayLabel:setText("Error: " .. tostring(err))
        balanceDisplayLabel.style.fgColor = colors.red
        accountDisplayLabel:setText("")
    end
    root:markDirty()
    showScreen("checkBalance")
end
menuScreen:addChild(checkBalanceBtn)

local withdrawBtn = sgl.Button:new(btnX, 8, btnWidth, btnHeight, "Withdraw")
withdrawBtn.onClick = function()
    withdrawAmountInput:setText("")
    withdrawStatusLabel:setText("")
    showScreen("withdraw")
end
menuScreen:addChild(withdrawBtn)

local depositBtn = sgl.Button:new(btnX, 11, btnWidth, btnHeight, "Deposit")
depositBtn.onClick = function()
    depositAmountInput:setText("")
    depositStatusLabel:setText("")
    showScreen("deposit")
end
menuScreen:addChild(depositBtn)

local transferBtn = sgl.Button:new(btnX, 14, btnWidth, btnHeight, "Transfer")
transferBtn.onClick = function()
    transferAccountInput:setText("")
    transferAmountInput:setText("")
    transferStatusLabel:setText("")
    showScreen("transfer")
end
menuScreen:addChild(transferBtn)

local logoutBtn = sgl.Button:new(2, 13, 15, 1, "Logout")
logoutBtn.style.bgColor = colors.red
logoutBtn.onClick = function()
    sessionToken = nil
    accountNumber = nil
    username = nil
    balance = 0
    usernameInput:setText("")
    passwordInput:setText("")
    loginStatusLabel:setText("")
    currentScreen = "welcome"
    showScreen("welcome")
end
menuScreen:addChild(logoutBtn)

-- Check balance screen
local checkBalanceScreen = sgl.Panel:new(2, 2, 47, 15)
checkBalanceScreen:setBorder(false)
checkBalanceScreen:setVisible(false)
checkBalanceScreen.data = {isScreen = true, screenName = "checkBalance"}
root:addChild(checkBalanceScreen)

local balanceTitleLabel = sgl.Label:new(2, 1, "Current Balance", 43)
balanceTitleLabel.style.fgColor = colors.yellow
checkBalanceScreen:addChild(balanceTitleLabel)

local balanceDisplayLabel = sgl.Label:new(2, 4, "", 43)
balanceDisplayLabel.style.fgColor = colors.green
checkBalanceScreen:addChild(balanceDisplayLabel)

local accountDisplayLabel = sgl.Label:new(2, 7, "", 43)
checkBalanceScreen:addChild(accountDisplayLabel)

local balanceBackBtn = sgl.Button:new(12, 10, 20, 2, "Back to Menu")
balanceBackBtn.onClick = function()
    updateMenuLabels()
    showScreen("menu")
end
checkBalanceScreen:addChild(balanceBackBtn)

-- Withdraw screen
local withdrawScreen = sgl.Panel:new(2, 2, 47, 15)
withdrawScreen:setBorder(false)
withdrawScreen:setVisible(false)
withdrawScreen.data = {isScreen = true, screenName = "withdraw"}
root:addChild(withdrawScreen)

local withdrawTitleLabel = sgl.Label:new(2, 1, "Withdrawal", 43)
withdrawTitleLabel.style.fgColor = colors.yellow
withdrawScreen:addChild(withdrawTitleLabel)

local withdrawBalanceLabel = sgl.Label:new(2, 3, "", 43)
withdrawScreen:addChild(withdrawBalanceLabel)

local withdrawAmountLabel = sgl.Label:new(2, 5, "Amount to withdraw:", 43)
withdrawScreen:addChild(withdrawAmountLabel)

local withdrawAmountInput = sgl.Input:new(2, 6, 43, 1)
withdrawScreen:addChild(withdrawAmountInput)

local withdrawStatusLabel = sgl.Label:new(2, 8, "", 43)
withdrawScreen:addChild(withdrawStatusLabel)

local withdrawBtn = sgl.Button:new(8, 10, 30, 2, "Withdraw")
withdrawBtn.style.bgColor = colors.orange
withdrawBtn.onClick = function()
    local amount = tonumber(withdrawAmountInput:getText())
    
    if not amount or amount <= 0 then
        withdrawStatusLabel:setText("Invalid amount")
        withdrawStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    if amount > balance then
        withdrawStatusLabel:setText("Insufficient funds")
        withdrawStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    if amount > config.atm.maxWithdrawal then
        withdrawStatusLabel:setText("Exceeds withdrawal limit")
        withdrawStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    withdrawStatusLabel:setText("Processing...")
    withdrawStatusLabel.style.fgColor = colors.white
    root:markDirty()
    
    local response, err = sendToServer(network.MSG.WITHDRAW, {
        amount = amount,
        atmID = atmID
    }, true)
    
    if response then
        balance = response.newBalance
        withdrawStatusLabel:setText("Withdrawal successful!")
        withdrawStatusLabel.style.fgColor = colors.green
        updateMenuLabels()
        root:markDirty()
        
        -- Wait for currency to be dispensed
        sleep(2)
        showScreen("menu")
    else
        withdrawStatusLabel:setText("Withdrawal failed: " .. tostring(err))
        withdrawStatusLabel.style.fgColor = colors.red
        root:markDirty()
    end
end
withdrawScreen:addChild(withdrawBtn)

local withdrawCancelBtn = sgl.Button:new(8, 13, 30, 2, "Cancel")
withdrawCancelBtn.onClick = function()
    showScreen("menu")
end
withdrawScreen:addChild(withdrawCancelBtn)

-- Deposit screen
local depositScreen = sgl.Panel:new(2, 2, 47, 15)
depositScreen:setBorder(false)
depositScreen:setVisible(false)
depositScreen.data = {isScreen = true, screenName = "deposit"}
root:addChild(depositScreen)

local depositTitleLabel = sgl.Label:new(2, 1, "Deposit", 43)
depositTitleLabel.style.fgColor = colors.yellow
depositScreen:addChild(depositTitleLabel)

local depositInfoLabel = sgl.Label:new(2, 3, "Insert currency into deposit slot", 43)
depositScreen:addChild(depositInfoLabel)

local depositAmountLabel = sgl.Label:new(2, 6, "Amount to deposit:", 43)
depositScreen:addChild(depositAmountLabel)

local depositAmountInput = sgl.Input:new(2, 7, 43, 1)
depositScreen:addChild(depositAmountInput)

local depositStatusLabel = sgl.Label:new(2, 13, "", 43)
depositScreen:addChild(depositStatusLabel)

local scanBtn = sgl.Button:new(5, 10, 18, 2, "Scan Currency")
scanBtn.onClick = function()
    depositStatusLabel:setText("Scanning currency...")
    depositStatusLabel.style.fgColor = colors.white
    root:markDirty()
    -- Would verify currency here
end
depositScreen:addChild(scanBtn)

local depositConfirmBtn = sgl.Button:new(25, 10, 18, 2, "Deposit")
depositConfirmBtn.style.bgColor = colors.green
depositConfirmBtn.onClick = function()
    local amount = tonumber(depositAmountInput:getText())
    
    if not amount or amount <= 0 then
        depositStatusLabel:setText("Invalid amount")
        depositStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    if amount > config.atm.maxDeposit then
        depositStatusLabel:setText("Exceeds deposit limit")
        depositStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    depositStatusLabel:setText("Processing...")
    depositStatusLabel.style.fgColor = colors.white
    root:markDirty()
    
    local response, err = sendToServer(network.MSG.DEPOSIT, {
        amount = amount,
        atmID = atmID
    }, true)
    
    if response then
        balance = response.newBalance
        depositStatusLabel:setText("Deposit successful!")
        depositStatusLabel.style.fgColor = colors.green
        updateMenuLabels()
        root:markDirty()
        sleep(2)
        showScreen("menu")
    else
        depositStatusLabel:setText("Deposit failed: " .. tostring(err))
        depositStatusLabel.style.fgColor = colors.red
        root:markDirty()
    end
end
depositScreen:addChild(depositConfirmBtn)

local depositCancelBtn = sgl.Button:new(8, 13, 30, 2, "Cancel")
depositCancelBtn.onClick = function()
    showScreen("menu")
end
depositScreen:addChild(depositCancelBtn)

-- Transfer screen
local transferScreen = sgl.Panel:new(2, 2, 47, 15)
transferScreen:setBorder(false)
transferScreen:setVisible(false)
transferScreen.data = {isScreen = true, screenName = "transfer"}
root:addChild(transferScreen)

local transferTitleLabel = sgl.Label:new(2, 1, "Transfer Funds", 43)
transferTitleLabel.style.fgColor = colors.yellow
transferScreen:addChild(transferTitleLabel)

local transferBalanceLabel = sgl.Label:new(2, 3, "", 43)
transferScreen:addChild(transferBalanceLabel)

local transferAccountLabel = sgl.Label:new(2, 5, "To Account Number:", 43)
transferScreen:addChild(transferAccountLabel)

local transferAccountInput = sgl.Input:new(2, 6, 43, 1)
transferScreen:addChild(transferAccountInput)

local transferAmountLabel = sgl.Label:new(2, 8, "Amount:", 43)
transferScreen:addChild(transferAmountLabel)

local transferAmountInput = sgl.Input:new(2, 9, 43, 1)
transferScreen:addChild(transferAmountInput)

local transferStatusLabel = sgl.Label:new(2, 11, "", 43)
transferScreen:addChild(transferStatusLabel)

local transferConfirmBtn = sgl.Button:new(8, 10, 30, 1, "Transfer")
transferConfirmBtn.style.bgColor = colors.blue
transferConfirmBtn.onClick = function()
    local toAccount = transferAccountInput:getText()
    local amount = tonumber(transferAmountInput:getText())
    
    if toAccount == "" then
        transferStatusLabel:setText("Enter account number")
        transferStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    if not amount or amount <= 0 then
        transferStatusLabel:setText("Invalid amount")
        transferStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    if amount > balance then
        transferStatusLabel:setText("Insufficient funds")
        transferStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    if amount > config.atm.maxTransfer then
        transferStatusLabel:setText("Exceeds transfer limit")
        transferStatusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    transferStatusLabel:setText("Processing...")
    transferStatusLabel.style.fgColor = colors.white
    root:markDirty()
    
    local response, err = sendToServer(network.MSG.TRANSFER, {
        amount = amount,
        toAccount = toAccount
    }, true)
    
    if response then
        balance = response.newBalance
        transferStatusLabel:setText("Transfer successful!")
        transferStatusLabel.style.fgColor = colors.green
        updateMenuLabels()
        root:markDirty()
        sleep(2)
        showScreen("menu")
    else
        transferStatusLabel:setText("Transfer failed: " .. tostring(err))
        transferStatusLabel.style.fgColor = colors.red
        root:markDirty()
    end
end
transferScreen:addChild(transferConfirmBtn)

local transferCancelBtn = sgl.Button:new(8, 13, 30, 1, "Cancel")
transferCancelBtn.onClick = function()
    showScreen("menu")
end
transferScreen:addChild(transferCancelBtn)

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
            -- Update balance labels before showing screens
            withdrawBalanceLabel:setText("Available: " .. balance .. " " .. config.currency.displayNamePlural)
            transferBalanceLabel:setText("Available: " .. balance .. " " .. config.currency.displayNamePlural)
            
            -- Show initial screen
            app:setFocus(usernameInput)
            showScreen("welcome")
            
            -- Start UI
            app:run()
        end
    )
end

-- Run application
main()
