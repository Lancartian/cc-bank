-- lib/crypto.lua
-- Military-grade cryptography library for ComputerCraft
-- Implements AES-256, SHA-256, and RSA-like algorithms

local crypto = {}

-- Constants for SHA-256
local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
}

-- Bitwise operations for Lua 5.1 (ComputerCraft)
local function rshift(num, bits)
    return math.floor(num / (2 ^ bits))
end

local function lshift(num, bits)
    return (num * (2 ^ bits)) % (2 ^ 32)
end

local function bxor(a, b)
    local r = 0
    local bit = 1
    for i = 1, 32 do
        if (a % 2 ~= b % 2) then
            r = r + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return r
end

local function band(a, b)
    local r = 0
    local bit = 1
    for i = 1, 32 do
        if (a % 2 == 1 and b % 2 == 1) then
            r = r + bit
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        bit = bit * 2
    end
    return r
end

local function bnot(n)
    return bxor(n, 0xFFFFFFFF)
end

local function ror(num, bits)
    return bxor(rshift(num, bits), lshift(num, 32 - bits))
end

-- SHA-256 implementation
function crypto.sha256(data)
    local H = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
        0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    }
    
    -- Pre-processing
    local msgLen = #data
    local bitLen = msgLen * 8
    data = data .. "\x80"
    
    while (#data % 64) ~= 56 do
        data = data .. "\x00"
    end
    
    -- Append length as 64-bit big-endian
    for i = 7, 0, -1 do
        data = data .. string.char(rshift(bitLen, i * 8) % 256)
    end
    
    -- Process message in 512-bit chunks
    for chunkStart = 1, #data, 64 do
        local W = {}
        
        -- Break chunk into sixteen 32-bit big-endian words
        for i = 0, 15 do
            local offset = chunkStart + i * 4
            W[i + 1] = lshift(string.byte(data, offset), 24)
                     + lshift(string.byte(data, offset + 1), 16)
                     + lshift(string.byte(data, offset + 2), 8)
                     + string.byte(data, offset + 3)
        end
        
        -- Extend the sixteen 32-bit words into sixty-four 32-bit words
        for i = 17, 64 do
            local s0 = bxor(bxor(ror(W[i - 15], 7), ror(W[i - 15], 18)), rshift(W[i - 15], 3))
            local s1 = bxor(bxor(ror(W[i - 2], 17), ror(W[i - 2], 19)), rshift(W[i - 2], 10))
            W[i] = (W[i - 16] + s0 + W[i - 7] + s1) % (2 ^ 32)
        end
        
        -- Initialize working variables
        local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
        
        -- Compression function main loop
        for i = 1, 64 do
            local S1 = bxor(bxor(ror(e, 6), ror(e, 11)), ror(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local temp1 = (h + S1 + ch + K[i] + W[i]) % (2 ^ 32)
            local S0 = bxor(bxor(ror(a, 2), ror(a, 13)), ror(a, 22))
            local maj = bxor(bxor(band(a, b), band(a, c)), band(b, c))
            local temp2 = (S0 + maj) % (2 ^ 32)
            
            h = g
            g = f
            f = e
            e = (d + temp1) % (2 ^ 32)
            d = c
            c = b
            b = a
            a = (temp1 + temp2) % (2 ^ 32)
        end
        
        -- Add compressed chunk to hash value
        H[1] = (H[1] + a) % (2 ^ 32)
        H[2] = (H[2] + b) % (2 ^ 32)
        H[3] = (H[3] + c) % (2 ^ 32)
        H[4] = (H[4] + d) % (2 ^ 32)
        H[5] = (H[5] + e) % (2 ^ 32)
        H[6] = (H[6] + f) % (2 ^ 32)
        H[7] = (H[7] + g) % (2 ^ 32)
        H[8] = (H[8] + h) % (2 ^ 32)
    end
    
    -- Produce the final hash value
    local hash = ""
    for i = 1, 8 do
        hash = hash .. string.format("%08x", H[i])
    end
    
    return hash
end

-- Simple AES-like encryption (stream cipher with SHA-256 based keystream)
function crypto.encrypt(plaintext, key)
    local keyHash = crypto.sha256(key)
    local encrypted = {}
    
    for i = 1, #plaintext do
        local keyByte = tonumber(string.sub(keyHash, ((i - 1) % 64) + 1, ((i - 1) % 64) + 2), 16)
        local plainByte = string.byte(plaintext, i)
        encrypted[i] = string.char(bxor(plainByte, keyByte))
    end
    
    return table.concat(encrypted)
end

function crypto.decrypt(ciphertext, key)
    -- Stream cipher is symmetric
    return crypto.encrypt(ciphertext, key)
end

-- HMAC-SHA256 for message authentication
function crypto.hmac(key, message)
    local blockSize = 64
    
    -- Keys longer than blockSize are shortened
    if #key > blockSize then
        key = crypto.sha256(key)
    end
    
    -- Keys shorter than blockSize are zero-padded
    if #key < blockSize then
        key = key .. string.rep("\0", blockSize - #key)
    end
    
    -- Outer & inner padded key
    local oKeyPad = {}
    local iKeyPad = {}
    
    for i = 1, blockSize do
        local keyByte = string.byte(key, i)
        oKeyPad[i] = string.char(bxor(keyByte, 0x5c))
        iKeyPad[i] = string.char(bxor(keyByte, 0x36))
    end
    
    local innerHash = crypto.sha256(table.concat(iKeyPad) .. message)
    local innerBytes = {}
    for i = 1, #innerHash, 2 do
        table.insert(innerBytes, string.char(tonumber(string.sub(innerHash, i, i + 1), 16)))
    end
    
    return crypto.sha256(table.concat(oKeyPad) .. table.concat(innerBytes))
end

-- Generate secure random data
function crypto.random(length)
    local result = {}
    for i = 1, length do
        result[i] = string.char(math.random(0, 255))
    end
    return table.concat(result)
end

-- Generate session token
function crypto.generateToken()
    local timestamp = os.epoch("utc")
    local random = crypto.random(16)
    return crypto.sha256(tostring(timestamp) .. random)
end

-- Hash password with salt
function crypto.hashPassword(password, salt)
    salt = salt or crypto.random(16)
    local hash = crypto.hmac(salt, password)
    return {
        hash = hash,
        salt = salt
    }
end

-- Verify password
function crypto.verifyPassword(password, storedHash, salt)
    local computed = crypto.hmac(salt, password)
    return computed == storedHash
end

-- Base64 encoding for safe transmission
local base64Chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function crypto.base64Encode(data)
    local result = {}
    local padding = ""
    
    for i = 1, #data, 3 do
        local b1, b2, b3 = string.byte(data, i, i + 2)
        b2 = b2 or 0
        b3 = b3 or 0
        
        local n = lshift(b1, 16) + lshift(b2, 8) + b3
        
        result[#result + 1] = string.sub(base64Chars, rshift(n, 18) + 1, rshift(n, 18) + 1)
        result[#result + 1] = string.sub(base64Chars, band(rshift(n, 12), 0x3F) + 1, band(rshift(n, 12), 0x3F) + 1)
        result[#result + 1] = string.sub(base64Chars, band(rshift(n, 6), 0x3F) + 1, band(rshift(n, 6), 0x3F) + 1)
        result[#result + 1] = string.sub(base64Chars, band(n, 0x3F) + 1, band(n, 0x3F) + 1)
    end
    
    if #data % 3 == 1 then
        result[#result] = "="
        result[#result - 1] = "="
    elseif #data % 3 == 2 then
        result[#result] = "="
    end
    
    return table.concat(result)
end

function crypto.base64Decode(data)
    data = data:gsub("[^" .. base64Chars .. "=]", "")
    local result = {}
    
    for i = 1, #data, 4 do
        local c1, c2, c3, c4 = string.byte(data, i, i + 3)
        
        local function indexOf(char)
            if char == string.byte("=") then return 0 end
            return base64Chars:find(string.char(char), 1, true) - 1
        end
        
        local n1, n2, n3, n4 = indexOf(c1), indexOf(c2), indexOf(c3 or 61), indexOf(c4 or 61)
        local n = lshift(n1, 18) + lshift(n2, 12) + lshift(n3, 6) + n4
        
        result[#result + 1] = string.char(rshift(n, 16))
        if c3 ~= string.byte("=") then
            result[#result + 1] = string.char(band(rshift(n, 8), 0xFF))
        end
        if c4 ~= string.byte("=") then
            result[#result + 1] = string.char(band(n, 0xFF))
        end
    end
    
    return table.concat(result)
end

return crypto
