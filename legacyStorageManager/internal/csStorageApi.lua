local module = {}

local expect = require("cc.expect")
local csFuncs = require("internal.csFuncs")

function module.searchByString(searchIn, filter, update)
    expect(1, filter, "string")
    expect(2, update, "function", "nil")
    
    local name = filter:lower()

    if update ~= nil then
        return module.searchWithCustomHandler(searchIn, function(item)
            return item.prettyName:find(name) ~= nil
        end, update)
    else
        return module.search(searchIn, function(item)
            return item.prettyName:find(name) ~= nil
        end)
    end
end

function module.searchByMod(searchIn, filter, update)
    expect(1, filter, "string")
    expect(2, update, "function", "nil")
    
    local mod = filter:lower()

    if update ~= nil then
        return module.searchWithCustomHandler(searchIn, function(item)
            return item.mod:find(mod) ~= nil
        end, update)
    else
        return module.search(searchIn, function(item)
            return item.mod:find(mod) ~= nil
        end)
    end
end

function module.searchWithCustomHandler(searchIn, filter, update)
    expect(1, searchIn, "table")
    expect(2, filter, "function")
    expect(3, update, "function", "nil")

    -- local results = {}
    -- local items = module.getAllItems(searchIn);    

    local items = {}
    local total_amount = 0

    for _, inventory in ipairs(searchIn) do
        local contents = peripheral.wrap(inventory).list()

        for slot, item in pairs(contents) do
            total_amount = total_amount + item.count

            item.mod = item.name:gsub(":.*", "")
            item.prettyName = item.name:gsub(".*:", ""):gsub("_", " ")
            item.slot = slot
            item.inventory = inventory

            if filter(item) and update ~= nil then
                update(item)
            end 
        end
    end

    return total_amount
end

function module.search(searchIn, filter)
    expect(1, searchIn, "table")
    expect(2, filter, "function")
    local items = module.getAllItems(searchIn);
    local results = {}

    for inventory, contents in pairs(items.items) do
        for slot, item in pairs(contents) do
            item.mod = item.name:gsub(":.*", "")
            item.prettyName = item.name:gsub(".*:", ""):gsub("_", " ")

            if filter(item) then
                if results[item.name] == nil then
                    results[item.name] = {name=item.name, mod=item.mod, prettyName=item.prettyName, totalAmount=item.count, containedIn={{count=item.count, slot=slot, inventory=inventory}}}
                else
                    results[item.name].totalAmount = results[item.name].totalAmount + item.count
                    table.insert(results[item.name].containedIn, {count=item.count, slot=slot, inventory=inventory})
                end
            end
        end
    end

    return results, items.allItemsTotal
end

function module.getAllItemsCount(searchIn)
    expect(1, searchIn, "table")

    local total_amount = 0

    for _, inventory in ipairs(searchIn) do
        local contents = peripheral.wrap(inventory).list()
        for slot, item in pairs(contents) do
            total_amount = total_amount + item.count
        end
    end
    
    return total_amount
end

function module.dropItem(config, from, slot, count) 
    expect(1, config, "table")
    expect(2, from, "string")
    expect(3, slot, "number")
    expect(4, count, "number")

    if config.output_inventory ~= nil then
        return peripheral.wrap(from).pushItems(config.output_inventory, slot, count);
    end
    return
end

function module.pushMultipleItems(inputItemsFrom, to, count)
    expect(1, inputItemsFrom, "table")
    expect(2, to, "string")

    local amountOfPushedItems = 0
    local remainingTakeAmount = count

    for i, container in ipairs(inputItemsFrom) do 
        local takingFromThisContainer = math.min(remainingTakeAmount, container.count)
        if remainingTakeAmount ~= nil and remainingTakeAmount <= 0 then
            break
        end
        
        local result = peripheral.wrap(container.inventory).pushItems(to, container.slot, takingFromThisContainer);
        if result == nil then
            error("Destination inventory does not exist")
            break
        else
            remainingTakeAmount = remainingTakeAmount - result
            amountOfPushedItems = amountOfPushedItems + result
        end
    end

    return amountOfPushedItems
end

return module
