-- server/main.lua
-- Main bank server backend

local config = require("config")
local network = require("lib.network")
local crypto = require("lib.crypto")
local accounts = require("server.accounts")
local currency = require("server.currency")
local transactions = require("server.transactions")

-- Initialize configuration
config.init()
config.load()

-- Generate server encryption key if not exists
if not config.security.encryptionKey then
    config.security.encryptionKey = crypto.sha256(crypto.random(32) .. os.epoch("utc"))
    config.save()
end

local encryptionKey = config.security.encryptionKey

-- Session management
local sessions = {}  -- token -> session data
local atmRegistry = {}  -- atmID -> {frequency, lastPing, online, authorized}
local messageNonces = {}  -- Track nonces to prevent replay attacks

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

-- Message handlers
local handlers = {}

-- Ping handler
handlers[network.MSG.PING] = function(message, sender)
    return network.createMessage(network.MSG.PONG, {
        serverID = os.getComputerID(),
        timestamp = os.epoch("utc")
    })
end

-- Authentication
handlers[network.MSG.AUTH_REQUEST] = function(message, sender)
    -- Decrypt credentials if encrypted
    local data = message.data
    if message.data.isEncrypted then
        local success, decrypted = network.verifyMessage(message, encryptionKey, encryptionKey)
        if not success then
            return network.errorResponse("decryption_failed", "Could not decrypt credentials")
        end
        data = decrypted
    end
    
    local username = data.username
    local password = data.password
    
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

-- Balance check
handlers[network.MSG.BALANCE_CHECK] = function(message, sender)
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
    local frequency = message.data.frequency
    local authToken = message.data.authToken
    
    if not atmID or not frequency then
        return network.errorResponse("missing_fields", "ATM ID and frequency required")
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
        frequency = frequency,
        lastPing = os.epoch("utc"),
        online = true,
        authorized = true,
        computerID = sender
    }
    
    print("ATM registered: " .. atmID .. " (Frequency: " .. frequency .. ")")
    
    return network.successResponse({
        registered = true,
        serverTime = os.epoch("utc"),
        encryptionKey = encryptionKey  -- Share encryption key
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

-- Currency dispensing with redstone control for hopper/dropper selection
-- Note: Void chest frequencies are set in Create Utilities GUI (not via redstone)
-- Redstone controls which hopper/dropper pushes items into which void chest
local function dispenseToATM(atmID, items)
    if not atmRegistry[atmID] then
        return false, "atm_not_registered"
    end
    
    if not atmRegistry[atmID].authorized then
        return false, "atm_not_authorized"
    end
    
    local frequency = atmRegistry[atmID].frequency
    
    -- Activate redstone to control the hopper/dropper that pushes items
    -- into the void chest matching this ATM's frequency
    -- Server has multiple void chests, each with unique frequency
    -- ATM has void chest with matching frequency for item transfer
    local sides = {"left", "right", "front", "back", "top", "bottom"}
    
    if atmID > 6 then
        print("ERROR: ATM ID " .. atmID .. " exceeds maximum of 6 ATMs")
        return false, "atm_id_too_high"
    end
    
    local side = sides[atmID]
    if side then
        redstone.setOutput(side, true)
        sleep(2)  -- Keep active long enough to transfer items
        redstone.setOutput(side, false)
    else
        print("ERROR: Invalid ATM ID " .. atmID)
        return false, "invalid_atm_id"
    end
    
    print("Dispensed to ATM " .. atmID .. " (Frequency: " .. frequency .. ")")
    
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
                    network.broadcast(modem, config.server.port, response)
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
