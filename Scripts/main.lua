local VERSION='0.1.19'
local Registrations=require('registrations')
local Binding=require('dmm_binding')
local function log(event,detail)
    if event:find('FAILED',1,true) or event:find('UNAVAILABLE',1,true) or event:find('EXCEPTION',1,true) then
        print(string.format('[ModMenuDecorator] %s %s\n',event,detail or ''))
    end
end
local registry=Registrations.discover(log)
if #registry.decorations==0 then return end
local ok,err=Binding.install(registry,log)
if not ok then log('DMM_BINDING_UNAVAILABLE',tostring(err));return end
print('[ModMenuDecorator] '..VERSION..' ready\n')
