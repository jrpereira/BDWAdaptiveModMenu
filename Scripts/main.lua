local VERSION='0.2.24'
local Bootstrap=require('dmm_bootstrap')
local function log(event,detail)
    if event=='SELECTOR_DISABLED' or event=='DMM_REQUIRED' or event=='DMM_INCOMPATIBLE'
        or event=='DMM_RESTART_REQUIRED' or event=='DMM_DUPLICATE_INIT' or event=='DMM_PATCHED'
        or event=='ENABLEMENT_MIGRATION_FAILED'
        or event:find('FAILED',1,true) or event:find('UNAVAILABLE',1,true) or event:find('EXCEPTION',1,true) then
        print(string.format('[AdaptiveModMenu] %s %s\n',event,detail or ''))
    end
end
local initialized=false
local function initialize()
    if initialized then return true end
    local Binding=require('dmm_binding')
    local ok,err=Binding.install(log)
    if not ok then log('DMM_BINDING_UNAVAILABLE',tostring(err));return false end
    initialized=true
    print('[AdaptiveModMenu] '..VERSION..' ready\n')
    return true
end
Bootstrap.run(log,initialize)
