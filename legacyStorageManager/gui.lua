-- Message
local messageTimerToken
local messageText
local messageColor

-- Keys
local isShifting = false

-- Colors
local warningColor = colors.gray

-- Search Info
local didSearchInThisSession = false
local searchResult = {}
local searchEntries = {}
local totalItems = 0
local takeAmount = 1
local takeAmountLimit = 256

-- Search bar
local searchBarString = ""
local searchBarFocus = true
local searchBarCursor = 0

local sizeX, sizeY
local searchBarSizeX
local searchBarStartX

-- List
local listSizeY
local listSizeX
local listStartX
local listStartY

local listCursor = 0
local listOffset = 0

local storageApi = require("internal.csStorageApi")
local csDrawUtils = require("internal.csDrawUtils")
local ccStrings = require("cc.strings")
local shared = require("internal.shared")

-- Config
local config = shared.loadConfig()

-- Stats
local statsTotalItemAmount = 0

-- Drawing
function redrawSearchBar()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.setCursorPos(searchBarStartX, searchBarStartY)
    term.write(ccStrings.ensure_width(searchBarString, searchBarSizeX+1))
    term.setCursorPos(searchBarStartX+searchBarCursor, searchBarStartY)
    term.setCursorBlink(searchBarFocus and searchBarCursor < searchBarSizeX)
end

function redrawMonitor()
    local monitor = peripheral.find("monitor")
    if monitor ~= nil then
        monitor.clear()
        monitor.setTextScale(0.5)
        monitor.setCursorPos(1, 1)
        monitor.write("Total:")
        monitor.setCursorPos(1, 2)
        monitor.write(""..statsTotalItemAmount)
        if currently_searching then
            monitor.setCursorPos(1, 4)
            monitor.write("Working...")
        end
    end
end

function redrawList()
    --csDrawUtils.outline(listStartX, listStartY, listSizeX-1, listSizeY, colors.black, colors.lightGray)

    i = 0
    while i < listSizeY do
        term.setCursorPos(listStartX, listStartY+i)
        -- text
        if (i + listOffset) % 2 == 0 then
            term.setTextColor(colors.lightGray)
        else
            term.setTextColor(colors.white)
        end
        
        -- background
        if i == listCursor-listOffset and not searchBarFocus then
            term.setBackgroundColor(colors.blue)
            term.setTextColor(colors.white)
        else
            term.setBackgroundColor(colors.black)
        end
        
        if #searchEntries > 0 then
            entry = searchResult[searchEntries[i+listOffset+1] ]
            if entry ~= nil then
                term.write(ccStrings.ensure_width(string.char(7).." x"..entry.totalAmount.." '"..entry.prettyName.."'", listSizeX))
            else
                term.write(ccStrings.ensure_width("", listSizeX))
            end
        else
            if i == 0 then
                if didSearchInThisSession then
                    term.setTextColor(colors.red)
                    term.write(ccStrings.ensure_width("Nothing found", listSizeX))
                else
                    term.write(ccStrings.ensure_width("Try searching for something!", listSizeX))
                end
            elseif i == 2 then
                term.setTextColor(colors.yellow)
                term.write("text", listSizeX)
                term.setTextColor(colors.lightGray)
                term.write(ccStrings.ensure_width(" - Search by item name", listSizeX-4))
            elseif i == 3 then
                term.setTextColor(colors.yellow)
                term.write("@text", listSizeX)
                term.setTextColor(colors.lightGray)
                term.write(ccStrings.ensure_width(" - Search by item namespace", listSizeX-5))
            else
                term.write(ccStrings.ensure_width("", listSizeX))
            end
        end
        
        i = i + 1
    end
end

