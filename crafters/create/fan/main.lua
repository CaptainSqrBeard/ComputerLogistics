local baseCrafter = require("baseCrafter")

local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")
local csimpleConfig = require("csimpleConfig")

local modem = peripheral.find("modem") or error("No modem attached", 0)

local DEPOTS = 8
local PORT = 24869

local barrelInUse = false

local depotData = {}

local cfg = csimpleConfig.initConfig("./config.json")

csimpleConfig.newParameter(cfg, "processingType", nil, "string")
csimpleConfig.newParameter(cfg, "tempStorage", nil, "string")
for i = 1, DEPOTS do
    csimpleConfig.newParameter(cfg, "depot_"..i, nil, "string")
end

local success, error = csimpleConfig.processConfig(cfg)

local tempStorage = cfg.tempStorage

if not success then
    print("Unable to process config:", error)
    return
end

for i = 1, DEPOTS do
    depotData[i] = {
        depot = cfg["depot_"..i],
        depotPeripheral = peripheral.wrap(cfg["depot_"..i])
    }
end

local function isDepotContains(depotPeripheral, id)
    local items = depotPeripheral.list()
    for i = 1, 9 do
        if items[i] ~= nil and items[i].name == id then
            return true
        end
    end
    return false
end 

local function countItemsOnDepot(depotPeripheral, id)
    local counted = 0
    local items = depotPeripheral.list()
    for i = 1, 9 do
        if items[i] ~= nil and items[i].name == id then
            counted = counted + items[i].count
        end
    end
    return counted
end 

local function cleanUp(storage)
    local message, header = logisticsHelper.buildPullItems(storage)
    local signedMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedMessage)
end

local function oneBatch(task, repeats, depot)
    print("Making batch of", repeats, "crafts")
    local message, header = logisticsHelper.buildPushItemsMessage(true, {
        logisticsHelper.buildInstruction(task.crafterData.id, repeats, cfg.tempStorage)
    })

    local missed = 0

    if barrelInUse then
        print("Barrel in use...")
    end
    while barrelInUse do
        sleep(0.5)
    end

    local signedMessage = csecureNet.writeMessage(message, header)
    barrelInUse = true
    modem.transmit(PORT, PORT, signedMessage)

    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)

    if respond == csecureNet.responses.processing then
        local finalRespond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        if finalRespond == csecureNet.responses.success then
            depot.depotPeripheral.pullItems(tempStorage, 1)
            barrelInUse = false

            while true do
                if not isDepotContains(depot.depotPeripheral, task.crafterData.id) then
                    break
                end
                sleep(0.5)
            end

            if task.crafterData.expect ~= nil then
                local count = countItemsOnDepot(depot.depotPeripheral, task.crafterData.expect.id)
                missed = missed + (math.max(0, task.crafterData.expect.amount * repeats - count))
            else
                print("Made batch of", repeats, "crafts")
            end

            cleanUp(depot.depot)
            cleanUp(tempStorage)
            
            return nil, missed
        else
            barrelInUse = false
            print("Batch failed at item request, got response", finalRespond)
            
            cleanUp(depot.depot)
            cleanUp(tempStorage)

            return csecureNet.responses.cannot_provide
        end
        
    else
        barrelInUse = false
        print("Batch failed at start, got response", respond)
        return csecureNet.responses.cannot_provide
    end
end

local function craft(queueEntry, thread)
    local depot = depotData[thread]
    local craftsLeft = queueEntry.repeats

    local totalMissed = 0
    while craftsLeft > 0 do
        local canPutAtOnce = math.min(64, craftsLeft)

        local result, missed = oneBatch(queueEntry, canPutAtOnce, depot)

        if result == nil then
            craftsLeft = craftsLeft - canPutAtOnce
            totalMissed = totalMissed + missed
            print("Items left:", craftsLeft)
        else
            return result
        end
    end

    sleep(2)
    
    cleanUp(depot.depot)
    cleanUp(tempStorage)

    if totalMissed > 0 then
        return csecureNet.responses.partial_content, {missed=totalMissed}
    else
        return csecureNet.responses.success
    end

end

modem.open(PORT)

csecureNet.verbose = false

baseCrafter.initCrafter(cfg.processingType, craft, modem, PORT, DEPOTS)