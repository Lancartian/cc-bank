-- lib/network.lua
-- Secure networking protocol for bank communications

local crypto = require("/lib/crypto")

local network = {}

-- Protocol constants
network.PROTOCOL = "CCBANK_v1"
network.PORT_SERVER = 42000
network.PORT_ATM = 42001
network.PORT_MANAGEMENT = 42002

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
    
    -- Transactions
    BALANCE_CHECK = "BAL_CHECK",
    WITHDRAW = "WITHDRAW",
    DEPOSIT = "DEPOSIT",
    TRANSFER = "TRANSFER",
    
    -- Currency
    CURRENCY_MINT = "CURR_MINT",
    CURRENCY_VERIFY = "CURR_VERIFY",
    CURRENCY_DISPENSE = "CURR_DISPENSE",
    
    -- System
    PING = "PING",
    PONG = "PONG",
    ERROR = "ERROR",
    SUCCESS = "SUCCESS",
    
    -- ATM specific
    ATM_REGISTER = "ATM_REG",
    ATM_STATUS = "ATM_STATUS",
    
    -- Management console
    MGMT_LOGIN = "MGMT_LOGIN",
    ATM_AUTHORIZE = "ATM_AUTHORIZE"
}

-- Open modem on specified port
function network.init(port)
    local modem = peripheral.find("modem")
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
    local nonce = crypto.base64Encode(crypto.random(8))
    
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
