-- server/main.lua
-- Main bank server backend

local config = require("/config")
local network = require("/lib/network")
local crypto = require("/lib/crypto")
local accounts = require("/server/accounts")
local currency = require("/server/currency")
local transactions = require("/server/transactions")
local networkStorage = require("/server/network_storage")

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

local storageStatus = networkStorage.getStatus()
print("\nNetwork Storage Status:")
print("  MINT chest: " .. (storageStatus.mintChest and "OK" or "NOT FOUND"))
print("  OUTPUT chest: " .. (storageStatus.outputChest and "OK" or "NOT FOUND"))
print("  Denomination chests: " .. storageStatus.denominationChestCount)
print("  Total chests: " .. storageStatus.totalChests)

local encryptionKey = config.security.encryptionKey

-- Session management
local sessions = {}  -- token -> session data
local atmRegistry = {}  -- atmID -> {lastPing, online, authorized, computerID}
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
currency.load()
transactions.load()

print("Accounts loaded: " .. #accounts.list())
print("Transactions loaded: " .. transactions.getStats().totalTransactions)

local supply = currency.getTotalSupply()
print("Currency supply: " .. supply.totalValue .. " " .. config.currency.displayNamePlural)

-- Session management functions
local function createSession(accountNumber)
    local token = crypto.generateToken()
    sessions[token] = {
        accountNumber = accountNumber,
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
        timestamp = os.epoch("utc")
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
        local success, data = pcall(textutils.unserialiseJSON, decrypted)
        if not success then
            return network.errorResponse("decryption_failed", "Could not decrypt credentials")
        end
        
        username = data.username
        password = data.password
    else
        -- Fallback for unencrypted (should not happen in production)
        username = message.data.username
        password = message.data.password
    end
    
    if not username or not password then
        return network.errorResponse("missing_fields", "Username and password required")
    end
    
    local accountNumber, err = accounts.authenticate(username, password)
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

-- Withdrawal
handlers[network.MSG.WITHDRAW] = function(message, sender)
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
    local atmID = message.data.atmID
    
    if not amount or amount <= 0 then
        return network.errorResponse("invalid_amount", "Amount must be positive")
    end
    
    -- Check balance
    local balance = accounts.getBalance(session.accountNumber)
    if balance < amount then
        return network.errorResponse("insufficient_funds", "Insufficient funds")
    end
    
    -- Prepare currency for dispensing
    local dispenseData, err = currency.prepareDispense(amount, atmID)
    if not dispenseData then
        return network.errorResponse("dispense_error", err)
    end
    
    -- Update account balance
    local success, err = accounts.updateBalance(session.accountNumber, -amount)
    if not success then
        return network.errorResponse("balance_update_error", err)
    end
    
    -- Log transaction
    local txID = transactions.withdrawal(session.accountNumber, amount, atmID)
    
    return network.successResponse({
        transactionID = txID,
        amount = amount,
        newBalance = accounts.getBalance(session.accountNumber),
        dispenseData = dispenseData
    })
end

-- Deposit
handlers[network.MSG.DEPOSIT] = function(message, sender)
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
    local atmID = message.data.atmID
    
    if not amount or amount <= 0 then
        return network.errorResponse("invalid_amount", "Amount must be positive")
    end
    
    -- Update account balance
    local success, err = accounts.updateBalance(session.accountNumber, amount)
    if not success then
        return network.errorResponse("balance_update_error", err)
    end
    
    -- Log transaction
    local txID = transactions.deposit(session.accountNumber, amount, atmID)
    
    return network.successResponse({
        transactionID = txID,
        amount = amount,
        newBalance = accounts.getBalance(session.accountNumber)
    })
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

-- ATM registration (requires authorization token)
handlers[network.MSG.ATM_REGISTER] = function(message, sender)
    local atmID = message.data.atmID
    local authToken = message.data.authToken
    
    if not atmID then
        return network.errorResponse("missing_fields", "ATM ID required")
    end
    
    -- Check if ATM authorization is required
    if config.management.requireATMAuth then
        if not authToken then
            return network.errorResponse("auth_required", "Authorization token required")
        end
        
        -- Verify authorization token
        local authorized = config.management.authorizedATMs[tostring(atmID)]
        if not authorized or authorized.token ~= authToken then
            print("WARNING: Unauthorized ATM registration attempt - ID: " .. atmID)
            return network.errorResponse("not_authorized", "ATM not authorized")
        end
    end
    
    atmRegistry[atmID] = {
        lastPing = os.epoch("utc"),
        online = true,
        authorized = true,
        computerID = sender
    }
    
    print("ATM registered: " .. atmID .. " (Computer #" .. sender .. ")")
    
    return network.successResponse({
        registered = true,
        serverTime = os.epoch("utc"),
        encryptionKey = encryptionKey  -- Share encryption key
    })
end

-- ATM authorization from management console
handlers[network.MSG.ATM_AUTHORIZE] = function(message, sender)
    -- Require management authentication
    local mgmtSession, err = validateManagementSession(message.token)
    if not mgmtSession then
        return network.errorResponse("unauthorized", err or "Management authentication required")
    end
    
    local atmID = message.data.atmID
    local authToken = message.data.authToken
    
    if not atmID or not authToken then
        return network.errorResponse("missing_fields", "ATM ID and token required")
    end
    
    local atmNum = tonumber(atmID)
    if not atmNum or atmNum < 1 or atmNum > 16 then
        return network.errorResponse("invalid_atm_id", "ATM ID must be between 1 and 16")
    end
    
    -- Save authorization to server config
    config.management.authorizedATMs[tostring(atmID)] = {
        token = authToken,
        authorized = os.epoch("utc")
    }
    config.save()
    
    print("ATM #" .. atmID .. " authorized by management console")
    
    return network.successResponse({
        atmID = atmID,
        authorized = true
    })
end

-- ATM status update
handlers[network.MSG.ATM_STATUS] = function(message, sender)
    local atmID = message.data.atmID
    
    if atmRegistry[atmID] then
        atmRegistry[atmID].lastPing = os.epoch("utc")
        atmRegistry[atmID].online = true
        
        return network.successResponse({
            acknowledged = true
        })
    end
    
    return network.errorResponse("atm_not_registered", "ATM not registered")
end

-- Currency verification
handlers[network.MSG.CURRENCY_VERIFY] = function(message, sender)
    local nbtHash = message.data.nbtHash
    
    if not nbtHash then
        return network.errorResponse("missing_fields", "NBT hash required")
    end
    
    local record, err = currency.verify(nbtHash)
    if not record then
        return network.errorResponse("verification_failed", err)
    end
    
    return network.successResponse({
        valid = true,
        value = record.value,
        denomination = record.denomination
    })
end

-- Currency minting with automatic sorting
handlers[network.MSG.CURRENCY_MINT] = function(message, sender)
    -- Require management authentication
    local mgmtSession, err = validateManagementSession(message.token)
    if not mgmtSession then
        return network.errorResponse("unauthorized", err or "Management authentication required")
    end
    
    local autoSort = message.data.autoSort
    
    if autoSort then
        -- Automatic minting: read book names and sort to denomination chests
        local result, err = currency.mintAndSort()
        if not result then
            return network.errorResponse("mint_error", err or "Failed to mint currency")
        end
        
        return network.successResponse({
            totalAmount = result.totalAmount,
            processedCount = result.processedCount,
            denominationBreakdown = result.mintedByDenom
        })
    else
        -- Legacy manual minting (kept for compatibility)
        local amount = message.data.amount
        local denomination = message.data.denomination
        
        if not amount or not denomination then
            return network.errorResponse("missing_fields", "Amount and denomination required")
        end
        
        if amount <= 0 or denomination <= 0 then
            return network.errorResponse("invalid_values", "Values must be positive")
        end
        
        local success, err = currency.mint(amount, denomination)
        if not success then
            return network.errorResponse("mint_error", err)
        end
        
        return network.successResponse({
            totalAmount = amount * denomination,
            processedCount = amount
        })
    end
end

-- Currency dispensing using peripheral network and void chests
-- Process:
-- 1. currency.prepareDispense() moves bills from denomination chests to OUTPUT chest
-- 2. This function transfers items from OUTPUT chest to ATM's void chest
-- 3. Void chest frequency (set in-game) handles wireless transfer to ATM location
local function dispenseToATM(atmID, amount)
    if not atmRegistry[atmID] then
        return false, "atm_not_registered"
    end
    
    if not atmRegistry[atmID].authorized then
        return false, "atm_not_authorized"
    end
    
    -- Validate ATM ID range (1-16)
    if atmID < 1 or atmID > 16 then
        print("ERROR: ATM ID " .. atmID .. " out of range (1-16)")
        return false, "invalid_atm_id"
    end
    
    -- Prepare currency - this moves bills to OUTPUT chest
    local dispensed, err = currency.prepareDispense(amount, atmID)
    if not dispensed then
        print("ERROR: " .. (err or "Unknown error") .. " for ATM " .. atmID .. " withdrawal")
        return false, err or "insufficient_currency"
    end
    
    print("Currency prepared in OUTPUT chest:")
    for _, bill in ipairs(dispensed.bills) do
        print("  " .. bill.count .. "x $" .. bill.denomination .. " bills")
    end
    
    -- Get OUTPUT chest and ATM void chest
    local outputChest = networkStorage.getOutputChest()
    if not outputChest then
        print("ERROR: OUTPUT chest not found")
        return false, "output_chest_not_configured"
    end
    
    -- Get ATM's void chest from network storage
    local atmVoidChestInfo = networkStorage.getVoidChest(atmID)
    
    if not atmVoidChestInfo then
        print("ERROR: Void chest for ATM " .. atmID .. " not found on network")
        print("       Place a paper renamed with 'ATM " .. atmID .. "' inside the void chest")
        return false, "atm_void_chest_not_found"
    end
    
    print("Transferring from OUTPUT chest to void chest: " .. atmVoidChestInfo.name)
    
    -- Transfer all items from OUTPUT chest to ATM void chest
    local outputPeripheral = outputChest.peripheral
    local totalTransferred = 0
    
    local items = outputPeripheral.list()
    for slot, item in pairs(items) do
        -- Skip marker slot
        if slot ~= outputChest.markerSlot and item.name == config.currency.itemName then
            -- Use pushItems to transfer to void chest
            local moved = outputPeripheral.pushItems(atmVoidChestInfo.name, slot)
            totalTransferred = totalTransferred + moved
            print("  Transferred " .. moved .. " items from slot " .. slot)
        end
    end
    
    print("Total dispensed: $" .. amount .. " to ATM #" .. atmID)
    print("  " .. totalTransferred .. " total bills transferred")
    
    return true, nil
end

-- Main server loop
local function serverLoop()
    while true do
        local message, distance = network.receive(config.server.port, 1)
        
        if message then
            -- Check for replay attacks
            if message.nonce then
                if messageNonces[message.nonce] then
                    print("WARNING: Replay attack detected - duplicate nonce")
                else
                    messageNonces[message.nonce] = os.epoch("utc")
                end
            end
            
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
                       message.type == network.MSG.CURRENCY_MINT or
                       message.type == network.MSG.ACCOUNT_CREATE or
                       message.type == network.MSG.ACCOUNT_LIST or
                       message.type == network.MSG.ACCOUNT_DELETE or
                       message.type == network.MSG.ATM_AUTHORIZE then
                        responsePort = config.management.port
                    -- ATM messages get responses on ATM port  
                    elseif message.type == network.MSG.ATM_REGISTER or
                           message.type == network.MSG.ATM_STATUS or
                           message.type == network.MSG.AUTH_REQUEST or
                           message.type == network.MSG.BALANCE_CHECK or
                           message.type == network.MSG.WITHDRAW or
                           message.type == network.MSG.DEPOSIT or
                           message.type == network.MSG.TRANSFER then
                        responsePort = config.atm.port
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
        
        -- Check ATM status
        for atmID, atm in pairs(atmRegistry) do
            if now - atm.lastPing > 60000 then  -- 60 seconds
                atm.online = false
            end
        end
    end
end

-- Start server
print("\n=== Server started ===\n")
serverLoop()
