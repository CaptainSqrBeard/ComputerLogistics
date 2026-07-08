local ed25519 = require("ccryptolib.ed25519")
local random = require("ccryptolib.random")
local base64 = require("cc.base64")
local expect = require("cc.expect")

local SECRET_KEY_PATH = "./client_secret.key"
local PUBLIC_KEY_PATH = "./client_public.key.temp"
local MAX_AGE_MS = 20000;

local module = {}

local secretKey
local secretKeyBase64

module.verbose = false
module.authorizedKeys = {}
module.requireAuthorizedKey = true

module.responses = {}
module.responses.processing = 100
module.responses.hold_it = 104

module.responses.success = 200
module.responses.partial_content = 206

module.responses.cannot_provide = 309

module.responses.bad_request = 400
module.responses.unauthorized = 401
module.responses.i_am_teapot = 418

module.responses.internal_server_error = 500
module.responses.not_implemented = 501

function module.init()
    random.initWithTiming()

    local file = fs.open(SECRET_KEY_PATH, "r")
    if file ~= nil then
        -- Use generated key pair
        local keyB64 = file.readAll()
        file.close()

        secretKey = base64.decode(keyB64)
        secretKeyBase64 = base64.encode(secretKey)

        module.publicKey = ed25519.publicKey(secretKey)
        module.publicKeyBase64 = base64.encode(module.publicKey)
    else
        -- Generate new key pair
        secretKey = random.random(32)
        secretKeyBase64 = base64.encode(secretKey)

        module.publicKey = ed25519.publicKey(secretKey)
        module.publicKeyBase64 = base64.encode(module.publicKey)

        local secretFile = fs.open(SECRET_KEY_PATH, "w")
        secretFile.write(base64.encode(secretKey))
        secretFile.close()
        
        local publicFile = fs.open(PUBLIC_KEY_PATH, "w")
        publicFile.write(base64.encode(module.publicKey))
        publicFile.close()

        print("Generated new key pair. Public key:\n"..base64.encode(module.publicKey))
    end
    if (module.verbose) then
        print("Public key: "..module.publicKeyBase64)
    end
end

function module.authorizeKey(publicKeyBase64)
    if (publicKeyBase64 == nil) then
        return false
    end
    table.insert(module.authorizedKeys, publicKeyBase64)
    return true
end

function module.importAuthorizedKeys(path)
    expect(1, path, "string")

    local file = fs.open(path, "r")
    if file ~= nil then
        while module.authorizeKey(file.readLine()) do end
        file.close()
    else
        print("WARNING. Provided path", path, "for authorized keys does not exist!")
    end
end

function module.readMessage(signedMessage)
    expect(1, signedMessage, "table")

    if (module.verbose) then
        print("Reading message from "..signedMessage.publicKey)
    end

    local verified = false;

    -- Listen keys
    if module.requireAuthorizedKey then
        local found = false
        for i, publicKey in ipairs(module.authorizedKeys) do
            if signedMessage.publicKey == publicKey then
                found = true;
                break
            end
        end
        if not found then
            if (module.verbose) then
                print("Cannot verify; Unauthorized public key")
            end
            return nil, module.responses.unauthorized
        end
    end

    local tryVerify = {pcall(function()
        local senderKey = base64.decode(signedMessage.publicKey)
        local messageSignature = base64.decode(signedMessage.signature)
        verified = ed25519.verify(senderKey, signedMessage.payload, messageSignature)
    end)}
    if not tryVerify then
        if (module.verbose) then
            print("Cannot verify; Error in verification: ".. textutils.tabulate(tryVerify))
        end
        return nil, module.responses.unauthorized -- cannot be verified
    end

    -- Sign is invalid
    if not verified then
        if (module.verbose) then
            print("Cannot verify; Invalid signature")
        end
        return nil, module.responses.unauthorized
    end

    local payload = textutils.unserializeJSON(signedMessage.payload)
    
    -- No signature time
    if payload.signTime == nil then
        if (module.verbose) then
            print("Cannot verify; No sign time")
        end
        return nil, module.responses.unauthorized
    end

    -- Expired message
    local time = os.epoch("utc")
    if payload.signTime < time - MAX_AGE_MS then
        if (module.verbose) then
            print("Cannot verify; Message is expired")
        end
        return nil, module.responses.unauthorized
    end
    
    if (module.verbose) then
        print("Verified message from "..base64.encode(signedMessage.publicKey))
    end

    return {
        publicKey = signedMessage.publicKey,
        message = payload.message
    }, module.responses.success
