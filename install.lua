-- install.lua
-- Installer for CC-Bank digital banking system

local REPO_URL = "https://raw.githubusercontent.com/Lancartian/cc-bank/main/"
local component = nil  -- Will be set by user choice or argument
local isUpdate = false  -- Track if this is an update or fresh install

-- Check arguments
local args = {...}
if #args > 0 then
    component = args[1]
end

-- Check if this is an existing installation
local function checkExistingInstall()
    local hasConfig = fs.exists("config.lua") or fs.exists("/config.lua")
    local hasServer = fs.exists("server/main.lua") or fs.exists("/server/main.lua")
    local hasManagement = fs.exists("management/main.lua") or fs.exists("/management/main.lua")
    local hasPocket = fs.exists("pocket/main.lua") or fs.exists("/pocket/main.lua")
    
    return hasConfig or hasServer or hasManagement or hasPocket
end

print("CC-Bank Digital Banking Installer v2.0")
print("=======================================")
print("")

-- Check if updating existing installation
if checkExistingInstall() then
    print("Existing installation detected!")
    print("")
    print("Would you like to:")
    print("1. Update existing installation (preserves data)")
    print("2. Fresh install (WARNING: will overwrite files)")
    print("3. Cancel")
    print("")
    write("Enter choice (1-3): ")
    
    local updateChoice = tonumber(read())
    print("")
    
    if updateChoice == 1 then
        isUpdate = true
        print("Update mode: Your data files will be preserved.")
        print("")
    elseif updateChoice == 2 then
        isUpdate = false
        print("Fresh install mode: Files will be overwritten.")
        print("")
    else
        print("Installation cancelled.")
        return
    end
end

-- Helper function to download file
local function downloadFile(url, path)
    print("Downloading: " .. path)
    print("  From: " .. url)
    
    -- Always delete existing file first
    if fs.exists(path) then
        print("  Deleting old file...")
        fs.delete(path)
    end
    
    print("  Running wget...")
    local success = shell.run("wget", url, path)
    
    if not success then
        print("ERROR: wget command failed!")
        return false
    end
    
    -- Check if file was actually created
    if not fs.exists(path) then
        print("ERROR: File was not created: " .. path)
        return false
    end
    
    print("  Success!")
    return true
end

-- Helper function to backup data directory
local function backupData()
    if not fs.exists("/data") then
        return true
    end
    
    print("Backing up data directory...")
    
    if fs.exists("/data.backup") then
        fs.delete("/data.backup")
    end
    
    -- Create backup directory
    fs.makeDir("/data.backup")
    
    -- Copy all data files
    local dataFiles = fs.list("/data")
    for _, file in ipairs(dataFiles) do
        local srcPath = "/data/" .. file
        local dstPath = "/data.backup/" .. file
        
        if fs.isDir(srcPath) then
            -- Skip subdirectories for now
        else
            fs.copy(srcPath, dstPath)
            print("  Backed up: " .. file)
        end
    end
    
    print("Data backup complete!")
    print("")
    return true
end

-- Helper function to restore data directory
local function restoreData()
    if not fs.exists("/data.backup") then
        return true
    end
    
    print("Restoring data files...")
    
    -- Restore all backed up files
    local backupFiles = fs.list("/data.backup")
    for _, file in ipairs(backupFiles) do
        local srcPath = "/data.backup/" .. file
        local dstPath = "/data/" .. file
        
        if not fs.isDir(srcPath) then
            if fs.exists(dstPath) then
                fs.delete(dstPath)
            end
            fs.copy(srcPath, dstPath)
            print("  Restored: " .. file)
        end
    end
    
    -- Clean up backup
    fs.delete("/data.backup")
    
    print("Data restored!")
    print("")
    return true
end

print("CC-Bank Digital Banking Installer v2.0")
print("=======================================")
print("")

-- Check if updating existing installation
if component == nil then
    print("Which component do you want to install?")
    print("1. All components (recommended for first install)")
    print("2. Server only")
    print("3. Management Console only")
    print("4. Pocket Computer App only")
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
        component = "pocket"
    else
        print("Invalid choice!")
        return
    end
elseif component ~= "all" and component ~= "server" and component ~= "management" and component ~= "pocket" then
    -- Invalid argument provided
    print("ERROR: Invalid component '" .. component .. "'")
    print("Valid options: all, server, management, pocket")
    return
end

print("")
print("Installing: " .. component)
print("")

-- Clean up old files for fresh install
if not isUpdate then
    print("Fresh install: Cleaning up old files...")
    
    -- Remove all program directories
    local cleanupDirs = {"/lib", "/server", "/management", "/pocket"}
    for _, dir in ipairs(cleanupDirs) do
        if fs.exists(dir) then
            print("  Removing: " .. dir)
            fs.delete(dir)
        end
    end
    
    -- Remove root files
    local cleanupFiles = {"config.lua", "startup.lua"}
    for _, file in ipairs(cleanupFiles) do
        if fs.exists(file) then
            print("  Removing: " .. file)
            fs.delete(file)
        end
    end
    
    print("Cleanup complete!")
    print("")
end

-- Backup data directory if updating
if isUpdate then
    if not backupData() then
        print("ERROR: Failed to backup data!")
        return
    end
end

-- Create directories
local dirs = {
    "/lib",
    "/server",
    "/management",
    "/pocket",
    "/data"
}

for _, dir in ipairs(dirs) do
    if not fs.exists(dir) then
        fs.makeDir(dir)
        print("Created directory: " .. dir)
    end
end

print("")

