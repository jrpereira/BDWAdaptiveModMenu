package.path='Scripts/?.lua;'..package.path
local Choices=dofile(assert(os.getenv('DMM_CHOICES_PATH')))
local Navigation=require('navigation')
local InitConfig=require('init_config')
assert(Navigation.install(Choices))
local manifest=[[
[Mod]
Id=NavigationTest
[Category.Options]
kemHeading=0
[Setting.View]
Id=View
Type=picker
Label=View
Group=Options
PresetValues=0|1|2
PresetLabels=More|Primary|Secondary
Default=0
kemNavigation=1
kemType=tab
[Setting.Real]
Id=Real
Type=integer
Label=Real
Group=Options
Minimum=0
Maximum=10
Step=1
Default=4
ConfigFile=config.ini
ConfigSection=Settings
ConfigKey=Real
VisibleWhen=View
VisibleValues=1
]]
local items=Choices.parse(manifest)
assert(#items==2 and items[1].kemNavigation and not items[2].kemNavigation)
local path='/tmp/kem-navigation-test/config.ini'
local files={[path]='[Settings]\nReal=4\n'}
Choices.fs={
    read=function(p) return files[p] end,
    write=function(p,value) files[p]=value end,
    rename=function(a,b) assert(files[a]);files[b],files[a]=files[a],nil end,
    remove=function(p) files[p]=nil end,
}
local provider={id='NavigationTest',path='/tmp/kem-navigation-test/mod_settings.ini',choices=items}
local model=Choices.open(provider)
assert(not model.error,model.error)
assert(not model:dirty() and not model:visibility()[2])
model:set(1,1)
assert(not model:dirty() and model.pending[1]==1 and model:visibility()[2])
assert(model:apply() and files[path]=='[Settings]\nReal=4\n')
model:set(2,5)
assert(model:dirty())
local ok,why,event=model:apply()
assert(ok,why)
assert(files[path]=='[Settings]\nReal=5\n')
assert(event.values.Real==5 and event.values.View==nil and event.changes.View==nil)
assert(not model:dirty())
model:restore()
assert(model.pending[1]==1,'Restore must retain the navigation view')
model:reset()
assert(model.pending[1]==1 and model.committed[1]==1,
    'Reset must retain the current navigation view')
assert(model.pending[2]==4 and model:dirty(),
    'Reset must still reset persistent settings')
model:restore()
assert(model.pending[1]==1 and model.pending[2]==5 and not model:dirty())
local unsupported=manifest:gsub('%[Setting.View%]',
    '[Setting.Ignored]\nType=unsupported\nId=Ignored\n[Setting.View]')
local withIgnored=Choices.parse(unsupported)
assert(#withIgnored==2 and withIgnored[1].kemNavigation,
    'Unsupported settings ignored by DMM must not break navigation parsing')
local plan=assert(InitConfig.plan(provider,manifest,Choices,Choices.fs,items))
assert(not plan.content:find('View=',1,true),'config initialization must omit navigation')
print('Navigation picker remains transient, controls visibility and never writes a config key')
