local module = {}
local expect = require("cc.expect")

local allConfigData = {}

local function toDesiredType(value, desiredType, nullable)
    if value == "" and nullable then
        return nil, true
    elseif desiredType == "number" then
        local num = tonumber(value)
        return num, num ~= nil
    elseif desiredType == "string" then
        return value, true
    elseif desiredType == "table" then
        local parsed = textutils.unserialize(value)
        return parsed, parsed ~= nil
    elseif desiredType == "boolean" then
        local lowerValue = string.lower(value)
        if lowerValue == "true" or lowerValue == "y" then
            return true, true
        elseif lowerValue == "false" or lowerValue == "n" then
            return false, true
        else
            return nil, false
        end
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

function module.newParameterWithPostFunc(config, id, defaultValue, postFunc, ...)
    table.insert(allConfigData[config].parameterOrder, id)
    allConfigData[config].parameters[id] = {
        id=id,
        defaultValue=defaultValue,
        postFunc=postFunc,
        types={...}
    }
end

function module.initConfig(path)
    local publicConfig = {}
    local configData = {parameters={}, path=path, parameterOrder = {}}
    allConfigData[publicConfig] = configData
    return publicConfig
end

function module.promptParameterValue(paramData, isNullable)
    local defaultText = ""
    if paramData.defaultValue ~= nil then
        defaultText = tostring(paramData.defaultValue)
    end

    write("> ("..table.concat(paramData.types, ", ")..") "..paramData.id..": ")
    local value = read(nil, nil, nil, defaultText)

    local converted, success = toDesiredType(value, paramData.types[1], isNullable)

    if success then
        if converted == nil and paramData.defaultValue == nil and not isNullable then
            return nil, "Value '"..id.."' cannot be nil!"
        end
        return converted
    else
        return paramData.defaultValue
    end
end

function module.processConfig(config)
    local configData = allConfigData[config]
    local toSerialize = {}

    local askForNullable = true
    local file = fs.open(configData.path, "r")
    if file ~= nil then
        askForNullable = false
        local raw = file.readAll()
        local parsed = textutils.unserializeJSON(raw, {parse_null = true})
        if parsed ~= nil then
            for i, paramId in ipairs(configData.parameterOrder) do
                local paramValue = parsed[paramId]
                if paramValue ~= nil then
                    if paramValue == textutils.json_null then
                        paramValue = nil
                    end
                    local paramData = configData.parameters[paramId]
                    local valueType = type(paramValue)
                    for i, validType in ipairs(configData.parameters[paramId].types) do
                        if validType == valueType then
                            if paramValue == nil then
                                toSerialize[paramId] = textutils.json_null
                            else
                                toSerialize[paramId] = paramValue
                            end
                            config[paramId] = paramValue
                            break
                        end
                    end
                    if paramData.postFunc ~= nil then
                        local success, postErrorMsg = paramData.postFunc(paramValue)
                        if not success then
                            file.close()
                            return false, postErrorMsg
                        end
                        paramData.postFunc = nil
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

            if isNullable and askForNullable or not isNullable then
                local value, errorMsg = module.promptParameterValue(paramData, isNullable)

                if errorMsg == nil then
                    if value == nil then
                        toSerialize[id] = textutils.json_null
                    else
                        toSerialize[id] = value
                    end
                    config[id] = value
                    if paramData.postFunc ~= nil then
                        local success, postErrorMsg = paramData.postFunc(value)
                        if not success then
                            return false, postErrorMsg
                        end
                    end
                else
                    return false, errorMsg
                end
            else
                toSerialize[id] = textutils.json_null
            end
        end
    end

    local serialized = textutils.serializeJSON(toSerialize)

    local newFile = fs.open(configData.path, "w+")
    newFile.write(serialized)
    newFile.close()

    return true
end

return module