function redrawHint()
    paintutils.drawFilledBox(1, 1, sizeX, searchBarStartY-2, colors.lightGray)
    
    term.setBackgroundColor(colors.lightGray)
    term.setTextColor(colors.gray)
    
    term.setCursorPos(searchBarStartX - 1, searchBarStartY-2)
    term.write("Search:")
    if searchBarFocus then
        if #searchEntries > 0 then
            csDrawUtils.writeRightAligned("[F1] Sort", searchBarStartX + searchBarSizeX + 2, 1)
            csDrawUtils.writeRightAligned("[Enter] Confirm, [Tab] List", searchBarStartX + searchBarSizeX + 2, 2)
        else
            csDrawUtils.writeRightAligned("[F1] Sort, [Enter] Confirm", searchBarStartX + searchBarSizeX + 2, 2)
        end
    else
        csDrawUtils.writeRightAligned("["..string.char(24).."/"..string.char(25).."] Select, ["..string.char(27).."/"..string.char(26).."] Amount (+Shift)", searchBarStartX + searchBarSizeX + 2, 1)
        csDrawUtils.writeRightAligned("[S]ort, [Enter] Pick, [Tab] Search", searchBarStartX + searchBarSizeX + 2, 2)
    end

    term.setCursorPos(searchBarStartX - 1, sizeY)
    term.write(ccStrings.ensure_width("Amount: x"..takeAmount))
    
    if messageText ~= nil then
        term.setTextColor(messageColor)
        csDrawUtils.writeRightAligned(messageText, searchBarStartX + searchBarSizeX + 2, sizeY)
    end 

    if messageText == nil then
        csDrawUtils.writeRightAligned(totalItems.." items for "..#searchEntries.." entries", searchBarStartX + searchBarSizeX + 2, sizeY)
    end
    
    restoreCursor()
end


function redrawGui()
    term.clear()

    paintutils.drawFilledBox(1, 1, sizeX, sizeY, colors.lightGray)

    csDrawUtils.outline(listStartX, listStartY, listSizeX-1, listSizeY, colors.black, colors.lightGray)
    csDrawUtils.outline(searchBarStartX, searchBarStartY, searchBarSizeX, 1, colors.black, colors.lightGray)

    term.setCursorPos(searchBarStartX, searchBarStartY)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)

    redrawList()
    redrawHint()
    redrawSearchBar()
end



-- Interactions
function ensureListOffset()
    if listCursor-listOffset >= listSizeY then
        listOffset = listCursor-listSizeY+1
    elseif listCursor-listOffset < 0 then
        listOffset = listCursor
    end
end

function focusSearchBar()
    searchBarFocus = true

    redrawList()
    redrawHint()
    redrawSearchBar()
end

function unfocusSearchBar()
    searchBarFocus = false

    redrawList()
    redrawHint()
    redrawSearchBar()
end

function showMessage(text, color, time)
    messageText = text
    messageColor = color
    redrawHint()
    messageTimerToken = os.startTimer(time)
end


