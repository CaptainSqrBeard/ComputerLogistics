local function printUsage()
    local programName = fs.getName(shell.getRunningProgram()) or arg[0]
    print("Usages:")
    print(programName .. " sort")
    print(programName .. " search <prompt>")
    print(programName .. " set-output <storage>")
    print(programName .. " set-input <storage>")
    print(programName .. " add-inventory <storage>")
end

local args = { ... }
if #args < 1 then
    printUsage()
    return
end

local storageApi = require("internal.csStorageApi")
local csFuncs = require("internal.csFuncs")
local shared = require("internal.shared")

if args[1] == "sort" then
    shared.sort(shared.loadConfig())
elseif args[1] == "search" then
    print("todo search")
elseif args[1] == "set-output" then
    if args[2] == nil then
        printUsage()
        return
    end
    local config = shared.loadConfig()
    local newConfig = shared.setOutputInventory(config, args[2])
    shared.saveConfig(newConfig)
    print("Output inventory is now", args[2])
elseif args[1] == "set-input" then
    if args[2] == nil then
        printUsage()
        return
    end
    local config = shared.loadConfig()
    shared.saveConfig(shared.setInputInventory(config, args[2]))
    print("Input inventory is now", args[2])
elseif args[1] == "add-inventory" then
    if args[2] == nil then
        printUsage()
        return
    end
    local config = shared.loadConfig()
    shared.saveConfig(shared.addInventory(config, args[2]))
    print("Inventory", args[2], "is now used")
else
    printUsage()
    return
end