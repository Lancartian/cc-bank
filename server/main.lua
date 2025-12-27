-- server/main.lua
-- Main bank server backend

local config = require("/config")
local network = require("/lib/network")
local crypto = require("/lib/crypto")
local accounts = require("/server/accounts")
local transactions = require("/server/transactions")
local networkStorage = require("/server/network_storage")
local catalog = require("/server/catalog")

-- Initialize configuration
config.init()
config.load()

-- First-run setup: Create management password if not set
if not config.management.masterPasswordHash then
    print("\n" .. string.rep("=", 50))
    print("FIRST RUN SETUP - Management Password Required")
    print(string.rep("=", 50))
    print("\nNo management password configured.")
    print("This password will be required for management console access.")
    print("\nPassword requirements:")
    print("  - Minimum 8 characters")
    print("  - Keep it secure - this controls all admin functions")
    print("")
    
    local password, confirm
    local validPassword = false
    
    while not validPassword do
        write("Enter master password: ")
        password = read("*")
        
        if #password < 8 then
            print("ERROR: Password must be at least 8 characters")
            print("")
        else
            write("Confirm password: ")
            confirm = read("*")
            
            if password ~= confirm then
                print("ERROR: Passwords do not match")
                print("")
            else
                validPassword = true
            end
        end
    end
    
    -- Hash and save password
    local passData = crypto.hashPassword(password)
    config.management.masterPasswordHash = passData.hash
    config.management.masterPasswordSalt = crypto.base64Encode(passData.salt)
    config.save()
    
    print("\n" .. string.rep("=", 50))
    print("Management password configured successfully!")
    print(string.rep("=", 50))
    print("")
end

-- Generate server encryption key if not exists
if not config.security.encryptionKey then
    config.security.encryptionKey = crypto.sha256(crypto.random(32) .. os.epoch("utc"))
    config.save()
end

-- Scan network for chests
print("\nScanning peripheral network...")
if not networkStorage.scanNetwork() then
    print("WARNING: No chests found on network!")
    print("Make sure chests are connected via wired modems")
end

local storageStatus = networkStorage.getChestInfo()
print("\nNetwork Storage Status:")
print("  STORAGE chests: " .. storageStatus.storageChests)
print("  Void chests: " .. storageStatus.voidChests)
print("  Total chests: " .. storageStatus.totalChests)

local encryptionKey = config.security.encryptionKey

-- Session management
local sessions = {}  -- token -> session data
local messageNonces = {}  -- Track nonces to prevent replay attacks
local managementSessions = {}  -- token -> {created, lastActivity, computerID}
local loginAttempts = {}  -- Track login attempts by sender for rate limiting

-- Initialize modem
local modem = network.init(config.server.port)

print("CC-Bank Server v1.0")
print("Server ID: " .. os.getComputerID())
print("Listening on port: " .. config.server.port)

-- Load data
print("\nLoading data...")
accounts.load()
transactions.load()
catalog.load()
networkStorage.initialize()

