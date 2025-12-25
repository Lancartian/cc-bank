-- install.lua
-- Installer for CC-Bank system

local REPO_URL = "https://raw.githubusercontent.com/Lancartian/cc-bank/main/"
local component = nil  -- Will be set by user choice or argument

-- Check arguments
local args = {...}
if #args > 0 then
    component = args[1]
end

print("CC-Bank Installer v1.0")
print("======================")
print("")

-- Helper function to download file
local function downloadFile(url, path)
    print("Downloading: " .. path)
    local success = shell.run("wget", url, path)
    if not success then
        print("ERROR: Failed to download " .. path)
        return false
    end
    return true
end

-- Check if SGL is installed
print("Checking for CC-SGL...")
if not fs.exists("lib/sgl/sgl.lua") and not fs.exists("/lib/sgl/sgl.lua") then
    print("CC-SGL not found! Installing...")
    print("")
    
    shell.run("wget", "https://raw.githubusercontent.com/Lancartian/cc-sgl/main/installer.lua", "sgl_installer.lua")
    shell.run("sgl_installer.lua", "install")
    
    if fs.exists("sgl_installer.lua") then
        fs.delete("sgl_installer.lua")
    end
    print("")
else
    print("CC-SGL already installed.")
    print("")
end

-- Ask which component to install (if not specified as argument)
if not component or (component ~= "all" and component ~= "server" and component ~= "management" and component ~= "atm") then
    print("Which component do you want to install?")
    print("1. All components (recommended for first install)")
    print("2. Server only")
    print("3. Management Console only")
    print("4. ATM only")
    print("")
    write("Enter choice (1-4): ")
    
    local choice = tonumber(read())
    
    if choice == 1 then
        component = "all"
    elseif choice == 2 then
        component = "server"
    elseif choice == 3 then
        component = "management"
    elseif choice == 4 then
        component = "atm"
    else
        print("Invalid choice!")
        return
    end
end

print("")
print("Installing: " .. component)
print("")

-- Create directories
local dirs = {
    "/lib",
    "/server",
    "/management",
    "/atm",
    "/data"
}

for _, dir in ipairs(dirs) do
    if not fs.exists(dir) then
        fs.makeDir(dir)
        print("Created directory: " .. dir)
    end
end

print("")
print("Downloading files...")
print("")

-- Core files (always needed)
local coreFiles = {
    "config.lua",
    "startup.lua",
    "lib/crypto.lua",
    "lib/network.lua",
    "lib/logger.lua",
    "lib/utils.lua"
}

-- Component-specific files
local serverFiles = {
    "server/main.lua",
    "server/accounts.lua",
    "server/currency.lua",
    "server/transactions.lua"
}

local managementFiles = {
    "management/main.lua"
}

local atmFiles = {
    "atm/main.lua"
}

-- Download core files
print("Installing core libraries...")
for _, file in ipairs(coreFiles) do
    if not downloadFile(REPO_URL .. file, file) then
        print("Installation failed!")
        return
    end
end

-- Download component-specific files
if component == "all" or component == "server" then
    print("")
    print("Installing server component...")
    for _, file in ipairs(serverFiles) do
        if not downloadFile(REPO_URL .. file, file) then
            print("Installation failed!")
            return
        end
    end
end

if component == "all" or component == "management" then
    print("")
    print("Installing management console...")
    for _, file in ipairs(managementFiles) do
        if not downloadFile(REPO_URL .. file, file) then
            print("Installation failed!")
            return
        end
    end
end

if component == "all" or component == "atm" then
    print("")
    print("Installing ATM component...")
    for _, file in ipairs(atmFiles) do
        if not downloadFile(REPO_URL .. file, file) then
            print("Installation failed!")
            return
        end
    end
end

print("")
print("========================================")
print("Installation Complete!")
print("========================================")
print("")

-- Component-specific instructions
if component == "all" then
    print("All components installed successfully!")
    print("")
    print("Next steps:")
    print("1. Edit config.lua to configure settings")
    print("2. Attach wireless modems to all computers")
    print("3. On server: Run 'server/main'")
    print("4. On management: Run 'management/main'")
    print("5. On ATM: Configure and run 'atm/main'")
    print("")
elseif component == "server" then
    print("Server Installation Complete!")
    print("")
    print("Next steps:")
    print("1. Edit config.lua to configure server settings")
    print("2. Attach a wireless modem")
    print("3. Attach a chest for currency (default: bottom)")
    print("4. Set up void chests with unique frequencies")
    print("5. Run: server/main")
    print("")
elseif component == "management" then
    print("Management Console Installation Complete!")
    print("")
    print("Next steps:")
    print("1. Edit config.lua if needed")
    print("2. Attach a wireless modem")
    print("3. Run: management/main")
    print("4. Create master password on first run")
    print("5. Authorize ATMs and create user accounts")
    print("")
elseif component == "atm" then
    print("ATM Installation Complete!")
    print("")
    print("Next steps:")
    print("1. Get authorization token from management console")
    print("2. Edit config.lua:")
    print("   - Set config.atm.id")
    print("   - Set config.atm.frequency")
    print("   - Set config.atm.authToken")
    print("3. Attach a wireless modem")
    print("4. Set up void chest with matching frequency")
    print("5. Run: atm/main")
    print("")
end

print("For complete documentation:")
print("  https://github.com/Lancartian/cc-bank")
print("")
print("Need help? Check the troubleshooting section!")
print("")
