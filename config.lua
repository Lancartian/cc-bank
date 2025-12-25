-- config.lua
-- Configuration file for CC-Bank system

local config = {}

-- Server configuration
config.server = {
    -- Computer ID of the server (set this on the server computer)
    id = nil,  -- Will be set to os.getComputerID() on first run
    
    -- Network ports
    port = 42000,
    
    -- Data storage
    dataDir = "/data",
    accountsFile = "/data/accounts.json",
    transactionsFile = "/data/transactions.json",
    currencyFile = "/data/currency.json",
    
    -- Session timeout (seconds)
    sessionTimeout = 300,
    
    -- Maximum failed login attempts before lockout
    maxLoginAttempts = 3,
    lockoutDuration = 600,
    
    -- Currency storage (now uses peripheral network)
    -- Chests are identified by paper markers placed inside them:
    -- - "MINT" paper in mint chest
    -- - "OUTPUT" paper in output chest  
    -- - "1", "5", "10", "20", "50", "100" papers in denomination chests
}

-- Management console configuration
config.management = {
    -- Master password hash (change this!)
    masterPasswordHash = nil,  -- Set on first run
    masterPasswordSalt = nil,
    
    -- Network port
    port = 42002,
    
    -- Network storage configuration
    -- All chests connected via wired modem network
    -- Special chests identified by paper markers with specific names
    maxATMs = 16,  -- Maximum ATMs supported
    maxDenominations = 6,  -- Number of different bill denominations
    
    -- ATM Authorization
    authorizedATMs = {},  -- List of authorized ATM IDs with their tokens
    requireATMAuth = true,  -- Require authorization for ATM registration
}

-- ATM configuration
config.atm = {
    -- Network port
    port = 42001,
    
    -- ATM ID (unique identifier for each ATM)
    id = nil,  -- Set automatically based on computer ID
    
    -- Authorization token (obtained from management console)
    authToken = nil,  -- MUST be set by administrator
    
    -- Void chest frequency (unique for each ATM)
    frequency = nil,  -- Must be set for each ATM
    
    -- Dispense configuration
    dispenseSide = "back",  -- Side where dispensed items come out
    
    -- UI configuration
    displayName = "CC-Bank ATM",
    welcomeMessage = "Welcome to CC-Bank",
    
    -- Transaction limits
    maxWithdrawal = 10000,
    maxDeposit = 10000,
    maxTransfer = 10000,
}

-- UI Theme colors (for SGL)
config.theme = {
    primary = colors.blue,
    secondary = colors.lightBlue,
    success = colors.green,
    error = colors.red,
    warning = colors.orange,
    background = colors.black,
    foreground = colors.white,
    border = colors.gray,
}

-- Currency configuration
config.currency = {
    -- Item to use as currency
    itemName = "minecraft:written_book",  -- Signed books prevent forgery
    
    -- Display name
    displayName = "Credit",
    displayNamePlural = "Credits",
    
    -- Minting configuration
    mintAmount = 100,  -- Amount to mint per operation
    
    -- Currency verification
    requireNBT = true,  -- Require NBT tag for currency
    nbtPrefix = "CCBANK_",  -- Prefix for NBT tags
    
    -- Denomination system (different bill values)
    denominations = {
        {value = 1, name = "1 Credit", color = "white"},
        {value = 5, name = "5 Credits", color = "green"},
        {value = 10, name = "10 Credits", color = "blue"},
        {value = 20, name = "20 Credits", color = "purple"},
        {value = 50, name = "50 Credits", color = "orange"},
        {value = 100, name = "100 Credits", color = "red"}
    },
    
    -- Default denomination for withdrawals (try to use largest bills first)
    preferLargeBills = true
}

-- Security configuration
config.security = {
    -- Password requirements
    minPasswordLength = 8,
    requireComplexPassword = false,  -- Require uppercase, lowercase, numbers
    
    -- PIN requirements
    pinLength = 4,
    
    -- Account number format
    accountNumberLength = 10,
    
    -- Encryption
    encryptionEnabled = true,
    encryptionKey = nil,  -- Set automatically on first run
    
    -- Message encryption
    encryptSensitiveData = true,  -- Encrypt passwords, balances in transit
    
    -- Rate limiting
    maxRequestsPerMinute = 60,
    
    -- Network security
    requireMessageSignatures = true,
    replayProtectionWindow = 30000,  -- 30 seconds
}

-- Logging configuration
config.logging = {
    enabled = true,
    logFile = "/data/bank.log",
    logLevel = "INFO",  -- DEBUG, INFO, WARN, ERROR
    maxLogSize = 1000000,  -- 1MB
}

-- Load configuration from file
function config.load(filename)
    filename = filename or "/config.json"
    
    if fs.exists(filename) then
        local file = fs.open(filename, "r")
        if file then
            local content = file.readAll()
            file.close()
            
            local loaded = textutils.unserialiseJSON(content)
            if loaded then
                -- Merge loaded config
                for section, values in pairs(loaded) do
                    if config[section] then
                        for key, value in pairs(values) do
                            config[section][key] = value
                        end
                    end
                end
            end
        end
    end
    
    return config
end

-- Save configuration to file
function config.save(filename)
    filename = filename or "/config.json"
    
    local file = fs.open(filename, "w")
    if file then
        file.write(textutils.serialiseJSON(config))
        file.close()
        return true
    end
    
    return false
end

-- Initialize default configuration
function config.init()
    -- Set computer-specific defaults
    if not config.server.id then
        config.server.id = os.getComputerID()
    end
    
    if not config.atm.id then
        config.atm.id = os.getComputerID()
    end
    
    -- Create data directory
    if not fs.exists(config.server.dataDir) then
        fs.makeDir(config.server.dataDir)
    end
    
    return config
end

return config
