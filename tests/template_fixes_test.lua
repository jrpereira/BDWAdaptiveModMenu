local template=dofile('templates/fixes.lua')

assert(template.collection==nil,'menu fixes template must not declare a collection')
assert(template.category=='menu.fixes','menu fixes template category changed')
assert(template.events==nil and template.subscribe==nil,
    'menu fixes template must not declare events')
assert(template.settings and template.settings.enabled==false,
    'menu fixes template must be disabled by default')

local eventRegistrations=0
local textLibrary={}
function textLibrary:IsValid() return true end
function textLibrary:Conv_StringToText(value) return value end
local callbacks=template.createCallbacks(function() end,{
    StaticFindObject=function() return textLibrary end,
    ExecuteWithDelay=function() end,
    RegisterHook=function() eventRegistrations=eventRegistrations+1 end,
})

assert(type(callbacks)=='table','menu fixes callback factory must return a table')
for _,name in ipairs({'afterReset','afterSetup','afterCreate','afterSelect'}) do
    assert(type(callbacks[name])=='function','missing menu fixes callback: '..name)
end
assert(eventRegistrations==0,'loading or preparing menu fixes must register no events')

print('PASS inert menu.fixes template defaults disabled and registers no events')
