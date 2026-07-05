local module = {}

local expect = require("cc.expect")

module.PROTOCOL = "csLogistics"
module.ROLE_MAIN_STORAGE = "mainStorage"
module.ROLE_BRIGADIER = "brigadier"
module.ROLE_CRAFTER = "crafter"

function module.buildPingMessage()
    return {
        type = "ping"
    }, {
        protocol = module.PROTOCOL,
        toRole = module.ROLE_MAIN_STORAGE,
        requestId = math.random(10000000, 99999999)
    }
end

function module.buildPushItemsMessage(onlyFull, instructions)
    expect(1, onlyFull, "boolean")
    expect(2, instructions, "table")

    return {
        type = "moveItems",
        instructions = instructions,
        onlyFull = onlyFull
    }, {
        protocol = module.PROTOCOL,
        toRole = module.ROLE_MAIN_STORAGE,
        requestId = math.random(10000000, 99999999)
    }
end

function module.buildInstruction(id, amount, container, slot)
    expect(1, id, "string")
    expect(2, amount, "number")
    expect(3, container, "string")
    expect(4, slot, "number", "nil")
    
    return {id = id, amount = amount, container = container, slot = slot}
end

function module.buildGetItemAmount(id)
    expect(1, id, "string")

    return {
        type = "getItem",
        id = id
    }, {
        protocol = module.PROTOCOL,
        toRole = module.ROLE_MAIN_STORAGE,
        requestId = math.random(10000000, 99999999)
    }
end

function module.buildGetItemsAmount(id)
    expect(1, id, "string")

    return {
        type = "getItems",
        id = id
    }, {
        protocol = module.PROTOCOL,
        toRole = module.ROLE_MAIN_STORAGE,
        requestId = math.random(10000000, 99999999)
    }
end

function module.buildPullItems(fromContainer)
    expect(1, fromContainer, "string")

    return {
        type = "pullItems",
        fromContainer = fromContainer
    }, {
        protocol = module.PROTOCOL,
        toRole = module.ROLE_MAIN_STORAGE,
        requestId = math.random(10000000, 99999999)
    }
end

return module