local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")

local REQUEST_TIMEOUT = 20
local SUPPORT_DELAY = 20

local knownRecipes = {}
local knownRecipesReferences = {}

local knownItemAmounts = {}
local trackedItems = {}
local promisedItems = {}
local supportedItems = {}

local spawnNewParallel
local timerItemSupport

local SUPPORTED_ITEMS_PATH = "./supportedItems.json"
local RECIPES_PATH = "/recipes/"
local PORT = 24869
local PROTOCOL = logisticsHelper.PROTOCOL

local modem = peripheral.find("modem") or error("No modem attached", 0)
modem.open(PORT)

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
        return math.max(0, promisedItems[id])
    end
end

local function getPossibleCraftRepeats(threshold, recipe)
    local craftAmount = threshold

    for i, requiredItem in ipairs(recipe.requires) do
        local maxCrafts = math.floor(knownItemAmounts[requiredItem.id] / requiredItem.amount)
        craftAmount = math.min(craftAmount, maxCrafts)
    end

    return craftAmount
end

local function requestItem(id, repeats, repeatIfPartial, multiplier, repeatsQuota)
    local recipe = knownRecipesReferences[id]

    if recipe == nil then
        return false
    end

    local message, header, requestId = logisticsHelper.buildCrafterCraftRequest(recipe.crafter, repeats, recipe.crafterData)

    local signedPingMessage = csecureNet.writeMessage(message, header)

    modem.transmit(PORT, PORT, signedPingMessage)

    local respond = csecureNet.awaitRespond(5, modem, PORT, requestId)

    if respond == csecureNet.responses.processing then
        local promise = repeats * recipe.amount
        promiseItem(id, promise)

        local prettyAmount
        if multiplier ~= 1 then
            prettyAmount = (promise/multiplier).."x"..multiplier
        else
            prettyAmount = promise.."x"
        end

        -- Remove used resources for craft from available.
        for i, requiredItem in ipairs(recipe.requires) do
            knownItemAmounts[requiredItem.id] = knownItemAmounts[requiredItem.id] - requiredItem.amount * repeats
        end

        print("Requested "..id.." "..prettyAmount.." (#"..requestId.."). Now promised:", getPromiseItem(id))

        while true do
            local processRespond, finalContext = csecureNet.awaitRespond(REQUEST_TIMEOUT, modem, PORT, requestId)
            if processRespond == csecureNet.responses.success then
                promiseItem(id, -promise)
                print("Compeleted request for "..id.." "..prettyAmount..". Now promised: "..getPromiseItem(id))
                return true
            elseif processRespond == csecureNet.responses.partial_content then
                promiseItem(id, -promise)
                local missed
                if type(finalContext) == "table" and finalContext.missed ~= nil then
                    print("Partially completed request for "..id.." "..prettyAmount.." (Missed "..finalContext.missed.."x). Now promised: "..getPromiseItem(id))
                    missed = finalContext.missed
                else
                    print("Partially completed request for "..id.." "..prettyAmount..". Now promised: "..getPromiseItem(id))
                end
                
                if repeatIfPartial and missed ~= nil then
                    if repeatsQuota == nil then
                        repeatsQuota = math.ceil(repeats/multiplier)
                    end

                    local repeatsMade = repeats - math.ceil(missed/recipe.amount)
                    local nextQuota = repeatsQuota - repeatsMade
                    local craftAmount = getPossibleCraftRepeats(nextQuota * multiplier, recipe)

                    if nextQuota <= 0 then
                        return true
                    end

                    if craftAmount > 0 then
                        print("Repeating last partial request for", nextQuota*recipe.amount, "items")
                        requestItem(id, craftAmount, repeatIfPartial, multiplier, nextQuota)
                    end
                end
                return true
            elseif processRespond == csecureNet.responses.hold_it then
                --print("Notified about request for "..id.." "..prettyAmount.." (#"..requestId..")")
            else
                promiseItem(id, -promise)
                print("Failed request for "..id.." "..prettyAmount.." ("..tostring(processRespond)..")! Now promised: "..getPromiseItem(id))
                return false
            end
        end
    else
        print("Unable to request "..id..":", respond) 
    end
end

local function commandRequestItem(id, repeats)
    local result = requestItem(id, repeats, false, 1)
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

