local module = {}

function module.outline(solidStartX, solidStartY, solidSizeX, solidSizeY, outlineColor, bgColor)
    -- left
    term.setBackgroundColor(outlineColor)
    term.setTextColor(bgColor)
    module.writeRepeatVertical(string.char(149), solidSizeY, solidStartX-1, solidStartY)

    -- left upper
    term.setCursorPos(solidStartX-1, solidStartY-1)
    term.write(string.char(159))
    
    -- upper
    module.writeRepeat(string.char(143), solidSizeX+1)
    term.setBackgroundColor(bgColor)
    term.setTextColor(outlineColor)

    -- right upper
    term.write(string.char(144))

    -- left below
    term.setCursorPos(solidStartX-1, solidStartY+solidSizeY)
    term.write(string.char(130))

    -- below
    module.writeRepeat(string.char(131), solidSizeX+1)

    -- right below
    term.write(string.char(129))
    
    -- right
    module.writeRepeatVertical(string.char(149), solidSizeY, solidStartX+solidSizeX+1, solidStartY)
end

function module.writeRightAligned(text, x, y) 
    term.setCursorPos(x - string.len(text), y)
    term.write(text)
end

function module.writeRepeatVertical(text, times, x, y)
    while times > 0 do
        times = times - 1
        term.setCursorPos(x, y+times)
        term.write(text)
    end
end

function module.writeRepeat(text, times)
    while times > 0 do
        term.write(text)
        times = times - 1
    end
end

return module