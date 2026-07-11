local module = {}
local expect = require("cc.expect")

local allConfigData = {}

local function toDesiredType(value, type, nullable)
    if value == "" and nullable then
        return nil, true
    elseif type == "number" then
        local num = tonumber(value)
        return num, num ~= nil
    elseif type == "string" then
        return value, true
    elseif type == "table" then
        local parsed = textutils.unserialize(value)
        return parsed, parsed ~= nil
    end

    return nil, false
end

function module.newParameter(config, id, defaultValue, ...)
    table.insert(allConfigData[config].parameterOrder, id)
    allConfigData[config].parameters[id] = {
        id=id,
        defaultValue=defaultValue,
        types={...}
    }
end

function module.initConfig(path)
    local publicConfig = {}
    local configData = {parameters={}, path=path, parameterOrder = {}}
    allConfigData[publicConfig] = configData
    return publicConfig
end

function module.processConfig(config)
    local configData = allConfigData[config]

    local askForNullable = true
    local file = fs.open(configData.path, "r")
    if file ~= nil then
        askForNullable = false
        local raw = file.readAll()
        local parsed = textutils.unserializeJSON(raw)
        if parsed ~= nil then
            for parameterKey, parameterValue in pairs(parsed) do
                local parameterType = type(parameterValue)
                for i, validType in ipairs(configData.parameters[parameterKey].types) do
                    if validType == parameterType then
                        config[parameterKey] = parameterValue
                        break
                    end
                end
            end
        end
        file.close()
    end

    local isFirstValue = true
    for i, id in ipairs(configData.parameterOrder) do
        local paramData = configData.parameters[id]
        if config[id] == nil then
            local isNullable = false

            for i, validType in ipairs(configData.parameters[id].types) do
                if validType == "nil" then
                    isNullable = true
                    break
                end
            end

            if not isNullable or isNullable and askForNullable then
                if isFirstValue then
                    isFirstValue = false
                    print("Configure:")
                end

                local defaultText = ""
                if paramData.defaultValue ~= nil then
                    defaultText = tostring(paramData.defaultValue)
                end

                write("> ("..table.concat(configData.parameters[id].types, ", ")..") "..id..": ")
                local value = read(nil, nil, nil, defaultText)

                local converted, success = toDesiredType(value, type(configData.parameters[id].types[1]), isNullable)

                if success then
                    if converted == nil and paramData.defaultValue == nil and not isNullable then
                        return false, "Value '"..id.."' cannot be nil!"
                    end
                    config[id] = converted
                else
                    config[id] = paramData.defaultValue
                end
            end
        end
    end

    local serialized = textutils.serializeJSON(config)

    local newFile = fs.open(configData.path, "w+")
    newFile.write(serialized)
    newFile.close()

    return true
end

return module