-- Install SGL (after cleanup and directory creation)
print("Checking for CC-SGL...")
local sglPath = "/lib/sgl/sgl.lua"
if not fs.exists(sglPath) then
    print("CC-SGL not found! Installing...")
    print("")
    
    -- Download SGL installer
    if fs.exists("sgl_installer.lua") then
        fs.delete("sgl_installer.lua")
    end
    
    print("Downloading SGL installer...")
    local success = shell.run("wget", "https://raw.githubusercontent.com/Lancartian/cc-sgl/main/installer.lua", "sgl_installer.lua")
    
    if not success or not fs.exists("sgl_installer.lua") then
        print("ERROR: Failed to download SGL installer!")
        print("Please install CC-SGL manually first:")
        print("  pastebin run wHDNcd6j")
        return
    end
    
    print("Running SGL installer...")
    shell.run("sgl_installer.lua")
    
    -- Clean up installer
    if fs.exists("sgl_installer.lua") then
        fs.delete("sgl_installer.lua")
    end
    
    -- Verify SGL was installed
    if not fs.exists(sglPath) then
        print("ERROR: SGL installation failed!")
        print("Please install CC-SGL manually:")
        print("  pastebin run wHDNcd6j")
        return
    end
    
    print("SGL installed successfully!")
    print("")
else
    print("CC-SGL already installed.")
    print("")
end

print("Downloading files...")
print("")

-- Core files (always needed)
local coreFiles = {
    "startup.lua",
    "lib/crypto.lua",
    "lib/network.lua",
    "lib/logger.lua",
    "lib/utils.lua"
}

-- Config file (only download on fresh install, not updates)
local configFile = "config.lua"

-- Component-specific files
local serverFiles = {
    "server/main.lua",
    "server/accounts.lua",
    "server/catalog.lua",
    "server/transactions.lua",
    "server/network_storage.lua"
}

local managementFiles = {
    "management/main.lua"
}

local pocketFiles = {
    "pocket/main.lua"
}

-- Download config file (only on fresh install)
print("DEBUG: isUpdate = " .. tostring(isUpdate))
if not isUpdate then
    print("Installing configuration file...")
    if not downloadFile(REPO_URL .. configFile, configFile) then
        print("Installation failed!")
        return
    end
else
    print("Skipping config.lua (preserving your settings)")
    print("")
end

-- Download core files
print("DEBUG: Core files count = " .. #coreFiles)
print("Installing core libraries...")
for _, file in ipairs(coreFiles) do
    print("DEBUG: Processing core file: " .. file)
    if not downloadFile(REPO_URL .. file, file) then
        print("Installation failed!")
        return
    end
end
print("DEBUG: Core files complete")

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

if component == "all" or component == "pocket" then
    print("")
    print("DEBUG: Installing pocket component...")
    print("DEBUG: Pocket files count = " .. #pocketFiles)
    print("Installing pocket computer app...")
    for _, file in ipairs(pocketFiles) do
        print("DEBUG: Processing pocket file: " .. file)
        if not downloadFile(REPO_URL .. file, file) then
            print("Installation failed!")
            return
        end
    end
end

print("")
print("========================================")

-- Restore data if this was an update
if isUpdate then
    if not restoreData() then
        print("ERROR: Failed to restore data!")
        print("Your data backup is in /data.backup")
        return
    end
    print("Update Complete!")
else
    print("Installation Complete!")
end

print("========================================")
print("")

-- Component-specific instructions
if isUpdate then
    print("Update successful! Changes:")
    print("- Updated all program files to latest version")
    print("- Preserved your data (accounts, transactions)")
    print("- Preserved your config.lua settings")
    print("")
    print("IMPORTANT: Check for new config options!")
    print("Compare your config.lua with the latest version:")
    print("  " .. REPO_URL .. "config.lua")
    print("")
    print("You may need to manually add new settings like:")
    print("  - config.pocket (if missing)")
    print("  - New security options")
    print("  - New feature toggles")
    print("")
    print("Next steps:")
    print("1. Review and update config.lua if needed")
    print("2. Restart the server and any running components")
    print("3. Test all functionality to ensure compatibility")
    print("")
    print("If you experience issues:")
    print("- Check the changelog for breaking changes")
    print("- Verify your config.lua has all required settings")
    print("- Compare against the default config.lua template")
    print("")
elseif component == "all" then
    print("All components installed successfully!")
    print("")
    print("Next steps:")
    print("1. Edit config.lua to configure settings")
    print("2. Attach wireless modems to all computers")
    print("3. Set up STORAGE, INPUT, and void chests (see README)")
    print("4. On server: Run 'server/main'")
    print("5. On management: Run 'management/main'")
    print("6. On pocket computers: Run 'pocket/main'")
    print("")
elseif component == "server" then
    print("Server Installation Complete!")
    print("")
    print("Next steps:")
    print("1. Edit config.lua to configure server settings")
    print("2. Attach a wireless modem")
    print("3. Set up peripheral network with wired modems:")
    print("   - STORAGE chests (label with 'STORAGE' paper)")
    print("   - INPUT chests (label with 'INPUT' paper)")
    print("   - User void chests (label with username papers)")
    print("4. Run: server/main")
    print("")
elseif component == "management" then
    print("Management Console Installation Complete!")
    print("")
    print("Next steps:")
    print("1. Edit config.lua if needed")
    print("2. Attach a wireless modem")
    print("3. Run: management/main")
    print("4. Create master password on first run")
    print("5. Manage accounts and shop items")
    print("")
elseif component == "pocket" then
    print("Pocket Computer App Installation Complete!")
    print("")
    print("Next steps:")
    print("1. Attach a wireless modem")
    print("2. Run: pocket/main")
    print("3. Login with your account")
    print("4. Access balance, transfers, and shop")
    print("")
end

print("For complete documentation:")
print("  https://github.com/Lancartian/cc-bank")
print("")
print("Need help? Check the troubleshooting section!")
print("")
