local baseCrafter = require("baseCrafter")

local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")
local csimpleConfig = require("csimpleConfig")

local MIXERS = 3
local mixerData = {}

local PORT = 24869

local modem = peripheral.find("modem") or error("No modem attached", 0)

local cfg = csimpleConfig.initConfig("./config.json")

csimpleConfig.newParameter(cfg, "merged_output", nil, "string")
for i = 1, MIXERS do
    csimpleConfig.newParameter(cfg, "basin_"..i, nil, "string")
    csimpleConfig.newParameter(cfg, "out_"..i, nil, "string")
end

local success, error = csimpleConfig.processConfig(cfg)

local mergedOutput = cfg.merged_output
local mergedOutputPeripheral = peripheral.wrap(mergedOutput)

if not success then
    print("Unable to process config:", error)
    return
end

for i = 1, MIXERS do
    mixerData[i] = {
        basin = cfg["basin_"..i],
        basinPeripheral = peripheral.wrap(cfg["basin_"..i]),
        out = cfg["out_"..i]
    }
end

local function isBasinEmpty(basinPeripheral)
    local items = basinPeripheral.list()
    for i = 1, 18 do
        if items[i] ~= nil then
            return false
        end
    end
    return true
end 

local function cleanUp(storage)
    local message, header = logisticsHelper.buildPullItems(storage)
    local signedMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedMessage)
end

local function oneBatch(task, repeats, mixer)
        local instructions = {}

    print("Making batch of", repeats, "crafts")

    for i, ingredient in ipairs(task.crafterData.ingredients) do
        table.insert(instructions, logisticsHelper.buildInstruction(ingredient.id, repeats * ingredient.amount, mixer.basin))
    end

    local message, header = logisticsHelper.buildPushItemsMessage(true, instructions)
    local signedMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedMessage)

    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)

    if respond == csecureNet.responses.processing then
        local finalRespond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        if finalRespond == csecureNet.responses.success then
            while true do
                mergedOutputPeripheral.pullItems(mixer.out, 1)
                if isBasinEmpty(mixer.basinPeripheral) then
                    break
                end
                sleep(0.5)
            end

            print("Made batch of", repeats, "crafts")

            cleanUp(mixer.basin)
            
            return nil
        else
            print("Batch failed at item request, got response", finalRespond)
            
            cleanUp(mergedOutput)
            cleanUp(mixer.out)
            cleanUp(mixer.basin)

            return csecureNet.responses.cannot_provide
        end
        
    else
        print("Batch failed at start, got response", finalRespond)
        return csecureNet.responses.cannot_provide
    end
end

local function craft(queueEntry, thread)
    local mixer = mixerData[thread]
    local craftsLeft = queueEntry.repeats

    while craftsLeft > 0 do
        local canPutAtOnce = math.min(64, craftsLeft)
        for i, ingredient in ipairs(queueEntry.crafterData.ingredients) do
            canPutAtOnce = math.min(canPutAtOnce, math.floor(64/ingredient.amount))
        end

        local result = oneBatch(queueEntry, canPutAtOnce, mixer)

        if result == nil then
            craftsLeft = craftsLeft - canPutAtOnce
            print("Items left:", craftsLeft)
        else
            return result
        end
    end

    sleep(2)
    
    cleanUp(mixer.out)
    cleanUp(mixer.basin)
    cleanUp(mergedOutput)

    return csecureNet.responses.success
end

modem.open(PORT)

csecureNet.verbose = false

baseCrafter.initCrafter("create:mixing", craft, modem, PORT, MIXERS)