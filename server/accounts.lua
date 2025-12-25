-- server/accounts.lua
-- Account management system

local crypto = require("lib.crypto")
local config = require("config")

local accounts = {}

-- In-memory account storage
local accountData = {}
local accountIndex = {}  -- username -> account

-- Generate unique account number
local function generateAccountNumber()
    local number
    repeat
        number = ""
        for i = 1, config.security.accountNumberLength do
            number = number .. tostring(math.random(0, 9))
        end
    until not accountIndex[number]
    return number
end

-- Load accounts from disk
function accounts.load()
    if fs.exists(config.server.accountsFile) then
        local file = fs.open(config.server.accountsFile, "r")
        if file then
            local content = file.readAll()
            file.close()
            
            accountData = textutils.unserialiseJSON(content) or {}
            
            -- Rebuild index
            accountIndex = {}
            for accountNumber, account in pairs(accountData) do
                accountIndex[account.username] = accountNumber
            end
            
            return true
        end
    end
    return false
end

-- Save accounts to disk
function accounts.save()
    local file = fs.open(config.server.accountsFile, "w")
    if file then
        file.write(textutils.serialiseJSON(accountData))
        file.close()
        return true
    end
    return false
end

-- Create new account
function accounts.create(username, password, initialBalance)
    initialBalance = initialBalance or 0
    
    -- Check if username exists
    if accountIndex[username] then
        return nil, "username_exists"
    end
    
    -- Validate password
    if #password < config.security.minPasswordLength then
        return nil, "password_too_short"
    end
    
    -- Generate account number
    local accountNumber = generateAccountNumber()
    
    -- Hash password
    local passwordData = crypto.hashPassword(password)
    
    -- Create account
    local account = {
        accountNumber = accountNumber,
        username = username,
        passwordHash = passwordData.hash,
        passwordSalt = passwordData.salt,
        balance = initialBalance,
        created = os.epoch("utc"),
        lastLogin = nil,
        locked = false,
        failedAttempts = 0,
        lockoutUntil = nil,
        pin = nil,  -- Optional PIN for ATM
        pinHash = nil,
        pinSalt = nil,
    }
    
    accountData[accountNumber] = account
    accountIndex[username] = accountNumber
    
    accounts.save()
    
    return accountNumber, nil
end

-- Authenticate user
function accounts.authenticate(username, password)
    local accountNumber = accountIndex[username]
    if not accountNumber then
        return nil, "invalid_credentials"
    end
    
    local account = accountData[accountNumber]
    
    -- Check if account is locked
    if account.locked then
        if account.lockoutUntil and os.epoch("utc") < account.lockoutUntil then
            return nil, "account_locked"
        else
            account.locked = false
            account.failedAttempts = 0
            account.lockoutUntil = nil
        end
    end
    
    -- Verify password
    if crypto.verifyPassword(password, account.passwordHash, account.passwordSalt) then
        account.failedAttempts = 0
        account.lastLogin = os.epoch("utc")
        accounts.save()
        return accountNumber, nil
    else
        -- Failed attempt
        account.failedAttempts = account.failedAttempts + 1
        
        if account.failedAttempts >= config.server.maxLoginAttempts then
            account.locked = true
            account.lockoutUntil = os.epoch("utc") + (config.server.lockoutDuration * 1000)
        end
        
        accounts.save()
        return nil, "invalid_credentials"
    end
end

-- Authenticate with PIN (for ATM)
function accounts.authenticatePIN(accountNumber, pin)
    local account = accountData[accountNumber]
    if not account then
        return false, "invalid_account"
    end
    
    if not account.pinHash then
        return false, "no_pin_set"
    end
    
    -- Check if account is locked
    if account.locked then
        if account.lockoutUntil and os.epoch("utc") < account.lockoutUntil then
            return false, "account_locked"
        else
            account.locked = false
            account.failedAttempts = 0
            account.lockoutUntil = nil
        end
    end
    
    -- Verify PIN
    if crypto.verifyPassword(pin, account.pinHash, account.pinSalt) then
        account.failedAttempts = 0
        account.lastLogin = os.epoch("utc")
        accounts.save()
        return true, nil
    else
        account.failedAttempts = account.failedAttempts + 1
        
        if account.failedAttempts >= config.server.maxLoginAttempts then
            account.locked = true
            account.lockoutUntil = os.epoch("utc") + (config.server.lockoutDuration * 1000)
        end
        
        accounts.save()
        return false, "invalid_pin"
    end
end

-- Set PIN for account
function accounts.setPIN(accountNumber, pin)
    local account = accountData[accountNumber]
    if not account then
        return false, "invalid_account"
    end
    
    if #pin ~= config.security.pinLength then
        return false, "invalid_pin_length"
    end
    
    local pinData = crypto.hashPassword(pin)
    account.pinHash = pinData.hash
    account.pinSalt = pinData.salt
    
    accounts.save()
    return true, nil
end

-- Get account by number
function accounts.get(accountNumber)
    return accountData[accountNumber]
end

-- Get account by username
function accounts.getByUsername(username)
    local accountNumber = accountIndex[username]
    if accountNumber then
        return accountData[accountNumber]
    end
    return nil
end

-- Update account balance
function accounts.updateBalance(accountNumber, amount)
    local account = accountData[accountNumber]
    if not account then
        return false, "invalid_account"
    end
    
    local newBalance = account.balance + amount
    if newBalance < 0 then
        return false, "insufficient_funds"
    end
    
    account.balance = newBalance
    accounts.save()
    
    return true, nil
end

-- Get balance
function accounts.getBalance(accountNumber)
    local account = accountData[accountNumber]
    if not account then
        return nil, "invalid_account"
    end
    
    return account.balance, nil
end

-- Delete account
function accounts.delete(accountNumber)
    local account = accountData[accountNumber]
    if not account then
        return false, "invalid_account"
    end
    
    accountIndex[account.username] = nil
    accountData[accountNumber] = nil
    
    accounts.save()
    return true, nil
end

-- List all accounts (admin function)
function accounts.list()
    local list = {}
    for accountNumber, account in pairs(accountData) do
        table.insert(list, {
            accountNumber = accountNumber,
            username = account.username,
            balance = account.balance,
            created = account.created,
            lastLogin = account.lastLogin,
            locked = account.locked
        })
    end
    return list
end

-- Lock/unlock account
function accounts.setLocked(accountNumber, locked)
    local account = accountData[accountNumber]
    if not account then
        return false, "invalid_account"
    end
    
    account.locked = locked
    if not locked then
        account.failedAttempts = 0
        account.lockoutUntil = nil
    end
    
    accounts.save()
    return true, nil
end

return accounts
