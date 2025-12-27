# CC-Bank - Digital Banking System for ComputerCraft

A modern, fully digital banking system for ComputerCraft with secure encryption, shop management, and void chest delivery.

## Table of Contents
- [Features](#features)
- [System Requirements](#system-requirements)
- [Installation](#installation)
- [Setup Guide](#setup-guide)
- [Shop System](#shop-system)
- [Usage](#usage)
- [Security](#security)
- [Troubleshooting](#troubleshooting)
- [File Structure](#file-structure)

## Features

### 🔐 Security
- **Military-grade encryption**: SHA-256 hashing, AES-like stream cipher, HMAC authentication
- **Secure sessions**: Token-based authentication with automatic expiration
- **Account protection**: Failed login lockout, password hashing with salt
- **Network security**: Encrypted message passing with signature verification
- **Replay Attack Prevention**: Nonce tracking prevents message replay attacks

### 💰 Banking Features
- **Digital accounts**: Create and manage user accounts with unique account numbers
- **Fully digital**: No physical currency - all transactions are account-based
- **Transfers**: Instant money transfers between accounts
- **Balance tracking**: Real-time balance updates and transaction history
- **Transaction logging**: Complete audit trail of all transactions

### 🛒 Shop System
- **Auto-scanning catalog**: Items automatically detected from STORAGE chests - no manual entry!
- **Simple setup**: Place items in STORAGE chests, rescan, set prices - items appear in shop
- **Live stock tracking**: Real-time inventory levels from physical chest contents
- **Void chest delivery**: Purchased items delivered directly to user's void chest
- **Easy price management**: Simple interface to set prices for detected items
- **Multiple STORAGE chests**: System scans all chests labeled "STORAGE" automatically

### 📱 Pocket Computer App
- **Mobile banking**: Access your account from any pocket computer
- **Shop browsing**: Browse shop inventory with scrollable lists
- **Instant transfers**: Send money to other users
- **Purchase items**: Buy items from the shop with instant delivery

### 🎮 Management Console
- **Admin interface**: Easy-to-use management console with SGL interface
- **Account administration**: Create accounts, adjust balances, manage users, unlock locked accounts
- **Auto-scanning shop**: View catalog, set prices, rescan STORAGE chests
- **Simple workflow**: No manual catalog entry - items auto-detected from chests
- **System monitoring**: View statistics, transaction history, account status

## System Requirements

- **ComputerCraft: Tweaked** (or CC: Restitched)
- **Create Mod** with **Create Utilities** addon (for void chests)
- **Wired Modems** and **Networking Cables** to connect chests to server
- **Wireless Modems** on server, management console, and pocket computers
- **Monitor** (optional, recommended for management console)

## Installation

### 1. Install CC-SGL Graphics Library

On each computer (server, management, pocket), run:

```
wget https://raw.githubusercontent.com/Lancartian/cc-sgl/main/installer.lua
installer install
```

### 2. Download CC-Bank

Using wget (recommended):
```
wget run https://raw.githubusercontent.com/Lancartian/cc-bank/main/install.lua
```

The installer will:
- Check for and install CC-SGL if needed
- Ask which component to install (all, server, management, or pocket)
- Create necessary directories
- Download all required files
- Provide setup instructions

## Setup Guide

### Server Setup

1. **Hardware Setup**:
   - Place an advanced computer
   - Attach a wireless modem (for network communication)
   - Attach a wired modem (for peripheral network)
   - Connect chests via networking cables and wired modems:
     * **STORAGE chests** - Multiple chests labeled "STORAGE" (place renamed paper inside)
     * **INPUT chests** - Multiple chests labeled "INPUT" (place renamed paper inside)
     * **User void chests** - One per user, labeled with username (place renamed paper inside)
   - **Important**: Do NOT directly attach chests to computer - use wired modem network

2. **Chest Labeling**:
   - Use anvil to rename paper
   - Place renamed paper in first slot of each chest:
     * "STORAGE" - for shop inventory
     * "INPUT" - for items waiting to be processed
     * "[username]" - for user delivery (e.g., "Steve", "Alex")
   - Server automatically detects and categorizes chests

3. **Void Chest Frequencies** (Create Utilities):
   - Each user void chest needs a unique frequency
   - Set frequency by placing two items in the void chest's frequency slots
   - Example: Steve = Stone + Stone, Alex = Stone + Dirt
   - Users set matching frequency on their personal void chest at home
   - Items delivered to server void chest appear instantly in user's void chest

4. **Software Setup**:
   ```
   cd /
   edit config.lua  # Configure ports and settings
   server/main
   ```

5. **First Run**:
   - Server creates /data directory automatically
   - Generates encryption key
   - Scans peripheral network for chests
   - Starts listening on port 42000 (default)

### Management Console Setup

1. **Hardware Setup**:
   - Place an advanced computer
   - Attach a wireless modem
   - Attach a monitor (optional but recommended)

2. **Software Setup**:
   ```
   cd /
   edit config.lua  # If needed
   management/main
   ```

3. **First Run**:
   - Create master password (SAVE THIS!)
   - Password required for all management operations

4. **Admin Functions**:
   - Create user accounts
   - Manage shop catalog (add items, set prices)
   - Process INPUT chests to organize items into STORAGE
   - View system statistics

### Pocket Computer Setup

1. **Hardware Setup**:
   - Craft a pocket computer
   - Attach a wireless modem

2. **Software Setup**:
   ```
   cd /
   pocket/main
   ```

3. **User Functions**:
   - Login with account credentials
   - Check balance
   - Transfer money to other users
   - Browse shop and purchase items
   - Items delivered to your void chest automatically

### User Void Chest Setup

Each user needs a personal void chest at their base:

1. **Place Void Chest**:
   - Place a Create Utilities void chest at your home/base
   - Right-click bottom slot to claim it (prevents tampering)

2. **Set Frequency**:
   - Contact admin to get your assigned frequency
   - Place the same two items in your void chest's frequency slots
   - Example: If admin says "Stone + Stone", place stone in both slots
   - Your void chest now links to server void chest

3. **Test Delivery**:
   - Purchase item from shop on pocket computer
   - Item should appear instantly in your void chest
   - Set up collection system (conveyor, hopper, etc.)

## Shop System

### Overview

The shop system automatically detects items in STORAGE chests and makes them available for purchase. No manual catalog entry needed!

**Simple workflow:**
```
[Place items in STORAGE chest with "STORAGE" paper marker]
          ↓
[Rescan STORAGE chests via management console]
          ↓
[Set prices for items you want to sell]
          ↓
[Items with prices appear in shop automatically]
          ↓
[Users purchase items on pocket computer]
          ↓
[Balance deducted, items delivered to void chest]
```

### For Admins: Setting Up Shop Items

#### Step 1: Label STORAGE Chests
1. Use anvil to rename paper to "STORAGE"
2. Place renamed paper in first slot of chest
3. Connect chest to server via wired modem + networking cable
4. Multiple STORAGE chests supported - system scans them all

#### Step 2: Add Items to Sell
- Simply place items in any STORAGE chest
- Items stay there until purchased
- Add more stock anytime by adding items to chests

#### Step 3: Rescan STORAGE Chests
1. Open management console
2. Navigate to **Shop Management**
3. Select **Rescan STORAGE Chests**
4. Click **Rescan Now**

The system will:
- Scan all STORAGE chests automatically
- Detect all items and quantities
- Get display names from Minecraft
- Update the catalog cache
- Report total items and stock found

#### Step 4: Set Prices
1. Navigate to **Shop Management** → **Set Item Prices**
2. Enter item details:
   - **Item Name**: Exact Minecraft ID (e.g., `minecraft:diamond`, `minecraft:iron_ingot`)
     - Tip: Check "View Shop Catalog" to see exact item names detected
   - **Price**: How much users pay (in Credits)
3. Click **Set Price**

**Important**: Only items with price > 0 appear in the shop!

#### Managing the Shop
- **View Shop Catalog**: See all items in STORAGE chests with prices and stock
- **Set Item Prices**: Update prices anytime
- **Rescan STORAGE Chests**: Refresh catalog when you add/remove items
- **Stock levels update automatically** - based on what's physically in chests

### Auto-Scanning Details

The system works like the CC-STR storage system you might be familiar with:

**Automatic Detection**:
- Scans all chests with "STORAGE" marker paper
- Detects every item type and counts quantity
- Gets proper display names from Minecraft
- Groups items by type across multiple chests
- Caches results for fast performance

**Benefits**:
- **No manual entry** - just put items in chests
- **Always accurate** - stock reflects physical inventory
- **Simple to use** - rescan whenever you restock
- **Multiple chests** - distributes load, organized however you want
- **Real-time pricing** - change prices without rescanning

### For Users: Shopping on Pocket Computer

1. **Browse Shop**:
   - Login to pocket computer app
   - Select **Shop** from main menu
   - Scrollable list shows all items with:
     * Display name
     * Price
     * Current stock level
   - Only items with prices appear in the shop

2. **Purchase Item**:
   - Tap item to view details
   - Enter quantity
   - Click **Buy**
   - System checks:
     * Your balance (sufficient funds?)
     * Stock availability (enough items?)
   - If successful:
     * Funds deducted from account
     * Items transferred from STORAGE to your void chest
     * Transaction logged
     * Confirmation displayed

3. **Collect Items**:
   - Items appear instantly in your void chest at home
   - Pick them up from your collection system

## Usage

### For Bank Users (Pocket Computer)

#### Login
1. Run `pocket/main`
2. Enter username and password
3. Click **Login**

#### Check Balance
- Main menu shows current balance

#### Transfer Money
1. Select **Transfer**
2. Enter recipient username
3. Enter amount
4. Click **Send**
5. Confirmation displayed

#### Shop
1. Select **Shop**
2. Browse items (scroll through list)
3. Tap item to view details
4. Enter quantity
5. Click **Buy**
6. Items delivered to your void chest

### For Admins (Management Console)

#### Create Account
1. Login with master password
2. Select **Manage Accounts** → **Create Account**
3. Enter:
   - Username
   - Password
   - Initial balance (optional)
4. Click **Create**

#### Manage Shop
1. **Add Items to Sell**:
   - Place items in any STORAGE chest
   - Shop Management → Rescan STORAGE Chests
   - Shop Management → Set Item Prices → Enter item name and price

2. **View Catalog**:
   - Shop Management → View Shop Catalog
   - Shows all detected items with prices and stock

3. **Update Prices**:
   - Shop Management → Set Item Prices
   - Enter item name and new price

#### View Statistics
- Main Menu → View Statistics
- Shows:
  * Total accounts
  * Total balance in system
  * Locked accounts

## Security

### Account Security
- **Password Hashing**: SHA-256 with salt, never stored in plaintext
- **Session Tokens**: Temporary authentication, auto-expire
- **Failed Login Protection**: Account locks after multiple failed attempts
- **Admin Separation**: Management password separate from user accounts

### Network Security
- **Encrypted Messages**: All network traffic encrypted
- **Message Authentication**: HMAC verification prevents tampering
- **Replay Protection**: Nonce system prevents message replay
- **Session Validation**: Every request validated against active session

### Physical Security
- **Void Chest Claiming**: Users claim void chests to prevent tampering
- **Peripheral Network**: Backend chests only accessible via peripheral network
- **No Direct Access**: Chests not directly attached to computers

### Best Practices
1. **Use strong passwords** for all accounts
2. **Claim your void chest** by right-clicking bottom slot
3. **Keep management password secure** - cannot be recovered
4. **Monitor transaction logs** for suspicious activity
5. **Isolate server computer** in secure location

## Troubleshooting

### Server Won't Start
- Check wireless modem attached
- Check wired modem attached
- Verify networking cables connect chests
- Check config.lua syntax

### Chests Not Detected
- Ensure paper markers in chests (first slot)
- Paper must be renamed in anvil
- Chests must connect via wired modem network
- Run server again to rescan

### Shop Items Not Appearing
1. Verify items physically in STORAGE chests
2. Rescan STORAGE chests via management console
3. Check that prices are set (price must be > 0)
4. View Shop Catalog to see detected item names
5. Ensure item name matches exactly (e.g., `minecraft:diamond`)

### Void Chest Delivery Not Working
- Verify void chest frequency matches server
- Check user void chest labeled with correct username
- Ensure both void chests claimed
- Test with known working frequency combination

### Pocket Computer Can't Connect
- Check wireless modem attached
- Verify server running
- Check port configuration (default 42001)
- Test network range (modems have limited range)

### Balance Not Updating
- Check transaction logs on server
- Verify account not locked
- Check server console for errors
- Ensure session still valid (re-login)

## File Structure

```
cc-bank/
├── config.lua              # System configuration
├── startup.lua             # Auto-start script
├── install.lua             # Installer script
├── README.md               # This file
│
├── lib/                    # Shared libraries
│   ├── crypto.lua          # Encryption and hashing
│   ├── network.lua         # Network protocol
│   ├── logger.lua          # Logging utilities
│   └── utils.lua           # Helper functions
│
├── server/                 # Server component
│   ├── main.lua            # Server main loop
│   ├── accounts.lua        # Account management
│   ├── catalog.lua         # Manual shop catalog (legacy)
│   ├── shop_catalog.lua    # Auto-scanning shop catalog
│   ├── transactions.lua    # Transaction logging
│   └── network_storage.lua # Peripheral storage management
│
├── management/             # Management console
│   └── main.lua            # Management interface
│
├── pocket/                 # Pocket computer app
│   └── main.lua            # Pocket app interface
│
└── data/                   # Runtime data (auto-created)
    ├── accounts.json       # Account database
    ├── transactions.json   # Transaction history
    ├── catalog.json        # Manual catalog (legacy)
    ├── shop_catalog_cache.dat # Auto-scanned catalog cache
    ├── config.json         # Saved configuration
    └── sessions.json       # Active sessions
```

## Credits

- **CC-SGL**: Graphics library by Lancartian
- **ComputerCraft**: Original Minecraft mod by dan200 (Daniel Ratcliffe)
- **ComputerCraft: Tweaked**: Continuation/fork by SquidDev
- **Create**: Minecraft mod by simibubi
- **Create Utilities**: Addon by possible_triangle

## License

MIT License - See LICENSE file for details

## Version History

### v2.1 - Auto-Scanning Shop System
- **Auto-scanning catalog**: Items automatically detected from STORAGE chests
- **Inspired by CC-STR**: Simple workflow like popular storage systems
- **No manual entry**: Just place items, rescan, set prices
- **Cache system**: Fast performance with automatic caching
- **Easy price management**: Simple interface to set prices for detected items
- **Account unlocking**: Management console can unlock locked accounts

### v2.0 - Digital Banking Release
- Complete redesign: Digital-only banking (no physical currency)
- New shop system with INPUT/STORAGE chest processing
- Smart item organization algorithm
- Pocket computer app for mobile banking
- Void chest delivery system
- Catalog management for shop items
- Removed ATM network (replaced with pocket computers)
- Enhanced security for digital transactions

### v1.0 - Initial Release
- Physical currency system with signed books
- ATM network support
- Management console for administration
