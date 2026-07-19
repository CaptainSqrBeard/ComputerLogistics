local baseCrafter = require("baseCrafter")

local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")
local csimpleConfig = require("csimpleConfig")

local CRUSHERS = 3
local crusherData = {}

local PORT = 24869

local modem = peripheral.find("modem") or error("No modem attached", 0)

local cfg = csimpleConfig.initConfig("./config.json")

for i = 1, CRUSHERS do
    csimpleConfig.newParameter(cfg, "crusher_"..i, nil, "string")
    csimpleConfig.newParameter(cfg, "out_"..i, nil, "string")
end

local success, error = csimpleConfig.processConfig(cfg)

if not success then
    print("Unable to process config:", error)
    return
end

for i = 1, CRUSHERS do
    crusherData[i] = {
        crusher = cfg["crusher_"..i],
        crusherPeripheral = peripheral.wrap(cfg["crusher_"..i]),
        out = cfg["out_"..i]
    }
end

local function isCrusherEmpty(crusherPeripheral)
    local items = crusherPeripheral.list()
    if items[1] ~= nil then
        return false
    end
    return true
end

local function countItemsInside(depotPeripheral, id)
    local counted = 0
    local items = depotPeripheral.list()
    for k, item in pairs(items) do
        if item.name == id then
            counted = counted + item.count
        end
    end
    return counted
end 

local function cleanUp(storage)
    local message, header = logisticsHelper.buildPullItems(storage)
    local signedMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedMessage)
end

local function oneBatch(task, repeats, crusher)
    print("Making batch of", repeats, "crafts")
    
    local missed = 0

    local message, header = logisticsHelper.buildPushItemsMessage(true, {
        logisticsHelper.buildInstruction(task.crafterData.id, repeats, crusher.crusher)
    })

    local signedMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedMessage)

    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)

    if respond == csecureNet.responses.processing then
        local finalRespond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        if finalRespond == csecureNet.responses.success then
            while true do
                if isCrusherEmpty(crusher.crusherPeripheral) then
                    break
                end
                sleep(0.5)
            end

            if task.crafterData.expect ~= nil then
                local count = countItemsInside(depot.depotPeripheral, task.crafterData.expect.id)
                missed = missed + (math.max(0, task.crafterData.expect.amount * repeats - count))
            end

            print("Made batch of", repeats, "crafts")
            
            return nil, missed
        else
            print("Batch failed at item request, got response", finalRespond)
            
            cleanUp(crusher.out)
            cleanUp(crusher.crusher)

            return csecureNet.responses.cannot_provide
        end
        
    else
        print("Batch failed at start, got response", respond)
        return csecureNet.responses.cannot_provide
    end
end

local function craft(queueEntry, thread)
    local crusher = crusherData[thread]
    local craftsLeft = queueEntry.repeats

    local totalMissed = 0
    while craftsLeft > 0 do
        local shouldPut = math.min(64, craftsLeft)

        local result, missed = oneBatch(queueEntry, shouldPut, crusher)

        if result == nil then
            craftsLeft = craftsLeft - shouldPut
            totalMissed = totalMissed + missed
            print("Items left:", craftsLeft)
        else
            return result
        end
    end

    sleep(2)
    
    cleanUp(crusher.out)
    cleanUp(crusher.crusher)

    if totalMissed > 0 then
        return csecureNet.responses.partial_content, {missed=totalMissed}
    else
        return csecureNet.responses.success
    end
end

modem.open(PORT)

csecureNet.verbose = false

baseCrafter.initCrafter("create:crushing", craft, modem, PORT, CRUSHERS)