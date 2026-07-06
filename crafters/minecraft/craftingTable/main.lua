local baseCrafter = require("baseCrafter")

local secureNet = require("secureNet")

local CRAFTER_PATH = "minecraft:crafter_0"
local OUTPUT_STORAGE_NAME = "minecraft:chest_0"
local REDSTONE_LINK_NAME = "redstone_link_0"

local function oneBatch(task, repeats)
    local instructions = {}

    for i, ingredient in ipairs(task.crafterData.shape) do
        if ingredient ~= nil then
            local item = task.crafterData.ingredients[ingredient]
            if item == nil then
                return secureNet.responces.bad_request
            end

            table.insert(instructions, logisticsHelper.buildInstruction(item, repeats, CRAFTER_PATH, i))
        end
    end

    local message, header = logisticsHelper.buildPushItemsMessage(true, instructions)
    local signedMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedMessage)

    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)

    if respond == csecureNet.responses.processing then
        local finalRespond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        if finalRespond == secureNet.responces.success then
            
            return nil
        else
            return secureNet.responces.cannot_provide
        end
    else
        return secureNet.responces.cannot_provide
    end
end

local function craft(task)
    local itemLeft = task.repeats
    
    while itemLeft > 0 do
        local batchRepeats = math.min(task.repeats, 16)
        local result = oneBatch(task, batchRepeats)

        if result == nil then
            itemLeft = itemLeft - batchRepeats
        else
            return false
        end
    end

    return true
end

baseCrafter.initCrafter("minecraft:crafting", craft)