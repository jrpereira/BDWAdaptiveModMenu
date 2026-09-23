local loaded={}
local installs={}
local shared={}
ModRef={SetSharedVariable=function(_,key,value) shared[key]=value end}
local originalLoadfile=loadfile
debug.getinfo=function() return {source='@C:/Mods/AdaptiveModMenu/Scripts/dmm_extension.lua'} end
loadfile=function(path)
    loaded[#loaded+1]=path
    local name=assert(path:match('([^/\\]+)%.lua$'))
    return function()
        if name=='dmm_lifecycle' then
            return {publisher=function() return {publish=function(_,event) installs[#installs+1]={name='publish',event=event} end} end}
        end
        return {install=function(...)
            installs[#installs+1]={name=name,args={...}}
        end}
    end
end
local extension=assert(originalLoadfile('Scripts/dmm_extension.lua'))()
assert(extension.id=='AdaptiveModMenu' and extension.apiVersion==1 and type(extension.install)=='function')
local choices,controls,pages={},{},{}
local callbacks={}
local events={on=function(_,name,callback) callbacks[name]=callback end}
extension.install({version=1,choices=choices,controls=controls,pages=pages,events=events})
assert(#loaded==5 and loaded[1]:match('navigation%.lua$') and loaded[2]:match('mapped_presets%.lua$')
 and loaded[3]:match('presentation%.lua$') and loaded[4]:match('init_config%.lua$')
 and loaded[5]:match('dmm_lifecycle%.lua$'))
assert(installs[1].args[1]==choices)
assert(installs[2].args[1]==choices and installs[2].args[2]==controls)
assert(installs[3].args[1]==choices and installs[3].args[2]==controls and installs[3].args[3]==pages)
assert(installs[4].args[1]==choices)
for _,name in ipairs({'providerPrepared','providerRefreshed','hostClosing'}) do
 assert(type(callbacks[name])=='function');callbacks[name]({});assert(installs[#installs].event==name)
end
assert(shared['AMM_DMM_Extension_v1.ready']=='1')
assert(not pcall(extension.install,{version=2,choices=choices,controls=controls,pages=pages,events=events}))
assert(not pcall(extension.install,{version=1,choices=choices,controls=controls,events=events}))
print('PASS pure-Lua DMM extension loads owned modules in order and rejects incompatible APIs')
