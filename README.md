# CC-Bank - Advanced Banking System for ComputerCraft

A comprehensive, secure banking system for ComputerCraft with military-grade encryption, physical currency management, and ATM network support.

## Table of Contents
- [Features](#features)
- [System Requirements](#system-requirements)
- [Installation](#installation)
- [Setup Guide](#setup-guide)
- [Void Chest Configuration](#void-chest-configuration)
- [Currency Minting](#currency-minting)
- [Usage](#usage)
- [API Reference](#api-reference)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [File Structure](#file-structure)
- [License](#license)

## Features

### 🔐 Security
- **Military-grade encryption**: SHA-256 hashing, AES-like stream cipher, HMAC authentication
- **Secure sessions**: Token-based authentication with automatic expiration
- **Account protection**: Failed login lockout, password hashing with salt
- **Network security**: Encrypted message passing with signature verification
- **ATM Authorization**: Only manager-approved ATMs can register
- **Replay Attack Prevention**: Nonce tracking prevents message replay attacks

### 💰 Banking Features
- **Account management**: Create and manage user accounts with unique account numbers
- **Transactions**: Deposits, withdrawals, transfers with full transaction logging
- **Balance tracking**: Real-time balance updates and history
- **PIN support**: Optional PIN codes for ATM access

### 🏦 Physical Currency System
- **Signed Book Currency**: Uses signed books (written_book) to prevent forgery - signatures cannot be faked
- **NBT-based verification**: Each currency item has a unique NBT hash for authenticity
- **Denomination system**: Support for different bill values (1, 5, 10, 20, 50, 100 Credits)
- **Smart dispensing**: Automatically selects appropriate bills for withdrawals
- **Minting system**: Worker creates, writes, and signs books to mint new currency
- **Currency verification**: Validate currency authenticity before accepting using NBT hash
- **Supply tracking**: Monitor total currency supply and minted items by denomination
- **Peripheral network**: All inventory management via wired modem network using inventory API

### 🏧 ATM Network
- **Multiple ATMs**: Support for up to 16 ATMs with unique IDs
- **Secure Two-Network Architecture**: ATM network isolated from backend network for security
- **Authorization Required**: Only manager-authorized ATMs can register
- **User-friendly interface**: Beautiful SGL-based touch interface
- **Complete functionality**: Withdraw, deposit, transfer, and balance checks
- **Smart deposit system**: ATM scans books locally, backend processes via auxiliary chest
- **Void chest integration**: Backend pushes to void chests, Create Utilities handles delivery

### 🎮 Management Console
- **Admin interface**: Easy-to-use management console with SGL interface
- **Account administration**: Create accounts, adjust balances, manage users
- **Automatic currency minting**: Name signed books with denomination, system reads and sorts them automatically
- **System monitoring**: View statistics, transaction history, ATM status
- **ATM Management**: Authorize new ATMs, view registered ATMs, revoke access

## System Requirements

- **ComputerCraft: Tweaked** (or CC: Restitched)
- **Create Mod** with **Create Utilities** addon (for void chests with frequency system)
- **Wired Modems** and **Networking Cables** to connect all chests to the server
- **Wireless Modem** on server, management console, and ATMs for communication
- **Monitor** (optional, recommended for better display)

## Installation

### 1. Install CC-SGL Graphics Library

On each computer (server, management, ATM), run:

```
wget https://raw.githubusercontent.com/Lancartian/cc-sgl/main/installer.lua
installer install
```

### 2. Download CC-Bank

Option A - Using wget (recommended):
```
wget run https://raw.githubusercontent.com/Lancartian/cc-bank/main/install.lua
```

The installer will:
- Check for and install CC-SGL if needed
- Ask which component to install (all, server, management, or ATM)
- Create necessary directories
- Download all required files
- Provide setup instructions

Option B - Manual installation:
1. Download all files from this repository
2. Place files in the correct directories on each computer
3. Ensure file structure matches the layout in [File Structure](#file-structure)

## Setup Guide

### Server Setup

1. **Hardware Setup**:
   - Place a computer (advanced recommended)
   - Attach a wireless modem (for network communication with ATMs/management)
   - Attach a wired modem (for peripheral network - inventory management)
   - Connect chests to the peripheral network using networking cables and wired modems:
     * 1 MINT chest (place paper named "MINT" inside)
     * 1 OUTPUT chest (place paper named "OUTPUT" inside)
     * 1 AUXILIARY chest (place paper named "AUXILIARY" inside) - receives deposited books
     * 6+ denomination chests (place papers named "1", "5", "10", "20", "50", "100" inside)
       - You can have **multiple chests for the same denomination** for more storage
       - Example: 3 chests with "100" papers for $100 bills
     * 16 void chests for ATMs (name peripherals as "atm1", "atm2", etc. or "void_1", "void_2", etc.)
   - **Important**: Do NOT directly attach chests to the computer - only via wired modem network
   - Set void chest frequencies by placing two items in each void chest's frequency slots
   - AUXILIARY chest receives books from deposit void chests (separate from ATM void chests)

2. **Software Setup**:
   ```
   cd /
   edit config.lua
   
   server/main
   ```

3. **First Run**:
   - Server will create /data directory automatically
   - Generate encryption key automatically
   - Load initial configuration
   - Start listening on port 42000 (default)

### Management Console Setup

1. **Hardware Setup**:
   - Place a computer (advanced recommended for touch)
   - Attach a wireless modem
   - Attach a monitor (optional but recommended)

2. **Software Setup**:
   ```
   cd /
   edit config.lua
   
   management/main
   ```

3. **First Run**:
   - Create master password (SAVE THIS - cannot be recovered!)
   - This password is required for all management operations

### ATM Setup

1. **Hardware Setup**:
   - Place a computer (advanced recommended for touch)
   - Attach a wireless modem
   - Place a void chest at ATM location
   - Set void chest frequency in-game by placing two items in the frequency slots
   - Set up currency collection (conveyor belt from void chest to customer pickup)
   - Right-click bottom slot to claim the void chest (prevents tampering)

2. **Get Authorization** (on management console):
   - Login with master password
   - Navigate to "ATM Management" > "Authorize ATM"
   - Enter desired ATM ID (1-16)
   - Copy the generated authorization token (shown on screen and in terminal)

3. **First Run** (on ATM):
   ```
   cd /
   atm/main
   ```
   - ATM will detect no configuration and run setup wizard
   - Enter the ATM ID (must match authorization)
   - Paste the authorization token
   - Configuration saves automatically
   - ATM starts and registers with server

4. **Server Void Chest Setup for Withdrawals**:
   - On server's peripheral network, set the corresponding ATM void chest to SAME frequency as ATM
   - Example: If ATM #1 withdrawal void chest has Stone + Stone, server's ATM #1 void chest must also have Stone + Stone
   - Items pushed to server void chest will instantly appear in ATM void chest for withdrawal

5. **Server Deposit System Setup**:
   - Set up a **separate deposit void chest** at each ATM location (not the withdrawal void chest)
   - This deposit void chest transports books to the server's AUXILIARY chest
   - On server side, connect the AUXILIARY chest to the backend network with a wired modem
   - Place paper marker named "AUXILIARY" in the AUXILIARY chest
   - Set AUXILIARY chest's associated deposit void chest to match ATM's deposit void chest frequency
   - **Security**: ATM network and backend network remain completely isolated
   - Books flow: ATM scan chest → user moves to deposit void chest → AUXILIARY chest → backend processes

## Void Chest Configuration

### Peripheral Network Setup

**All inventory management is handled via the peripheral network using wired modems and networking cables. This provides:**
- Direct item transfer using `pushItems()` and `pullItems()` from CC:Tweaked's inventory API
- No redstone required for routing
- Automatic chest detection and registration
- Clean, deterministic item transfers

**Network Architecture**:
```
                    [Server Computer]
                          │
                    [Wired Modem]
                          │
              ┌───────────┴───────────┐
              │   Networking Cables   │
              │                       │
    ┌─────────┼────────┬───────┬──────┼─────┬─────┐
    │         │        │       │      │     │     │
[Wired    [Wired   [Wired [Wired [Wired [Wired [Wired
 Modem]    Modem]   Modem] Modem] Modem] Modem] Modem]
    │         │        │       │      │     │     │
[MINT]    [OUTPUT]  [$1]    [$5]  [$10] [Void] [Void]
[Chest]   [Chest]  [Chest] [Chest][Chest][Chest][Chest]
                                            │      │
                                          ATM #1 ATM #2
```

**Important Rules**:
1. **Never attach chests directly to the computer** - always use wired modem + networking cable
2. **Chest identification**: Place renamed paper inside chests to identify their purpose
3. **Void chest naming**: Name void chest peripherals with ATM ID (e.g., "atm1", "void_2")

### Chest Registration with Paper Markers

The system automatically scans the peripheral network and identifies chests by paper items placed inside them:

**Special Chest Markers**:
- **MINT chest**: Place a paper renamed to "MINT" inside
- **OUTPUT chest**: Place a paper renamed to "OUTPUT" inside
- **AUXILIARY chest**: Place a paper renamed to "AUXILIARY" inside (receives deposited books from void chests)
- **Denomination chests**: Place papers with the denomination number in the name
  * The system extracts numbers from the display name and matches against valid denominations (1, 5, 10, 20, 50, 100)
  * Examples that work:
    - "1" → $1 chest
    - "5 dollar bills" → $5 chest
    - "my 10 note chest" → $10 chest
    - "$20" → $20 chest
    - "50credits" → $50 chest
    - "100 Credit Bills" → $100 chest
  * Any paper containing a valid denomination number will work - other text is ignored
- **ATM void chests**: Place papers with "ATM" followed by the ATM number
  * The system searches for "ATM" followed by a number (1-16) in the display name
  * Examples that work:
    - "ATM1" → ATM #1 void chest
    - "ATM 5" → ATM #5 void chest
    - "atm_10" → ATM #10 void chest
    - "This is ATM 3 chest" → ATM #3 void chest
  * Each ATM (1-16) needs its own void chest with a unique marker

**How to create marker papers**:
1. Place paper in anvil
2. Rename it to include the marker:
   - "MINT", "OUTPUT", or "AUXILIARY" for special chests
   - Any denomination number (1, 5, 10, 20, 50, 100) for denomination chests
   - "ATM" + number (1-16) for void chests
3. Place the renamed paper in the chest
4. The system will automatically detect it during network scan
5. Flexible naming - the system searches for the required numbers/keywords and ignores other text

### How Create Utilities Void Chests Work
- Void chests with the SAME frequency can transfer items wirelessly
- Frequency is set by placing TWO ITEMS in the frequency slots of the void chest (in-game)
- The combination of these two items determines the frequency (e.g., stone + dirt, iron + gold)
- Frequencies act as "channels" for item transfer
- Right click on the bottom slot to claim the void chest in order to prevent tampering

**Server Side Setup**:
1. Connect 16 void chests to the peripheral network with wired modems
2. Place a paper marker in each void chest with its ATM number:
   - ATM #1 void chest: paper renamed "ATM1" or "ATM 1"
   - ATM #2 void chest: paper renamed "ATM2" or "ATM 2"
   - ... up to ATM #16
3. Set each void chest to a UNIQUE frequency by placing two items in its frequency slots
   - Example: ATM #1 = Stone + Stone, ATM #2 = Stone + Dirt, ATM #3 = Stone + Cobblestone
4. Backend will automatically detect and use the correct void chest based on the paper marker
5. Backend pushes items directly to the correct void chest using `pushItems()`

**ATM Side Setup**:
1. Place void chest at ATM location
2. Set frequency to match the corresponding server void chest by placing the SAME TWO ITEMS
   - Example: If server ATM #1 void chest has Stone + Stone, ATM void chest must also have Stone + Stone
3. Items pushed into server's void chest will instantly appear in ATM's matching void chest
4. Connect void chest to collection point for customer pickup

**Example Setup for 3 ATMs**:
```
SERVER PERIPHERAL NETWORK:
[MINT Chest] [OUTPUT Chest] [$1 Chest] [$5 Chest] ... [Void atm1] [Void atm2] [Void atm3]
     │             │              │          │              │           │           │
     └─────────────┴──────────────┴──────────┴──────────────┴───────────┴───────────┘
                                    │
                            [Wired Modem Network]
                                    │
                            [Server Computer]

BACKEND PROCESS:
1. User withdraws $125 at ATM #1
2. Backend calculates: 1×$100 + 1×$20 + 1×$5
3. Backend pulls $100 bill from [$100 Chest] → [OUTPUT Chest]
4. Backend pulls $20 bill from [$20 Chest] → [OUTPUT Chest]
5. Backend pulls $5 bill from [$5 Chest] → [OUTPUT Chest]
6. Backend pushes all bills from [OUTPUT Chest] → [Void atm1]
7. Void chest frequency matching → Items appear in ATM #1's void chest
8. Customer collects bills from ATM #1

VOID CHEST FREQUENCIES:
Server [Void atm1] (Stone+Stone) ←→ Wireless ←→ ATM #1 [Void Chest] (Stone+Stone)
Server [Void atm2] (Stone+Dirt)  ←→ Wireless ←→ ATM #2 [Void Chest] (Stone+Dirt)
Server [Void atm3] (Stone+Cobble)←→ Wireless ←→ ATM #3 [Void Chest] (Stone+Cobble)
```

### How Inventory API Ensures Correct Amounts

The system uses ComputerCraft's peripheral inventory API for deterministic item transfers:

**Key Functions Used**:
- `peripheral.wrap(name)` - Access chest as peripheral
- `chest.list()` - Get all items in chest
- `chest.getItemDetail(slot)` - Get NBT hash and item details
- `chest.pushItems(targetName, slot, count)` - Transfer specific items to target chest

**Why This is Better Than Redstone**:
1. **Direct control**: No timing issues or mechanical failures
2. **Exact counts**: Transfer exactly N items, no more, no less
3. **NBT awareness**: Can verify each bill's NBT hash before transfer
4. **Deterministic**: pushItems() returns exact number of items moved
5. **Network-based**: All chests accessible via single peripheral network

**Transfer Process**:
```lua
-- Step 1: Calculate bills needed
amount = 125
bills_needed = {1×$100, 1×$20, 1×$5}

-- Step 2: Pull from denomination chests to OUTPUT chest
$100_chest.pushItems("OUTPUT_chest", slot, 1)  -- Returns 1 (success)
$20_chest.pushItems("OUTPUT_chest", slot, 1)   -- Returns 1 (success)
$5_chest.pushItems("OUTPUT_chest", slot, 1)    -- Returns 1 (success)

-- Step 3: Push from OUTPUT chest to ATM void chest
OUTPUT_chest.pushItems("void_atm1", slot, 3)  -- Returns 3 (all bills moved)

-- Step 4: Void chest frequency matching handles wireless transfer
```

**Verification**:
- Each `pushItems()` call returns the actual number of items transferred
- Backend can verify transfer success before proceeding
- If any transfer fails, withdrawal is rolled back
- Transaction log records exact bills dispensed with their NBT hashes

## Currency Minting

### How Currency Works

CC-Bank uses **signed books (written_book)** as currency for built-in forgery prevention:

1. **Creation Process**:
   - A worker creates a new book and quill
   - Writes content into the book (bank name, denomination, serial number, etc.)
   - **Signs the book** - this is the critical security step
   - Signing adds the author's signature to the NBT data
   - This signature **cannot be forged** without the original author account

2. **NBT Hash Verification**:
   - ComputerCraft's `getItemDetail()` API returns an `nbt` field
   - This field is already a **hash string** representing the item's NBT data
   - For signed books, this includes the author signature, making each book unique
   - The backend stores this hash in the currency database
   - Only bills with registered NBT hashes are accepted as valid currency

3. **Why Signed Books?**:
   - Unsigned books/paper can be copied by anyone
   - Signed books require the original author to sign (cannot be duplicated)
   - Each signed book has a unique NBT hash
   - Perfect for unforgeable physical currency in Minecraft

### Currency Minting Process

1. **Prepare Signed Books**:
   - Have a worker (player) create books and sign them
   - **IMPORTANT: Read each book after signing it** - the NBT hash changes after the first read
   - Books that haven't been read will not match their hash during scanning
   - **Name each book with its denomination value** (e.g., "1 Token", "5 Credits", "100 Notes")
   - The system extracts the first number from the book's display name
   - Examples: "5 Credits", "10 Dollar Bill", "100", "my 50 note" all work
   - Place all signed books in the server's MINT chest (connected via wired modem)

2. **Mint Currency**:
   - Open management console
   - Login with master password
   - Navigate to "Mint Currency"
   - Press "Process Mint Chest" button
   - System automatically:
     * Scans all books in the MINT chest
     * Parses denomination from each book's display name
     * Registers each book's NBT hash in the currency database
     * Sorts books into appropriate denomination chests
     * Reports total amount minted and number of books processed

3. **Verification**:
   - Each signed book's NBT hash is recorded in currency database
   - Only registered currency is accepted by the system
   - Currency can be tracked and invalidated if needed
   - Database stored in `/data/currency.json`

4. **Distribution**:
   - Minted currency can be withdrawn from ATMs
   - Backend automatically:
     * Selects appropriate denominations for the withdrawal amount
     * Transfers bills from denomination chests to OUTPUT chest
     * Pushes items to ATM void chest via peripheral network
     * Items transfer wirelessly via Create Utilities void chest frequency matching
   - Currency is verified on every transaction using NBT hash

### Secure Two-Network Deposit System

The deposit system uses a sophisticated two-network architecture to maintain backend security:

**Architecture**:
1. **ATM Network** (front-facing, potentially compromised):
   - Scan chest directly attached to ATM computer
   - ATM reads NBT data from books locally
   - Deposit void chest for user to manually transfer books
   
2. **Backend Network** (secure, isolated):
   - AUXILIARY chest receives books from deposit void chests
   - All denomination storage chests
   - Server computer with wired modem network

**Deposit Flow**:
1. User places signed books in ATM's scan chest
2. User clicks "Scan Currency" → ATM reads NBT locally without network access
3. ATM sends NBT data to server for validation
4. Server validates each book hash against currency registry
5. Server stores hash→username mappings in deposit registry
6. User manually moves books from scan chest to deposit void chest
7. Books transport wirelessly to backend's AUXILIARY chest
8. **Auxiliary chest processor** (runs in parallel with server):
   - Scans AUXILIARY chest every 5 seconds
   - For each book: computes hash → looks up owner → credits account → moves to denomination storage
   - Handles multiple users depositing simultaneously
   - Books can arrive in any order
9. User clicks "Check Status" to verify deposit completion

**Security Benefits**:
- Backend network never connects to ATM network
- ATM cannot access backend chests or manipulate storage
- Hash registry prevents double-spending (same book can't be registered twice)
- Ownership-agnostic currency (any valid bill works, regardless of who deposited it originally)
- Backend location remains secret and secure

**Technical Implementation**:
- Server runs two processes in parallel using `parallel.waitForAny()`
- Main server loop handles network messages
- Auxiliary chest processor handles physical book arrival
- Deposit registry stored in memory: `depositRegistry[nbtHash] = {username, value, denomination, processed}`
- Books marked as processed when moved to storage, then credit applied on next status check

## Usage

### For Bank Users (ATM)

1. **Login**:
   - Touch "Touch to Begin"
   - Enter username and password
   - Touch "Login"

2. **Check Balance**:
   - Select "Check Balance" from main menu
   - View current balance and account number

3. **Withdraw**:
   - Select "Withdraw"
   - Enter amount
   - Touch "Withdraw"
   - Collect currency from void chest dispensing area
   - Wait for currency to appear (transferred via void chest frequency)

4. **Deposit**:
   - Select "Deposit"
   - Place signed books in the **scan chest** (directly attached to ATM computer)
   - Touch "Scan Currency" - ATM reads NBT from books locally
   - Server validates and registers books to your account
   - **Manually move books** from scan chest to the **deposit void chest**
   - Touch "Check Status" to verify books arrived and were processed
   - Account automatically credited when backend receives and processes books

5. **Transfer**:
   - Select "Transfer"
   - Enter recipient account number
   - Enter amount
   - Touch "Transfer"
   - Confirmation displayed

6. **Logout**:
   - Touch "Logout" to end session securely
   - Sessions automatically expire after 5 minutes

### For Administrators (Management Console)

1. **First Time Setup**:
   - Create master password (SAVE THIS - cannot be recovered!)
   - Login with master password

2. **Authorize ATM**:
   - Navigate to "ATM Management" > "Authorize ATM"
   - Enter ATM ID and void chest frequency
   - Copy the generated authorization token
   - Provide token to ATM administrator
   - ATM must use this token to register with server

3. **Create Account**:
   - Navigate to "Manage Accounts" > "Create Account"
   - Enter username, password, initial balance
   - Touch "Create Account"
   - 10-digit account number generated automatically

4. **Mint Currency**:
   - Have workers create and sign books with denomination in the name (e.g., "5 Credits")
   - Place signed books in the MINT chest (connected to server)
   - Navigate to "Mint Currency"
   - Touch "Process Mint Chest"
   - System reads book names, registers NBT hashes, and sorts to denomination chests automatically

5. **View Statistics**:
   - Navigate to "View Statistics"
   - See total accounts, transactions, currency supply
   - Monitor system health

6. **Manage ATMs**:
   - Navigate to "ATM Management"
   - View all authorized ATMs with frequencies
   - Revoke ATM access if needed

## API Reference

### Cryptography API (`lib/crypto.lua`)

**crypto.sha256(data)** - Calculate SHA-256 hash
```lua
local hash = crypto.sha256("Hello, World!")
-- Returns: 64-character hex string
```

**crypto.encrypt(plaintext, key)** - Encrypt data with AES-like stream cipher
```lua
local ciphertext = crypto.encrypt("secret", "encryption_key")
```

**crypto.decrypt(ciphertext, key)** - Decrypt data
```lua
local plaintext = crypto.decrypt(ciphertext, "encryption_key")
```

**crypto.hmac(key, message)** - Calculate HMAC-SHA256 signature
```lua
local signature = crypto.hmac(sessionToken, messageData)
```

**crypto.hashPassword(password, salt)** - Hash password with salt
```lua
local data = crypto.hashPassword("mypassword")
-- Returns: {hash = "...", salt = "..."}
```

**crypto.verifyPassword(password, storedHash, salt)** - Verify password
```lua
local valid = crypto.verifyPassword(enteredPassword, storedHash, salt)
-- Returns: true/false
```

**crypto.generateToken()** - Generate cryptographically secure session token
```lua
local token = crypto.generateToken()
-- Returns: 64-character hex string
```

**crypto.base64Encode(data)** - Base64 encode string
**crypto.base64Decode(data)** - Base64 decode string

### Network API (`lib/network.lua`)

**network.createMessage(msgType, data, sessionToken, encryptionKey)** - Create secure message
```lua
local msg = network.createMessage(network.MSG.AUTH_REQUEST, {
    username = "alice",
    password = "secret"
}, nil, encryptionKey)
-- Message includes: protocol, type, data, timestamp, nonce, signature
```

**network.verifyMessage(message, sessionToken, encryptionKey)** - Verify and decrypt message
```lua
local valid, decryptedData = network.verifyMessage(msg, token, key)
-- Validates signature, checks nonce, decrypts data
```

**network.send(modem, recipient, port, message)** - Send message to specific computer
```lua
network.send(modem, 5, 42000, message)
```

**network.broadcast(modem, port, message)** - Broadcast message to all computers
```lua
network.broadcast(modem, 42000, message)
```

**network.receive(port, timeout)** - Receive message with timeout
```lua
local message, distance = network.receive(42000, 5)
```

**network.successResponse(data)** - Create success response
**network.errorResponse(errorCode, errorMessage)** - Create error response

### Message Types

- `AUTH_REQUEST` - User login
- `AUTH_RESPONSE` - Login response with session token
- `BALANCE_CHECK` - Check account balance
- `WITHDRAW` - Withdraw funds
- `DEPOSIT` - Deposit funds
- `TRANSFER` - Transfer between accounts
- `CURRENCY_MINT` - Mint new currency
- `CURRENCY_VERIFY` - Verify currency authenticity
- `ATM_REGISTER` - Register ATM (requires authorization token)
- `ATM_STATUS` - ATM heartbeat ping

### Accounts API (`server/accounts.lua`)

**accounts.create(username, password, initialBalance)** - Create new account
```lua
local account = accounts.create("alice", "password123", 1000)
-- Returns: {accountNumber, username, balance, ...}
```

**accounts.authenticate(username, password)** - Authenticate user
```lua
local account, error = accounts.authenticate("alice", "password123")
```

**accounts.get(accountNumber)** - Get account by account number
```lua
local account = accounts.get("1234567890")
```

**accounts.getByUsername(username)** - Get account by username

**accounts.getBalance(accountNumber)** - Get account balance
```lua
local balance = accounts.getBalance("1234567890")
```

**accounts.updateBalance(accountNumber, amount)** - Update balance (positive or negative)
```lua
accounts.updateBalance("1234567890", -100)  -- Deduct 100
accounts.updateBalance("1234567890", 50)    -- Add 50
```

**accounts.setPIN(accountNumber, pin)** - Set ATM PIN code
**accounts.verifyPIN(accountNumber, pin)** - Verify PIN code
**accounts.list()** - Get list of all accounts
**accounts.save()** - Save accounts to disk
**accounts.load()** - Load accounts from disk

### Currency API (`server/currency.lua`)

**currency.mintAndSort()** - Automatically mint and sort currency from MINT chest
```lua
local result, err = currency.mintAndSort()
-- Returns: {totalAmount, processedCount, mintedByDenom, sortResults}
-- Reads book names, registers NBT hashes, sorts to denomination chests
```

**currency.mint(amount, denomination)** - Legacy manual minting (kept for compatibility)
```lua
currency.mint(100, 1)  -- Mint 100 credits
```

**currency.verify(nbtHash)** - Verify currency authenticity
```lua
local valid = currency.verify("abc123...")
-- Returns: true if currency is registered
```

**currency.verifyContainer(containerSide)** - Verify all currency in a container
```lua
local valid, total = currency.verifyContainer("bottom")
```

**currency.getTotalSupply()** - Get total currency supply
```lua
local supply = currency.getTotalSupply()
-- Returns: {totalValue, totalItems, denominations}
```

**currency.invalidate(nbtHash)** - Invalidate/remove currency from registry
**currency.prepareDispense(amount)** - Prepare currency for ATM dispensing

### Transactions API (`server/transactions.lua`)

**transactions.log(txType, fromAccount, toAccount, amount, metadata)** - Log transaction
```lua
transactions.log("WITHDRAW", "1234567890", nil, 100, {atmID = 1})
```

**transactions.get(txID)** - Get transaction by ID
```lua
local tx = transactions.get("TXN1234567890")
```

**transactions.getForAccount(accountNumber, limit)** - Get transactions for account
```lua
local txList = transactions.getForAccount("1234567890", 10)
-- Returns: Last 10 transactions for account
```

**transactions.getRecent(limit)** - Get recent transactions system-wide
```lua
local txList = transactions.getRecent(50)
```

**transactions.getStats()** - Get transaction statistics
```lua
local stats = transactions.getStats()
-- Returns: {totalTransactions, totalVolume, ...}
```

## Security

### 🔒 Security Features

1. **ATM Authorization System**
   - Only authorized ATMs can register with server
   - Each ATM requires unique authorization token generated by management console
   - Tokens are cryptographically secure (64-char hex)
   - Prevents rogue ATMs from intercepting transactions or dispensing unauthorized currency

2. **Full Message Encryption**
   - All sensitive data encrypted end-to-end
   - Passwords and credentials never transmitted in plaintext
   - AES-like stream cipher with SHA-256 based keys
   - Unique encryption key per server instance

3. **HMAC Message Authentication**
   - Every message cryptographically signed with HMAC-SHA256
   - Signature includes session token and message data
   - Detects any tampering attempts
   - Prevents man-in-the-middle attacks

4. **Replay Attack Prevention**
   - Unique nonce (number used once) per message
   - Messages older than 30 seconds automatically rejected
   - Server tracks all nonces in memory
   - Duplicate nonces immediately detected and rejected

5. **Password Security**
   - Salted SHA-256 password hashing
   - Passwords never stored in plaintext
   - Account lockout after 3 failed login attempts
   - 10-minute lockout duration with automatic unlock

6. **Session Management**
   - Session tokens expire after 5 minutes of inactivity
   - Tokens are cryptographically secure
   - Automatic logout on timeout
   - Sessions validated on every request

7. **Currency Verification**
   - NBT-based currency registry
   - Each currency item has unique hash
   - Only minted currency accepted
   - Anti-counterfeiting protection

8. **Data Encryption at Rest**
   - Sensitive configuration encrypted
   - Master password hashed with salt
   - Database access controlled

### Attack Vectors & Mitigations

| Attack | Protection | How It Works |
|--------|-----------|--------------|
| Password Interception | End-to-end encryption | Credentials encrypted with AES-like cipher before transmission |
| Man-in-the-Middle | HMAC signatures | Every message signed, tampering detected immediately |
| Replay Attacks | Nonce + timestamp | Duplicate messages rejected, 30-second validity window |
| Rogue ATMs | Authorization tokens | Only manager-authorized ATMs can register and dispense |
| Brute Force | Account lockout | 3 failed attempts = 10 minute lockout period |
| Session Hijacking | Token expiration | Sessions timeout after 5 minutes inactivity |
| Counterfeiting | NBT registry | Only currency with registered NBT hash accepted |
| Database Theft | Salted hashing | Passwords cannot be recovered even if database stolen |
| Network Sniffing | Message encryption | All sensitive data encrypted end-to-end |
| Unauthorized Access | Master password | Management console requires master password |

### Security Architecture

```
Layer 7: User Interface (input validation, session timeouts)
Layer 6: Application Logic (transaction limits, business rules)
Layer 5: Session Management (token generation, validation, expiration)
Layer 4: Authentication (password verification, ATM authorization)
Layer 3: Message Security (HMAC signatures, encryption, nonce tracking)
Layer 2: Network Protocol (message validation, error handling)
Layer 1: Physical Currency (NBT verification, supply tracking)
```

### Security Best Practices

**For Administrators:**
- Use a strong master password (minimum 8 characters, mix of letters/numbers/symbols)
- Store master password securely offline (write it down, don't lose it!)
- Only authorize trusted ATMs from secure locations
- Keep authorization tokens secret - treat them like passwords
- Perform daily backups of /data directory
- Monitor logs regularly for suspicious activity (`data/bank.log`)
- Review failed login attempts
- Conduct regular ATM authorization audits
- Revoke ATM access immediately if compromised
- Keep server computer in secure, protected area

**For Users:**
- Use strong, unique passwords for each account
- Always logout after completing ATM transactions
- Don't share your password or account number
- Verify ATM ID before entering credentials
- Report suspicious ATM behavior to administrators
- Check transaction history regularly

**For Server Operators:**
- Keep ComputerCraft and Create mods updated
- Protect server computer from unauthorized physical access
- Use chunk loaders to keep server online
- Monitor server performance and logs
- Implement access controls for server area
- Regular backups with off-site storage

### Compliance Standards

This system implements security controls aligned with:
- **PCI DSS** concepts (password protection, encryption, access control)
- **Defense in Depth** strategy (multiple security layers)
- **Principle of Least Privilege** (ATM authorization, session tokens)
- **Zero Trust** model (verify every request, assume breach)

## Troubleshooting

### Server Not Responding
- Check if modem is attached and enabled
- Verify server is running (`ps` command or check computer display)
- Check network port configuration matches (default: 42000)
- Review logs: `edit data/bank.log`
- Restart server: `Ctrl+R` or `reboot`

### ATM Can't Register
- **"not_authorized" error**: ATM not authorized by management console
  - Solution: Get authorization token from management console first
  - Set `config.atm.authToken` in config.lua
  - Ensure ATM ID and frequency match authorization
- **"No response"**: Server not running or network issue
  - Check server is online and running
  - Verify modem attached to both server and ATM
  - Test network: `ping <server-computer-id>`
- **"Invalid token"**: Authorization token incorrect
  - Copy token exactly from management console
  - Check for typos or extra spaces

### Currency Not Dispensing
1. **Check Void Chest Frequencies**:
   - Server void chest and ATM void chest must have EXACT SAME two items in frequency slots
   - Open void chest GUI and verify the two items in frequency slots match exactly
   - Both items must be identical (e.g., both have Stone + Dirt, not Stone + Cobblestone)
   
2. **Check Peripheral Network**:
   - Verify all chests are connected via wired modems and networking cables
   - Check that denomination chests are detected: view server startup output
   - Ensure OUTPUT chest and void chests are properly registered with marker papers
   
3. **Check Currency Supply**:
   - Ensure minted currency in server storage chest
   - Verify currency registered: check management console statistics
   - View currency database: `edit data/currency.json`

### Login Failed
- **"invalid_credentials"**: Wrong username or password
  - Double-check spelling and case sensitivity
  - Verify account exists in management console
  - Try resetting password via management console
- **"account_locked"**: Too many failed login attempts
  - Wait 10 minutes for automatic unlock
  - Admin can unlock via management console
- **"session_expired"**: Previous session timed out
  - Login again (this is normal after 5 minutes inactivity)

### Currency Not Accepted
1. Items must have NBT tags (rename in anvil or use custom items with NBT)
2. Currency must be minted through management console first
3. Check currency registry: `edit data/currency.json`
4. Verify NBT hash matches database entry
5. Ensure currency hasn't been invalidated

### Unauthorized ATM Detected
- Server log shows: "Unauthorized ATM registration attempt"
- Solution: Authorize ATM through management console first
- Each ATM needs unique authorization token
- Verify ATM is using correct token in config.lua

### Performance Issues
- Too many nonces in memory: Server automatically cleans old nonces
- Database file corruption: Restore from backup in /data directory
- Network congestion: Reduce ATM ping frequency in config
- Memory issues: Restart computer periodically

### Data Loss / Corruption
1. Stop all systems immediately
2. Check `/data` directory for JSON files
3. Restore from most recent backup
4. If no backup: Manually edit JSON files (valid JSON format required)
5. Restart server after restoring data

## File Structure

```
cc-bank/
├── README.md                  # This file - Complete documentation
├── LICENSE                    # MIT License
├── config.lua                 # Configuration file (edit this!)
├── install.lua                # Installation script
├── startup.lua                # Auto-start script
├── server/
│   ├── main.lua              # Server backend with message handlers
│   ├── accounts.lua          # Account management (create, auth, balance)
│   ├── currency.lua          # Currency management (mint, verify, track)
│   └── transactions.lua      # Transaction logging and history
├── management/
│   └── main.lua              # Management console with SGL interface
├── atm/
│   └── main.lua              # ATM client with SGL interface
├── lib/
│   ├── crypto.lua            # Cryptography library (SHA-256, HMAC, AES)
│   ├── network.lua           # Network protocol (messages, encryption)
│   ├── logger.lua            # Logging system with levels
│   └── utils.lua             # Utility functions (formatting, validation)
└── data/                     # Created automatically on first run
    ├── accounts.json         # Account database
    ├── currency.json         # Currency database (NBT hashes)
    ├── transactions.json     # Transaction log
    └── bank.log             # System log file
```

## Configuration

Key configuration options in `config.lua`:

```lua
-- Server
config.server.port = 42000  -- Network port
config.server.sessionTimeout = 300  -- 5 minutes
config.management.maxLoginAttempts = 3

-- Management & Peripheral Network
config.management.maxATMs = 16  -- Maximum 16 ATMs supported
config.management.maxDenominations = 6  -- Number of denomination chests
config.management.requireATMAuth = true  -- Require ATM authorization

-- ATM
config.atm.id = 1  -- Unique ATM ID (1-16)
config.atm.frequency = 1  -- Reference only - actual frequency set by placing two items in void chest GUI
config.atm.authToken = "..."  -- Authorization token from management console (required)

-- Currency
config.currency.itemName = "minecraft:written_book"  -- Signed books prevent forgery
config.currency.preferLargeBills = true  -- Use largest bills first when dispensing
config.currency.denominations = {  -- Bill values: 1, 5, 10, 20, 50, 100
    {value = 1, name = "1 Credit", color = "white"},
    {value = 5, name = "5 Credits", color = "green"},
    {value = 10, name = "10 Credits", color = "blue"},
    {value = 20, name = "20 Credits", color = "purple"},
    {value = 50, name = "50 Credits", color = "orange"},
    {value = 100, name = "100 Credits", color = "red"}
}

-- Security
config.security.encryptionKey = "..."  -- Auto-generated on first run
config.security.encryptSensitiveData = true  -- Encrypt passwords/balances in transit
config.security.requireMessageSignatures = true  -- HMAC signature verification
config.security.replayProtectionWindow = 30  -- Reject messages older than 30 seconds
```

### How the Peripheral Network System Works

The backend controls all currency movement using **ComputerCraft's peripheral network and inventory API**:

**Network Setup**:
1. All chests connected to server via wired modems and networking cables
2. Chests identified by paper markers placed inside them
3. No direct chest attachments to computer (only via network)
4. Void chests named with ATM IDs (e.g., "atm1", "void_2")

**Dispensing Process**:
  Signal 2 → $10 bills chest
  Signal 3 → $20 bills chest
  Signal 4 → $50 bills chest
  Signal 5 → $100 bills chest
  ```
- Backend automatically calculates which bills are needed for the withdrawal amount
- Activates each denomination chest sequentially to dispense the correct bills

**2. Output Side (ATM Selection)**:
- Controls which ATM void chest to send the currency to
- Signal strength 0-15 selects one of 16 ATM void chests:
  ```
**Dispensing Process**:
1. User requests $125 withdrawal at ATM #3
2. Backend calculates bills needed: 1×$100 + 1×$20 + 1×$5
3. Backend uses `pushItems()` to transfer:
   - Pull 1×$100 from [$100 Chest] → [OUTPUT Chest]
   - Pull 1×$20 from [$20 Chest] → [OUTPUT Chest]
   - Pull 1×$5 from [$5 Chest] → [OUTPUT Chest]
4. Backend transfers from [OUTPUT Chest] → [Void atm3]
5. Void chest frequency matching → Bills appear at ATM #3
6. Customer collects bills

**Key Functions**:
- `peripheral.getNames()` - Scan for all peripherals on network
- `peripheral.wrap(name)` - Access chest as peripheral
- `chest.list()` - List all items
- `chest.getItemDetail(slot)` - Get NBT hash
- `chest.pushItems(target, slot, count)` - Transfer exact count of items

**Benefits**:
- No redstone timing issues
- Exact item counts guaranteed
- NBT verification on every transfer
- Deterministic and traceable
- Network-based architecture scales easily

## Contributing

Contributions are welcome! Please ensure:
- Code follows existing style and conventions
- Security features are maintained and enhanced
- Documentation is updated for any changes
- Testing is performed before submitting

## License

MIT License - See LICENSE file for details.

This software is provided "as is" without warranty of any kind. Use at your own risk.

## Credits

- **CC-SGL**: Graphics library by Lancartian - https://github.com/Lancartian/cc-sgl
- **ComputerCraft**: By dan200 - https://www.computercraft.info/
- **Create Mod**: By simibubi - https://github.com/Creators-of-Create/Create
- **Create Utilities**: Void chest functionality

## Support

For issues, questions, or suggestions:
- Open an issue on GitHub
- Check existing documentation sections above
- Review troubleshooting section
- Check logs in `/data/bank.log`

## Notes

- **This is a virtual banking system for Minecraft**
- Physical currency is represented by in-game items with NBT tags
- Always backup your `/data` directory regularly!
- Keep your master password safe - it cannot be recovered if lost
- Void chest frequencies are set in Create Utilities GUI (place two items in frequency slots)
- ATM authorization tokens should be kept secret and secure

---

**Happy Banking! 🏦**
