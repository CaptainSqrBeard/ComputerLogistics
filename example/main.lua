---@diagnostic disable: unused-function
local csecureNet = require("csecureNet")
local logisticsHelper = require("logisticsHelper")

-- Default port
local PORT = 24869

-- Protocol name
local PROTOCOL = "csLogistics"

-- Open modem
local modem = peripheral.find("modem") or error("No modem attached", 0)
modem.open(PORT)
-- It's recommended to use wired modems in logistics setup as containers could be attached to them.
-- Wireless modems could be used too, but be sure that all used containers are attached to computer by wire.

-- Add authorized keys. Only messages signed with these keys will be accepted
csecureNet.importAuthorizedKeys("./authorizedKeys.txt")

-- Initialize networking. This function will also generate keypair if it doesn't exist
csecureNet.init()

-- 1. Sending ping message
local function pingMessage()
    -- Construct ping message
    local message, header = logisticsHelper.buildPingMessage()

    -- Sign message with our key. Note that these messages will expire in some time!
    local signedPingMessage = csecureNet.writeMessage(message, header)
    -- Note that this only prevents spoofing. Messages still could be read by anyone in the network

    -- Send our signed message
    modem.transmit(PORT, PORT, signedPingMessage)

    -- Wait for server respond. This will return one of csecureNet.responses or nil if server didn't respond
    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
    print("Ping respond:", respond)
    
    -- Possible responces
    -- [200] success - Request is fully complete
end

-- 2. Sending push items message / Move items from main storage to container
local function pushItemsMessage()
    -- Construct push items message
    local message, header = logisticsHelper.buildPushItemsMessage(true, -- This controls if request should be fully completable to be executed
        {
            logisticsHelper.buildInstruction("minecraft:stick", 1, "minecraft:crafter_0", 5), -- Put 1 stick in 5th slot of crafter
            logisticsHelper.buildInstruction("minecraft:stick", 1, "minecraft:crafter_0", 8), -- Put 1 stick in 8th slot of crafter
            logisticsHelper.buildInstruction("minecraft:diamond", 1, "minecraft:crafter_0", 1), -- Put 1 diamond in 1st slot of crafter
            logisticsHelper.buildInstruction("minecraft:diamond", 1, "minecraft:crafter_0", 2),
            logisticsHelper.buildInstruction("minecraft:diamond", 1, "minecraft:crafter_0", 3),

            logisticsHelper.buildInstruction("minecraft:iron_ingot", 10, "minecraft:chest_7"), -- Put 10 iron ingots in first available slot of chest
        }
    )

    -- Sign message with our key and send it.
    local signedPingMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedPingMessage)

    -- Server will first anounce that it started to process request.
    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
    print("First respond:", respond)

    -- Wait for final respond
    if respond == csecureNet.responses.processing then
        local finalRespond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        print("Final respond:", finalRespond)
    end

    -- Possible responces
    -- [309] cannot_provide - Storage doesn't have any required items/request cannot be fully completed
    -- [206] partial_content - Request is partially complete
    -- [200] success - Request is fully complete

    -- [500] internal_server_error - If error was caught during request process. This responce is possible for any command shown here.
    -- Fun fact: There is almost no server-side validation for messages. This responce could be very well be caused by invalid arguments in message.
end

-- 3. Sending get item message / Get how much of specified item is in storage 
local function getItemMessage()
    -- Construct pull items message
    local message, header = logisticsHelper.buildGetItemAmount("minecraft:diamond")

    -- Sign message with our key and send it.
    local signedPingMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedPingMessage)

    -- Server will first anounce that it started to process request.
    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
    print("Initial respond:", respond)

    -- If server started to process initial respond, then wait for final respond.
    if respond == csecureNet.responses.processing then
        -- This respond will have additional context: item amount
        local finalRespond, finalContext = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        print("Final respond:", finalRespond)
        print("Context:", finalContext)
    end
    
    -- Possible responces
    -- [200] success - Request is fully complete
end

-- 4. Sending pull items message / Move items from provided container to main storage
local function pullItemsMessage()
    -- Construct pull items message
    local message, header = logisticsHelper.buildPullItems("minecraft:chest_7")

    -- Sign message with our key and send it.
    local signedPingMessage = csecureNet.writeMessage(message, header)
    modem.transmit(PORT, PORT, signedPingMessage)

    -- Server will first anounce that it started to process request.
    local respond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
    print("Initial respond:", respond)

    -- Wait for final respond.
    if respond == csecureNet.responses.processing then
        local finalRespond = csecureNet.awaitRespond(5, modem, PORT, header.requestId)
        print("Final respond:", finalRespond)
    end
    
    -- Possible responces
    -- [200] success - Request is fully complete
    -- [206] partial_content - Request is partially complete
end