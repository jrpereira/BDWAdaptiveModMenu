package.path='Scripts/?.lua;'..package.path
package.loaded.widget_discovery={}
local DirtyLabels=require('dirty_labels')
local original=loadfile
local call
loadfile=function(...)
    call=table.pack(...)
    return function() return {initialize=function() end,provider=function() end} end
end
local errors={}
DirtyLabels.new(function(event,detail) errors[#errors+1]=event..':'..detail end,
    {dmmChoicesPath='C:\\Game\\ue4ss\\Mods\\DawnwalkerModMenu\\Scripts\\choices.lua'})
loadfile=original
assert(call and call.n==1,'localization load must pass only the rewritten path')
assert(call[1]=='C:\\Game\\ue4ss\\Mods\\DawnwalkerModMenu\\Scripts\\localization.lua')
assert(#errors==0,table.concat(errors,'\n'))
print('PASS DMM localization path does not leak gsub replacement count into loadfile mode')
