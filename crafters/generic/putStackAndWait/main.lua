local baseCrafter = require("baseCrafter")

local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")
local csimpleConfig = require("csimpleConfig")
local cstorage = require("cstorage")

local modem = peripheral.find("modem") or error("No modem attached", 0)

local PORT = 24869

local isTempStorageUsed = false

local processorData = {}

local cfg = csimpleConfig.initConfig("./config.json")

csimpleConfig.newParameter(cfg, "processingType", nil, "string")
csimpleConfig.newParameter(cfg, "tempInputStorage", nil, "string", "nil")
csimpleConfig.newParameter(cfg, "maxBatch", 64, "number")
csimpleConfig.newParameter(cfg, "orderAtOnce", true, "boolean")
csimpleConfig.newParameter(cfg, "checkDelay", 1.0, "number")
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

local tempStoragePeripheral = peripheral.wrap(cfg.tempInputStorage)

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

local function canFitInStorage(storagePeripheral, stacks)
    local emptySlots = storagePeripheral.size()

    for slot, item in pairs(storagePeripheral.list()) do
        emptySlots = emptySlots - 1
    end

    return emptySlots >= stacks
end

local function waitForSpace(storagePeripheral, stacks)
    if not canFitInStorage(storagePeripheral, stacks) then
        print("Waiting for space inside input storage...")
        sleep(cfg.checkDelay)
        while not canFitInStorage(storagePeripheral, stacks) do
            sleep(cfg.checkDelay)
        end
        print("Got space in storage.")
    end
end

local function shouldOrderAtOnce()
    return cfg.orderAtOnce and cfg.tempInputStorage ~= nil
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
    local putIntoPeripheral
    if cfg.tempInputStorage ~= nil then
        putInto = cfg.tempInputStorage
        putIntoPeripheral = tempStoragePeripheral
    else
        putInto = processor.processor
        putIntoPeripheral = processor.processorPeripheral
    end
    
    local respond
    
    if not shouldOrderAtOnce() then
        local toFit = math.ceil(repeats / 64)
        waitForSpace(putIntoPeripheral, toFit)

        local message, header = logisticsHelper.buildPushItemsMessage(true, {
            logisticsHelper.buildInstruction(task.crafterData.id, repeats, putInto)
        })

        local signedMessage = csecureNet.writeMessage(message, header)
        modem.transmit(PORT, PORT, signedMessage)
        respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
    else
        respond = csecureNet.responses.processing
    end
    local missed = 0


    if respond == csecureNet.responses.processing then
        local finalRespond

        if shouldOrderAtOnce() then
            finalRespond = csecureNet.responses.success
        else
            finalRespond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        end

        if finalRespond == csecureNet.responses.success then
            if cfg.tempInputStorage ~= nil then
                local found, items = cstorage.searchByExactId({putInto}, repeats, task.crafterData.id)
                if found < repeats then
                    print("WARN: Found less items than required ("..found.." < "..repeats..")")
                end
                local pushed = cstorage.pushItems(items, processor.processor, nil, repeats, false)
                if pushed < repeats then
                    print("WARN: Pushed less items than expected ("..pushed.." < "..repeats..")")
                end
            end

            if processor.processorOutPeripheral ~= nil then
                while true do
                    if not isStorageEmpty(processor.processorOutPeripheral) then
                        cleanUp(processor.processorOut)
                    elseif isStorageEmpty(processor.processorOutPeripheral) and isStorageEmpty(processor.processorPeripheral) then
                        break
                    end
                    sleep(cfg.checkDelay)
                end
            else
                while true do
                    if not isStorageContains(processor.processorPeripheral, task.crafterData.id) then
                        break
                    end
                    sleep(cfg.checkDelay)
                end
            end

            if task.crafterData.expect ~= nil then
                local count = countItemsInStorage(processor.processorPeripheral, task.crafterData.expect.id)
                missed = missed + (math.max(0, task.crafterData.expect.amount * repeats - count))
            end
            
            print("Made batch of", repeats, "crafts")

            cleanUp(processor.processor)
            cleanUp(processor.processorOut)
            if not shouldOrderAtOnce() then
                cleanUp(cfg.tempInputStorage)
            end
            
            return nil, missed
        else
            print("Batch failed at item request, got response", finalRespond)
            
            cleanUp(processor.processor)
            cleanUp(processor.processorOut)
            if not shouldOrderAtOnce() then
                cleanUp(cfg.tempInputStorage)
            end

            return csecureNet.responses.cannot_provide
        end
        
    else
        print("Batch failed at start, got response", respond)
        return csecureNet.responses.cannot_provide
    end
end

local function craft(queueEntry, thread)
    local processor = processorData[thread]
    local craftsLeft = queueEntry.repeats

    local totalMissed = 0

    if shouldOrderAtOnce() then
        local toFit = math.ceil(craftsLeft / 64)

        waitForSpace(tempStoragePeripheral, toFit)

        local message, header = logisticsHelper.buildPushItemsMessage(true, {
            logisticsHelper.buildInstruction(queueEntry.crafterData.id, craftsLeft, cfg.tempInputStorage)
        })
        local signedMessage = csecureNet.writeMessage(message, header)
        modem.transmit(PORT, PORT, signedMessage)
        
        print("0 - ", cfg.tempInputStorage)
        local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        if respond == csecureNet.responses.processing then
            local finalRespond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)

            if finalRespond ~= csecureNet.responses.success then
                cleanUp(processor.processor)
                cleanUp(processor.processorOut)
                cleanUp(cfg.tempInputStorage)
                return csecureNet.responses.cannot_provide
            end
        else
            cleanUp(processor.processor)
            cleanUp(processor.processorOut)
            cleanUp(cfg.tempInputStorage)
            return csecureNet.responses.cannot_provide
        end
    end

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

if cfg.orderAtOnce and cfg.tempInputStorage == nil then
    print("orderAtOnce is enabled, but input storage is undefined! orderAtOnce will not be enabled.")
end

modem.open(PORT)

csecureNet.verbose = false

--cleanUp(cfg.tempInputStorage)
--for i, processor in ipairs(processorData) do
--    cleanUp(processor.processor)
--    cleanUp(processor.processorOut)
--end

baseCrafter.initCrafter(cfg.processingType, craft, modem, PORT, cfg.threads)