local function updateKnownItemAmounts()
    -- Get tracked items
    local message, header, requestId = logisticsHelper.buildGetItemsAmount(trackedItems)
    local signedPingMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedPingMessage)

    local respond = csecureNet.awaitRespond(5, modem, PORT, requestId)

    if respond == csecureNet.responses.processing then
        local finalRespond, finalContext = csecureNet.awaitRespond(5, modem, PORT, requestId)

        if finalRespond ~= csecureNet.responses.success then
            print("Failed to update known item amounts:", finalRespond)
            return false -- Request failed
        end

        knownItemAmounts = finalContext
    else
        print("Failed to update known item amounts:", respond, "(At request begin)")
        return false -- Request failed
    end

    return true
end

local function doItemSupport()
    if #supportedItems == 0 then
        return
    end

    -- Update known item amounts
    if not updateKnownItemAmounts() then
        print("Unable to begin item support as known item amounts failed to update")
        return
    end

    for i, supportedItem in ipairs(supportedItems) do
        local recipe = knownRecipesReferences[supportedItem.id]
        local amountInStorage = knownItemAmounts[supportedItem.id]
        if knownItemAmounts[supportedItem.id] + getPromiseItem(supportedItem.id) < supportedItem.amount then
            local requiredAmount = math.ceil((supportedItem.amount - amountInStorage) * supportedItem.multiplier)
            local craftRepeats = getPossibleCraftRepeats(requiredAmount, recipe)

            if craftRepeats > 0 then
                spawnNewParallel(function ()
                    requestItem(supportedItem.id, craftRepeats, supportedItem.repeatIfPartial, supportedItem.multiplier)
                end)
            end
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
                    timerItemSupport = os.startTimer(SUPPORT_DELAY)
                    spawnNewParallel(doItemSupport)
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
                            csecureNet.sendRespond(csecureNet.responses.internal_server_error, PROTOCOL, csecureNet.getHeaderValue(msg, "requestId"), usedModem, replyChannel)
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

local function supportItem(id, amount, multiplier, repeatIfPartial)
    if amount <= 0 then
        return
    end
    
    if multiplier == nil then
        multiplier = 1.0
    end
    if repeatIfPartial == nil then
        repeatIfPartial = false
    end

    local recipe = knownRecipesReferences[id]
    if recipe == nil then
        print("Cannot support item", id, "as it doesn't have recipe")
        return
    end

    table.insert(supportedItems, {
        id = id,
        amount = amount,
        multiplier = multiplier,
        repeatIfPartial = repeatIfPartial
    })
    
    trackItem(id)
    for i, required in ipairs(recipe.requires) do
        trackItem(required.id)
    end

    print("Supporting", amount, "items of", id)
end

local function requiresItem(id, amount)
    return {id = id, amount = amount}
end

local function addRecipe(id, amount, requires, crafter, crafterData)
    local recipe = {
        id = id,
        amount = amount,
        requires = requires,
        crafter = crafter,
        crafterData = crafterData
    }
    knownRecipesReferences[id] = recipe
    table.insert(knownRecipes, recipe)
    print("Added recipe '"..id.."' for crafter '"..crafter.."'")
end

local function initRecipes()
    print("Initializing recipes")
    local allFiles = fs.list(RECIPES_PATH)
    for i, filePath in ipairs(allFiles) do
        if string.sub(filePath, -5) == ".json" then
            local file, reason = fs.open(fs.combine(RECIPES_PATH, filePath), "r")
            if file ~= nil then
                local content = file.readAll()
                local parsed = textutils.unserializeJSON(content)
                file.close()
                
                if parsed ~= nil then
                    addRecipe(parsed.id, parsed.amount, parsed.requires, parsed.crafter, parsed.crafterData)
                else
                    print("Unable to parse recipe ", filePath)
                end
            else
                print("Cannot open file:", reason)
            end
        end
    end
end

local function initSupportedItems()
    print("Initializing supported items")
    local file, reason = fs.open(SUPPORTED_ITEMS_PATH, "r")
    if file ~= nil then
        local content = file.readAll()
        local parsed = textutils.unserializeJSON(content)
        file.close()

        if parsed ~= nil then
            for i, item in ipairs(parsed) do
                supportItem(item.id, item.amount, item.requestMultiplier, item.repeatIfPartial)
            end
        else
            print("Unable to parse supported items")
        end
    else
        print("Cannot open file:", reason)
    end
end

csecureNet.init()

csecureNet.importAuthorizedKeys()
csecureNet.requestAuthorizedKeys(modem, PORT)
csecureNet.saveAuthorizedKeys()

initRecipes()
initSupportedItems()

timerItemSupport = os.startTimer(SUPPORT_DELAY)
parallel.waitForAll(processEvents, doItemSupport)