end

function module.writeMessage(message, header)
    expect(2, header, "table", "nil")

    if secretKey == nil then
        error("Attempted to write message without secret key. Is networking module initialized?", 1)
        return
    end

    local time = os.epoch("utc")

    local payload = {
        signTime = time,
        message = message
    }

    local jsonPayload = textutils.serializeJSON(payload)
    local signature = base64.encode(ed25519.sign(secretKey, module.publicKey, jsonPayload))

    local signedMessage = {
        header = header,
        payload = jsonPayload,
        publicKey = module.publicKeyBase64,
        signature = signature
    }

    return signedMessage
end

function module.isValidMessage(message)
    return (type(message.header) == "table" or message.header == nil) and
        type(message.payload) == "string" and
        type(message.publicKey) == "string" and
        type(message.signature) == "string"
end

function module.getHeaderValue(message, value)
    expect(2, value, "string")

    if type(message.header) ~= "table" then
        return
    end

    return message.header[value]
end

function module.sendRespond(statusCode, protocol, requestId, modem, port)
    expect(1, statusCode, "number")
    expect(2, protocol, "string", nil)
    expect(3, requestId, "number", nil)
    expect(5, port, "number")

    local respond = module.writeMessage({
            status = statusCode
        }, {
            protocol = protocol,
            requestId = requestId
        })
    modem.transmit(port, port, respond)

    if (module.verbose) then
        print("Send respond", statusCode, "to request #"..requestId)
    end
end

function module.sendRespondWithContext(statusCode, context, protocol, requestId, modem, port)
    expect(1, statusCode, "number")
    expect(3, protocol, "string")
    expect(4, requestId, "number")
    expect(6, port, "number")

    local respond = module.writeMessage({
            requestId = requestId,
            status = statusCode,
            context = context
        }, {
            protocol = protocol,
            requestId = requestId
        })
    modem.transmit(port, port, respond)

    if (module.verbose) then
        print("Send contexted respond", statusCode, "to request #"..requestId)
    end
end

function module.awaitRespond(timeout, modem, port, requestId)
    expect(1, timeout, "number", "nil")
    expect(3, port, "number")
    expect(4, requestId, "number")

    local timer
    if timeout ~= nil then
        timer = os.startTimer(timeout)
    end

    if (module.verbose) then
        print("Waiting respond to request #"..requestId..". Wait:", timeout)
    end

    while true do
        local eventData
        if timer ~= nil then
            eventData = {os.pullEvent()}
        else
            eventData = {os.pullEvent("modem_message")}
        end
        
        local event = eventData[1]

        if event == "modem_message" then
            local usedModem = eventData[2]
            local usedPort = eventData[3]
            local msg = eventData[5]

            if peripheral.getName(modem) == usedModem and
                port == usedPort and
                module.isValidMessage(msg) and
                module.getHeaderValue(msg, "requestId") == requestId
            then
                local verifiedMessage = module.readMessage(msg)
                if verifiedMessage ~= nil then
                    return verifiedMessage.message.status, verifiedMessage.message.context
                end
            end
        elseif event == "timer" then
            if eventData[2] == timer then
                return nil
            end
        end
    end
end

function module.processMessage(message, modem, port)
    local verifiedMessage, statusCode = module.readMessage(message)

    if verifiedMessage == nil then
        module.sendRespond(statusCode, module.getHeaderValue(message, "protocol"), module.getHeaderValue(message, "requestId"), modem, port)
        return
    end

    return verifiedMessage
end

return module