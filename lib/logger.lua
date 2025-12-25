-- lib/logger.lua
-- Logging system for CC-Bank

local config = require("/config")

local logger = {}

logger.LEVEL = {
    DEBUG = 1,
    INFO = 2,
    WARN = 3,
    ERROR = 4
}

local levelNames = {
    [1] = "DEBUG",
    [2] = "INFO",
    [3] = "WARN",
    [4] = "ERROR"
}

local currentLevel = logger.LEVEL.INFO

-- Set log level
function logger.setLevel(level)
    currentLevel = level
end

-- Format log message
local function formatMessage(level, message)
    local timestamp = os.date("%Y-%m-%d %H:%M:%S")
    local levelName = levelNames[level] or "UNKNOWN"
    return string.format("[%s] [%s] %s", timestamp, levelName, message)
end

-- Write to log file
local function writeToFile(message)
    if not config.logging.enabled then
        return
    end
    
    local file = fs.open(config.logging.logFile, fs.exists(config.logging.logFile) and "a" or "w")
    if file then
        file.writeLine(message)
        file.close()
        
        -- Check log size and rotate if needed
        if fs.getSize(config.logging.logFile) > config.logging.maxLogSize then
            local backup = config.logging.logFile .. ".old"
            if fs.exists(backup) then
                fs.delete(backup)
            end
            fs.move(config.logging.logFile, backup)
        end
    end
end

-- Log function
local function log(level, message)
    if level < currentLevel then
        return
    end
    
    local formatted = formatMessage(level, message)
    
    -- Print to console
    print(formatted)
    
    -- Write to file
    writeToFile(formatted)
end

-- Convenience functions
function logger.debug(message)
    log(logger.LEVEL.DEBUG, message)
end

function logger.info(message)
    log(logger.LEVEL.INFO, message)
end

function logger.warn(message)
    log(logger.LEVEL.WARN, message)
end

function logger.error(message)
    log(logger.LEVEL.ERROR, message)
end

return logger
