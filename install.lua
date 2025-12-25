-- install.lua
-- Installer for CC-Bank system

local component = "server"  -- server, management, or atm

-- Check arguments
local args = {...}
if #args > 0 then
    component = args[1]
end

print("CC-Bank Installer")
print("=================")
print("")

-- Check if SGL is installed
if not fs.exists("lib/sgl/sgl.lua") and not fs.exists("/lib/sgl/sgl.lua") then
    print("CC-SGL not found!")
    print("Installing CC-SGL...")
    
    shell.run("wget", "https://raw.githubusercontent.com/Lancartian/cc-sgl/main/installer.lua", "sgl_installer.lua")
    shell.run("sgl_installer.lua", "install")
    
    if fs.exists("sgl_installer.lua") then
        fs.delete("sgl_installer.lua")
    end
end

-- Ask which component to install
if component ~= "server" and component ~= "management" and component ~= "atm" then
    print("Which component do you want to install?")
    print("1. Server")
    print("2. Management Console")
    print("3. ATM")
    print("")
    write("Enter choice (1-3): ")
    
    local choice = tonumber(read())
    
    if choice == 1 then
        component = "server"
    elseif choice == 2 then
        component = "management"
    elseif choice == 3 then
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
print("Installation complete!")
print("")

-- Component-specific instructions
if component == "server" then
    print("Server Installation Complete!")
    print("")
    print("Next steps:")
    print("1. Edit config.lua to configure server settings")
    print("2. Attach a wireless modem")
    print("3. Attach a chest for currency (default: bottom)")
    print("4. Run: server/main")
    print("")
elseif component == "management" then
    print("Management Console Installation Complete!")
    print("")
    print("Next steps:")
    print("1. Attach a wireless modem")
    print("2. Run: management/main")
    print("3. Create master password on first run")
    print("4. Create user accounts and mint currency")
    print("")
elseif component == "atm" then
    print("ATM Installation Complete!")
    print("")
    print("Next steps:")
    print("1. Edit config.lua to set ATM ID and frequency")
    print("2. Attach a wireless modem")
    print("3. Configure void chest for dispensing")
    print("4. Run: atm/main")
    print("")
end

print("For complete documentation, see README.md")
