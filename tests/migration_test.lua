package.path='Scripts/?.lua;'..package.path
local C=require('init_config')
local schema=[[
[Setting.Count]
Id=Count
DefaultFrom=OldCount
DefaultFromMap=0:1;1:2
[DefaultRule.PositionAlias]
Target=Position
SourceSection=New
SourceKey=Alias
[DefaultRule.PositionLegacy]
Target=Position
SourceSection=Old
SourceKey=Upper
SourceDefault=40
WhenAbsent=General/Role
WhenZero=Old/Swap
[DefaultRule.PositionFallback]
Target=Position
SourceSection=Old
SourceKey=Lower
SourceDefault=20
]]
local function settings()
    return {{id='Count',key='Count',section='General',default=2,file='config.ini',kind='picker'},
        {id='Role',key='Role',section='General',default=0,file='config.ini',kind='picker'},
        {id='Position',key='Position',section='New',default=20,file='config.ini',kind='slider'}}
end
local choices={index=function(s,v)
    if s.id=='Count' then return v==1 or v==2 end
    if s.id=='Role' then return v==0 or v==1 end
    return type(v)=='number' and v>=-1000 and v<=1000
end,snap=function(_,v) return math.floor(v) end}
local function merge(original,metadata)
    local s=settings();C.defaultSources(metadata or schema,s)
    return C.merge(original,s,choices)
end
local function fails(fn,needle)
    local ok,err=pcall(fn);assert(not ok and tostring(err):find(needle,1,true),tostring(err))
end
for _,role in ipairs({'', 'Role=0\n','Role=1\n'}) do
    for _,swap in ipairs({'','Swap=0\n','Swap=1\n','Swap=-2\n'}) do
        for _,old in ipairs({'','OldCount=0\n','OldCount=1\n'}) do
            local original=';personal\r\n[General]\n'..role..old..'[Old]\n'..swap..'Upper=-75\nLower=125\nUnknown=leave me\n'
            local result=merge(original)
            local expected=(role=='' and (swap=='' or swap=='Swap=0\n')) and -75 or 125
            assert(result:find('Position='..expected,1,true))
            assert(result:find('\nCount='..(old=='OldCount=0\n' and 1 or 2),1,true))
            assert(result:find('Unknown=leave me',1,true))
            assert(merge(result)==result,'migration must be byte-idempotent')
        end
    end
end
assert(merge('[General]\nRole=1\n[Old]\nSwap=broken\nLower=25\n'):find('Position=25',1,true))
assert(merge('[New]\nAlias=-12\n[Old]\nSwap=broken\n'):find('Position=-12',1,true))
assert(merge('[General]\nCount=1\nOldCount=broken\n[New]\nPosition=99\n[Old]\nSwap=broken\n'):find('Position=99',1,true))
assert(merge(nil):find('Position=40',1,true),'source-specific absent default')
fails(function() merge('[General]\nOldCount=7\n') end,'unmapped')
fails(function() merge('[General]\nOldCount=nan\n') end,'invalid numeric')
fails(function() merge('[Old]\nSwap=broken\n') end,'invalid numeric')
fails(function() merge('[Old]\nSwap=0.5\n') end,'integer')
fails(function() merge('[Old]\nUpper=1001\n') end,'outside destination')
fails(function() merge('[Old]\nUpper=1.5\n') end,'off step')
fails(function() merge('[Old]\nUpper=1\nUpper=2\n') end,'duplicate config key')
fails(function() merge('[Old]\n[Old]\n') end,'duplicate config section')
fails(function() merge(nil,schema..'UnknownField=2\n') end,'unknown DefaultRule field')
fails(function() merge(nil,schema..'not an assignment\n') end,'malformed DefaultRule')
fails(function() merge(nil,schema..'SourceDefault=5\n') end,'duplicate migration field')
fails(function() merge(nil,schema:gsub('0:1;1:2','0:1;0:2')) end,'duplicate DefaultFromMap')
fails(function() merge(nil,schema:gsub('Target=Position','Target=Missing')) end,'unknown DefaultRule target')
fails(function() merge(nil,schema..'[DefaultRule.PositionAlias]\nTarget=Position\n') end,'duplicate DefaultRule')

-- Exercise the owned open adapter including failure recovery and ordinary providers.
local files={['Mod/mod_settings.ini']=schema,['Mod/config.ini']='[General]\nOldCount=0\n'}
local writes,failWrite=0,false
local fs={read=function(p) return files[p] end,
    write=function(p,v) if failWrite then error('disk unavailable') end;writes=writes+1;files[p]=v end,
    rename=function(a,b) assert(files[a] and not files[b]);files[b]=files[a];files[a]=nil end,
    remove=function(p) files[p]=nil end}
choices.fs=fs
choices.parse=function() return settings() end
choices.open=function(provider)
    local m={}
    local base=assert(provider.path:match('^(.*)[/\\][^/\\]+$'))
    local text=choices.fs.read(base..'/config.ini') or ''
    m.value=tonumber(text:match('\nCount=(%d+)')) or 2
    function m:set(v) if not self.error then self.value=v end end
    function m:apply() if self.error then return false,self.error end;return true end
    return m
end
assert(C.install(choices,fs) and not C.install(choices,fs))
local provider={id='Example',path='Mod/mod_settings.ini',choices=choices.parse(schema)}
local model=choices.open(provider)
assert(not model.error and model.value==1 and model:apply() and writes==1)
assert(not choices.open(provider).error and writes==1)
files['Mod/config.ini']='[General]\nOldCount=7\n'
model=choices.open(provider)
assert(model.error:find('Configuration initialization failed',1,true) and not model:apply())
model:set(1);assert(model.value==2 and writes==1)
files['Mod/config.ini']='[General]\nOldCount=0\n';failWrite=true
model=choices.open(provider);assert(model.error and not model:apply())
assert(files['Mod/config.ini']=='[General]\nOldCount=0\n')
failWrite=false;assert(not choices.open(provider).error,'failed attempt must not poison subsequent opens')
files['Mod/mod_settings.ini']='[Setting.Count]\nId=Count\nDefaultFromMap=0:1\n'
provider.choices=choices.parse(files['Mod/mod_settings.ini'])
model=choices.open(provider);assert(model.error and not model:apply(),'malformed map-only declaration must fail closed')
files['Missing/metadata.ini']='[Setting.Unrelated]\n'
local before=writes
local unrelated={path='Missing/metadata.ini',choices=choices.parse(files['Missing/metadata.ini'])}
local unrelatedModel=choices.open(unrelated)
assert(not unrelatedModel.error,'ordinary provider initialization failed: '..tostring(unrelatedModel.error))
assert(writes==before+1 and files['Missing/config.ini'],'ordinary provider config was not created')
print('PASS declarative original-snapshot migration matrix, precedence, invalid inputs, idempotence and fail-closed provider recovery')
