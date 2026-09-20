local loaded={}
local installs={}
local originalLoadfile=loadfile
debug.getinfo=function() return {source='@C:/Mods/ModMenuDecorator/Scripts/dmm_extension.lua'} end
loadfile=function(path)
    loaded[#loaded+1]=path
    local name=assert(path:match('([^/\\]+)%.lua$'))
    return function()
        return {install=function(...)
            installs[#installs+1]={name=name,args={...}}
        end}
    end
end
local extension=assert(originalLoadfile('Scripts/dmm_extension.lua'))()
assert(extension.id=='ModMenuDecorator' and extension.apiVersion==1 and type(extension.install)=='function')
local choices,controls,pages={},{},{}
extension.install({version=1,choices=choices,controls=controls,pages=pages})
assert(#loaded==3 and loaded[1]:match('mapped_presets%.lua$') and loaded[2]:match('presentation%.lua$') and loaded[3]:match('init_config%.lua$'))
assert(installs[1].args[1]==choices and installs[1].args[2]==controls)
assert(installs[2].args[1]==choices and installs[2].args[2]==controls and installs[2].args[3]==pages)
assert(installs[3].args[1]==choices)
assert(not pcall(extension.install,{version=2,choices=choices,controls=controls,pages=pages}))
assert(not pcall(extension.install,{version=1,choices=choices,controls=controls}))
print('PASS pure-Lua DMM extension loads owned modules in order and rejects incompatible APIs')
