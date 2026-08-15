local csimpleConfig = require("csimpleConfig")
local cstorage = require("cstorage")

local spawnNewParallel

local cfg = csimpleConfig.initConfig("./config.json")
csimpleConfig.newParameter(cfg, "internalStorage", nil, "string")
csimpleConfig.newParameter(cfg, "trashStorage", nil, "string")
csimpleConfig.newParameter(cfg, "interfaceStorage", nil, "string")
csimpleConfig.newParameter(cfg, "relayControl", nil, "string")
csimpleConfig.newParameter(cfg, "relayControlSide", nil, "string")
csimpleConfig.newParameter(cfg, "relayInterface", nil, "string")
csimpleConfig.newParameter(cfg, "relayInterfaceSide", nil, "string")
csimpleConfig.newParameter(cfg, "plantSpace", 16^2, "number")
csimpleConfig.newParameter(cfg, "slotsKeptEmpty", 8, "number")
local success, error = csimpleConfig.processConfig(cfg)
if not success then
    print("Unable to process config:", error)
    return
end

local interfaceStoragePeripheral = peripheral.wrap(cfg.interfaceStorage) or error("Storage Interface is not attached")
local internalStoragePeripheral = peripheral.wrap(cfg.internalStorage) or error("Internal storage is not attached")
local relayInterfacePeripheral = peripheral.wrap(cfg.relayInterface) or error("Redstone relay for interface is not attached")
local relayControlPeripheral = peripheral.wrap(cfg.relayControl) or error("Redstone relay for control is not attached")

local timerStorageCheck
local availableSpace = internalStoragePeripheral.size()

local function endswith(text, ending)
    return ending == "" or text:sub(-#ending) == ending
end

local STORAGE_CHECK_DELAY = 20
local itemThresholds = {
    ["minecraft:stick"] = 64*4,
    ["minecraft:apple"] = 64*8,
    ["minecraft:birch_sapling"] = 64*4,
    ["minecraft:oak_sapling"] = 64*4,
}

local trackedItems = {}
for k, v in pairs(itemThresholds) do
    table.insert(trackedItems, k)
end

local function isOnThreshold(id)
    return itemThresholds[id] ~= nil
end

local function isSapling(id)
    return endswith(id, "sapling")
end

local function checkStorageSpace()
    local emptySlots = availableSpace

    for slot, item in pairs(internalStoragePeripheral.list()) do
        emptySlots = emptySlots - 1
    end

    local shouldBeEnabled = emptySlots > cfg.slotsKeptEmpty
    relayControlPeripheral.setOutput(cfg.relayControlSide, shouldBeEnabled)
end

local function collectResources()
    local itemAmounts = cstorage.getItemAmounts({cfg.internalStorage}, trackedItems)

    if interfaceStoragePeripheral.size() == 0 then
        return
    end

    local itemList = interfaceStoragePeripheral.list()
    if itemList == nil then
        return
    end

    local saplingsUnkept = cfg.plantSpace

    for slot, item in pairs(itemList) do
        local shouldBeKeeped = 0
        if isSapling(item.name) then
            shouldBeKeeped = math.min(item.count, saplingsUnkept)
        end

        local canTake = item.count - shouldBeKeeped
        
        if canTake > 0 then
            if isOnThreshold(item.name) then
                local freeSpace = itemThresholds[item.name] - itemAmounts[item.name]
                local toTake = math.min(canTake, freeSpace)
                local toTrash = canTake - toTake
                if toTake > 0 then
                    interfaceStoragePeripheral.pushItems(cfg.internalStorage, slot, toTake)
                end
                if toTrash > 0 then
                    interfaceStoragePeripheral.pushItems(cfg.trashStorage, slot, toTrash)
                end
            else
                interfaceStoragePeripheral.pushItems(cfg.internalStorage, slot, canTake)
            end
        end
    end

    os.cancelTimer(timerStorageCheck)
    timerStorageCheck = os.startTimer(STORAGE_CHECK_DELAY)
    checkStorageSpace()
end

local function processEvents(spawn)
    spawnNewParallel = spawn

    while true do
        local eventData = {os.pullEvent()}
        local event = eventData[1]
        
        if event == "redstone" then
            if relayInterfacePeripheral.getInput(cfg.relayInterfaceSide) then
                collectResources()
            end
        elseif event == "timer" then
            if eventData[2] == timerStorageCheck then
                timerStorageCheck = os.startTimer(STORAGE_CHECK_DELAY)
                checkStorageSpace()
            end 
        end
    end
end

checkStorageSpace()
timerStorageCheck = os.startTimer(STORAGE_CHECK_DELAY)

parallel.waitForAll(processEvents)