package.path='Scripts/?.lua;'..package.path
local Config=require('init_config')
local function fails(fn,pattern)
    local ok,err=pcall(fn)
    assert(not ok and tostring(err):find(pattern,1,true),tostring(err))
end
local choices={index=function(s,value) return type(value)=='number' and value>=0 and value<=255 end}
local migrated={{id='Primary',key='Primary',section='General',default=200},{id='Secondary',key='Secondary',section='General',default=200}}
Config.defaultSources('[Setting.Primary]\nId=Primary\nDefaultFrom=Legacy\n[Setting.Secondary]\nId=Secondary\nDefaultFrom=Legacy',migrated)
local migrationChoices={index=function(_,value) return type(value)=='number' and value>=50 and value<=1000 end}
assert(Config.merge('[General]\nLegacy=375\n',migrated,migrationChoices)=='[General]\nLegacy=375\nPrimary=375\nSecondary=375\n')
assert(Config.merge('[General]\nLegacy=375\nPrimary=250\n',migrated,migrationChoices)=='[General]\nLegacy=375\nPrimary=250\nSecondary=375\n')
assert(Config.merge(nil,migrated,migrationChoices)=='[General]\nPrimary=200\nSecondary=200\n')
fails(function() Config.merge('[General]\nLegacy=9999\n',migrated,migrationChoices) end,'outside destination')
local settings={
    {key='Key',section='Bindings',default=82,file='config.ini'},
    {key='Mode',section='Bindings',default=1,file='config.ini'},
    {key='Enabled',section='General',default=1,file='config.ini'},
}
local merged=Config.overlay({a=true,b=1,c='default',d=7},{a=false,b=0,c='',other=9})
assert(merged.a==false and merged.b==0 and merged.c=='' and merged.d==7 and merged.other==9)
assert(Config.merge(nil,settings,choices)=='[Bindings]\nKey=82\nMode=1\n[General]\nEnabled=1\n')
local partial=';personal\r\n[Bindings]\r\nKey = 0 ; unbound\r\nUnknown=abc\r\n[Other]\r\nUnrelated=false'
local complete=Config.merge(partial,settings,choices)
assert(complete==';personal\r\n[Bindings]\r\nKey = 0 ; unbound\r\nUnknown=abc\r\nMode=1\r\n[Other]\r\nUnrelated=false\r\n[General]\r\nEnabled=1\r\n')
assert(Config.merge(complete,settings,choices)==complete,'unchanged config must be byte-identical')
assert(Config.merge('[Bindings]\nKey=false\nMode=\n[General]\nEnabled=0\n',settings,choices)
    =='[Bindings]\nKey=false\nMode=\n[General]\nEnabled=0\n','merge must not filter existing values')
local global={{key='Key',default=82,file='config.ini'}}
assert(Config.merge('[Bindings]\nKey=0',global,choices)=='[Bindings]\nKey=0','unqualified key can live in a section')
assert(Config.merge('[Other]\nThing=2',global,choices)=='Key=82\n[Other]\nThing=2')
fails(function() Config.merge('[A]\nKey=1\n[B]\nKey=2',global,choices) end,'ambiguous')
fails(function() Config.merge('[Bindings]\nKey=0\nKey=1',settings,choices) end,'duplicate')
fails(function() Config.merge('[Bindings]\n[Bindings]',settings,choices) end,'duplicate config section')
fails(function() Config.merge('[Bad',settings,choices) end,'malformed')
fails(function() Config.merge('',{{key='Bad\nKey',default=0}},choices) end,'invalid ConfigKey')

local function memory(initial)
    local files={};for k,v in pairs(initial or {}) do files[k]=v end
    local fs={writes=0}
    function fs.read(path) return files[path] end
    function fs.write(path,text) fs.writes=fs.writes+1;files[path]=text end
    function fs.remove(path) files[path]=nil end
    function fs.rename(a,b) assert(files[a]~=nil,'source missing');assert(files[b]==nil,'destination exists');files[b]=files[a];files[a]=nil end
    return fs,files
