local module = {}
local expect = require("cc.expect")

function module.icontains(table, object)
    expect(1, table, "table")
    for _, tableObject in ipairs(table) do
        if tableObject == object then
            return true
        end
    end
    return false
end

function module.contains(table, object)
    expect(1, table, "table")
    for _, tableObject in pairs(table) do
        if tableObject == object then
            return true
        end
    end
    return false
end

function module.containsKey(table, key)
    expect(1, table, "table")
    for k, _ in pairs(table) do
        if key == k then
            return true
        end
    end
    return false
end

return module