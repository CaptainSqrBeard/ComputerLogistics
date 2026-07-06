local csecureNet
local logisticsHelper = require("logisticsHelper")

local PROTOCOL = "csLogistics"
local NOTIFY_QUEUE_DELAY = 10
local module = {}

local queue = {}
local notifyQueueTimer = {}

local function respondToCommand(verifiedMessage, msg, usedModem, replyChannel)
    local requestId = csecureNet.getHeaderValue(msg, "requestId")
    local type = verifiedMessage.message.type

    if type == "ping" then
        csecureNet.sendRespond(csecureNet.responses.success, PROTOCOL, requestId, usedModem, replyChannel)
    elseif type == "craft" then
        csecureNet.sendRespond(csecureNet.responses.processing, PROTOCOL, requestId, usedModem, replyChannel)
        addToQueue(csecureNet.message.crafterData, csecureNet.message.amount, requestId, usedModem, replyChannel)
    end
end

local function addToQueue(crafterData, amount, requestId, usedModem, replyChannel)
    table.insert(queue, {
        amount = amount,
        crafterData = crafterData,
        requestId = requestId,
        usedModem = usedModem,
        replyChannel = replyChannel,
    })
end

local function doQueueNotify()
    for i, entry in ipairs(queue) do
        csecureNet.sendRespond(csecureNet.responses.hold_it, PROTOCOL, entry.requestId, entry.usedModem, entry.replyChannel)
    end
end

local function processCrafting()
    while true do
        local currentTask = queue[1]

        local craftResult
        local success, error = function()
            craftResult = module.crafterCraftProcessor(currentTask)
        end

        if not success then
            csecureNet.sendRespond(csecureNet.responses.internal_server_error, PROTOCOL, currentTask.requestId, currentTask.usedModem, currentTask.replyChannel)
        elseif craftResult then
            csecureNet.sendRespond(csecureNet.responses.success, PROTOCOL, currentTask.requestId, currentTask.usedModem, currentTask.replyChannel)
        else
            csecureNet.sendRespond(csecureNet.responses.cannot_provide, PROTOCOL, currentTask.requestId, currentTask.usedModem, currentTask.replyChannel)
        end

        table.remove(queue, 1)
        sleep(0.5)
    end
end

local function processEvents(spawn)
    spawnNewParallel = spawn

    while true do
        local eventData = {os.pullEvent()}
        local event = eventData[1]
        
        if event == "timer" then
            if eventData[2] == notifyQueueTimer then
                local success, errorMsg = pcall(function ()
                    notifyQueueTimer = os.startTimer(NOTIFY_QUEUE_DELAY)
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

            if csecureNet.isValidMessage(msg) and csecureNet.getHeaderValue(msg, "protocol") == PROTOCOL and csecureNet.getHeaderValue(msg, "toRole") == logisticsHelper.ROLE_CRAFTER then
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

function module.initCrafter(type, craftProcessor)
    secureNet = require("csecureNet")
    module.secureNet = secureNet
    module.crafterType = type
    module.crafterCraftProcessor = craftProcessor
    
    notifyQueueTimer = os.startTimer(NOTIFY_QUEUE_DELAY)
    parallel.waitForAll(processEvents, processCrafting)
end