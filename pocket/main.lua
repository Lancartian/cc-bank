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

-- Forward declarations for screen functions
local showLogin, showMenu, showShop, showPurchase, showTransfer

local function clearScreen()
    -- Remove all children from root panel
    while root.children and #root.children > 0 do
        root:removeChild(root.children[1])
    end
end

local function showError(message)
    local errorLabel = sgl.Label:new(2, h - 2, message, w - 2)
    errorLabel.style.fgColor = colors.red
    root:addChild(errorLabel)
    root:markDirty()
    sleep(2)
    root:removeChild(errorLabel)
end

-- Login Screen
showLogin = function()
    clearScreen()
    currentScreen = "login"
    
    local title = sgl.Label:new(2, 2, "CC-Bank", w - 2)
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    local usernameLabel = sgl.Label:new(2, 4, "Username:", w - 2)
    root:addChild(usernameLabel)
    
    local usernameInput = sgl.Input:new(2, 5, w - 2, "")
    root:addChild(usernameInput)
    
    local passwordLabel = sgl.Label:new(2, 7, "Password:", w - 2)
    root:addChild(passwordLabel)
    
    local passwordInput = sgl.Input:new(2, 8, w - 2, "")
    passwordInput.masked = true
    root:addChild(passwordInput)
    
    -- Status/error label
    local statusLabel = sgl.Label:new(2, 14, "", w - 2)
    statusLabel.style.fgColor = colors.red
    root:addChild(statusLabel)
    
    local loginBtn = sgl.Button:new(2, 10, w - 2, 3, "Login")
    loginBtn.onClick = function()
        local user = usernameInput:getText() or ""
        local pass = passwordInput:getText() or ""
        
        statusLabel:setText("")
        
        if user == "" or pass == "" then
            statusLabel:setText("Enter username and password")
            return
        end
        
        statusLabel.style.fgColor = colors.yellow
        statusLabel:setText("Authenticating...")
        
        -- Debug: Log the request
        local f = fs.open("/auth_request_debug.txt", "w")
        if f then
            f.writeLine("Sending AUTH_REQUEST")
            f.writeLine("Username: " .. user)
            f.writeLine("Password length: " .. #pass)
            f.writeLine("Listening on port: " .. config.pocket.port)
            f.close()
        end
        
        -- Send plain password (will be encrypted by network layer)
        local response, err = sendToServer(network.MSG.AUTH_REQUEST, {
            username = user,
            password = pass
        }, true)
        
        -- Debug: Log the response
        f = fs.open("/auth_response_debug.txt", "w")
        if f then
            f.writeLine("Response received: " .. tostring(response ~= nil))
            if response then
                f.writeLine("Response type: " .. tostring(response.type))
                f.writeLine("Has data: " .. tostring(response.data ~= nil))
                if response.data then
                    f.writeLine("data.encrypted: " .. tostring(response.data.encrypted ~= nil))
                    f.writeLine("data.isEncrypted: " .. tostring(response.data.isEncrypted))
                end
            else
                f.writeLine("Error: " .. tostring(err))
            end
            f.close()
        end
        
        if response and response.type == network.MSG.AUTH_RESPONSE then
            f = fs.open("/auth_processing_debug.txt", "w")
            if f then
                f.writeLine("Processing AUTH_RESPONSE")
                f.writeLine("Checking data.encrypted...")
                f.close()
            end
            
            if response.data.encrypted then
                local f2 = fs.open("/auth_decrypt_debug.txt", "w")
                if f2 then
                    f2.writeLine("Decrypting response...")
                    f2.close()
                end
                
                local decrypted = crypto.base64Decode(response.data.encrypted)
                local decryptedData = crypto.decrypt(decrypted, encryptionKey)
                local authData = textutils.unserialiseJSON(decryptedData)
                
                local f3 = fs.open("/auth_data_debug.txt", "w")
                if f3 then
                    f3.writeLine("Auth data parsed: " .. tostring(authData ~= nil))
                    if authData then
                        f3.writeLine("Has token: " .. tostring(authData.token ~= nil))
                        f3.writeLine("Has accountNumber: " .. tostring(authData.accountNumber ~= nil))
                        f3.writeLine("Has balance: " .. tostring(authData.balance ~= nil))
                    end
                    f3.close()
                end
                
                if authData and authData.token then
                    local f4 = fs.open("/auth_success_debug.txt", "w")
                    if f4 then
                        f4.writeLine("Setting session data...")
                        f4.close()
                    end
                    
                    sessionToken = authData.token
                    accountNumber = authData.accountNumber
                    username = user
                    balance = authData.balance or 0
                    
                    local f5 = fs.open("/auth_menu_debug.txt", "w")
                    if f5 then
                        f5.writeLine("About to call showMenu()")
                        f5.writeLine("Current screen: " .. currentScreen)
                        f5.close()
                    end
                    
                    showMenu()
                    
                    local f6 = fs.open("/auth_complete_debug.txt", "w")
                    if f6 then
                        f6.writeLine("showMenu() returned")
                        f6.writeLine("Current screen: " .. currentScreen)
                        f6.close()
                    end
                else
                    statusLabel.style.fgColor = colors.red
                    statusLabel:setText("Authentication failed")
                end
            else
                statusLabel.style.fgColor = colors.red
                statusLabel:setText("Invalid response from server")
            end
        elseif response and response.type == network.MSG.ERROR then
            -- Handle error response from server
            local errorMsg = "Login failed"
            if response.data and response.data.message then
                errorMsg = response.data.message
            end
            statusLabel.style.fgColor = colors.red
            statusLabel:setText(errorMsg)
        else
            -- Network or timeout error
            local errorMsg = "Connection failed"
            if err == "timeout" then
                errorMsg = "Server timeout - check connection"
            elseif err then
                errorMsg = "Error: " .. err
            end
            statusLabel.style.fgColor = colors.red
            statusLabel:setText(errorMsg)
        end
    end
    root:addChild(loginBtn)
    
    root:markDirty()
end

-- Main Menu Screen
showMenu = function()
    local f = fs.open("/showmenu_debug.txt", "w")
    if f then
        f.writeLine("showMenu() started")
        f.close()
    end
    
    clearScreen()
    
    f = fs.open("/showmenu_debug.txt", "a")
    if f then
        f.writeLine("clearScreen() completed")
        f.close()
    end
    
    currentScreen = "menu"
    
    f = fs.open("/showmenu_debug.txt", "a")
    if f then
        f.writeLine("Creating title label...")
        f.writeLine("username: " .. tostring(username))
        f.close()
    end
    
    local title = sgl.Label:new(2, 1, username, w - 2)
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    f = fs.open("/showmenu_debug.txt", "a")
    if f then
        f.writeLine("Title added, creating balance label...")
        f.writeLine("balance: " .. tostring(balance))
        f.close()
    end
    
    local balanceLabel = sgl.Label:new(2, 2, "Balance: $" .. balance, w - 2)
    balanceLabel.style.fgColor = colors.lime
    root:addChild(balanceLabel)
    
    local shopBtn = sgl.Button:new(2, 4, w - 2, 3, "Shop")
    shopBtn.onClick = function() showShop() end
    root:addChild(shopBtn)
    
    local transferBtn = sgl.Button:new(2, 8, w - 2, 3, "Transfer")
    transferBtn.onClick = function() showTransfer() end
    root:addChild(transferBtn)
    
    local logoutBtn = sgl.Button:new(2, h - 3, w - 2, 3, "Logout")
    logoutBtn.style.bgColor = colors.red
    logoutBtn.onClick = function()
        sessionToken = nil
        accountNumber = nil
        username = nil
        showLogin()
    end
    root:addChild(logoutBtn)
    
    f = fs.open("/showmenu_debug.txt", "a")
    if f then
        f.writeLine("All buttons added, marking dirty...")
        f.close()
    end
    
    root:markDirty()
    
    f = fs.open("/showmenu_debug.txt", "a")
    if f then
        f.writeLine("showMenu() complete!")
        f.close()
    end
end

-- Shop Screen
showShop = function()
    clearScreen()
    currentScreen = "shop"
    
    local title = sgl.Label:new(2, 1, "Shop", w - 2)
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    local statusLabel = sgl.Label:new(2, 2, "Loading...", w - 2)
    root:addChild(statusLabel)
    
    local backBtn = sgl.Button:new(2, h - 3, w - 2, 3, "Back")
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
showPurchase = function(item)
    clearScreen()
    currentScreen = "purchase"
    
    local title = sgl.Label:new(2, 1, item.displayName, w - 2)
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    local priceLabel = sgl.Label:new(2, 3, "Price: $" .. item.price, w - 2)
    root:addChild(priceLabel)
    
    local stockLabel = sgl.Label:new(2, 4, "Stock: " .. item.stock, w - 2)
    root:addChild(stockLabel)
    
    local qtyLabel = sgl.Label:new(2, 6, "Quantity:", w - 2)
    root:addChild(qtyLabel)
    
    local qtyInput = sgl.Input:new(2, 7, w - 2, "1")
    root:addChild(qtyInput)
    
    local buyBtn = sgl.Button:new(2, 9, w - 2, 3, "Buy")
    buyBtn.style.bgColor = colors.green
    buyBtn.onClick = function()
        local qty = tonumber(qtyInput:getText())
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
    
    local backBtn = sgl.Button:new(2, h - 3, w - 2, 3, "Back")
    backBtn.onClick = function() showShop() end
    root:addChild(backBtn)
    
    root:markDirty()
end

-- Transfer Screen
showTransfer = function()
    clearScreen()
    currentScreen = "transfer"
    
    local title = sgl.Label:new(2, 1, "Transfer", w - 2)
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    local toLabel = sgl.Label:new(2, 3, "To:", w - 2)
    root:addChild(toLabel)
    
    local toInput = sgl.Input:new(2, 4, w - 2, "")
    root:addChild(toInput)
    
    local amountLabel = sgl.Label:new(2, 6, "Amount:", w - 2)
    root:addChild(amountLabel)
    
    local amountInput = sgl.Input:new(2, 7, w - 2, "")
    root:addChild(amountInput)
    
    local sendBtn = sgl.Button:new(2, 9, w - 2, 3, "Send")
    sendBtn.style.bgColor = colors.green
    sendBtn.onClick = function()
        local toUser = toInput:getText()
        local amount = tonumber(amountInput:getText())
        
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
    
    local backBtn = sgl.Button:new(2, h - 3, w - 2, 3, "Back")
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
