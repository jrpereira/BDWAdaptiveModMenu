package.path='Scripts/?.lua;'..package.path
local M=require('registrations')
local function file(name,path) return {__name=name,__absolute_path=path or name} end
local dmm={__name='DawnwalkerModMenu',__files={file('enabled.txt')},Scripts={__files={file('main.lua')}}}
local provider={__name='Consumer',__files={file('enabled.txt'),file('mod_settings.ini','consumer.ini')}}
local archived={__name='Archive',DawnwalkerModMenu=dmm,Consumer=provider}
local mods={__name='Mods',__absolute_path='Mods',__files={},Archive=archived}
IterateGameDirectories=function() return {Game={Binaries={Win64={ue4ss={Mods=mods}}}}} end
local reads=0
local original=io.open
io.open=function(path)
 reads=reads+1
 assert(path=='consumer.ini','unexpected archived/config read: '..path)
 return {read=function() return '[Mod]\nId=Consumer\nName=Consumer\n[Setting.Key]\nId=Key\nType=integer\nDecoration=keybind\nMinimum=0\nMaximum=254\nDefault=82\n' end,close=function() end}
end
local events={};local log=function(e) events[e]=true end
local result=M.discover(log)
assert(not result.dmmEligible and reads==0 and #result.decorations==0)
assert(events.DMM_DEPENDENCY_INACTIVE)
print('PASS archived DMM cannot activate discovery; no manifest reads when dependency absent')
mods.DawnwalkerModMenu=dmm;mods.Consumer=provider
result=M.discover(log)
assert(result.dmmEligible and reads==1 and result.manifests==1 and #result.decorations==1)
print('PASS enabled direct provider scanned once; nested archive manifest ignored')
provider.__files={file('mod_settings.ini','consumer.ini')};reads=0
result=M.discover(log)
assert(reads==1 and #result.configProviders==1 and #result.providerList==0 and #result.decorations==0)
print('PASS disabled direct provider remains available for config initialization without decoration')
dmm.__files={};reads=0
result=M.discover(log)
assert(not result.dmmEligible and reads==0)
print('PASS direct but disabled DMM leaves discovery inert')
io.open=original
