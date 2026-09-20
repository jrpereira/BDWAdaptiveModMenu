-- Loaded by DawnwalkerModMenu's extension loader inside DMM's Lua state.
-- Keep this file self-contained: the ordinary MMD mod runs in a different state.
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
    id='ModMenuDecorator',
    apiVersion=1,
    install=function(dmm)
        assert(type(dmm)=='table' and dmm.version==1,'unsupported DMM extension API')
        assert(type(dmm.choices)=='table' and type(dmm.controls)=='table' and type(dmm.pages)=='table',
            'DMM extension modules unavailable')
        local mapped=module('mapped_presets')
        local presentation=module('presentation')
        local config=module('init_config')
        assert(type(mapped.install)=='function','mapped preset installer unavailable')
        assert(type(presentation.install)=='function','presentation installer unavailable')
        assert(type(config.install)=='function','configuration installer unavailable')
        mapped.install(dmm.choices,dmm.controls)
        presentation.install(dmm.choices,dmm.controls,dmm.pages)
        config.install(dmm.choices)
    end,
}
