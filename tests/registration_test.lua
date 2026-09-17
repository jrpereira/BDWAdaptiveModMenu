package.path='Scripts/?.lua;'..package.path
local manifest='examples/ExampleMod/mod_settings.ini'
IterateGameDirectories=function()
    return {Game={Binaries={Win64={ue4ss={Mods={ExampleMod={
        __files={{__name='mod_settings.ini',__absolute_path=manifest}}
    }}}}}}}
end
local logs={}
local registry=require('registrations').discover(function(event) logs[#logs+1]=event end)
assert(registry.manifests==1 and #registry.decorations==1 and registry.modes==1)
local d=registry.decorations[1]
assert(d.providerId=='ExampleMod' and d.settingId=='Interact' and d.modeId=='InteractMode')
assert(d.minimum==0 and d.maximum==254)
assert(d.modeOptions[1]=='Tap' and d.modeOptions[2]=='Hold')
assert(require('registrations').get(registry,'ExampleMod','Interact')==d)
print('PASS documented manifest registers one keybind and its explicit decorated mode')
