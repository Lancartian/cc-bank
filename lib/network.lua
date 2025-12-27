-- lib/network.lua
-- Secure networking protocol for bank communications

local crypto = require("/lib/crypto")

local network = {}

-- Protocol constants
network.PROTOCOL = "CCBANK_v1"
network.PORT_SERVER = 42000
network.PORT_POCKET = 42001
network.PORT_MANAGEMENT = 42002
network.PORT_SHOP = 42003

-- Message types
network.MSG = {
    -- Authentication
    AUTH_REQUEST = "AUTH_REQ",
    AUTH_RESPONSE = "AUTH_RESP",
    AUTH_CHALLENGE = "AUTH_CHAL",
    
    -- Account operations
    ACCOUNT_CREATE = "ACCT_CREATE",
    ACCOUNT_INFO = "ACCT_INFO",
    ACCOUNT_DELETE = "ACCT_DELETE",
    ACCOUNT_LIST = "ACCT_LIST",
    ACCOUNT_UNLOCK = "ACCT_UNLOCK",
    ACCOUNT_RESET_PASSWORD = "ACCT_RESET_PASS",
    
    -- Transactions
    BALANCE_CHECK = "BAL_CHECK",
    TRANSFER = "TRANSFER",
    
    -- Shop operations
    SHOP_BROWSE = "SHOP_BROWSE",
    SHOP_PURCHASE = "SHOP_PURCHASE",
    SHOP_STATUS = "SHOP_STATUS",
    SHOP_GET_CATALOG = "SHOP_GET_CAT",
    SHOP_SET_PRICE = "SHOP_SET_PRC",
    SHOP_RENAME_ITEM = "SHOP_REN_ITM",
    SHOP_RESCAN = "SHOP_RESCAN",
    
    -- System
    PING = "PING",
    PONG = "PONG",
    ERROR = "ERROR",
    SUCCESS = "SUCCESS",
    
    -- Management console
    MGMT_LOGIN = "MGMT_LOGIN",
    SHOP_MANAGE = "SHOP_MANAGE"
}

-- Open modem on specified port
function network.init(port)
    -- First try to find a wireless modem (preferred for servers/pocket computers)
    local modem = peripheral.find("modem", function(name, wrapped)
        return wrapped.isWireless and wrapped.isWireless()
    end)
    
    -- If no wireless modem, try any modem (including wired network modems)
    if not modem then
        modem = peripheral.find("modem")
    end
    
    -- If still no modem, check all peripherals on the network
    if not modem then
        local peripherals = peripheral.getNames()
        for _, name in ipairs(peripherals) do
            local p = peripheral.wrap(name)
            if p and p.isWireless then
                modem = p
                break
            end
        end
    end
    
    if not modem then
        error("No modem found")
    end
    
    if not modem.isOpen(port) then
        modem.open(port)
    end
    
    return modem
end

-- Create secure message with encryption
function network.createMessage(msgType, data, sessionToken, encryptionKey)
    local timestamp = os.epoch("utc")
    -- Make nonce more unique by including computer ID and timestamp
    local randomPart = crypto.random(8)
    local computerID = os.getComputerID()
    local nonceSource = tostring(computerID) .. tostring(timestamp) .. randomPart
    local nonce = crypto.base64Encode(crypto.sha256(nonceSource):sub(1, 16))
    
    -- Encrypt sensitive data if encryption key provided
    local processedData = data or {}
    if encryptionKey and data then
        -- Encrypt the entire data payload
        local serialized = textutils.serialiseJSON(data)
        local encrypted = crypto.encrypt(serialized, encryptionKey)
        processedData = {
            encrypted = crypto.base64Encode(encrypted),
            isEncrypted = true
        }
    end
    
    local message = {
        protocol = network.PROTOCOL,
        type = msgType,
        data = processedData,
        timestamp = timestamp,
        nonce = nonce
    }
    
    if sessionToken then
        message.token = sessionToken
        -- Sign the message with HMAC
        local signData = textutils.serialiseJSON(processedData) .. timestamp .. nonce
        message.signature = crypto.hmac(sessionToken, signData)
    end
    
    return message
end

-- Verify message signature and decrypt if needed
function network.verifyMessage(message, sessionToken, encryptionKey)
    if not message.signature or not sessionToken then
        return false, "missing_signature"
    end
    
    -- Check replay attack (message not too old)
    local now = os.epoch("utc")
    if now - message.timestamp > 30000 then  -- 30 seconds
        return false, "message_expired"
    end
    
    -- Verify signature
    local signData = textutils.serialiseJSON(message.data) .. message.timestamp .. message.nonce
    local computed = crypto.hmac(sessionToken, signData)
    if computed ~= message.signature then
        return false, "invalid_signature"
    end
    
    -- Decrypt data if encrypted
    if message.data.isEncrypted and encryptionKey then
        local decoded = crypto.base64Decode(message.data.encrypted)
        local decrypted = crypto.decrypt(decoded, encryptionKey)
        local success, data = pcall(textutils.unserialiseJSON, decrypted)
        if not success then
            return false, "decryption_failed"
        end
        return true, data
    end
    
    return true, message.data
end

-- Send message to specific computer
function network.send(modem, recipient, port, message)
    local serialized = textutils.serialiseJSON(message)
    modem.transmit(port, port, serialized)
end

-- Broadcast message
function network.broadcast(modem, port, message)
    local serialized = textutils.serialiseJSON(message)
    modem.transmit(port, port, serialized)
end

-- Receive message with timeout
function network.receive(port, timeout)
    timeout = timeout or 5
    
    local timer = os.startTimer(timeout)
    
    while true do
        local event, side, senderChannel, replyChannel, message, senderDistance = os.pullEvent()
        
        if event == "timer" and side == timer then
            return nil, "timeout"
        elseif event == "modem_message" and senderChannel == port then
            os.cancelTimer(timer)
            
            -- Parse message
            local success, parsed = pcall(textutils.unserialiseJSON, message)
            if not success or not parsed then
                return nil, "invalid_message"
            end
            
            -- Verify protocol
            if parsed.protocol ~= network.PROTOCOL then
                return nil, "invalid_protocol"
            end
            
            return parsed, senderDistance
        end
    end
end

-- Request-response pattern with timeout
function network.request(modem, recipient, port, message, timeout)
    network.send(modem, recipient, port, message)
    return network.receive(port, timeout)
end

-- Create encrypted channel between two parties
function network.createSecureChannel(sharedSecret)
    return {
        secret = sharedSecret,
        
        encrypt = function(self, data)
            local serialized = textutils.serialiseJSON(data)
            local encrypted = crypto.encrypt(serialized, self.secret)
            return crypto.base64Encode(encrypted)
        end,
        
        decrypt = function(self, data)
            local decoded = crypto.base64Decode(data)
            local decrypted = crypto.decrypt(decoded, self.secret)
            return textutils.unserialiseJSON(decrypted)
        end
    }
end

-- Error response helper
function network.errorResponse(errorCode, errorMessage)
    return network.createMessage(network.MSG.ERROR, {
        code = errorCode,
        message = errorMessage
    })
end

-- Success response helper
function network.successResponse(data)
    return network.createMessage(network.MSG.SUCCESS, data)
end

return network
