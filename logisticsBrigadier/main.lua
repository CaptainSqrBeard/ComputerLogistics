local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")

local knownRecipes = {}
local knownRecipesReferences = {}

local trackedItems = {}
local promisedItems = {}
local supportedItems = {}

local spawnNewParallel
local timerItemSupport

local PROTOCOL = logisticsHelper.PROTOCOL

local function commandRequestItem(id, repeats)
    local result = requestItem(id, repeats)
    if result then
        return csecureNet.responses.success
    end
    return csecureNet.responses.cannot_provide
end

local function respondToCommand(verifiedMessage, msg, usedModem, replyChannel)
    local requestId = csecureNet.getHeaderValue(msg, "requestId")
    local type = verifiedMessage.message.type

    if type == "ping" then
        csecureNet.sendRespond(csecureNet.responses.success, PROTOCOL, requestId, usedModem, replyChannel)
    elseif type == "requestItem" then
        csecureNet.sendRespond(csecureNet.responses.processing, PROTOCOL, requestId, usedModem, replyChannel)

        local result = commandRequestItem(verifiedMessage.message.id, verifiedMessage.message.repeats)
        csecureNet.sendRespond(result, PROTOCOL, requestId, usedModem, replyChannel)
    end
end

local function requestItem(id, repeats)
    local recipe = knownRecipesReferences[id]

    if recipe == nil then
        return false
    end

    local message, header = logisticsHelper.buildCrafterCraftRequest(recipe.crafter, repeats, recipe.crafterData)

    local signedPingMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedPingMessage)

    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)

    if respond == csecureNet.responses.processing then
        local promise = repeats * recipe.amount
        promiseItem(id, promise)

        while true do
            local processRespond, finalContext = csecureNet.awaitRespond(recipe.timeout, modem, PORT, header.requestId)
            if processRespond ~= csecureNet.responses.hold_it then
                promiseItem(id, -promise)
                return false
            elseif processRespond == csecureNet.responses.success then
                promiseItem(id, -promise)
                return true
            end
        end
    end
end

local function doItemSupport()
    -- Get tracked items
    local itemAmounts

    local message, header = logisticsHelper.buildGetItemsAmount(trackedItems)
    local signedPingMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedPingMessage)

    local respond = csecureNet.awaitRespond(5, modem, PORT)

    if respond == csecureNet.responses.processing then
        local finalRespond, finalContext = csecureNet.awaitRespond(5, modem, PORT)

        if finalRespond ~= csecureNet.responses.success then
            return -- Request failed
        end

        itemAmounts = finalContext
    else
        return -- Request failed
    end

    for i, supportedItem in ipairs(supportedItems) do
        local recipe = knownRecipesReferences[supportedItem.id]
        local amountInStorage = itemAmounts[supportedItem.id]
        if itemAmounts[supportedItem.id] + getPromiseItem(supportedItem.id) < supportedItem.amount then
            spawnNewParallel(function ()
                requestItem(supportedItem.id, math.ceil((supportedItem.amount - amountInStorage) / recipe.amount))
            end)
        end
    end
end

local function processEvents(spawn)
    spawnNewParallel = spawn

    while true do
        local eventData = {os.pullEvent()}
        local event = eventData[1]
        
        if event == "timer" then
            if eventData[2] == timerItemSupport then
                local success, errorMsg = pcall(function ()
                    -- Start new timer
                    timerItemSupport = os.startTimer(timeout)
                    doItemSupport()
                end)
                if not success then
                    print("Error in item support process:\n", errorMsg)
                end
            end
        elseif event == "modem_message" then
            local usedModem = peripheral.wrap(eventData[2])
            local usedPort = eventData[3]
            local replyChannel = eventData[4]
            local msg = eventData[5]
            local distance = eventData[6]

            if csecureNet.isValidMessage(msg) and csecureNet.getHeaderValue(msg, "protocol") == PROTOCOL and csecureNet.getHeaderValue(msg, "toRole") == logisticsHelper.ROLE_BRIGADIER then
                local receivedModem  = usedModem
                spawnNewParallel(function()
                    local verifiedMessage = csecureNet.processMessage(msg, receivedModem, replyChannel)
                    if verifiedMessage ~= nil then
                        local success, errorMsg = pcall(respondToCommand, verifiedMessage, msg, usedModem, replyChannel)

                        if not success then
                            csecureNet.sendRespond(csecureNet.responses.internal_server_error, PROTOCOL, verifiedMessage.publicKey, usedModem, replyChannel)
                            print("Error while running command!\n"..errorMsg)
                        end
                    end
                end)
            end
        end

        sleep(0.5)
    end
end

local function trackItem(id)
    for i, item in ipairs(trackedItems) do
        if item == id then
            return
        end
    end
    table.insert(trackedItems, id)
end

local function supportItem(id, amount)
    table.insert(supportedItems, {
        id = id,
        amount = amount
    })
end

local function requiresItem(id, amount)
    return {id = id, amount = amount}
end

local function addRecipe(id, amount, timeout, requires, crafter, crafterData)
    local recipe = {
        id = id,
        amount = amount,
        timeout = timeout,
        requires = requires,
        crafter = crafter,
        crafterData = crafterData
    }
    for i, required in ipairs(requires) do
        trackItem(required)
    end
    knownRecipesReferences[id] = recipe
    table.insert(knownRecipes, recipe)
end

local function promiseItem(id, amount)
    if promisedItems[id] == nil then
        promisedItems[id] = math.max(0, amount)
    else
        promisedItems[id] = math.max(0, promisedItems[id] + amount)
    end
end

local function getPromiseItem(id)
    if promisedItems[id] == nil then
        return 0
    else
        promisedItems[id] = math.max(0, promisedItems[id] + amount)
    end
end

local function initRecipes()
    local allFiles = fs.list("/recipes/")
    for i, filePath in ipairs(allFiles) do
        if string.sub(-5) == ".json" then
            local file = fs.open(filePath, "r")
            if file ~= nil then
                local content = file.readAll()
                local parsed = textutils.deserialize(content)
                
                if parsed ~= nil then
                    addRecipe(parsed.id, parsed.amount, parsed.timeout, parsed.requires, parsed.crafter, parsed.crafterData)
                end

                file.close()
            end 
        end
    end
end

initRecipes()

timerItemSupport = os.startTimer(timeout)
parallel.waitForAll(processEvents)