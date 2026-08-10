local expect = require("cc.expect")

local module = {}

function module.extractNamespace(id)
    expect(1, id, "string")

    return item.name:gsub(":.*", "")
end

function module.extractPrettyName(id)
    expect(1, id, "string")

    return item.name:gsub(".*:", ""):gsub("_", " ")
end

function module.searchByName(searchIn, thresholdAmount, filter, update)
    expect(1, searchIn, "table")
    expect(2, thresholdAmount, "number", "nil")
    expect(3, filter, "string")
    expect(4, update, "function", "nil")
    
    local name = filter:lower()
    
    local predicate = function(item)
        return module.extractPrettyName(item.id):find(name) ~= nil
    end

    if update ~= nil then
        return module.searchWithCustomHandler(searchIn, thresholdAmount, predicate, update)
    else
        return module.search(searchIn, predicate)
    end
end

function module.searchByMod(searchIn, thresholdAmount, filter, update)
    expect(1, searchIn, "table")
    expect(2, thresholdAmount, "number", "nil")
    expect(3, filter, "string")
    expect(4, update, "function", "nil")
    
    local mod = filter:lower()

    local predicate = function(item)
        return module.extractNamespace(item.id):find(mod) ~= nil
    end

    if update ~= nil then
        return module.searchWithCustomHandler(searchIn, thresholdAmount, predicate, update)
    else
        return module.search(searchIn, predicate)
    end
end

function module.searchByExactId(searchIn, thresholdAmount, id, update)
    expect(1, searchIn, "table")
    expect(2, thresholdAmount, "number", "nil")
    expect(3, id, "string")
    expect(4, update, "function", "nil")

    local predicate = function(item)
        return item.id == id
    end

    if update ~= nil then
        return module.searchWithCustomHandler(searchIn, thresholdAmount, predicate, update)
    else
        return module.search(searchIn, thresholdAmount, predicate)
    end
end

function module.searchWithCustomHandler(searchIn, thresholdAmount, filter, update)
    expect(1, searchIn, "table")
    expect(2, thresholdAmount, "number", "nil")
    expect(3, filter, "function")
    expect(4, update, "function", "nil")

    local totalFound = 0

    for _, inventory in ipairs(searchIn) do
        local contents = peripheral.wrap(inventory).list()

        for slot, item in pairs(contents) do
            local itemEntry = {
                id = item.name,
                amount = item.count,
                slot = slot,
                inventory = inventory
            }

            if filter(itemEntry) and update ~= nil then
                totalFound = totalFound + item.count
                update(itemEntry)
            end

            if thresholdAmount ~= nil and thresholdAmount <= totalFound then
                return totalFound
            end
        end
    end

    return totalFound
end

function module.getItemAmounts(searchIn, itemIds)
    local itemAmounts = {}
    for i, id in ipairs(itemIds) do
        itemAmounts[id] = 0
    end

    local totalFound = module.searchWithCustomHandler(searchIn, nil,
    function(item)
        for i, id in ipairs(itemIds) do
            if id == item.id then
                return true
            end
        end
        return false
    end,
    function(item)
        itemAmounts[item.id] = itemAmounts[item.id] + item.amount
    end)

    return itemAmounts, totalFound
end

function module.search(searchIn, thresholdAmount, filter)
    local foundEntries = {}

    local consumer = function (itemEntry)
        table.insert(foundEntries, itemEntry)
    end

    local totalFound = module.searchWithCustomHandler(searchIn, thresholdAmount, filter, consumer)

    return totalFound, foundEntries
end

function module.pushItems(itemEntries, targetContainer, targetSlot, amount, simulate)
    expect(1, itemEntries, "table")
    expect(2, targetContainer, "string")
    expect(3, targetSlot, "number", "nil")
    expect(4, amount, "number")
    expect(5, simulate, "boolean")

    local amountOfPushedItems = 0
    local remainingTakeAmount = amount

    for i, itemEntry in ipairs(itemEntries) do
        if remainingTakeAmount <= 0 then
            break
        end

        if itemEntry.amount > 0 then
            local result = module.moveItems(itemEntry.inventory, itemEntry.slot, targetContainer, targetSlot, remainingTakeAmount, simulate)
            if result ~= nil then
                itemEntry.amount = itemEntry.amount - result
                remainingTakeAmount = remainingTakeAmount - result
                amountOfPushedItems = amountOfPushedItems + result
            end
        end
        
    end

    return amountOfPushedItems
end

function module.pullItems(fromContainer, toContainers)
    expect(2, toContainers, "table")

    local itemAmount = 0
    local actuallyPulledItems = 0

    for slot, item in pairs(fromContainer.list()) do
        itemAmount = itemAmount + item.count

        local count = item.count
        for i, targetContainer in ipairs(toContainers) do
            if count > 0 then
                local pushedAmount = fromContainer.pushItems(targetContainer, slot, count)
                actuallyPulledItems = actuallyPulledItems + pushedAmount
                count = count - pushedAmount
            end
        end
    end

    return actuallyPulledItems, itemAmount
end

function module.moveItems(itemContainer, itemSlot, targetContainer, targetSlot, amount, simulated)
    expect(1, itemContainer, "string")
    expect(2, itemSlot, "number")
    expect(3, targetContainer, "string")
    expect(4, targetSlot, "number", "nil")
    expect(5, amount, "number")
    expect(6, simulated, "boolean")
    
    if simulated then
        local itemPeripheral = peripheral.wrap(itemContainer)
        local targetPeripheral = peripheral.wrap(targetContainer)

        local itemDetail = itemPeripheral.getItemDetail(itemSlot)

        local realAmount = amount
        if realAmount == nil then
            realAmount = itemDetail.count
        end

        local slotLimit = targetPeripheral.getItemLimit(targetSlot)
        if targetSlot ~= nil then
            local targetDetail = targetPeripheral.getItemDetail(targetSlot)

            if item == nil then
                return math.min(realAmount, slotLimit)
            else
                if item.id ~= targetDetail.id then
                    return 0
                end
                return math.min(realAmount, slotLimit - targetDetail.count)
            end
        else
            local leftAmount = realAmount
            local size = targetContainer.size()
            local itemList = targetContainer.list()
            for i = 1, size do
                if itemList == nil then
                    leftAmount = leftAmount - targetContainer.getItemLimit(i)
                else
                    leftAmount = leftAmount - math.min(slotLimit - targetDetail.count, leftAmount)
                end
                if leftAmount <= 0 then
                    return realAmount
                end
            end
            return realAmount - leftAmount
        end
    else
        return peripheral.wrap(itemContainer).pushItems(targetContainer, itemSlot, amount, targetSlot)
    end
end

return module