-- Sort firstly by name, then by amount 
function sortList(prompt) 
    table.sort(searchEntries, function(a, b) 
        local a_pretty = searchResult[a].prettyName:sub(1, #prompt) == prompt
        local b_pretty = searchResult[b].prettyName:sub(1, #prompt) == prompt

        if a_pretty == b_pretty then
            return searchResult[a].totalAmount > searchResult[b].totalAmount
        elseif a_pretty then
            return true
        elseif b_pretty then
            return false
        end
    end)
end

function createFunction(func, ...) 
    local packed = {...}
    return function () func(table.unpack(packed)) end
end

local currently_searching = false
function search(prompt)
    if currently_searching then 
        -- please do not the cat!!! 
        return false
    end

    currently_searching = true

    search_start = os.clock()

    didSearchInThisSession = true

    paintutils.drawFilledBox(listStartX, listStartY, listSizeX+listStartX-1, listSizeY+listStartY-1, colors.black)
    term.setCursorPos(listStartX+listSizeX/2-6, listStartY+listSizeY/2)
    term.setTextColor(colors.white)
    term.write("Searching...")

    listCursor = 0
    listOffset = 0
    takeAmount = 1  

    totalItems = 0

    searchEntries = {}

    searchResult = {}

    showMessage("Searching...", colors.white, 5)
    local changedFocus = false

    -- Local function because changes local parameters
    function processSearchResult(item) 
        if searchResult[item.name] == nil then
            searchResult[item.name] = {name=item.name, mod=item.mod, prettyName=item.prettyName, totalAmount=item.count, containedIn={{count=item.count, slot=item.slot, inventory=item.inventory}}}
            table.insert(searchEntries, item.name)

            if searchBarFocus and not changedFocus then
                unfocusSearchBar()
                changedFocus = true
            end
        else
            searchResult[item.name].totalAmount = searchResult[item.name].totalAmount + item.count
            table.insert(searchResult[item.name].containedIn, {count=item.count, slot=item.slot, inventory=item.inventory})
        end
        
        totalItems = totalItems + item.count
        
        sortList(prompt)
        redrawList()
        restoreCursor()
    end

    function updateProgress() 
        while true do
            -- Show progress    
            local stage = math.floor((os.clock() - search_start) * 10) % 4

            if stage == 0
                then showMessage("Searching -", colors.gray, 4)
                elseif stage == 1 then showMessage("Searching \\", colors.gray, 4)
                elseif stage == 2 then showMessage("Searching |", colors.gray, 4)
                elseif stage == 3 then showMessage("Searching /", colors.gray, 4) 
            end

            sleep(0.07)
        end
    end

    function doSearch() 
        if prompt:find("^@") ~= nil then 
            prompt = prompt:sub(2)
            local statsTotalItemAmount = storageApi.searchByMod(shared.getInventoriesToPull(config), prompt, processSearchResult)
        else
            local statsTotalItemAmount = storageApi.searchByString(shared.getInventoriesToPull(config), prompt, processSearchResult)
        end

        sortList(prompt)
    end

    parallel.waitForAny(updateProgress, doSearch)


    redrawList()
    redrawHint()
    redrawMonitor()
    restoreCursor()

    function doSearch() 
        if prompt:find("^@") ~= nil then 
            local statsTotalItemAmount = storageApi.searchByMod(shared.getInventoriesToPull(config), prompt:sub(2), processSearchResult)
        else
            local statsTotalItemAmount = storageApi.searchByString(shared.getInventoriesToPull(config), prompt, processSearchResult)
        end
    end

    search_end = os.clock()
    search_time = search_end - search_start
    search_time = math.floor(search_time * 10) / 10

    showMessage("Completed in "..(search_time).."s", colors.gray, 1)
    
    currently_searching = false

    return #searchEntries > 0
end

function restoreCursor()
    if searchBarFocus then
        term.setCursorPos(searchBarStartX+searchBarCursor, searchBarStartY)
        term.setTextColor(colors.white)
    end
end

function startSort() 
    showMessage("Sorting...", colors.gray, 3)

    if config.input_inventory ~= nil then
        local totalItemsAmount, sortedItemsAmount = shared.sort(config)

        if totalItemsAmount == nil then
            showMessage("Cannot find input inventory", colors.red, 3)
            return
        end

        if totalItemsAmount == sortedItemsAmount then
            showMessage("Sort complete!", colors.gray, 3)
        else
            showMessage("Sort complete partially", warningColor, 3)
        end
    else
        showMessage("Define input inventory with \"Cli\"", colors.red, 3)
    end
end

function pickSelectedEntry()
    -- Initialize
    local gotError = false
    local item = searchResult[searchEntries[listCursor+1]]

    -- Check for having output chest
    if config.output_inventory == nil then
        showMessage("Define output inventory with \"Cli\"", colors.red, 3)
        return
    end

    -- Prepare values
    local actuallyTakenAmount = 0
    local remainingTakeAmount = takeAmount

    -- Pick items
    if item ~= nil then
        actuallyTakenAmount = storageApi.pushMultipleItems(item.containedIn, config.output_inventory, takeAmount)
    end
    remainingTakeAmount = takeAmount - actuallyTakenAmount

    -- Change amount of that item
    searchResult[searchEntries[listCursor+1]].totalAmount = searchResult[searchEntries[listCursor+1]].totalAmount - actuallyTakenAmount 
    redrawList()

    -- If it took less than it required to, show message
    if remainingTakeAmount > 0 and not gotError then
        showMessage("Taking only "..takeAmount-remainingTakeAmount.." item(s)", colors.gray, 3)
    end

    -- Change values of stuff that count items
    totalItems = totalItems - actuallyTakenAmount
    statsTotalItemAmount = statsTotalItemAmount - actuallyTakenAmount
    redrawMonitor()
end

-- Events
function timerEvent(token)
    if token == messageTimerToken then
        messageText = nil
        messageColor = nil
        redrawHint()
    end
end

function resizeEvent()
    sizeX, sizeY = term.current().getSize()
    searchBarSizeX = sizeX-8
    searchBarStartX = 4
    searchBarStartY = 4

    listSizeY = sizeY-8
    listSizeX = sizeX-7
    listStartX = 4
    listStartY = 7

    if term.isColor() then
        warningColor = colors.orange
    else
        warningColor = colors.gray
    end

    redrawGui()
end

function charEvent(char)
    if searchBarFocus then
        searchBarString = string.sub(searchBarString, 0, searchBarCursor)..char..string.sub(searchBarString, searchBarCursor+1, -1)
        searchBarCursor = searchBarCursor + 1
        redrawSearchBar()
    end
end

function keyUpEvent(key)
    if key == keys.leftShift then
        isShifting = false
    end
end

function keyEvent(key)
    if key == keys.leftShift then
        isShifting = true
    elseif key == keys.f1 then
        startSort()
    end

    if searchBarFocus then
        if key == keys.left and searchBarCursor > 0 then
            searchBarCursor = searchBarCursor - 1
            redrawSearchBar()
        elseif key == keys.right and searchBarCursor < string.len(searchBarString) then
            searchBarCursor = searchBarCursor + 1
            redrawSearchBar()
        elseif key == keys.backspace and searchBarCursor > 0 then
            searchBarString = string.sub(searchBarString, 0, searchBarCursor-1)..string.sub(searchBarString, searchBarCursor+1, -1)
            searchBarCursor = searchBarCursor - 1
            redrawSearchBar()
        elseif key == keys.enter then
            parallel.waitForAny(createFunction(search, searchBarString), runEvents)
            if not focusSearchBar then
                redrawSearchBar()
            end
        elseif key == keys.tab and #searchEntries > 0 then
            unfocusSearchBar()
        end
    else
        if key == keys.tab then
            focusSearchBar()
        elseif key == keys.up and listCursor > 0 then
            listCursor = listCursor - 1
            ensureListOffset()
            redrawList()
        elseif key == keys.down and listCursor < #searchEntries-1 then
            listCursor = listCursor + 1
            ensureListOffset()
            redrawList()
        elseif key == keys.left and takeAmount > 1 then
            if isShifting then
                takeAmount = takeAmount - 16
                if takeAmount < 1 then
                    takeAmount = 1
                end
            else
                takeAmount = takeAmount - 1
            end
            redrawHint()
        elseif key == keys.right and takeAmount < takeAmountLimit then
            if isShifting then
                takeAmount = takeAmount + 16
                if takeAmount > takeAmountLimit then
                    takeAmount = takeAmountLimit
                elseif takeAmount == 17 then
                    takeAmount = 16
                end
            else
                takeAmount = takeAmount + 1
            end
            redrawHint()
        elseif key == keys.enter then
            pickSelectedEntry()
        elseif key == keys.s then
            startSort()
        end
    end
end

resizeEvent()

function updateTotalAmount() 
    showMessage("Updating...", colors.gray, 3)
    statsTotalItemAmount = storageApi.getAllItemsCount(shared.getInventoriesToPull(config))
    redrawMonitor()
end

function runEvents() 
    while true do
        local eventData = {os.pullEvent()}
        local event = eventData[1]
    
        if event == "mouse_click" then
            -- nothing
        elseif event == "mouse_scroll" then
            -- nothing
        elseif event == "key" then
            keyEvent(eventData[2])
        elseif event == "key_up" then
            keyUpEvent(eventData[2])
        elseif event == "char" then
            charEvent(eventData[2])
        elseif event == "term_resize" then
            resizeEvent()
        elseif event == "timer" then
            timerEvent(eventData[2])
        end
    end
end

parallel.waitForAll(updateTotalAmount, runEvents)