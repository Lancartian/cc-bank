-- pocket/main.lua
-- Pocket computer banking app

local network = require("/lib/network")
local crypto = require("/lib/crypto")
local sgl = require("/lib/sgl/sgl")

-- Config
local config = {
    server = { port = 42000 },
    pocket = { port = 42001 }
}

-- State
local sessionToken = nil
local accountNumber = nil
local username = nil
local balance = 0
local currentScreen = "login"
local encryptionKey = nil

-- Initialize modem
local modem = network.init(config.pocket.port or network.PORT_POCKET)

if not modem then
    error("No modem found. Please attach a wireless modem.")
end

-- Screen dimensions for pocket computer
local w, h = term.getSize()

-- Create application
local app = sgl.createApplication("CC-Bank")

-- Create UI root
local root = sgl.Panel:new(1, 1, w, h)
root:setBorder(false)
app:setRoot(root)

-- Utility functions
local function sendToServer(msgType, data, waitForResponse)
    local message = network.createMessage(msgType, data, sessionToken, encryptionKey)
    network.broadcast(modem, config.server.port, message)
    
    if waitForResponse then
        local response, distance = network.receive(config.pocket.port or network.PORT_POCKET, 5)
        if response then
            return response, nil
        else
            return nil, "timeout"
        end
    end
    
    return true, nil
end

local function clearScreen()
    -- Remove all children from root panel
    while root.children and #root.children > 0 do
        root:removeChild(root.children[1])
    end
end

local function showError(message)
    local errorLabel = sgl.Label:new(2, h - 2, w - 2, message)
    errorLabel.style.fgColor = colors.red
    root:addChild(errorLabel)
    root:markDirty()
    sleep(2)
    root:removeChild(errorLabel)
end

-- Login Screen
local function showLogin()
    clearScreen()
    currentScreen = "login"
    
    local title = sgl.Label:new(2, 2, w - 2, "CC-Bank")
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    local usernameLabel = sgl.Label:new(2, 4, w - 2, "Username:")
    root:addChild(usernameLabel)
    
    local usernameInput = sgl.TextInput:new(2, 5, w - 2, 1, "")
    root:addChild(usernameInput)
    
    local passwordLabel = sgl.Label:new(2, 7, w - 2, "Password:")
    root:addChild(passwordLabel)
    
    local passwordInput = sgl.TextInput:new(2, 8, w - 2, 1, "")
    passwordInput.masked = true
    root:addChild(passwordInput)
    
    local loginBtn = sgl.Button:new(2, 10, w - 2, 1, "Login")
    loginBtn.onClick = function()
        local user = usernameInput.text
        local pass = passwordInput.text
        
        if user == "" or pass == "" then
            showError("Enter username and password")
            return
        end
        
        local passwordHash = crypto.sha256(pass)
        local response, err = sendToServer(network.MSG.AUTH_REQUEST, {
            username = user,
            passwordHash = passwordHash
        }, true)
        
        if response and response.type == network.MSG.AUTH_RESPONSE then
            if response.data.encrypted then
                local decrypted = crypto.base64Decode(response.data.encrypted)
                local decryptedData = crypto.decrypt(decrypted, encryptionKey)
                local authData = textutils.unserialiseJSON(decryptedData)
                
                if authData and authData.sessionToken then
                    sessionToken = authData.sessionToken
                    accountNumber = authData.accountNumber
                    username = user
                    showMenu()
                else
                    showError("Authentication failed")
                end
            else
                showError("Invalid response")
            end
        else
            showError(err or "Login failed")
        end
    end
    root:addChild(loginBtn)
    
    root:markDirty()
end

-- Main Menu Screen
local function showMenu()
    clearScreen()
    currentScreen = "menu"
    
    -- Update balance
    local response, err = sendToServer(network.MSG.BALANCE_CHECK, {}, true)
    if response and response.type == network.MSG.SUCCESS then
        balance = response.data.balance
    end
    
    local title = sgl.Label:new(2, 1, w - 2, username)
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    local balanceLabel = sgl.Label:new(2, 2, w - 2, "Balance: $" .. balance)
    balanceLabel.style.fgColor = colors.lime
    root:addChild(balanceLabel)
    
    local shopBtn = sgl.Button:new(2, 4, w - 2, 1, "Shop")
    shopBtn.onClick = function() showShop() end
    root:addChild(shopBtn)
    
    local transferBtn = sgl.Button:new(2, 6, w - 2, 1, "Transfer")
    transferBtn.onClick = function() showTransfer() end
    root:addChild(transferBtn)
    
    local logoutBtn = sgl.Button:new(2, h - 1, w - 2, 1, "Logout")
    logoutBtn.style.bgColor = colors.red
    logoutBtn.onClick = function()
        sessionToken = nil
        accountNumber = nil
        username = nil
        showLogin()
    end
    root:addChild(logoutBtn)
    
    root:markDirty()
end

