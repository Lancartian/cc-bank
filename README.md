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
- **Item catalog**: Browse and purchase items from the shop
- **Smart inventory**: Automatic organization of shop items into STORAGE chests
- **Real-time stock**: Live stock tracking across multiple STORAGE chests
- **Void chest delivery**: Purchased items delivered directly to user's void chest
- **Price management**: Admins set prices and manage catalog via management console
- **INPUT processing**: Place items in INPUT chests, process them into organized STORAGE

### 📱 Pocket Computer App
- **Mobile banking**: Access your account from any pocket computer
- **Shop browsing**: Browse shop inventory with scrollable lists
- **Instant transfers**: Send money to other users
- **Purchase items**: Buy items from the shop with instant delivery

### 🎮 Management Console
- **Admin interface**: Easy-to-use management console with SGL interface
- **Account administration**: Create accounts, adjust balances, manage users
- **Shop management**: Add items to catalog, set prices, process INPUT chests
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

The shop system allows admins to sell items to users with automatic delivery:

```
[Items placed in INPUT chest]
          ↓
[Admin processes via management console]
          ↓
[Smart organization into STORAGE chests]
          ↓
[Users browse catalog on pocket computer]
          ↓
[User purchases item]
          ↓
[Balance deducted, item delivered to void chest]
```

### For Admins: Adding Items to Shop

#### Step 1: Place Items in INPUT Chests
- Put items you want to sell into any chest labeled "INPUT"
- Multiple INPUT chests can be used
- Items stay in INPUT until processed

#### Step 2: Process INPUT Chests
1. Open management console
2. Navigate to **Shop Management**
3. Select **Process INPUT Chests**
4. Click **Process Now**

The system will:
- Scan all INPUT chests for items
- Intelligently organize items into STORAGE chests:
  * First tries to stack with existing items
  * Then fills empty slots
  * Distributes across multiple STORAGE chests
- Report how many items were processed

#### Step 3: Add Items to Catalog
1. Navigate to **Shop Management** → **Add Item**
2. Enter item details:
   - **Item Name**: Exact Minecraft ID (e.g., `minecraft:diamond`, `minecraft:iron_ingot`)
   - **Price**: How much users pay (in Credits)
   - **Category**: Organization (e.g., "Ores", "Tools", "Food")
   - **Description**: Optional description
3. Click **Add Item**

Item is now available for purchase!

#### Managing Catalog
- **List Items**: View all items in catalog
- **Edit Items**: Update prices or descriptions via SHOP_MANAGE
- **Remove Items**: Delete items from catalog (stock remains in STORAGE)

### For Users: Shopping on Pocket Computer

1. **Browse Shop**:
   - Login to pocket computer app
   - Select **Shop** from main menu
   - Scrollable list shows all items with:
     * Display name
     * Price
     * Current stock level

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

### Smart Organization Details

The system uses a two-phase organization algorithm:

**Phase 1 - Stack with existing items**:
- For each item in INPUT chests
- Search STORAGE chests for matching item stacks
- Push items to existing stacks (fills them up)
- Continue until item fully distributed or stacks full

**Phase 2 - Fill empty slots**:
- If items remain after Phase 1
- Find empty slots in STORAGE chests
- Place remaining items
- Distribute across multiple chests as needed

**Benefits**:
- Items of same type grouped together
- Efficient use of chest space
- Easy to locate specific items
- Automatic load balancing across chests

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
1. **Add Items**:
   - Place items in INPUT chests
   - Management → Shop Management → Process INPUT Chests
   - Shop Management → Add Item → Enter details

2. **View Inventory**:
   - Shop Management → List Items
   - Shows all catalog items with prices

3. **Update Prices**:
   - Re-add items with new prices to update

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
1. Verify items in STORAGE chests
2. Check items added to catalog (matching exact item ID)
3. Process INPUT chests via management console
4. Check stock levels (SHOP_BROWSE shows live stock)

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
│   ├── catalog.lua         # Shop catalog
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
    ├── catalog.json        # Shop catalog
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