print("Accounts loaded: " .. #accounts.list())
print("Transactions loaded: " .. transactions.getStats().totalTransactions)
local catalogStats = catalog.getStats()
print("Catalog items: " .. catalogStats.totalItems)
local storageInfo = networkStorage.getChestInfo()
print("Storage chests: " .. storageInfo.storageChests)
print("Void chests: " .. storageInfo.voidChests)

-- Session management functions
local function createSession(accountNumber)
    local token = crypto.generateToken()
    local account = accounts.get(accountNumber)
    sessions[token] = {
        accountNumber = accountNumber,
        username = account.username,
        created = os.epoch("utc"),
        lastActivity = os.epoch("utc")
    }
    return token
end

local function validateSession(token)
    local session = sessions[token]
    if not session then
        return nil, "invalid_session"
    end
    
    local now = os.epoch("utc")
    if now - session.lastActivity > (config.server.sessionTimeout * 1000) then
        sessions[token] = nil
        return nil, "session_expired"
    end
    
    session.lastActivity = now
    return session, nil
end

local function endSession(token)
    sessions[token] = nil
end

local function validateManagementSession(token)
    local session = managementSessions[token]
    if not session then
        return nil, "invalid_management_session"
    end
    
    local now = os.epoch("utc")
    if now - session.lastActivity > (config.server.sessionTimeout * 1000) then
        managementSessions[token] = nil
        return nil, "session_expired"
    end
    
    session.lastActivity = now
    return session, nil
end

-- Check if nonce has been used (replay attack prevention)
local function checkNonce(nonce, timestamp)
    if not nonce then
        return false, "missing_nonce"
    end
    
    -- Check if message is too old (30 seconds)
    local now = os.epoch("utc")
    if now - timestamp > 30000 then
        return false, "message_expired"
    end
    
    -- Check if nonce has been used
    if messageNonces[nonce] then
        print("WARNING: Replay detected - nonce already used: " .. nonce:sub(1, 8) .. "...")
        return false, "replay_detected"
    end
    
    -- Mark nonce as used
    messageNonces[nonce] = timestamp
    
    -- Clean old nonces (older than 1 minute)
    for n, t in pairs(messageNonces) do
        if now - t > 60000 then
            messageNonces[n] = nil
        end
    end
    
    return true, nil
end

-- Rate limiting for login attempts
local function checkRateLimit(sender)
    local now = os.epoch("utc")
    
    if not loginAttempts[sender] then
        loginAttempts[sender] = {count = 1, firstAttempt = now}
        return true, nil
    end
    
    local attempt = loginAttempts[sender]
    
    -- Reset if first attempt was more than 1 minute ago
    if now - attempt.firstAttempt > 60000 then
        loginAttempts[sender] = {count = 1, firstAttempt = now}
        return true, nil
    end
    
    -- Check if too many attempts
    if attempt.count >= 5 then
        return false, "rate_limit_exceeded"
    end
    
    attempt.count = attempt.count + 1
    return true, nil
end

-- Message handlers
local handlers = {}

-- Ping handler
handlers[network.MSG.PING] = function(message, sender)
    return network.createMessage(network.MSG.PONG, {
        serverID = os.getComputerID(),
        timestamp = os.epoch("utc"),
        encryptionKey = encryptionKey
    })
end

-- Management console login
handlers[network.MSG.MGMT_LOGIN] = function(message, sender)
    local password = message.data.password
    
    if not password then
        return network.errorResponse("missing_fields", "Password required")
    end
    
    -- Verify against management master password
    if not config.management.masterPasswordHash then
        return network.errorResponse("not_configured", "Management password not set")
    end
    
    local salt = crypto.base64Decode(config.management.masterPasswordSalt)
    if not crypto.verifyPassword(password, config.management.masterPasswordHash, salt) then
        return network.errorResponse("auth_failed", "Invalid password")
    end
    
    -- Create management session
    local token = crypto.generateToken()
    managementSessions[token] = {
        created = os.epoch("utc"),
        lastActivity = os.epoch("utc"),
        computerID = sender
    }
    
    print("Management console authenticated from computer #" .. tostring(sender))
    
    return network.successResponse({
        token = token,
        serverTime = os.epoch("utc")
    })
end

-- Authentication
handlers[network.MSG.AUTH_REQUEST] = function(message, sender)
    -- Debug logging
    local debugFile = fs.open("/auth_debug.txt", "a")
    if debugFile then
        debugFile.writeLine(os.epoch("utc") .. ": AUTH_REQUEST received")
        debugFile.writeLine("  isEncrypted: " .. tostring(message.data.isEncrypted))
        debugFile.close()
    end
    
    -- Check nonce to prevent replay attacks
    local nonceValid, nonceErr = checkNonce(message.nonce, message.timestamp)
    if not nonceValid then
        return network.errorResponse("replay_attack", nonceErr or "Replay attack detected")
    end
    
    -- Check rate limiting
    local rateLimitOk, rateLimitErr = checkRateLimit(sender)
    if not rateLimitOk then
        return network.errorResponse("rate_limited", "Too many login attempts. Please wait.")
    end
    
    -- Decrypt credentials if encrypted
    local username, password
    
    if message.data.isEncrypted and message.data.encrypted then
        -- Decrypt the payload
        local decoded = crypto.base64Decode(message.data.encrypted)
        local decrypted = crypto.decrypt(decoded, encryptionKey)
        
        -- Parse JSON
        local success, decryptedData = pcall(textutils.unserialiseJSON, decrypted)
        if not success or not decryptedData then
            debugFile = fs.open("/auth_debug.txt", "a")
            if debugFile then
                debugFile.writeLine("  Decryption/parsing failed: " .. tostring(decryptedData))
                debugFile.close()
            end
            return network.errorResponse("decryption_failed", "Could not decrypt credentials")
        end
        
        username = decryptedData.username
        password = decryptedData.password
        
        -- Debug: log decrypted values
        debugFile = fs.open("/auth_debug.txt", "a")
        if debugFile then
            debugFile.writeLine("  Decrypted username: " .. tostring(username))
            debugFile.writeLine("  Decrypted password length: " .. tostring(#tostring(password or "")))
            debugFile.close()
        end
    else
        -- Fallback for unencrypted (should not happen in production)
        username = message.data.username
        password = message.data.password
        
        debugFile = fs.open("/auth_debug.txt", "a")
        if debugFile then
            debugFile.writeLine("  Unencrypted username: " .. tostring(username))
            debugFile.writeLine("  Unencrypted password length: " .. tostring(#tostring(password or "")))
            debugFile.close()
        end
    end
    
    if not username or not password then
        return network.errorResponse("missing_fields", "Username and password required")
    end
    
    local accountNumber, err = accounts.authenticate(username, password)
    
    -- Debug: log authentication result
    debugFile = fs.open("/auth_debug.txt", "a")
    if debugFile then
        debugFile.writeLine("  Auth result: " .. tostring(accountNumber or err))
        debugFile.close()
    end
    
    if not accountNumber then
        return network.errorResponse("auth_failed", err or "Authentication failed")
    end
    
    local token = createSession(accountNumber)
    local account = accounts.get(accountNumber)
    
    -- Send encrypted response
    return network.createMessage(network.MSG.AUTH_RESPONSE, {
        success = true,
        token = token,
        accountNumber = accountNumber,
        username = account.username,
        balance = account.balance,
        encryptionKey = encryptionKey  -- Share encryption key for session
    }, nil, encryptionKey)
end

-- Account creation (management only)
handlers[network.MSG.ACCOUNT_CREATE] = function(message, sender)
    -- Require management authentication
    local mgmtSession, err = validateManagementSession(message.token)
    if not mgmtSession then
        return network.errorResponse("unauthorized", err or "Management authentication required")
    end
    
    local username = message.data.username
    local password = message.data.password
    local initialBalance = message.data.initialBalance or 0
    
    if not username or not password then
        return network.errorResponse("missing_fields", "Username and password required")
    end
    
    local accountNumber, err = accounts.create(username, password, initialBalance)
    if not accountNumber then
        return network.errorResponse("create_failed", err or "Failed to create account")
    end
    
    print("Account created: " .. username .. " (#" .. accountNumber .. ")")
    
    return network.successResponse({
        accountNumber = accountNumber,
        username = username,
        balance = initialBalance
    })
end

-- Account list (management only)
handlers[network.MSG.ACCOUNT_LIST] = function(message, sender)
    -- Require management authentication
    local mgmtSession, err = validateManagementSession(message.token)
    if not mgmtSession then
        return network.errorResponse("unauthorized", err or "Management authentication required")
    end
    
    local accountList = accounts.list()
    
    return network.successResponse({
        accounts = accountList,
        count = #accountList
    })
end

-- Balance check
handlers[network.MSG.BALANCE_CHECK] = function(message, sender)
    -- Check nonce
    local nonceValid, nonceErr = checkNonce(message.nonce, message.timestamp)
    if not nonceValid then
        return network.errorResponse("replay_attack", nonceErr or "Replay attack detected")
    end
    
    local session, err = validateSession(message.token)
    if not session then
        return network.errorResponse("session_error", err)
    end
    
    local balance, err = accounts.getBalance(session.accountNumber)
    if not balance then
        return network.errorResponse("balance_error", err)
    end
    
    return network.successResponse({
        balance = balance,
        accountNumber = session.accountNumber
    })
end

-- Shop browse
handlers[network.MSG.SHOP_BROWSE] = function(message, sender)
    -- Check nonce
    local nonceValid, nonceErr = checkNonce(message.nonce, message.timestamp)
    if not nonceValid then
        return network.errorResponse("replay_attack", nonceErr or "Replay attack detected")
    end
    
    local session, err = validateSession(message.token)
    if not session then
        return network.errorResponse("session_error", err)
    end
    
    local category = message.data.category
    local searchQuery = message.data.search
    
    local items = {}
    
    if searchQuery then
        items = catalog.search(searchQuery)
    elseif category then
        items = catalog.getItemsByCategory(category)
    else
        items = catalog.getAllItems()
    end
    
    -- Get available stock from storage
    local storageItems = networkStorage.scanStorageItems()
    
    -- Merge catalog prices with storage availability
    local availableItems = {}
    for _, catalogItem in ipairs(items) do
        local stockInfo = storageItems[catalogItem.name]
        table.insert(availableItems, {
            name = catalogItem.name,
            displayName = stockInfo and stockInfo.displayName or catalogItem.name,
            price = catalogItem.price,
            category = catalogItem.category,
            description = catalogItem.description,
            stock = stockInfo and stockInfo.count or 0
        })
    end
    
    return network.successResponse({
        items = availableItems,
        categories = catalog.getCategories()
    })
end

-- Shop purchase
handlers[network.MSG.SHOP_PURCHASE] = function(message, sender)
    -- Check nonce
    local nonceValid, nonceErr = checkNonce(message.nonce, message.timestamp)
    if not nonceValid then
        return network.errorResponse("replay_attack", nonceErr or "Replay attack detected")
    end
    
    local session, err = validateSession(message.token)
    if not session then
        return network.errorResponse("session_error", err)
    end
    
    local itemName = message.data.itemName
    local quantity = message.data.quantity or 1
    
    if not itemName then
        return network.errorResponse("missing_fields", "Item name required")
    end
    
    if quantity <= 0 then
        return network.errorResponse("invalid_quantity", "Quantity must be positive")
    end
    
    -- Get item from catalog
    local catalogItem = catalog.getItem(itemName)
    if not catalogItem then
        return network.errorResponse("item_not_found", "Item not in catalog")
    end
    
    -- Calculate total cost
    local totalCost = catalogItem.price * quantity
    
    -- Check balance
    local balance = accounts.getBalance(session.accountNumber)
    if balance < totalCost then
        return network.errorResponse("insufficient_funds", "Insufficient funds")
    end
    
    -- Check stock availability
    local storageItems = networkStorage.scanStorageItems()
    local stockInfo = storageItems[itemName]
    if not stockInfo or stockInfo.count < quantity then
        return network.errorResponse("insufficient_stock", "Not enough items in stock")
    end
    
    -- Deduct balance
    local success, err = accounts.updateBalance(session.accountNumber, -totalCost)
    if not success then
        return network.errorResponse("balance_update_error", err)
    end
    
    -- Deliver items to user's void chest
    local account = accounts.get(session.accountNumber)
    local delivered, deliverErr = networkStorage.deliverToUser(account.username, itemName, quantity)
    
    if not delivered then
        -- Refund on delivery failure
        accounts.updateBalance(session.accountNumber, totalCost)
        return network.errorResponse("delivery_failed", deliverErr or "Could not deliver items")
    end
    
    -- Log transaction
    local txID = transactions.purchase(session.accountNumber, itemName, quantity, totalCost)
    
    return network.successResponse({
        transactionID = txID,
        itemName = itemName,
        quantity = quantity,
        totalCost = totalCost,
        newBalance = accounts.getBalance(session.accountNumber)
    })
end

-- Shop Management (Admin only)
handlers[network.MSG.SHOP_MANAGE] = function(message, sender)
    -- Validate management session
    local session, err = validateManagementSession(message.token)
    if not session then
        return network.errorResponse("session_error", err or "Invalid management session")
    end
    
    local action = message.data.action
    
    if action == "add" then
        local itemName = message.data.itemName
        local price = message.data.price
        local category = message.data.category or "General"
        local description = message.data.description or ""
        
        if not itemName or not price then
            return network.errorResponse("missing_fields", "Item name and price required")
        end
        
        if price <= 0 then
            return network.errorResponse("invalid_price", "Price must be positive")
        end
        
        catalog.setItem(itemName, price, category, description)
        catalog.save()
        
        return network.successResponse({
            message = "Item added to catalog",
            itemName = itemName,
            price = price
        })
        
    elseif action == "remove" then
        local itemName = message.data.itemName
        
        if not itemName then
            return network.errorResponse("missing_fields", "Item name required")
        end
        
        catalog.removeItem(itemName)
        catalog.save()
        
        return network.successResponse({
            message = "Item removed from catalog",
            itemName = itemName
        })
        
    elseif action == "update" then
        local itemName = message.data.itemName
        local price = message.data.price
        local category = message.data.category
        local description = message.data.description
        
        if not itemName then
            return network.errorResponse("missing_fields", "Item name required")
        end
        
        local existing = catalog.getItem(itemName)
        if not existing then
            return network.errorResponse("item_not_found", "Item not in catalog")
        end
        
        -- Use existing values if not provided
        price = price or existing.price
        category = category or existing.category
        description = description or existing.description
        
        catalog.setItem(itemName, price, category, description)
        catalog.save()
        
        return network.successResponse({
            message = "Item updated",
            itemName = itemName,
            price = price
        })
        
    elseif action == "process" then
        -- Process items from INPUT chests to STORAGE
        local itemsProcessed, uniqueTypes = networkStorage.processInputChests()
        
        if not itemsProcessed then
            return network.errorResponse("process_error", uniqueTypes or "Failed to process items")
        end
        
        return network.successResponse({
            message = "Items processed",
            itemsProcessed = itemsProcessed,
            uniqueTypes = uniqueTypes
        })
    else
        return network.errorResponse("invalid_action", "Unknown action: " .. tostring(action))
    end
end

-- Transfer
handlers[network.MSG.TRANSFER] = function(message, sender)
    -- Check nonce
    local nonceValid, nonceErr = checkNonce(message.nonce, message.timestamp)
    if not nonceValid then
        return network.errorResponse("replay_attack", nonceErr or "Replay attack detected")
    end
    
    local session, err = validateSession(message.token)
    if not session then
        return network.errorResponse("session_error", err)
    end
    
    local amount = message.data.amount
    local toAccount = message.data.toAccount
    
    if not amount or amount <= 0 then
        return network.errorResponse("invalid_amount", "Amount must be positive")
    end
    
    if not toAccount then
        return network.errorResponse("missing_fields", "Destination account required")
    end
    
    -- Check if destination account exists
    if not accounts.get(toAccount) then
        return network.errorResponse("invalid_account", "Destination account not found")
    end
    
    -- Check balance
    local balance = accounts.getBalance(session.accountNumber)
    if balance < amount then
        return network.errorResponse("insufficient_funds", "Insufficient funds")
    end
    
    -- Perform transfer
    local success, err = accounts.updateBalance(session.accountNumber, -amount)
    if not success then
        return network.errorResponse("transfer_error", err)
    end
    
    success, err = accounts.updateBalance(toAccount, amount)
    if not success then
        -- Rollback
        accounts.updateBalance(session.accountNumber, amount)
        return network.errorResponse("transfer_error", err)
    end
    
    -- Log transaction
    local txID = transactions.transfer(session.accountNumber, toAccount, amount)
    
    return network.successResponse({
        transactionID = txID,
        amount = amount,
        toAccount = toAccount,
        newBalance = accounts.getBalance(session.accountNumber)
    })
end

local function serverLoop()
    while true do
        local message, distance = network.receive(config.server.port, 1)
        
        if message then
            -- Validate message signature if token present
            if message.token and config.security.requireMessageSignatures then
                local valid, err = network.verifyMessage(message, message.token, encryptionKey)
                if not valid then
                    print("WARNING: Invalid message signature: " .. tostring(err))
                    network.broadcast(modem, config.server.port, network.errorResponse("invalid_signature", err))
                end
            end
            
            local handler = handlers[message.type]
            
            if handler then
                local response = handler(message, distance)
                if response then
                    -- Determine which port to send response to based on message type
                    local responsePort = config.server.port
                    
                    -- Management console messages get responses on management port
                    if message.type == network.MSG.MGMT_LOGIN or 
                       message.type == network.MSG.ACCOUNT_CREATE or
                       message.type == network.MSG.ACCOUNT_LIST or
                       message.type == network.MSG.ACCOUNT_DELETE or
                       message.type == network.MSG.SHOP_MANAGE then
                        responsePort = config.management.port
                    -- Pocket/Shop messages get responses on their respective ports  
                    elseif message.type == network.MSG.PING or
                           message.type == network.MSG.AUTH_REQUEST or
                           message.type == network.MSG.BALANCE_CHECK or
                           message.type == network.MSG.TRANSFER or
                           message.type == network.MSG.SHOP_BROWSE or
                           message.type == network.MSG.SHOP_PURCHASE then
                        responsePort = config.pocket.port or config.server.port
                    end
                    
                    network.broadcast(modem, responsePort, response)
                end
            else
                print("Unknown message type: " .. tostring(message.type))
            end
        end
        
        -- Clean up expired sessions
        local now = os.epoch("utc")
        for token, session in pairs(sessions) do
            if now - session.lastActivity > (config.server.sessionTimeout * 1000) then
                sessions[token] = nil
            end
        end
        
        -- Clean up expired management sessions
        for token, session in pairs(managementSessions) do
            if now - session.lastActivity > (config.server.sessionTimeout * 1000) then
                managementSessions[token] = nil
            end
        end
        
        -- Clean up old nonces (prevent replay attacks)
        for nonce, timestamp in pairs(messageNonces) do
            if now - timestamp > config.security.replayProtectionWindow then
                messageNonces[nonce] = nil
            end
        end
    end
end

-- Start server
print("\n=== Server started ===\n")
serverLoop()
