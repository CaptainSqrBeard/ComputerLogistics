local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")

local knownRecipesReferences = {}
local trackedItems = {}

local spawnNewParallel
local timerItemSupport

local knownRecipes = {
    {
        id = "minecraft:iron_block",
        amount = 1,
        requires = {
            ["minecraft:iron_ingot"] = 9
        },
        crafter = "minecraft:craft",
        crafterData = {
            ingredients = {"minecraft:iron_ingot"},
            shape = {
                1,1,1,
                1,1,1,
                1,1,1,
            }
        }
    }
}

local supportedItems = {
    {
        id = "minecraft:iron_block",
        amount = 2
    }
}

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
end

local function requestItem(id, amount)
    
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
        local amountInStorage = itemAmounts[supportedItem.id]
        if itemAmounts[supportedItem.id] < supportedItem.amount then
            spawnNewParallel(function ()
                requestItem(supportedItem.id, supportedItem.amount - amountInStorage)
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
        end
        --[[
        if event == "modem_message" then
            local usedModem = peripheral.wrap(eventData[2])
            local usedPort = eventData[3]
            local replyChannel = eventData[4]
            local msg = eventData[5]
            local distance = eventData[6]

            if csecureNet.isValidMessage(msg) and csecureNet.getHeaderValue(msg, "protocol") == PROTOCOL and csecureNet.getHeaderValue(msg, "toRole") == logisticsHelper.ROLE_BRIGADIER then
                local receivedModem  = usedModem
                local verifiedMessage = csecureNet.processMessage(msg, receivedModem, replyChannel)
                if verifiedMessage ~= nil then
                    local success, errorMsg = pcall(respondToCommand, verifiedMessage, usedModem, replyChannel)

                    if not success then
                        csecureNet.sendRespond(csecureNet.responses.internal_server_error, PROTOCOL, verifiedMessage.publicKey, usedModem, replyChannel)
                        print("Error while running command!\n"..errorMsg)
                    end
                end
            end
        end
        ]]

        sleep(0.5)
    end
end

addRecipe("minecraft:iron_block", 1, {requiresItem("minecraft:iron_ingot", 9)}, "minecraft:craft",
    {
        ingredients = {"minecraft:iron_ingot"},
        shape = {
            1,1,1,
            1,1,1,
            1,1,1,
        }
    }
)

timerItemSupport = os.startTimer(timeout)
parallel.waitForAll(processEvents)