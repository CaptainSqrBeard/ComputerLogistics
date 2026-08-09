local baseCrafter = require("baseCrafter")

local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")
local csimpleConfig = require("csimpleConfig")

local modem = peripheral.find("modem") or error("No modem attached", 0)

local PORT = 24869

local isTempStorageUsed = false

local processorData = {}

local cfg = csimpleConfig.initConfig("./config.json")

csimpleConfig.newParameter(cfg, "processingType", nil, "string")
csimpleConfig.newParameter(cfg, "tempInputStorage", nil, "string", "nil")
csimpleConfig.newParameter(cfg, "maxBatch", 64, "number")
csimpleConfig.newParameterWithPostFunc(cfg, "threads", 1, function(val)
    for i = 1, val do
        csimpleConfig.newParameter(cfg, "processor_"..i, nil, "string")
        csimpleConfig.newParameter(cfg, "processorOut_"..i, nil, "string", "nil")
    end
    return true
end, "number")

local success, error = csimpleConfig.processConfig(cfg)

if not success then
    print("Unable to process config:", error)
    return
end

for i = 1, cfg.threads do
    local data = {
        processor = cfg["processor_"..i],
        processorPeripheral = peripheral.wrap(cfg["processor_"..i])
    }
    if cfg["processorOut_"..i] ~= nil then
        data.processorOut = cfg["processorOut_"..i]
        data.processorOutPeripheral = peripheral.wrap(cfg["processorOut_"..i])
    end
    processorData[i] = data
end

local function isStorageContains(storagePeripheral, id)
    local items = storagePeripheral.list()
    for k, item in pairs(items) do
        if item.name == id then
            return true
        end
    end
    return false
end

local function isStorageEmpty(storagePeripheral)
    local items = storagePeripheral.list()
    for k, item in pairs(items) do
        return false
    end
    return true
end

local function countItemsInStorage(storagePeripheral, id)
    local counted = 0
    local items = storagePeripheral.list()
    for k, item in pairs(items) do
        if item.name == id then
            counted = counted + item.count
        end
    end
    return counted
end 

local function cleanUp(storage)
    if storage == nil then
        return
    end

    local message, header = logisticsHelper.buildPullItems(storage)
    local signedMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedMessage)
end

local function oneBatch(task, repeats, processor)
    print("Making batch of", repeats, "crafts")

    local putInto
    if cfg.tempInputStorage ~= nil then
        putInto = cfg.tempInputStorage

        if isTempStorageUsed then
            print("Temporal input storage in use...")
            while isTempStorageUsed do
                sleep(0.5)
            end
        end
    else
        putInto = processor.processor
    end

    local message, header = logisticsHelper.buildPushItemsMessage(true, {
        logisticsHelper.buildInstruction(task.crafterData.id, repeats, putInto)
    })

    local missed = 0

    local signedMessage = csecureNet.writeMessage(message, header)
    isTempStorageUsed = true and cfg.tempInputStorage ~= nil
    modem.transmit(PORT, PORT, signedMessage)

    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)

    if respond == csecureNet.responses.processing then
        local finalRespond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        if finalRespond == csecureNet.responses.success then
            if cfg.tempInputStorage ~= nil then
                processor.processorPeripheral.pullItems(putInto, 1)
                isTempStorageUsed = false
            end

            if processor.processorOutPeripheral ~= nil then
                while true do
                    if not isStorageEmpty(processor.processorOutPeripheral) then
                        cleanUp(processor.processorOut)
                    elseif isStorageEmpty(processor.processorOutPeripheral) and isStorageEmpty(processor.processorPeripheral) then
                        break
                    end
                    sleep(0.5)
                end
            else
                while true do
                    if not isStorageContains(processor.processorPeripheral, task.crafterData.id) then
                        break
                    end
                    sleep(0.5)
                end
            end

            if task.crafterData.expect ~= nil then
                local count = countItemsInStorage(processor.processorPeripheral, task.crafterData.expect.id)
                missed = missed + (math.max(0, task.crafterData.expect.amount * repeats - count))
            end
            
            print("Made batch of", repeats, "crafts")

            cleanUp(processor.processor)
            cleanUp(processor.processorOut)
            cleanUp(cfg.tempInputStorage)
            
            return nil, missed
        else
            isTempStorageUsed = false
            print("Batch failed at item request, got response", finalRespond)
            
            cleanUp(processor.processor)
            cleanUp(processor.processorOut)
            cleanUp(cfg.tempInputStorage)

            return csecureNet.responses.cannot_provide
        end
        
    else
        isTempStorageUsed = false
        print("Batch failed at start, got response", respond)
        return csecureNet.responses.cannot_provide
    end
end

local function craft(queueEntry, thread)
    local processor = processorData[thread]
    local craftsLeft = queueEntry.repeats

    local totalMissed = 0
    while craftsLeft > 0 do
        local shouldPut = math.min(cfg.maxBatch, craftsLeft)

        local result, missed = oneBatch(queueEntry, shouldPut, processor)

        if result == nil then
            craftsLeft = craftsLeft - shouldPut
            totalMissed = totalMissed + missed
            print("Items left:", craftsLeft)
        else
            return result
        end
    end

    sleep(2)
    
    cleanUp(processor.processor)
    cleanUp(processor.processorOut)
    cleanUp(cfg.tempInputStorage)

    if totalMissed > 0 then
        return csecureNet.responses.partial_content, {missed=totalMissed}
    else
        return csecureNet.responses.success
    end

end

modem.open(PORT)

csecureNet.verbose = false

baseCrafter.initCrafter(cfg.processingType, craft, modem, PORT, cfg.threads)