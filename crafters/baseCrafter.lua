local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")

local PROTOCOL = "csLogistics"
local NOTIFY_QUEUE_DELAY = 10
local EMPTY_CRAFT_THREAD = {}

local module = {}

local craftThreadsAmount = 1
local craftThreads = {EMPTY_CRAFT_THREAD}

local craftQueue = {}

local notifyQueueTimer

local modem
local isActive = false
local spawnNewParallel

local function putIntoThread(entry)
    for i = 1, craftThreadsAmount do
        if craftThreads[i] == EMPTY_CRAFT_THREAD then
            craftThreads[i] = entry

            spawnNewParallel(function()
                print("Crafting on thread #"..i)

                local craftResult
                local craftResultContext
                local success, error = pcall(function()
                    craftResult, craftResultContext = module.crafterCraftProcessor(entry, i)
                end)

                if not success then
                    print("#"..i..": Got crafting processor error:", error)
                    csecureNet.sendRespond(csecureNet.responses.internal_server_error, PROTOCOL, entry.requestId, entry.usedModem, entry.replyChannel)
                elseif craftResult ~= nil then
                    if craftResultContext ~= nil then
                        csecureNet.sendRespondWithContext(craftResult, craftResultContext, PROTOCOL, entry.requestId, entry.usedModem, entry.replyChannel)
                    else
                        csecureNet.sendRespond(craftResult, PROTOCOL, entry.requestId, entry.usedModem, entry.replyChannel)
                    end
                end

                craftThreads[i] = EMPTY_CRAFT_THREAD
            end)
            
            return true
        end
    end
    return false
end

local function processCrafting()
    if isActive then
        return
    end

    while craftQueue[1] ~= nil do
        isActive = true
        local currentTask = craftQueue[1]

        if (putIntoThread(currentTask)) then
            table.remove(craftQueue, 1)
        end

        sleep(0.5)
    end

    isActive = false
end

local function addToQueue(crafterData, repeats, requestId, usedModem, replyChannel)
    table.insert(craftQueue, {
        repeats = repeats,
        crafterData = crafterData,
        requestId = requestId,
        usedModem = usedModem,
        replyChannel = replyChannel,
    })
    spawnNewParallel(processCrafting)
end

local function respondToCommand(verifiedMessage, msg, usedModem, replyChannel)
    local requestId = csecureNet.getHeaderValue(msg, "requestId")
    local type = verifiedMessage.message.type

    if type == "ping" then
        csecureNet.sendRespond(csecureNet.responses.success, PROTOCOL, requestId, usedModem, replyChannel)
    elseif type == "craft" then
        csecureNet.sendRespond(csecureNet.responses.processing, PROTOCOL, requestId, usedModem, replyChannel)
        addToQueue(verifiedMessage.message.crafterData, verifiedMessage.message.repeats, requestId, usedModem, replyChannel)
    end
end

local function notifyCraft(entry)
    csecureNet.sendRespond(csecureNet.responses.hold_it, PROTOCOL, entry.requestId, entry.usedModem, entry.replyChannel)
    print("Notify for request", entry.requestId)
end

local function doQueueNotify()
    for i, entry in ipairs(craftQueue) do
        notifyCraft(entry)
    end

    for i = 1, craftThreadsAmount do
        local entry = craftThreads[i]
        if entry ~= EMPTY_CRAFT_THREAD then
            notifyCraft(entry)
        end
    end
end

local function processEvent(eventData)
    local event = eventData[1]
        
    if event == "timer" then
        if eventData[2] == notifyQueueTimer then
            local success, errorMsg = pcall(function ()
                notifyQueueTimer = os.startTimer(NOTIFY_QUEUE_DELAY)
                doQueueNotify()
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

        if csecureNet.isValidMessage(msg) and
            csecureNet.getHeaderValue(msg, "protocol") == PROTOCOL and
            csecureNet.getHeaderValue(msg, "toRole") == logisticsHelper.ROLE_CRAFTER and
            csecureNet.getHeaderValue(msg, "crafter") == module.crafterType
        then
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
end

local function processEvents(spawn)
    spawnNewParallel = spawn

    while true do
        local eventData = {os.pullEvent()}
        spawnNewParallel(function()
            processEvent(eventData)
        end)
    end
end

function module.initCrafter(type, craftProcessor, usedModem, port, threads)
    csecureNet.init()

    csecureNet.importAuthorizedKeys()
    csecureNet.requestAuthorizedKeys(usedModem, port)
    csecureNet.saveAuthorizedKeys()
    
    module.crafterType = type
    module.crafterCraftProcessor = craftProcessor
    modem = usedModem
    module.spawnNewParallel = spawnNewParallel

    craftThreadsAmount = threads
    for i = 1, threads do
        craftThreads[i] = EMPTY_CRAFT_THREAD
    end
    
    notifyQueueTimer = os.startTimer(NOTIFY_QUEUE_DELAY)
    print("Crafter with type '"..type.."' initialized! Available threads:", threads)

    parallel.waitForAll(processEvents, processCrafting)
end

return module