local Bootstrap=assert(loadfile('Scripts/dmm_bootstrap.lua'))()
local test=Bootstrap._test

local originals={['main.lua']='main-original',['controls.lua']='controls-original',['pages.lua']='pages-original'}
local accepted={}
local completed={}
local transforms={}
for name,content in pairs(originals) do
    accepted[name]=test.signature(content)
    transforms[name]=function(value) return value..'\npatched' end
    completed[name]=test.signature(content..'\npatched')
end

local function directoryTree(files,options)
    options=options or {}
    local entries={}
    for _,name in ipairs({'main.lua','controls.lua','pages.lua'}) do
        entries[#entries+1]={__name=name,__absolute_path='C:/DMM/Scripts/'..name}
    end
    local mods={__name='Mods',DawnwalkerModMenu={__name='DawnwalkerModMenu',Scripts={__name='Scripts',__files=entries}}}
    return {Game={__name='Game',Binaries={__name='Binaries',Win64={__name='Win64',ue4ss={__name='ue4ss',Mods=mods}}}}}
end

local function environment(seed,options)
    options=options or {}
    local files={}
    for path,value in pairs(seed or {}) do files[path]=value end
    local shared={}
    local scheduled={}
    local writes=0
    local renames=0
    local env={supported=accepted,patched=completed,patchers=transforms}
    env.directories=function() return directoryTree(files,options) end
    env.read=function(path) return files[path] end
    env.write=function(path,value)
        writes=writes+1
        if options.failWrite==writes then return nil,'injected write failure' end
        files[path]=options.corruptWrite==writes and 'corrupt stage' or value;return true
    end
    env.remove=function(path)
        files[path]=nil;return true
    end
    env.rename=function(source,target)
        renames=renames+1
        if options.requireAllStaged and renames==1 then
            for _,name in ipairs({'main.lua','controls.lua','pages.lua'}) do
                assert(files['C:/DMM/Scripts/'..name..test.newSuffix],name..' was not staged before backup movement')
            end
            assert(files['C:/DMM/Scripts/extension_events.lua'..test.newSuffix],'extension payload was not staged before backup movement')
        end
        if options.failRenameSource==source then return nil,'injected rename failure' end
        if files[source]==nil or files[target]~=nil then return nil,'rename rejected' end
        files[target]=files[source];files[source]=nil;return true
    end
    env.get=function(key) return shared[key] end
    env.set=function(key,value) shared[key]=value end
    env.schedule=function(_,callback) scheduled[#scheduled+1]=callback end
    return env,files,shared,scheduled
end

local function seedOriginals()
    local result={}
    for name,value in pairs(originals) do result['C:/DMM/Scripts/'..name]=value end
    return result
end

local function drain(scheduled,limit)
    for _=1,limit or 40 do
        if #scheduled==0 then return end
        table.remove(scheduled,1)()
    end
    assert(#scheduled==0,'scheduler did not settle')
end

do
    local seed=seedOriginals();seed['C:/Previous/enabled.txt']='enabled'
    local env,files=environment(seed)
    assert(Bootstrap.run(function() end,function() error('unexpected init') end,env)=='waiting')
    assert(files['C:/Previous/enabled.txt']=='enabled' and files['C:/Previous/deprecated.txt']==nil,
        'KEM must not migrate or disable a previous mod')
end

do
    local events={}
    local env=environment({})
    env.directories=function() return {Game={__name='Game'}} end
    assert(Bootstrap.run(function(name) events[#events+1]=name end,function() error('unexpected init') end,env)==false)
    assert(events[1]=='DMM_REQUIRED')
end

do
    local event
    local env=environment({})
    env.directories=function() return {bad='shape'} end
    assert(Bootstrap.run(function(name) event=name end,function() error('unexpected init') end,env)==false)
    assert(event=='DMM_REQUIRED')
end

do
    local seed=seedOriginals();seed['C:/DMM/Scripts/main.lua']='unknown'
    local env=environment(seed)
    local event
    assert(Bootstrap.run(function(name) event=name end,function() error('unexpected init') end,env)==false)
    assert(event=='DMM_INCOMPATIBLE')
end

do
    local env,files,shared,scheduled=environment(seedOriginals(),{requireAllStaged=true})
    local events={}
    assert(Bootstrap.run(function(name) events[#events+1]=name end,function() error('unexpected init') end,env)=='waiting')
    assert(events[1]=='DMM_PATCHED')
    for name,value in pairs(originals) do
        assert(files['C:/DMM/Scripts/'..name]==value..'\npatched')
        assert(files['C:/DMM/Scripts/'..name..test.backupSuffix]==value)
    end
    assert(files['C:/DMM/Scripts/extension_events.lua']==test.payload)
    drain(scheduled)
    assert(events[#events]=='DMM_RESTART_REQUIRED')
    assert(shared[test.claimKey]==nil)
end

do
    local seed=seedOriginals()
    local env,files=environment(seed,{failRenameSource='C:/DMM/Scripts/controls.lua'..test.newSuffix})
    local event,detail
    assert(Bootstrap.run(function(name,value) event,detail=name,value end,function() error('unexpected init') end,env)==false)
    assert(event=='DMM_PATCH_FAILED' and detail:find('rolled back',1,true))
    for name,value in pairs(originals) do assert(files['C:/DMM/Scripts/'..name]==value) end
    assert(files['C:/DMM/Scripts/extension_events.lua']==nil)
    for name in pairs(originals) do assert(files['C:/DMM/Scripts/'..name..test.newSuffix]==nil) end
    assert(files['C:/DMM/Scripts/extension_events.lua'..test.newSuffix]==nil)
end

do
    local seed=seedOriginals()
    local env,files=environment(seed,{failWrite=2})
    local event,detail
    assert(Bootstrap.run(function(name,value) event,detail=name,value end,function() error('unexpected init') end,env)==false)
    assert(event=='DMM_PATCH_FAILED' and detail:find('live files unchanged',1,true))
    for name,value in pairs(originals) do
        assert(files['C:/DMM/Scripts/'..name]==value and files['C:/DMM/Scripts/'..name..test.backupSuffix]==nil)
        assert(files['C:/DMM/Scripts/'..name..test.newSuffix]==nil)
    end
end

do
    local seed=seedOriginals()
    local env,files=environment(seed,{corruptWrite=2})
    local event,detail
    assert(Bootstrap.run(function(name,value) event,detail=name,value end,function() error('unexpected init') end,env)==false)
    assert(event=='DMM_PATCH_FAILED' and detail:find('live files unchanged',1,true))
    for name,value in pairs(originals) do
        assert(files['C:/DMM/Scripts/'..name]==value)
        assert(files['C:/DMM/Scripts/'..name..test.newSuffix]==nil,'failed verification leaked a stage')
    end
end

do
    local seed=seedOriginals()
    seed['C:/DMM/Scripts/main.lua']=nil
    seed['C:/DMM/Scripts/main.lua'..test.backupSuffix]=originals['main.lua']
    for name,value in pairs(originals) do seed['C:/DMM/Scripts/'..name..test.newSuffix]=value..'\npatched' end
    seed['C:/DMM/Scripts/extension_events.lua'..test.newSuffix]=test.payload
    local env,files=environment(seed)
    assert(Bootstrap.run(function() end,function() error('unexpected init') end,env)=='waiting')
    for name,value in pairs(originals) do
        assert(files['C:/DMM/Scripts/'..name]==value..'\npatched')
        assert(files['C:/DMM/Scripts/'..name..test.backupSuffix]==value)
        assert(files['C:/DMM/Scripts/'..name..test.newSuffix]==nil)
    end
    assert(files['C:/DMM/Scripts/extension_events.lua']==test.payload)
    assert(files['C:/DMM/Scripts/extension_events.lua'..test.newSuffix]==nil)
end

do
    local seed=seedOriginals()
    for name,value in pairs(originals) do seed['C:/DMM/Scripts/'..name]=value..'\npatched' end
    seed['C:/DMM/Scripts/extension_events.lua']=test.payload
    local env=environment(seed)
    local event
    assert(Bootstrap.run(function(name) event=name end,function() error('unexpected init') end,env)==false)
    assert(event=='DMM_INCOMPATIBLE','patched DMM without verified baselines must be rejected')
end

do
    local seed=seedOriginals()
    for name,value in pairs(originals) do
        seed['C:/DMM/Scripts/'..name]=value..'\npatched'
        seed['C:/DMM/Scripts/'..name..test.backupSuffix]=value
    end
    seed['C:/DMM/Scripts/extension_events.lua']=test.payload
    local env,_,shared=environment(seed)
    shared[test.readyKey]='1'
    local initialized=0
    assert(Bootstrap.run(function() end,function() initialized=initialized+1;return true end,env)==true)
    assert(initialized==1 and shared[test.claimKey]~=nil)
    assert(Bootstrap.run(function() end,function() initialized=initialized+1;return true end,env)==false)
    assert(initialized==1)
end

do
    local seed=seedOriginals()
    for name,value in pairs(originals) do
        seed['C:/DMM/Scripts/'..name]=value..'\npatched'
        seed['C:/DMM/Scripts/'..name..test.backupSuffix]=value
    end
    seed['C:/DMM/Scripts/extension_events.lua']=test.payload
    local env,_,shared,scheduled=environment(seed)
    local initialized=0
    assert(Bootstrap.run(function() end,function() initialized=initialized+1;return true end,env)=='waiting')
    shared[test.readyKey]='1';drain(scheduled)
    assert(initialized==1)
end

print('PASS DMM bootstrap handles compatibility, transaction rollback, handshake and duplicate initialization')
