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
- **NBT-based verification**: Each currency item has a unique NBT hash for authenticity
- **Minting system**: Mint new currency with automatic database registration
- **Currency verification**: Validate currency authenticity before accepting
- **Supply tracking**: Monitor total currency supply and minted items

### 🏧 ATM Network
- **Multiple ATMs**: Support for up to 6 ATMs with unique void chest frequencies
- **Authorization Required**: Only manager-authorized ATMs can register
- **User-friendly interface**: Beautiful SGL-based touch interface
- **Complete functionality**: Withdraw, deposit, transfer, and balance checks
- **Void chest integration**: Automatic currency transfer via frequency-matched void chests

### 🎮 Management Console
- **Admin interface**: Easy-to-use management console with SGL interface
- **Account administration**: Create accounts, adjust balances, manage users
- **Currency minting**: Mint new currency with button press
- **System monitoring**: View statistics, transaction history, ATM status
- **ATM Management**: Authorize new ATMs, view registered ATMs, revoke access

## System Requirements

- **ComputerCraft: Tweaked** (or CC: Restitched)
- **Create Mod** with **Create Utilities** addon (for void chests with frequency system)
- **Wireless Modem** on all computers
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

Option B - Manual installation:
1. Download all files from this repository
2. Place files in the correct directories on each computer
3. Ensure file structure matches the layout in [File Structure](#file-structure)

## Setup Guide

### Server Setup

1. **Hardware Setup**:
   - Place a computer (advanced recommended)
   - Attach a wireless modem (any side)
   - Attach a chest for currency storage (default: bottom)
   - Set up multiple void chests for ATM dispensing (see [Void Chest Configuration](#void-chest-configuration))
   - Connect hoppers/droppers from chest to void chests with redstone control

2. **Software Setup**:
   ```lua
   cd /
   edit config.lua
   -- Configure server settings (port, data directory, etc.)
   
   -- Run server
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
   - Place a void chest and set its frequency in-game (using Create Utilities)
   - Set up currency collection mechanism (conveyor belt from void chest to customer pickup)

2. **Get Authorization**:
   ```lua
   -- On management console first:
   1. Login with master password
   2. Navigate to "ATM Management" > "Authorize ATM"
   3. Enter desired ATM ID and void chest frequency
   4. Copy the generated authorization token
   5. Provide token to ATM administrator
   ```

3. **Software Setup**:
   ```
   cd /
   edit config.lua
   
   config.atm.id = 1  -- Must match authorization
   config.atm.frequency = 1  -- For reference only - actual frequency set by items in void chest
   config.atm.authToken = "token_from_management_console"
   
   atm/main
   ```

4. **ATM Registration**:
   - ATM will register with server using authorization token
   - Unauthorized ATMs will be rejected
   - Verify registration in management console

## Void Chest Configuration

**How Create Utilities Void Chests Work**:
- Void chests with the SAME frequency can transfer items wirelessly
- Frequency is set by placing TWO ITEMS in the frequency slots of the void chest (in-game)
- The combination of these two items determines the frequency (e.g., stone + dirt, iron + gold)
- Frequencies act as "channels" for item transfer
- Right click on the bottom slot to claim the void chest in order to prevent tampering

**Server Side Setup**:
1. Place multiple void chests near the server computer
2. Set each void chest to a UNIQUE frequency by placing two items in its frequency slots
   - Example: ATM #1 = Stone + Stone, ATM #2 = Stone + Dirt, ATM #3 = Stone + Cobblestone
3. Connect each void chest to the main currency storage
4. Wire redstone from server computer to control which void chest gets chosen
5. When dispensing to ATM #1, server activates redstone to conveyor leading to ATM #1's void chest

**ATM Side Setup**:
1. Place void chest at ATM location
2. Set frequency to match the corresponding server void chest by placing the SAME TWO ITEMS in frequency slots
   - Example: If server ATM #1 void chest has Stone + Stone, ATM void chest must also have Stone + Stone
3. Items pushed into server's void chest will instantly appear in ATM's matching void chest
4. Connect void chest to conveyor belt or collection point for customer pickup

**Example Setup for 3 ATMs**:
```
SERVER:
Currency Storage Chest
    ↓ (conveyors with redstone control)
├─→ Void Chest (Freq: Stone+Stone) ←→ Wireless Transfer ←→ ATM #1 Void Chest (Stone+Stone)
├─→ Void Chest (Freq: Stone+Dirt) ←→ Wireless Transfer ←→ ATM #2 Void Chest (Stone+Dirt)
└─→ Void Chest (Freq: Stone+Cobble) ←→ Wireless Transfer ←→ ATM #3 Void Chest (Stone+Cobble)
```

**Redstone Control**:
- The server's redstone controls which hopper/dropper pushes items into which void chest
- Void chest frequencies are set in the Create Utilities GUI (NOT via redstone)
- Each ATM (1-6) uses one computer side: left, right, front, back, top, bottom
- ATM ID determines which redstone side activates
- **Maximum 6 ATMs** without additional mods (one per computer side)

## Currency Minting

### Currency Minting Process

1. **Prepare Items**:
   - Place currency in mint chest (default: bottom of server)
   - Items MUST have unique NBT data

2. **Mint Currency**:
   - Open management console
   - Login with master password
   - Navigate to "Mint Currency"
   - Enter amount to mint
   - Press "Mint Currency" button
   - System will scan chest and register all valid items with NBT tags

3. **Verification**:
   - Each item's NBT hash is recorded in currency database
   - Only registered currency is accepted by the system
   - Currency can be tracked and invalidated if needed
   - Database stored in `/data/currency.json`

4. **Distribution**:
   - Minted currency can be withdrawn from ATMs
   - Server automatically dispenses correct currency via void chests
   - Currency is verified on every transaction

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
   - Insert currency into deposit slot
   - Touch "Scan Currency"
   - Enter amount
   - Touch "Deposit"

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
   - Place items with NBT tags in mint chest
   - Navigate to "Mint Currency"
   - Enter amount to mint
   - Touch "Mint Currency"
   - Currency is registered in database

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

**currency.mint(amount, denomination)** - Mint new currency
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
   
2. **Check Redstone Control**:
   - Server redstone should activate correct hopper/dropper
   - Test manually: `redstone.setOutput("left", true)`
   - Verify wiring from computer to hoppers/droppers
   
3. **Check Currency Path**:
   - Currency storage chest → hopper → void chest (server)
   - Void chest (ATM) → conveyor belt → customer pickup
   - Ensure hoppers are pointed in correct direction
   
4. **Check Currency Supply**:
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

-- Management
config.management.redstoneStartSide = "left"  -- Redstone control side
config.management.maxATMs = 6  -- Maximum 6 ATMs (one per side)
config.management.requireATMAuth = true  -- Require ATM authorization

-- ATM
config.atm.id = 1  -- Unique ATM ID
config.atm.frequency = 1  -- Reference only - actual frequency set by items in void chest
config.atm.authToken = "..."  -- Authorization token from management

-- Security
config.security.encryptionKey = "..."  -- Auto-generated
config.security.encryptSensitiveData = true
config.security.requireMessageSignatures = true
config.security.replayProtectionWindow = 30  -- seconds

-- Currency
config.currency.itemName = "minecraft:gold_ingot"
config.currency.displayName = "Credit"
config.currency.displayNamePlural = "Credits"
config.currency.requireNBT = true
```

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
- Void chest frequencies are set in Create Utilities (not via redstone)
- Redstone controls which hopper/dropper pushes items into which void chest
- ATM authorization tokens should be kept secret and secure

---

**Happy Banking! 🏦**
