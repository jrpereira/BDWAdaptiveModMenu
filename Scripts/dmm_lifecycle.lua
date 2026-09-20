-- DMM publishes only primitive lifecycle identities across Lua states. UObject
-- work remains deferred to dmm_binding's game-thread update.
local M={version=1}
local COMMAND='AMM_DMM_Lifecycle_v1'
local CLAIM=COMMAND..'.owner'
local DATA=COMMAND..'.data'
local owner=tostring({}):gsub('%W','')
local kinds={providerPrepared=true,providerRefreshed=true,hostClosing=true}

local function encode(value)
    return (tostring(value or ''):gsub('%%','%%25'):gsub('\n','%%0A'):gsub('\r','%%0D'))
end
local function decode(value)
    return (value:gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end))
end
local function identity(widget)
    if not widget or not widget:IsValid() then return '','' end
    local full=widget:GetFullName()
    return full:match('^%S+ (.+)$') or '',tostring(widget:GetAddress())
end
local function revision(payload)
    return type(payload)=='string' and tonumber(payload:match('^(%d+)\n')) or 0
end
local function serialize(kind,context,nextRevision)
    assert(kinds[kind],'unsupported lifecycle event')
    context=context or {}
    local tree=context.tree
    local host=context.host
    if (not host or not host:IsValid()) and tree and tree:IsValid() then host=tree:GetOuter() end
    local hostPath,hostAddress=identity(host)
    local selection=context.panel and context.panel.scroll or nil
    local selectionPath,selectionAddress=identity(selection)
    local treeAddress=tree and tree:IsValid() and tostring(tree:GetAddress()) or ''
    local providerId=context.provider and context.provider.id or ''
    local fields={string.format('%.0f',nextRevision),kind,encode(hostPath),hostAddress,treeAddress,
        encode(selectionPath),selectionAddress,encode(providerId)}
    local payload=table.concat(fields,'\n')..'\n'
    assert(#payload<=16384,'lifecycle event exceeds bounds')
    return payload
end
local function parse(payload)
    assert(type(payload)=='string' and #payload<=16384,'invalid lifecycle event')
    local fields={}
    local start=1
    while true do
        local stop=payload:find('\n',start,true)
        if not stop then break end
        fields[#fields+1]=payload:sub(start,stop-1);start=stop+1
    end
    assert(#fields==8,'invalid lifecycle event fields')
    local rev=tonumber(fields[1])
    assert(rev and rev>=1 and rev<=9007199254740991,'invalid lifecycle revision')
    assert(kinds[fields[2]],'invalid lifecycle kind')
    local event={revision=rev,kind=fields[2],path=decode(fields[3]),address=fields[4],treeAddress=fields[5],
        providerId=decode(fields[8])}
    if fields[6]~='' then event.selection={path=decode(fields[6]),address=fields[7]} end
    return event
end
local function viewport(pc)
    assert(pc and pc:IsValid(),'settings player unavailable')
    local player=pc.Player
    assert(player and player:IsValid(),'local player unavailable')
    local result=player.ViewportClient
    assert(result and result:IsValid() and result:IsA('/Script/Engine.GameViewportClient'),'game viewport unavailable')
    return result
end

function M.publisher(log)
    log=log or function() end
    local publisher={}
    function publisher:publish(kind,context)
        local ok,err=pcall(function()
            if not ModRef or not ModRef:GetSharedVariable(CLAIM) then return end
            local previous=revision(ModRef:GetSharedVariable(DATA)) or 0
            assert(previous>=0 and previous<9007199254740991,'lifecycle revision exhausted')
            local payload=serialize(kind,context,previous+1)
            ModRef:SetSharedVariable(DATA,payload)
            assert(viewport(context and context.pc):ProcessConsoleExec(COMMAND,nil,context.pc)==true,
                'lifecycle event was not handled')
        end)
        if not ok then log('LIFECYCLE_PUBLISH_FAILED',kind..': '..tostring(err)) end
        return ok
    end
    return publisher
end

function M.install(log,onChange)
    if not ModRef or type(RegisterConsoleCommandHandler)~='function' then
        return nil,'DMM lifecycle notification API unavailable'
    end
    local scope={enabled=false,epoch=0,path=nil,address=nil,treeAddress=nil,last=revision(ModRef:GetSharedVariable(DATA)) or 0}
    local function revoke()
        scope.epoch=scope.epoch+1;scope.path=nil;scope.address=nil;scope.treeAddress=nil
        if onChange then onChange(nil,scope.epoch) end
    end
    local function receive(event)
        if event.revision<=scope.last then return end
        scope.last=event.revision
        if event.kind=='hostClosing' then
            if scope.path==event.path and scope.address==event.address then revoke() end
            return
        end
        if event.path=='' or event.address=='' or event.treeAddress=='' then return end
        if not event.selection or event.selection.path=='' or event.selection.address=='' or event.providerId=='' then return end
        scope.epoch=scope.epoch+1
        scope.path=event.path;scope.address=event.address;scope.treeAddress=event.treeAddress
        if onChange then onChange(scope.path,scope.epoch,event.selection) end
    end
    assert(ModRef:GetSharedVariable(CLAIM)==nil,'DMM lifecycle subscriber already registered; fully restart after script reloads')
    local ok,result=pcall(RegisterConsoleCommandHandler,COMMAND,function()
        local handled,message=pcall(function() receive(parse(ModRef:GetSharedVariable(DATA))) end)
        if not handled then log('LIFECYCLE_EVENT_FAILED',tostring(message)) end
        return true
    end)
    if not ok or result==false then return nil,tostring(ok and 'console command registration rejected' or result) end
    ModRef:SetSharedVariable(CLAIM,owner)
    scope.enabled=true
    function scope:ownerLive()
        if not self.enabled or not self.path then return false end
        local host=StaticFindObject(self.path)
        if not host or not host:IsValid() or tostring(host:GetAddress())~=self.address
            or not host:IsInViewport() or not host:IsActivated() or not host:IsVisible() then
            revoke();return false
        end
        local tree=host.WidgetTree
        if not tree or not tree:IsValid() or tostring(tree:GetAddress())~=self.treeAddress then revoke();return false end
        return true
    end
    function scope:current() if self.enabled then return self.path,self.epoch end end
    function scope:matches(path,epoch)
        return self.enabled and self.path==path and self.epoch==epoch
    end
    function scope:invalidate() if self.path then revoke() end end
    return scope
end

return M