end
local plan={path='config.ini',content=complete}
local fs,files=memory()
assert(Config.commit(plan,fs));assert(files['config.ini']==complete and fs.writes==1)
assert(not Config.commit({path=plan.path,original=complete,content=complete},fs) and fs.writes==1)
fs,files=memory({['config.ini']=partial})
plan.original=partial
assert(Config.commit(plan,fs));assert(files['config.ini']==complete and not files['config.ini.amm-init.bak'])
for _,phase in ipairs({'write','verify','backup','install'}) do
    fs,files=memory({['config.ini']=partial})
    local write,rename=fs.write,fs.rename
    if phase=='write' then fs.write=function(path,text) write(path,'partial');error('injected write') end
    elseif phase=='verify' then fs.write=function(path) write(path,'wrong bytes') end
    else fs.rename=function(a,b)
        if (phase=='backup' and b:match('%.bak$')) or (phase=='install' and a:match('%.tmp$')) then error('injected '..phase) end
        rename(a,b)
    end end
    assert(not pcall(Config.commit,plan,fs))
    assert(files['config.ini']==partial,'original must survive '..phase)
    assert(not files['config.ini.amm-init.tmp'])
end
fs,files=memory({['config.ini']=partial})
local write=fs.write
fs.write=function(path,text) write(path,text);files['config.ini']='external edit' end
fails(function() Config.commit(plan,fs) end,'changed during')
assert(files['config.ini']=='external edit')
fs,files=memory({['config.ini']=partial,['config.ini.amm-init.bak']='recovery'})
fails(function() Config.commit(plan,fs) end,'needs review')
assert(fs.writes==0 and files['config.ini.amm-init.bak']=='recovery')
fs,files=memory({['config.ini']=partial})
local rename=fs.rename
fs.rename=function(a,b)
    if a:match('%.tmp$') then files[b]='external edit';error('install failed') end
    rename(a,b)
end
fails(function() Config.commit(plan,fs) end,'rollback failed')
assert(files['config.ini']=='external edit' and files['config.ini.amm-init.bak']==partial)
fs,files=memory()
write=fs.write
fs.write=function(path,text) write(path,text);files['config.ini']='created externally' end
fails(function() Config.commit({path='config.ini',content='defaults'},fs) end,'changed during')
assert(files['config.ini']=='created externally' and not files['config.ini.amm-init.tmp'])

-- Plan validates paths and DMM compatibility before any writes, restoring its
-- private parser's fs even when DMM throws.
choices.parse=function() return settings end
choices.open=function() return {} end
local saved={};choices.fs=saved
fs,files=memory({['Mods/Example/config.ini']=partial})
local provider={id='Example',path='Mods/Example/mod_settings.ini'}
plan=Config.plan(provider,'schema',choices,fs)
assert(plan.content==complete and fs.writes==0 and choices.fs==saved)
settings[1].file='../outside.ini'
fails(function() Config.plan(provider,'schema',choices,fs) end,'invalid ConfigFile')
settings[1].file='config.ini'
choices.open=function() error('unsupported DMM') end
fails(function() Config.plan(provider,'schema',choices,fs) end,'unsupported DMM')
assert(choices.fs==saved and fs.writes==0)
choices.open=function() return {error='invalid user value'} end
fails(function() Config.plan(provider,'schema',choices,fs) end,'invalid user value')
assert(fs.writes==0)
choices.open=function() return {} end
for _,setting in ipairs(settings) do setting.file='nested/preferences.ini' end
local nested=Config.plan(provider,'schema',choices,fs)
assert(nested.path=='Mods/Example/nested/preferences.ini')

-- The DMM-owned wrapper initializes every ordinary provider, even when it has
-- no migration metadata. Test-only providers remain memory-only.
local ordinarySettings={{id='Enabled',kind='toggle',values={0,1},labels={'Off','On'},key='Enabled',section='General',default=1,file='config.ini'}}
local wrapped={}
function wrapped.parse() return ordinarySettings end
function wrapped.index(setting,value)
    for i,candidate in ipairs(setting.values or {}) do if candidate==value then return i end end
end
function wrapped.open(opened)
    if wrapped.fs then assert(wrapped.fs.read('Mods/Ordinary/config.ini')=='[General]\nEnabled=1\n') end
    return {provider=opened,items=opened.choices or {},error=nil}
end
fs,files=memory({['Mods/Ordinary/mod_settings.ini']='[Setting.Enabled]\nId=Enabled\n'})
assert(Config.install(wrapped,fs))
local ordinary={id='Ordinary',path='Mods/Ordinary/mod_settings.ini',choices=ordinarySettings}
assert(not wrapped.open(ordinary).error)
assert(files['Mods/Ordinary/config.ini']=='[General]\nEnabled=1\n','ordinary provider was not initialized')
local writes=fs.writes
wrapped.open({id='Test',path='missing',choices=ordinarySettings,testOnly=true})
assert(fs.writes==writes,'test-only provider touched configuration')
print('PASS in-state config planning preserves bytes, validates paths and recovers transactions')
