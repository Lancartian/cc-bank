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

-- Forward declarations for screen functions (order matters for cross-references)
local showLogin, showMenu, showShop, showTransfer, showPurchase
-- Reference to active shop list for background refresh
local pocketItemList = nil

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
        
        -- Send plain password (will be encrypted by network layer)
        local response, err = sendToServer(network.MSG.AUTH_REQUEST, {
            username = user,
            password = pass
        }, true)
        
        if response and response.type == network.MSG.AUTH_RESPONSE then
            if response.data.encrypted then
                local decrypted = crypto.base64Decode(response.data.encrypted)
                local decryptedData = crypto.decrypt(decrypted, encryptionKey)
                local authData = textutils.unserialiseJSON(decryptedData)
                
                if authData and authData.token then
                    sessionToken = authData.token
                    accountNumber = authData.accountNumber
                    username = user
                    balance = authData.balance or 0
                    
                    showMenu()
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
    local success, err = pcall(function()
        clearScreen()
        currentScreen = "menu"
        
        local title = sgl.Label:new(2, 1, username, w - 2)
        title.style.fgColor = colors.yellow
        root:addChild(title)
        
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
        
        root:markDirty()
    end)
    
    if not success then
        clearScreen()
        local errorLabel = sgl.Label:new(2, 2, "Error loading menu", w - 2)
        errorLabel.style.fgColor = colors.red
        root:addChild(errorLabel)
        local detailLabel = sgl.Label:new(2, 3, tostring(err), w - 2)
        detailLabel.style.fgColor = colors.gray
        root:addChild(detailLabel)
        local logoutBtn = sgl.Button:new(2, h - 3, w - 2, 3, "Logout")
        logoutBtn.onClick = function()
            sessionToken = nil
            accountNumber = nil
            username = nil
            showLogin()
        end
        root:addChild(logoutBtn)
        root:markDirty()
    end
end

-- Shop Screen
showShop = function()
    clearScreen()
    currentScreen = "shop"
    
    local title = sgl.Label:new(2, 1, "Shop", w - 2)
    title.style.fgColor = colors.yellow
    root:addChild(title)
    
    local statusLabel = sgl.Label:new(2, 2, "Loading catalog...", w - 2)
    root:addChild(statusLabel)
    
    local backBtn = sgl.Button:new(2, h - 3, w - 2, 3, "Back")
    backBtn.onClick = function() showMenu() end
    root:addChild(backBtn)
    
    root:markDirty()
    
    -- Fetch shop catalog (auto-scanned from STORAGE chests)
    local success, result = pcall(function()
        return sendToServer(network.MSG.SHOP_GET_CATALOG, {}, true)
    end)
    
    if not success then
        statusLabel:setText("Error: Connection failed")
        statusLabel.style.fgColor = colors.red
        root:markDirty()
        return
    end
    
    local response, err = result, nil
    if not response then
        err = "No response from server"
    end
    
    if response and response.type == network.MSG.SUCCESS then
        root:removeChild(statusLabel)
        
        local items = response.data.items
        if #items == 0 then
            local emptyLabel = sgl.Label:new(2, 2, "No items in stock", w - 2)
            emptyLabel.style.fgColor = colors.gray
            root:addChild(emptyLabel)
        else
            -- Create scrollable list
            local itemList = sgl.List:new(2, 3, w - 2, h - 5)
            local itemNames = {}
            local itemData = {}
            
            for i, item in ipairs(items) do
                if item.price > 0 then
                    -- Only show items with prices set
                    table.insert(itemNames, item.displayName .. " - $" .. item.price .. " (x" .. item.stock .. ")")
                    itemData[#itemNames] = item
                end
            end
            
            if #itemNames == 0 then
                local noPricesLabel = sgl.Label:new(2, 2, "No items priced yet", w - 2)
                noPricesLabel.style.fgColor = colors.gray
                root:addChild(noPricesLabel)
            else
                itemList.items = itemNames
                itemList.onSelectionChanged = function(index, text)
                    if itemData[index] then
                        showPurchase(itemData[index])
                    end
                end
                root:addChild(itemList)
                -- Save reference for background refresher
                pocketItemList = {widget = itemList, data = itemData}
            end
        end
    else
        statusLabel:setText("Error: " .. tostring(err or "Unknown error"))
    end
    
    root:markDirty()
end

-- Purchase Screen
showPurchase = function(item)
    local success, err = pcall(function()
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
    end)
    
    if not success then
        clearScreen()
        local errorLabel = sgl.Label:new(2, 2, "Error: " .. tostring(err), w - 2)
        errorLabel.style.fgColor = colors.red
        root:addChild(errorLabel)
        local backBtn = sgl.Button:new(2, h - 3, w - 2, 3, "Back")
        backBtn.onClick = function() showShop() end
        root:addChild(backBtn)
        root:markDirty()
    end
end

-- Transfer Screen
showTransfer = function()
    local success, err = pcall(function()
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
    end)
    
    if not success then
        clearScreen()
        local errorLabel = sgl.Label:new(2, 2, "Error: " .. tostring(err), w - 2)
        errorLabel.style.fgColor = colors.red
        root:addChild(errorLabel)
        local backBtn = sgl.Button:new(2, h - 3, w - 2, 3, "Back")
        backBtn.onClick = function() showMenu() end
        root:addChild(backBtn)
        root:markDirty()
    end
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
-- Run the application alongside a background refresher that updates the shop catalog every second
local function runApp()
    app:run()
end

local function backgroundRefresher()
    while true do
        if currentScreen == "shop" and pocketItemList and pocketItemList.widget then
            local success, response = pcall(function()
                return sendToServer(network.MSG.SHOP_GET_CATALOG, {}, true)
            end)
            if success and response and response.type == network.MSG.SUCCESS then
                local items = response.data.items or {}
                local itemNames = {}
                local itemData = {}
                for i, item in ipairs(items) do
                    if item.price and item.price > 0 then
                        table.insert(itemNames, item.displayName .. " - $" .. item.price .. " (x" .. item.stock .. ")")
                        itemData[#itemNames] = item
                    end
                end
                pocketItemList.data = itemData
                pocketItemList.widget.items = itemNames
                root:markDirty()
            end
        end
        sleep(1)
    end
end

parallel.waitForAny(runApp, backgroundRefresher)
