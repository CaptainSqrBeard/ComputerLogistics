local baseCrafter = require("baseCrafter")

local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")
local csimpleConfig = require("csimpleConfig")

local PORT = 24869

local modem = peripheral.find("modem") or error("No modem attached", 0)

local cfg = csimpleConfig.initConfig("./config.json")

csimpleConfig.newParameter(cfg, "crafter", nil, "string")
csimpleConfig.newParameter(cfg, "tempContainer", nil, "string")
csimpleConfig.newParameter(cfg, "outputContainer", nil, "string")
csimpleConfig.newParameter(cfg, "redstoneRelay", nil, "string")

local success, error = csimpleConfig.processConfig(cfg)

if not success then
    print("Unable to process config:", error)
    return
end

--[[
local CRAFTER_PATH = "minecraft:crafter_1"
local TEMP_STORAGE_NAME = "minecraft:barrel_3"
local OUTPUT_STORAGE_NAME = "minecraft:barrel_1"
local REDSTONE_RELAY_NAME = "bottom"
]]

local CRAFTER_PATH = cfg.crafter
local TEMP_STORAGE_NAME = cfg.tempContainer
local OUTPUT_STORAGE_NAME = cfg.outputContainer
local REDSTONE_RELAY_NAME = cfg.redstoneRelay

local redstoneRelay = peripheral.wrap(REDSTONE_RELAY_NAME)

local function cleanUp(storage)
    local message, header = logisticsHelper.buildPullItems(storage)
    local signedMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedMessage)
end

local function oneBatch(task, repeats)
    local instructions = {}

    print("Making batch of", repeats, "crafts")

    for i, ingredient in ipairs(task.crafterData.shape) do
        if ingredient ~= 0 then
            local item = task.crafterData.ingredients[ingredient]
            if item == nil then
                print("Invalid item with index", ingredient, "used in recipe at position", i)
                return csecureNet.responses.bad_request
            end

            table.insert(instructions, logisticsHelper.buildInstruction(item, repeats, TEMP_STORAGE_NAME, i))
        end
    end

    local message, header = logisticsHelper.buildPushItemsMessage(true, instructions)
    local signedMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedMessage)

    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)

    if respond == csecureNet.responses.processing then
        local finalRespond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        if finalRespond == csecureNet.responses.success then
            local tempStorage = peripheral.wrap(TEMP_STORAGE_NAME)
            for i = 1, 9 do
                tempStorage.pushItems(CRAFTER_PATH, i, nil, i)
            end

            for i = 1, repeats do
                redstoneRelay.setOutput("bottom", true)
                sleep(0.1)
                redstoneRelay.setOutput("bottom", false)
                sleep(0.1)
            end
            
            print("Made batch of", repeats, "crafts")

            sleep(0.1)
            cleanUp(CRAFTER_PATH)
            cleanUp(TEMP_STORAGE_NAME)
            
            return nil
        else
            print("Batch failed at item request, got response", finalRespond)
            
            cleanUp(TEMP_STORAGE_NAME)

            return csecureNet.responses.cannot_provide
        end
        
    else
        print("Batch failed at start, got response", finalRespond)
        return csecureNet.responses.cannot_provide
    end
end

local function craft(queueEntry, thread)
    local itemLeft = queueEntry.repeats
    print("Requested", itemLeft, "crafts")
    while itemLeft > 0 do
        local batchRepeats = math.min(itemLeft, 64)
        local result = oneBatch(queueEntry, batchRepeats)

        if result == nil then
            itemLeft = itemLeft - batchRepeats
            print("Items left:", itemLeft)
        else
            sleep(0.1)
            cleanUp(OUTPUT_STORAGE_NAME)
            return result
        end
    end

    sleep(0.1)
    cleanUp(OUTPUT_STORAGE_NAME)

    return csecureNet.responses.success
end

modem.open(PORT)

csecureNet.verbose = false

baseCrafter.initCrafter("minecraft:crafting", craft, modem, PORT, 1)