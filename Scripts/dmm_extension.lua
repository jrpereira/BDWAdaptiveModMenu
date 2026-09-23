-- Loaded by DawnwalkerModMenu's extension loader inside DMM's Lua state.
-- Keep this file self-contained: the ordinary KEngineMenu mod runs in a different state.
local source=assert(debug.getinfo(1,'S').source,'extension source unavailable')
local directory=assert(source:match('^@(.+[\\/])[^\\/]+$'),'extension directory unavailable')

local function module(name)
    local chunk,err=loadfile(directory..name..'.lua')
    assert(chunk,err)
    local value=chunk()
    assert(type(value)=='table',name..' did not return a module')
    return value
end

return {
    id='KEngineMenu',
    apiVersion=1,
    install=function(dmm)
        assert(type(dmm)=='table' and dmm.version==1,'unsupported DMM extension API')
        assert(type(dmm.choices)=='table' and type(dmm.controls)=='table' and type(dmm.pages)=='table',
            'DMM extension modules unavailable')
        local navigation=module('navigation')
        local mapped=module('mapped_presets')
        local presentation=module('presentation')
        local config=module('init_config')
        local lifecycle=module('dmm_lifecycle')
        assert(type(mapped.install)=='function','mapped preset installer unavailable')
        assert(type(presentation.install)=='function','presentation installer unavailable')
        assert(type(config.install)=='function','configuration installer unavailable')
        assert(type(dmm.events)=='table' and type(dmm.events.on)=='function','DMM lifecycle events unavailable')
        assert(type(lifecycle.publisher)=='function','lifecycle publisher unavailable')
        navigation.install(dmm.choices)
        mapped.install(dmm.choices,dmm.controls)
        presentation.install(dmm.choices,dmm.controls,dmm.pages)
        config.install(dmm.choices)
        local publisher=lifecycle.publisher(function(event,detail)
            print('[KEngineMenu] '..event..' '..tostring(detail or '')..'\n')
        end)
        for _,name in ipairs({'providerPrepared','providerRefreshed','hostClosing'}) do
            dmm.events:on(name,function(context) publisher:publish(name,context) end)
        end
        assert(ModRef and type(ModRef.SetSharedVariable)=='function','DMM extension handshake unavailable')
        ModRef:SetSharedVariable('KEM_DMM_Extension_v1.ready','1')
    end,
}
