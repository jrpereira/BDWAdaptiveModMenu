local M = {}

-- Numeric representation used by the first consumer prototype: Windows virtual-key codes.
-- Unreal FKey names are mapped explicitly; unsupported keys return nil and never touch stock state.
local byName = {
    LeftMouseButton=0x01, RightMouseButton=0x02, MiddleMouseButton=0x04,
    ThumbMouseButton=0x05, ThumbMouseButton2=0x06,

    BackSpace=0x08, Tab=0x09, Enter=0x0D, SpaceBar=0x20,
    PageUp=0x21, PageDown=0x22, End=0x23, Home=0x24,
    Left=0x25, Up=0x26, Right=0x27, Down=0x28,
    Insert=0x2D, Delete=0x2E,

    Zero=0x30, One=0x31, Two=0x32, Three=0x33, Four=0x34,
    Five=0x35, Six=0x36, Seven=0x37, Eight=0x38, Nine=0x39,

    Backslash=0xDC,
}

for c=string.byte('A'),string.byte('Z') do byName[string.char(c)] = c end
for i=1,12 do byName['F'..i] = 0x6F + i end

local aliases = {
    Backspace='BackSpace', Space='SpaceBar', Spacebar='SpaceBar',
    LeftMouse='LeftMouseButton', RightMouse='RightMouseButton', MiddleMouse='MiddleMouseButton',
    Mouse4='ThumbMouseButton', Mouse5='ThumbMouseButton2',
    UpArrow='Up', DownArrow='Down', LeftArrow='Left', RightArrow='Right',
}

local byValue = {}
for name,value in pairs(byName) do
    if not byValue[value] then byValue[value]=name end
end

function M.toValue(name)
    if type(name)~='string' then return nil end
    name=aliases[name] or name
    return byName[name]
end

function M.toName(value)
    return byValue[tonumber(value)]
end

function M.supported(name)
    return M.toValue(name)~=nil
end

return M
