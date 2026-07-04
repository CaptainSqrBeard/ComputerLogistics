local module = {}

local expect = require("cc.expect")
local PROTOCOL = "csLogistics"

function module.buildPingMessage()
    return {
        type = "ping"
    }, {
        protocol = PROTOCOL
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
        protocol = PROTOCOL
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
        protocol = PROTOCOL
    }
end

function module.buildPullItems(fromContainer)
    expect(1, fromContainer, "string")

    return {
        type = "pullItems",
        fromContainer = fromContainer
    }, {
        protocol = PROTOCOL
    }
end

return module