-- DawnwalkerModMenu compatibility bootstrap.
-- Keep discovery, compatibility checks, backup, patch, rollback and readiness
-- gating in this file so the integration transaction has one owner.
local M={version=1}

local READY='AMM_DMM_Extension_v1.ready'
local CLAIM='AMM_DMM_Bootstrap_v1.initialized'
local PATCH_MARKER='-- AMM_DMM_LIFECYCLE_PATCH=1'
local BACKUP_SUFFIX='.amm-1.0.7.bak'
local NEW_SUFFIX='.amm-new'
local DEPRECATED_MARKER='AdaptiveModMenu'
local MAX_FILE=262144
local WAIT_MS=100
local WAIT_ATTEMPTS=25

local EVENT_PAYLOAD=[=[-- Synchronous, startup-installed callbacks for extensions that need DMM-owned
-- lifecycle boundaries. A failed extension callback is logged and isolated.
local M={version=1}
local names={providerPrepared=true,providerRefreshed=true,hostClosing=true}

function M.new(report)
    report=report or function() end
    local bus={handlers={}}
    function bus:on(name,callback)
        assert(names[name],'unsupported extension event')
        assert(type(callback)=='function','extension event callback must be a function')
        local handlers=self.handlers[name]
        if not handlers then handlers={};self.handlers[name]=handlers end
        assert(#handlers<32,'extension event handler limit exceeded')
        handlers[#handlers+1]=callback
        local active=true
        return function()
            if not active then return end
            active=false
            for i,value in ipairs(handlers) do
                if value==callback then table.remove(handlers,i);break end
            end
        end
    end
    function bus:emit(name,context)
        assert(names[name],'unsupported extension event')
        for _,callback in ipairs(self.handlers[name] or {}) do
            local ok,err=pcall(callback,context)
            if not ok then report('EXTENSION_EVENT_FAILED',name..': '..tostring(err)) end
        end
    end
    return bus
end

return M
]=]

local supported={
    ['main.lua']={length=38752,a=20533,b=34583,h=823464120},
    ['controls.lua']={length=24704,a=45341,b=45889,h=1849011022},
    ['pages.lua']={length=11799,a=44920,b=14770,h=2559550986},
}
local patched={
    ['main.lua']={length=39049,a=47247,b=18334,h=1315845458},
    ['controls.lua']={length=24993,a=4755,b=1545,h=846892309},
    ['pages.lua']={length=11817,a=46707,b=57684,h=4136752645},
}

local function signature(content)
    local a,b,h=1,0,5381
    for i=1,#content do
        local byte=content:byte(i)
        a=(a+byte)%65521
        b=(b+a)%65521
        h=(h*33+byte)%4294967296
    end
    return {length=#content,a=a,b=b,h=h}
end

local function sameSignature(content,expected)
    local got=signature(content)
    return got.length==expected.length and got.a==expected.a and got.b==expected.b and got.h==expected.h
end

local function replaceOnce(content,before,after,label)
    local first,last=content:find(before,1,true)
    assert(first,label..' anchor unavailable')
    assert(not content:find(before,last+1,true),label..' anchor is ambiguous')
    return content:sub(1,first-1)..after..content:sub(last+1)
end
local function crlf(value) return (value:gsub('\n','\r\n')) end

local function patchMain(content)
    content=replaceOnce(content,
        'local Extensions = require("extensions")\nExtensions.load(IterateGameDirectories,{version=1,choices=require("choices"),controls=require("controls"),pages=Pages},log)',
        'local Extensions = require("extensions")\n'..PATCH_MARKER..'\nlocal ExtensionEvents = require("extension_events")\nlocal extensionEvents = ExtensionEvents.new(log)\nExtensions.load(IterateGameDirectories,{version=1,choices=require("choices"),controls=require("controls"),pages=Pages,events=extensionEvents},log)',
        'main extension API')
    content=replaceOnce(content,
        crlf('    s.phase = "closing"\n    clearPresses()'),
        crlf('    s.phase = "closing"\n    extensionEvents:emit("hostClosing",{host=s.host,tree=valid(s.host) and s.host.WidgetTree or nil,pc=s.pc})\n    clearPresses()'),
        'host close')
    content=replaceOnce(content,
        crlf('        highlight=function(widget,alpha,background) s.fx:highlight(widget,alpha,background) end,\n    })'),
        crlf('        highlight=function(widget,alpha,background) s.fx:highlight(widget,alpha,background) end,\n        events=extensionEvents,\n    })'),
        'page event API')
    return content
end

local function patchControls(content)
    content=replaceOnce(content,
        crlf('        panel.built=true\n    end'),
        crlf("        panel.built=true\n        if api.events then api.events:emit('providerPrepared',{tree=tree,provider=provider,panel=panel,pc=api.pc}) end\n    end"),
        'provider preparation')
    content=replaceOnce(content,
        crlf('        api.status(model.error or (dirty and T("Unapplied changes") or ""))\n    end'),
        crlf("        api.status(model.error or (dirty and T(\"Unapplied changes\") or \"\"))\n        if changed and api.events then\n            api.events:emit('providerRefreshed',{tree=tree,provider=providers[self.active],panel=panel,pc=api.pc})\n        end\n    end"),
        'provider refresh')
    return content
end

local function patchPages(content)
    content=replaceOnce(content,
        '        status=controlStatus,t=T,applied=api.applied,\n',
        '        status=controlStatus,t=T,applied=api.applied,events=api.events,\n',
        'controls event API')
    return content
end

local patchers={['main.lua']=patchMain,['controls.lua']=patchControls,['pages.lua']=patchPages}

local function child(node,wanted)
    if type(node)~='table' then return nil end
    wanted=wanted:lower()
    for key,value in pairs(node) do
        if type(value)=='table' and (tostring(key):lower()==wanted
            or tostring(value.__name or ''):lower()==wanted) then return value end
    end
end

local function file(node,wanted)
    wanted=wanted:lower()
    for _,value in pairs(type(node)=='table' and node.__files or {}) do
        if type(value)=='table' and tostring(value.__name or ''):lower()==wanted then return value end
    end
end

local function modsRoot(directories)
    local game=child(directories,'Game')
    if not game and type(directories)=='table' then
        for _,candidate in pairs(directories) do
            if child(candidate,'Binaries') then
                assert(not game,'ambiguous game directory')
                game=candidate
            end
        end
    end
    return child(child(child(child(game,'Binaries'),'Win64'),'ue4ss'),'Mods')
end

local function runtime()
    local function read(path)
        local handle,err=io.open(path,'rb');if not handle then return nil,err end
        local content,why=handle:read(MAX_FILE+1)
        local closed,closeError=handle:close()
        if not content or not closed then return nil,why or closeError or 'read failed' end
        if #content>MAX_FILE then return nil,'file exceeds 256 KiB' end
        return content
    end
    local function write(path,content)
        local handle,err=io.open(path,'wb');if not handle then return nil,err end
        local written,why=handle:write(content)
        local closed,closeError=handle:close()
        if not written or not closed then return nil,why or closeError or 'write failed' end
        return true
    end
    return {
        directories=IterateGameDirectories,read=read,write=write,remove=os.remove,rename=os.rename,
        unload=function(name)
            if type(UninstallMod)~='function' then return false,'unavailable' end
            return pcall(UninstallMod,name)
        end,
        get=function(key) return ModRef and ModRef:GetSharedVariable(key) end,
        set=function(key,value) assert(ModRef,'ModRef unavailable');ModRef:SetSharedVariable(key,value) end,
        schedule=ExecuteWithDelay,
    }
end

local function directories(env)
    local ok,value=pcall(env.directories)
    if not ok then return nil,'game directories unavailable: '..tostring(value) end
    return value
end

local function migrateEnablement(env,gameDirectories)
    local previous=child(modsRoot(gameDirectories),'ModMenuDecorator')
    local source=file(previous,'enabled.txt')
    if not source or type(source.__absolute_path)~='string' then return true end
    local target=source.__absolute_path:match('^(.+[\\/])[^\\/]+$')..'deprecated.txt'
    if env.read(target)~=nil then return true end
    local removed,removeError=env.remove(source.__absolute_path)
    if not removed and env.read(source.__absolute_path)~=nil then
        return nil,removeError or 'could not disable previous installation'
    end
    local written,err=env.write(target,DEPRECATED_MARKER)
    if not written or env.read(target)~=DEPRECATED_MARKER then
        return nil,err or 'could not create deprecation marker'
    end
    if type(env.unload)=='function' then env.unload('ModMenuDecorator') end
    return true
end

local function locate(env,gameDirectories)
    local mods=modsRoot(gameDirectories)
    local dmm=child(mods,'DawnwalkerModMenu')
    local scripts=child(dmm,'Scripts')
    if not scripts then return nil,'DawnwalkerModMenu is not installed' end
    local directory
    for _,entry in pairs(scripts.__files or {}) do
        if type(entry)=='table' and type(entry.__absolute_path)=='string' then
            local candidate=entry.__absolute_path:match('^(.+[\\/])[^\\/]+$')
            if candidate then
                assert(not directory or directory==candidate,'ambiguous DMM Scripts directory')
                directory=candidate
            end
        end
    end
    if not directory then return nil,'DawnwalkerModMenu Scripts directory is empty' end
    local paths={}
    for _,name in ipairs({'main.lua','controls.lua','pages.lua'}) do paths[name]=directory..name end
    paths['extension_events.lua']=directory..'extension_events.lua'
    return paths
end

local function readRequired(env,path)
    local content,err=env.read(path)
    assert(content,err or 'read failed')
    return content
end

local function recoverInterrupted(env,paths)
    local interrupted=false
    for _,path in pairs(paths) do if env.read(path..NEW_SUFFIX)~=nil then interrupted=true;break end end
    if not interrupted then return false end
    for name,expected in pairs(env.supported or supported) do
        local path=paths[name]
        if env.read(path)==nil then
            local backup=readRequired(env,path..BACKUP_SUFFIX)
            assert(sameSignature(backup,expected),'interrupted patch has no verified baseline for '..name)
            assert(env.write(path,backup),'could not restore interrupted '..name)
            assert(env.read(path)==backup,'interrupted restore verification failed for '..name)
        end
    end
    for _,path in pairs(paths) do
        local temp=path..NEW_SUFFIX
        if env.read(temp)~=nil then
            assert(env.remove(temp),'could not remove interrupted stage '..temp)
            assert(env.read(temp)==nil,'interrupted stage remains '..temp)
        end
    end
    return true
end

local function desiredFiles(env,paths)
    local current,baseline,desired={},{},{}
    local allPatched=true
    local accepted=env.supported or supported
    local completed=env.patched or patched
    local transforms=env.patchers or patchers
    for name,expected in pairs(accepted) do
        local content=readRequired(env,paths[name])
        current[name]=content
        if sameSignature(content,expected) then
            allPatched=false
            baseline[name]=content
            desired[name]=transforms[name](content)
            assert(sameSignature(desired[name],completed[name]),'internal patch signature mismatch for '..name)
        elseif sameSignature(content,completed[name]) then
            desired[name]=content
            local backup=env.read(paths[name]..BACKUP_SUFFIX)
            assert(backup and sameSignature(backup,expected),'supported backup missing for patched '..name)
            baseline[name]=backup
        else
            error('unsupported DawnwalkerModMenu 1.0.7 '..name)
        end
    end
    local payload=env.read(paths['extension_events.lua'])
    if payload and payload~=EVENT_PAYLOAD then error('unsupported DawnwalkerModMenu extension_events.lua') end
    local patched=allPatched and payload==EVENT_PAYLOAD
    return patched and 'patched' or 'needs-patch',current,baseline,desired,payload
end

local function rollback(env,paths,current,payload,touched,payloadTouched,staged)
    local errors={}
    for name in pairs(touched) do
        env.remove(paths[name])
        local ok,err=env.write(paths[name],current[name])
        if not ok or env.read(paths[name])~=current[name] then errors[#errors+1]=name..': '..tostring(err or 'restore verification failed') end
    end
    if payloadTouched and payload then
        env.remove(paths['extension_events.lua'])
        local ok,err=env.write(paths['extension_events.lua'],payload)
        if not ok or env.read(paths['extension_events.lua'])~=payload then errors[#errors+1]='extension_events.lua: '..tostring(err or 'restore verification failed') end
    elseif payloadTouched then
        local ok,err=env.remove(paths['extension_events.lua'])
        if not ok and env.read(paths['extension_events.lua']) then
            errors[#errors+1]='extension_events.lua: '..tostring(err)
        end
    end
    for _,temp in pairs(staged) do env.remove(temp) end
    return #errors==0,table.concat(errors,'; ')
end

local function patch(env,paths,current,baseline,desired,payload)
    assert(type(env.rename)=='function','atomic rename unavailable')
    local staged={}
    local function stage(path,content)
        local temp=path..NEW_SUFFIX
        assert(env.read(temp)==nil,'previous patch transaction needs review: '..temp)
        staged[path]=temp
        assert(env.write(temp,content),'could not stage '..path)
        assert(readRequired(env,temp)==content,'staged verification failed for '..path)
    end
    local stagedOK,stageError=pcall(function()
        for name,content in pairs(desired) do if current[name]~=content then stage(paths[name],content) end end
        if payload~=EVENT_PAYLOAD then stage(paths['extension_events.lua'],EVENT_PAYLOAD) end
    end)
    if not stagedOK then
        for _,temp in pairs(staged) do env.remove(temp) end
        return nil,tostring(stageError)..'; live files unchanged'
    end
    local touched,payloadTouched={},false
    local ok,err=pcall(function()
        -- Every replacement is complete and verified before any live file moves.
        for name,content in pairs(baseline) do
            local backup=paths[name]..BACKUP_SUFFIX
            local existing=env.read(backup)
            if existing then assert(existing==content,'backup does not match supported '..name)
            else
                assert(env.rename(paths[name],backup),'could not move backup for '..name)
                assert(readRequired(env,backup)==content,'backup verification failed for '..name)
                touched[name]=true
            end
        end
        for name,content in pairs(desired) do
            if current[name]~=content then
                if env.read(paths[name])~=nil then assert(env.remove(paths[name]),'could not replace '..name) end
                touched[name]=true
                assert(env.rename(staged[paths[name]],paths[name]),'could not promote '..name)
            end
        end
        if payload~=EVENT_PAYLOAD then
            if payload~=nil then assert(env.remove(paths['extension_events.lua']),'could not replace extension_events.lua') end
            payloadTouched=true
            assert(env.rename(staged[paths['extension_events.lua']],paths['extension_events.lua']),
                'could not promote extension_events.lua')
        end
        for name,content in pairs(desired) do
            assert(readRequired(env,paths[name])==content,'verification failed for '..name)
        end
        assert(readRequired(env,paths['extension_events.lua'])==EVENT_PAYLOAD,'extension payload verification failed')
    end)
    if ok then return true end
    local restored,restoreError=rollback(env,paths,current,payload,touched,payloadTouched,staged)
    if not restored then return nil,tostring(err)..'; rollback failed: '..restoreError end
    return nil,tostring(err)..'; changes rolled back'
end

function M.run(log,initialize,overrides)
    assert(type(log)=='function' and type(initialize)=='function','bootstrap callbacks unavailable')
    local env=overrides or runtime()
    local finished=false
    local owner=tostring({}):gsub('%W','')
    local function ready()
        if finished or env.get(READY)~='1' then return false end
        if env.get(CLAIM) then log('DMM_DUPLICATE_INIT','another AdaptiveModMenu instance already initialized');finished=true;return false end
        env.set(CLAIM,owner)
        local ok,result=pcall(initialize)
        if not ok or result==false then
            if env.get(CLAIM)==owner then env.set(CLAIM,nil) end
            log('DMM_INITIALIZATION_FAILED',tostring(ok and 'initializer rejected readiness' or result))
            finished=true;return false
        end
        finished=true;return true
    end

    local gameDirectories,directoryError=directories(env)
    if not gameDirectories then log('DMM_REQUIRED',directoryError);return false end
    local migrated,migrationError=migrateEnablement(env,gameDirectories)
    if not migrated then log('ENABLEMENT_MIGRATION_FAILED',tostring(migrationError));return false end
    local located,paths,locateError=pcall(locate,env,gameDirectories)
    if not located then log('DMM_REQUIRED',tostring(paths));return false end
    if not paths then log('DMM_REQUIRED',locateError);return false end
    local recovered,recoveryError=pcall(recoverInterrupted,env,paths)
    if not recovered then log('DMM_PATCH_FAILED',tostring(recoveryError));return false end
    local ok,state,current,baseline,desired,payload=pcall(desiredFiles,env,paths)
    if not ok then log('DMM_INCOMPATIBLE',tostring(state));return false end
    local changed=state~='patched'
    if changed then
        local patched,patchError=patch(env,paths,current,baseline,desired,payload)
        if not patched then log('DMM_PATCH_FAILED',patchError);return false end
        log('DMM_PATCHED','DawnwalkerModMenu 1.0.7 lifecycle API installed')
    end
    if ready() then return true end
    if finished then return false end
    if type(env.schedule)~='function' then
        log(changed and 'DMM_RESTART_REQUIRED' or 'DMM_HANDSHAKE_FAILED','restart the game to load the DMM lifecycle API')
        return false
    end
    local attempts=0
    local function wait()
        if finished or ready() then return end
        attempts=attempts+1
        if attempts>=WAIT_ATTEMPTS then
            finished=true
            log(changed and 'DMM_RESTART_REQUIRED' or 'DMM_HANDSHAKE_FAILED','restart the game to load the DMM lifecycle API')
            return
        end
        local scheduled,why=pcall(env.schedule,WAIT_MS,wait)
        if not scheduled then finished=true;log('DMM_HANDSHAKE_FAILED',tostring(why)) end
    end
    local scheduled,why=pcall(env.schedule,WAIT_MS,wait)
    if not scheduled then log('DMM_HANDSHAKE_FAILED',tostring(why));return false end
    return 'waiting'
end

M._test={signature=signature,patchers=patchers,payload=EVENT_PAYLOAD,backupSuffix=BACKUP_SUFFIX,
    newSuffix=NEW_SUFFIX,readyKey=READY,claimKey=CLAIM}
return M
