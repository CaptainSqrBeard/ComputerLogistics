local csecureNet = require("csecureNet")

local PORT = 24869
local PROTOCOL = csecureNet.PROTOCOL
local modem = peripheral.find("modem") or error("No modem attached", 0)

local function respondToCommand(verifiedMessage, msg, usedModem, replyChannel)
    local requestId = csecureNet.getHeaderValue(msg, "requestId")
    local type = verifiedMessage.message.type

    if type == "ping" then
        csecureNet.sendRespond(csecureNet.responses.success, PROTOCOL, requestId, usedModem, replyChannel)
    elseif type == "getPublicKeys" then
        csecureNet.sendRespondWithContext(csecureNet.responses.success, csecureNet.authorizedKeys, PROTOCOL, requestId, usedModem, replyChannel)
    end
end

local function readEvent(eventData)
    local event = eventData[1]

    if event == "modem_message" then
        local usedModem = peripheral.wrap(eventData[2])
        local usedPort = eventData[3]
        local replyChannel = eventData[4]
        local msg = eventData[5]
        local distance = eventData[6]
    
        if csecureNet.isValidMessage(msg) and
            csecureNet.getHeaderValue(msg, "protocol") == PROTOCOL and
            csecureNet.getHeaderValue(msg, "toRole") == csecureNet.ROLE_CERTIFICATE_SERVER
        then
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

modem.open(PORT)
csecureNet.verbose = true
csecureNet.importAuthorizedKeys("./authorizedKeys.txt")
csecureNet.init()
print("Certificate server initialized!")

parallel.waitForAll(processEvents)