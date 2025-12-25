-- startup.lua
-- Auto-start script for CC-Bank components
-- Copy this to 'startup' (no extension) to auto-run on boot

-- Detect which component this is based on files present
local function detectComponent()
    -- Check for server-specific files
    if fs.exists("/server/main.lua") then
        return "server"
    end
    
    -- Check for management-specific files
    if fs.exists("/management/main.lua") then
        return "management"
    end
    
    -- Check for ATM-specific files
    if fs.exists("/atm/main.lua") then
        return "atm"
    end
    
    return nil
end

-- Main startup
print("CC-Bank Starting...")

local component = detectComponent()

if not component then
    print("ERROR: Could not detect CC-Bank component")
    print("Please ensure files are installed correctly")
    return
end

print("Component: " .. component)
print("")

-- Add a small delay to allow peripherals to initialize
sleep(1)

-- Run the appropriate component
if component == "server" then
    print("Starting Bank Server...")
    shell.run("/server/main.lua")
elseif component == "management" then
    print("Starting Management Console...")
    shell.run("/management/main.lua")
elseif component == "atm" then
    print("Starting ATM...")
    shell.run("/atm/main.lua")
end

-- If the program exits, restart after a delay
print("")
print("CC-Bank stopped. Restarting in 5 seconds...")
print("Press Ctrl+T to cancel")
sleep(5)
os.reboot()
