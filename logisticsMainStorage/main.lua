local csecureNet = require("csecureNet")
local cstorage = require("cstorage")

local PORT = 24869
local PROTOCOL = "csLogistics"
local ITEM_STORAGES_FILE_PATH = "./item_storages.txt"

local spawnNewParallel

local modem = peripheral.find("modem") or error("No modem attached", 0)
modem.open(PORT)
local itemStorages = {}

-- instruction:
-- id
-- amount
-- container
-- slot (optional)
local function commandMoveItems(instructions, onlyFull)
    local usedItemAmounts = {}
    local usedItemLocations = {}

    for i, instr in ipairs(instructions) do
        if usedItemAmounts[instr.id] == nil then
            usedItemAmounts[instr.id] = instr.amount
        else
            usedItemAmounts[instr.id] = usedItemAmounts[instr.id] + instr.amount
        end
    end

    for item, amount in pairs(usedItemAmounts) do
        local totalFound, itemEntries = cstorage.searchByExactId(itemStorages, amount, item)
        usedItemLocations[item] = itemEntries

        if onlyFull and amount > totalFound then
            return csecureNet.responses.cannot_provide
        end
    end

    local nonEmpty = false
    local partial = false
    for i, instr in ipairs(instructions) do
        local pushed = cstorage.pushItems(usedItemLocations[instr.id], instr.container, instr.slot, instr.amount, false)
        if pushed < instr.amount then
            partial = true
        end
        if pushed > 0 then
            nonEmpty = true
        end
    end

    if not nonEmpty then
        return csecureNet.responses.cannot_provide
    elseif partial then
        return csecureNet.responses.partial_content
    end
    return csecureNet.responses.success
end

local function commandPullItems(fromContainer)
    local pulledItems, itemAmount = cstorage.pullItems(peripheral.wrap(fromContainer), itemStorages)
    if (itemAmount > pulledItems) then
        return csecureNet.responses.partial_content
    end
    return csecureNet.responses.success
end

local function commandGetItemAmount(id)
    local totalFound, itemEntries = cstorage.searchByExactId(itemStorages, nil, id)
    return csecureNet.responses.success, totalFound
end

local function commandGetItemsAmount(ids)
    local itemAmounts = {}
    for i, id in ipairs(ids) do
        local totalFound, itemEntries = cstorage.searchByExactId(itemStorages, nil, id)
        itemAmounts[id] = totalFound
    end

    return csecureNet.responses.success, itemAmounts
end

local function respondToCommand(verifiedMessage, msg, usedModem, replyChannel)
    local requestId = csecureNet.getHeaderValue(msg, "requestId")
    local type = verifiedMessage.message.type

    if type == "ping" then
        csecureNet.sendRespond(csecureNet.responses.success, PROTOCOL, requestId, usedModem, replyChannel)
    elseif type == "moveItems" then
        csecureNet.sendRespond(csecureNet.responses.processing, PROTOCOL, requestId, usedModem, replyChannel)

        local result = commandMoveItems(verifiedMessage.message.instructions, verifiedMessage.message.onlyFull)
        csecureNet.sendRespond(result, PROTOCOL, requestId, usedModem, replyChannel)
    elseif type == "getItem" then
        csecureNet.sendRespond(csecureNet.responses.processing, PROTOCOL, requestId, usedModem, replyChannel)

        local result, context = commandGetItemAmount(verifiedMessage.message.id)
        csecureNet.sendRespondWithContext(result, context, PROTOCOL, requestId, usedModem, replyChannel)
    elseif type == "getItems" then
        csecureNet.sendRespond(csecureNet.responses.processing, PROTOCOL, requestId, usedModem, replyChannel)

        local result, context = commandGetItemsAmount(verifiedMessage.message.ids)
        csecureNet.sendRespondWithContext(result, context, PROTOCOL, requestId, usedModem, replyChannel)
    elseif type == "pullItems" then
        csecureNet.sendRespond(csecureNet.responses.processing, PROTOCOL, requestId, usedModem, replyChannel)

        local result = commandPullItems(verifiedMessage.message.fromContainer)
        csecureNet.sendRespond(result, PROTOCOL, requestId, usedModem, replyChannel)
    end
end

local function addContainerToSystem(container)
    if container == nil then
        return false
    end
    table.insert(itemStorages, container)
    return true
end

local function readEvent(eventData)
    local event = eventData[1]

    if event == "modem_message" then
        local usedModem = peripheral.wrap(eventData[2])
        local usedPort = eventData[3]
        local replyChannel = eventData[4]
        local msg = eventData[5]
        local distance = eventData[6]
    
        if csecureNet.isValidMessage(msg) and csecureNet.getHeaderValue(msg, "protocol") == PROTOCOL and csecureNet.getHeaderValue(msg, "toRole") == "mainStorage" then
            local receivedModem  = usedModem
            local verifiedMessage = csecureNet.processMessage(msg, receivedModem, replyChannel)
            if verifiedMessage ~= nil then
                local success, errorMsg = pcall(respondToCommand, verifiedMessage, msg, usedModem, replyChannel)
            
                if not success then
                    csecureNet.sendRespond(csecureNet.responses.internal_server_error, PROTOCOL, csecureNet.getHeaderValue(msg, "requestId"), usedModem, replyChannel)
                    print("Error while running command!\n"..errorMsg)
                end
            end
        end
    end
end

local function processEvents(spawn)
    spawnNewParallel = spawn

    while true do
        local eventData = {os.pullEvent()}
        
        spawnNewParallel(function()
            readEvent(eventData)
        end)
    end
end

-- Program init
csecureNet.verbose = true
csecureNet.importAuthorizedKeys("./authorizedKeys.txt")
csecureNet.init()

local containersFile = fs.open(ITEM_STORAGES_FILE_PATH, "r")
if containersFile ~= nil then
    while addContainerToSystem(containersFile.readLine()) do end
    containersFile.close()
    print("Attached "..#itemStorages.." item storages")
else
    containersFile = fs.open(ITEM_STORAGES_FILE_PATH, "w")
    containersFile.close()
    print("Created new empty 'containers.txt'")
end

parallel.waitForAll(processEvents)