-- server/transactions.lua
-- Transaction management and logging

local config = require("/config")

local transactions = {}

-- Transaction log
local transactionLog = {}
local transactionCounter = 0

-- Load transactions
function transactions.load()
    if fs.exists(config.server.transactionsFile) then
        local file = fs.open(config.server.transactionsFile, "r")
        if file then
            local content = file.readAll()
            file.close()
            
            local data = textutils.unserialiseJSON(content)
            if data then
                transactionLog = data.log or {}
                transactionCounter = data.counter or 0
            end
            return true
        end
    end
    return false
end

-- Save transactions
function transactions.save()
    local file = fs.open(config.server.transactionsFile, "w")
    if file then
        file.write(textutils.serialiseJSON({
            log = transactionLog,
            counter = transactionCounter
        }))
        file.close()
        return true
    end
    return false
end

-- Generate transaction ID
local function generateTransactionID()
    transactionCounter = transactionCounter + 1
    return string.format("TXN%010d", transactionCounter)
end

-- Log transaction
function transactions.log(txType, fromAccount, toAccount, amount, metadata)
    local txID = generateTransactionID()
    
    local transaction = {
        id = txID,
        type = txType,
        from = fromAccount,
        to = toAccount,
        amount = amount,
        timestamp = os.epoch("utc"),
        metadata = metadata or {},
        status = "completed"
    }
    
    table.insert(transactionLog, transaction)
    transactions.save()
    
    return txID
end

-- Get transaction by ID
function transactions.get(txID)
    for _, tx in ipairs(transactionLog) do
        if tx.id == txID then
            return tx
        end
    end
    return nil
end

-- Get transactions for account
function transactions.getForAccount(accountNumber, limit)
    limit = limit or 50
    
    local accountTxs = {}
    
    -- Iterate backwards for most recent first
    for i = #transactionLog, 1, -1 do
        local tx = transactionLog[i]
        
        if tx.from == accountNumber or tx.to == accountNumber then
            table.insert(accountTxs, tx)
            
            if #accountTxs >= limit then
                break
            end
        end
    end
    
    return accountTxs
end

-- Get recent transactions
function transactions.getRecent(limit)
    limit = limit or 100
    
    local recent = {}
    local startIdx = math.max(1, #transactionLog - limit + 1)
    
    for i = startIdx, #transactionLog do
        table.insert(recent, transactionLog[i])
    end
    
    return recent
end

-- Transaction types
transactions.TYPE = {
    DEPOSIT = "deposit",
    WITHDRAWAL = "withdrawal",
    TRANSFER = "transfer",
    ADMIN_ADJUSTMENT = "admin_adjustment",
    CURRENCY_MINT = "currency_mint",
    FEE = "fee"
}

-- Create specific transaction types
function transactions.deposit(accountNumber, amount, atmID)
    return transactions.log(
        transactions.TYPE.DEPOSIT,
        nil,
        accountNumber,
        amount,
        { atmID = atmID }
    )
end

function transactions.withdrawal(accountNumber, amount, atmID)
    return transactions.log(
        transactions.TYPE.WITHDRAWAL,
        accountNumber,
        nil,
        amount,
        { atmID = atmID }
    )
end

function transactions.transfer(fromAccount, toAccount, amount)
    return transactions.log(
        transactions.TYPE.TRANSFER,
        fromAccount,
        toAccount,
        amount
    )
end

function transactions.adminAdjustment(accountNumber, amount, reason, adminID)
    return transactions.log(
        transactions.TYPE.ADMIN_ADJUSTMENT,
        nil,
        accountNumber,
        amount,
        { reason = reason, adminID = adminID }
    )
end

function transactions.currencyMint(amount, adminID)
    return transactions.log(
        transactions.TYPE.CURRENCY_MINT,
        nil,
        nil,
        amount,
        { adminID = adminID }
    )
end

-- Get statistics
function transactions.getStats()
    local stats = {
        totalTransactions = #transactionLog,
        totalDeposits = 0,
        totalWithdrawals = 0,
        totalTransfers = 0,
        totalVolume = 0
    }
    
    for _, tx in ipairs(transactionLog) do
        stats.totalVolume = stats.totalVolume + tx.amount
        
        if tx.type == transactions.TYPE.DEPOSIT then
            stats.totalDeposits = stats.totalDeposits + 1
        elseif tx.type == transactions.TYPE.WITHDRAWAL then
            stats.totalWithdrawals = stats.totalWithdrawals + 1
        elseif tx.type == transactions.TYPE.TRANSFER then
            stats.totalTransfers = stats.totalTransfers + 1
        end
    end
    
    return stats
end

return transactions
