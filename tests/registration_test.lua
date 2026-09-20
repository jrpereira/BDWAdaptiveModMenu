package.path='Scripts/?.lua;'..package.path
local manifest='examples/ExampleMod/mod_settings.ini'
IterateGameDirectories=function()
    return {Game={Binaries={Win64={ue4ss={Mods={DawnwalkerModMenu={__files={{__name='enabled.txt'}},Scripts={__files={{__name='main.lua'}}}},ExampleMod={
        __files={{__name='enabled.txt'},{__name='mod_settings.ini',__absolute_path=manifest}}
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

-- Duplicate providers must follow DMM's sorted-path, first-provider-wins rule.
local function file(name,path) return {__name=name,__absolute_path=path} end
local function mod(path) return {__files={file('enabled.txt'),file('mod_settings.ini',path)}} end
local mods={DawnwalkerModMenu={__files={file('enabled.txt')},Scripts={__files={file('main.lua')}}},
 Z=mod('b.ini'),A=mod('a.ini')}
IterateGameDirectories=function() return {Game={Binaries={Win64={ue4ss={Mods=mods}}}}} end
local function content(label,maximum,id,decoration)
 return '[Mod]\nId=Same\nName='..label..'\n[Setting.Key]\nId='..id..'\nType=integer\nLabel='..label..'\nDecoration='..decoration..'\nMinimum=0\nMaximum='..maximum..'\nDefault=75\n'
end
local manifests={['a.ini']=content('First',254,'Key','keybind'),['b.ini']=content('Second',127,'Key','keybind')}
local originalOpen=io.open
io.open=function(path) return {read=function() return assert(manifests[path]) end,close=function() end} end
local function discover()
 local duplicates=0
 local result=require('registrations').discover(function(event) if event=='DUPLICATE_PROVIDER_SKIPPED' then duplicates=duplicates+1 end end)
 assert(duplicates==1 and result.providers==1 and result.manifests==1 and #result.providerList==1)
 assert(result.providerModels.Same.path=='a.ini')
 return result
end
local result=discover()
assert(#result.decorations==1 and result.byProvider.Same.Key.maximum==254)
assert(result.byProvider.Same.Key.labels.First and not result.byProvider.Same.Key.labels.Second)
print('PASS duplicate Mod Id cannot overwrite first provider range or labels')
manifests['b.ini']=content('Second',127,'OtherKey','keybind')
result=discover()
assert(#result.decorations==1 and result.byProvider.Same.OtherKey==nil)
print('PASS duplicate provider settings cannot merge into first provider')
manifests['a.ini']=content('First',254,'Key','')
result=discover()
assert(#result.decorations==0 and result.byProvider.Same==nil)
print('PASS undecorated first provider still reserves its Mod Id')
manifests['a.ini']=content('First',254,'Key','')..'DecoType=keybind\n'
assert(#discover().decorations==1,'Canonical keybind overrides empty legacy metadata')
manifests['a.ini']=content('First',254,'Key','keybind')..'DecoType=tab\n'
assert(#discover().decorations==0,'Canonical type overrides legacy keybind registration')
print('PASS canonical DecoType registration and precedence')
local grouped='[Mod]\nId=Same\nName=Grouped\n'
for _,group in ipairs({'Primary','Secondary'}) do
 grouped=grouped..'[Category.'..group..']\nDecoLevel=4\n'
 for _,label in ipairs({'X','Y','Size','Opacity','Key'}) do
  grouped=grouped..'[Setting.'..group..label..']\nId='..group..label..'\nGroup='..group..'\nLabel='..label..'\nType=integer\nMinimum=0\nMaximum=254\nDefault=75\n'
  if label=='Key' then grouped=grouped..'DecoType=keybind\n' end
 end
end
manifests['a.ini']=grouped
result=discover()
assert(#result.providerList[1].choices==10 and #result.decorations==2)
for i,s in ipairs(result.providerList[1].choices) do
 assert(s.sourceIndex==i,'categories must not consume setting identity indices')
end
assert(result.byProvider.Same.PrimaryKey and result.byProvider.Same.SecondaryKey)
assert(not result.byProvider.Same.PrimaryKey.modeId and not result.byProvider.Same.SecondaryKey.modeId)
print('PASS grouped settings retain distinct IDs and schema order with repeated labels')
io.open=originalOpen
