local module = {}
local configDir = fs.getDir(shell.getRunningProgram()).."/config.luatable"

local expect = require("cc.expect")
local csFuncs = require("internal.csFuncs")

-- Config file management
function module.defaultConfig()
    return {inventories={},pull_only_inventories={}}
end

function module.loadConfig()
    local file = fs.open(configDir, "r")
    if file == nil then
        return module.defaultConfig()
    end

    local contents = file.readAll()
    file.close()

    local table = textutils.unserialise(contents)
    if table == nil or type(table) ~= "table" then
        return module.defaultConfig()
    else
        return table
    end
end

function module.saveConfig(config)
    expect(1, config, "table")
    local file = fs.open(configDir, "w")
    file.write(textutils.serialize(
        {
            input_inventory=config.input_inventory,
            output_inventory=config.output_inventory,
            inventories=config.inventories,
            pull_only_inventories=config.pull_only_inventories
        }
    ))
    file.close()
end

-- Get and set config data
function module.getInventoriesToPull(config)
    local list = {}

    for _, name in ipairs(config.pull_only_inventories) do
        local types = ({peripheral.getType(name)})
        if config.input_inventory ~= name and config.output_inventory ~= name and csFuncs.icontains(types, 'inventory') then
            table.insert(list, name)
        end
    end
    for _, name in ipairs(config.inventories) do
        local types = ({peripheral.getType(name)})
        if config.input_inventory ~= name and config.output_inventory ~= name and csFuncs.icontains(types, 'inventory') then
            table.insert(list, name)
        end
    end
    
    return list
end

function module.setInputInventory(config, name)
    expect(1, config, "table")
    expect(2, name, "string")

    config.input_inventory = name

    return config
end

function module.setOutputInventory(config, name)
    expect(1, config, "table")
    expect(2, name, "string")

    config.output_inventory = name

    return config
end

function module.addInventory(config, name)
    expect(1, config, "table")
    expect(2, name, "string")

    table.insert(config.inventories, name)

    return config
end

function module.addPullOnlyInventory(config, name)
    expect(1, config, "table")
    expect(2, name, "string")

    table.insert(config.pull_only_inventories, name)

    return config
end

-- Manage items
function module.sort(config)
    expect(1, config, "table")

    local totalItemsAmount = 0
    local sortedItemsAmount = 0

    if config.input_inventory == nil then
        return
    end

    local inputInventory = peripheral.wrap(config.input_inventory)
    if inputInventory == nil then
        return
    end

    for slot, item in pairs(inputInventory.list()) do
        totalItemsAmount = totalItemsAmount + item.count

        local count = item.count
        for i, inventory in ipairs(config.inventories) do
            local inventoryPeripheral = peripheral.wrap(inventory)
            if inventoryPeripheral ~= nil and csFuncs.icontains(({peripheral.getType(inventory)}), "inventory") then
                if count > 0 then
                    local pushedAmount = inputInventory.pushItems(inventory, slot, count)
                    count = count - pushedAmount
                    sortedItemsAmount = sortedItemsAmount + pushedAmount
                end
            end
        end
    end

    return totalItemsAmount, sortedItemsAmount
end

return module