-- Shop Screen
local function showShop()
    clearScreen()
    currentScreen = "shop"
    
    local title = sgl.Label:new(2, 1, w - 2, "Shop")
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    local statusLabel = sgl.Label:new(2, 2, w - 2, "Loading...")
    root:addChild(statusLabel)
    
    local backBtn = sgl.Button:new(2, h - 1, w - 2, 1, "Back")
    backBtn.onClick = function() showMenu() end
    root:addChild(backBtn)
    
    root:markDirty()
    
    -- Fetch shop items
    local response, err = sendToServer(network.MSG.SHOP_BROWSE, {}, true)
    if response and response.type == network.MSG.SUCCESS then
        root:removeChild(statusLabel)
        
        local items = response.data.items
        if #items == 0 then
            statusLabel.text = "No items available"
            root:addChild(statusLabel)
        else
            -- Create scrollable list
            local itemList = sgl.List:new(2, 3, w - 2, h - 5)
            local itemNames = {}
            local itemData = {}
            
            for i, item in ipairs(items) do
                table.insert(itemNames, item.displayName .. " - $" .. item.price .. " (x" .. item.stock .. ")")
                itemData[i] = item
            end
            
            itemList.items = itemNames
            itemList.onSelectionChanged = function(index, text)
                if itemData[index] then
                    showPurchase(itemData[index])
                end
            end
            root:addChild(itemList)
        end
    else
        statusLabel.text = "Error: " .. tostring(err)
    end
    
    root:markDirty()
end

-- Purchase Screen
local function showPurchase(item)
    clearScreen()
    currentScreen = "purchase"
    
    local title = sgl.Label:new(2, 1, w - 2, item.displayName)
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    local priceLabel = sgl.Label:new(2, 3, w - 2, "Price: $" .. item.price)
    root:addChild(priceLabel)
    
    local stockLabel = sgl.Label:new(2, 4, w - 2, "Stock: " .. item.stock)
    root:addChild(stockLabel)
    
    local qtyLabel = sgl.Label:new(2, 6, w - 2, "Quantity:")
    root:addChild(qtyLabel)
    
    local qtyInput = sgl.TextInput:new(2, 7, w - 2, 1, "1")
    root:addChild(qtyInput)
    
    local buyBtn = sgl.Button:new(2, 9, w - 2, 1, "Buy")
    buyBtn.style.bgColor = colors.green
    buyBtn.onClick = function()
        local qty = tonumber(qtyInput.text)
        if not qty or qty <= 0 then
            showError("Invalid quantity")
            return
        end
        
        local response, err = sendToServer(network.MSG.SHOP_PURCHASE, {
            itemName = item.name,
            quantity = qty
        }, true)
        
        if response and response.type == network.MSG.SUCCESS then
            showError("Purchase successful!")
            sleep(1)
            showMenu()
        else
            showError(err or "Purchase failed")
        end
    end
    root:addChild(buyBtn)
    
    local backBtn = sgl.Button:new(2, h - 1, w - 2, 1, "Back")
    backBtn.onClick = function() showShop() end
    root:addChild(backBtn)
    
    root:markDirty()
end

-- Transfer Screen
local function showTransfer()
    clearScreen()
    currentScreen = "transfer"
    
    local title = sgl.Label:new(2, 1, w - 2, "Transfer")
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    local toLabel = sgl.Label:new(2, 3, w - 2, "To:")
    root:addChild(toLabel)
    
    local toInput = sgl.TextInput:new(2, 4, w - 2, 1, "")
    root:addChild(toInput)
    
    local amountLabel = sgl.Label:new(2, 6, w - 2, "Amount:")
    root:addChild(amountLabel)
    
    local amountInput = sgl.TextInput:new(2, 7, w - 2, 1, "")
    root:addChild(amountInput)
    
    local sendBtn = sgl.Button:new(2, 9, w - 2, 1, "Send")
    sendBtn.style.bgColor = colors.green
    sendBtn.onClick = function()
        local toUser = toInput.text
        local amount = tonumber(amountInput.text)
        
        if toUser == "" or not amount or amount <= 0 then
            showError("Invalid transfer")
            return
        end
        
        local response, err = sendToServer(network.MSG.TRANSFER, {
            toUsername = toUser,
            amount = amount
        }, true)
        
        if response and response.type == network.MSG.SUCCESS then
            showError("Transfer successful!")
            sleep(1)
            showMenu()
        else
            showError(err or "Transfer failed")
        end
    end
    root:addChild(sendBtn)
    
    local backBtn = sgl.Button:new(2, h - 1, w - 2, 1, "Back")
    backBtn.onClick = function() showMenu() end
    root:addChild(backBtn)
    
    root:markDirty()
end

-- Get encryption key from server
print("Connecting to server...")
print("  Server port: " .. config.server.port)
print("  Pocket port: " .. config.pocket.port)
print("Sending PING...")
local pingResponse, err = sendToServer(network.MSG.PING, {}, true)
print("Response received: " .. tostring(pingResponse ~= nil))
if err then
    print("Error: " .. tostring(err))
end
if pingResponse then
    print("Response type: " .. tostring(pingResponse.type))
    if pingResponse.data then
        print("Has data: true")
        if pingResponse.data.encryptionKey then
            print("Has encryptionKey: true")
        else
            print("Has encryptionKey: false")
        end
    else
        print("Has data: false")
    end
end
if pingResponse and pingResponse.type == network.MSG.PONG then
    encryptionKey = pingResponse.data.encryptionKey
    print("Connected!")
else
    error("Could not connect to server")
end

-- Start with login screen
showLogin()

-- Run the application
app:run()
