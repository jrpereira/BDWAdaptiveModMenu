local Discovery=require('widget_discovery')
local KeySelector=require('key_selector')
local MenuScope=require('menu_scope')
local ClickDelivery=require('click_delivery')
local M={}

local function labelMatches(setting,row)
    return type(setting.labels)=='table' and row.label and setting.labels[row.label:gsub('%s+%*%s*$','')]==true
end

local function exactProviderMatch(provider,rows)
    if #provider.choices~=#rows then return false end
    for i,setting in ipairs(provider.choices) do
        local row=rows[i]
        if not row or row.kind~=setting.kind or not labelMatches(setting,row) then return false end
    end
    return true
end

local function candidateProviders(registry,rows)
    local out={}
    for _,provider in ipairs(registry.providerList or {}) do
        if exactProviderMatch(provider,rows) then out[#out+1]=provider end
    end
    return out
end

function M.install(registry,log)
    if not registry.dmmEligible then return false,'DMM direct-folder dependency inactive' end
    for _,api in ipairs({'StaticFindObject','ExecuteWithDelay','ExecuteInGameThread'}) do
        if type(_G[api])~='function' then return false,api..' unavailable' end
    end
    local clicks=ClickDelivery.new(log)
    local scope,schedule
    local active=nil
    local pending={}
    local function ledger(instance)
        local refs={}
        local function add(target,keys)
            for _,key in ipairs(keys) do
                local object=target[key]
                if object then
                    local full=object:GetFullName()
                    refs[#refs+1]={target=target,key=key,address=Discovery.address(object),name=object:GetFName():ToString(),full=full,path=assert(full:match('^%S+ (.+)$'))}
                end
            end
        end
        add(instance,{'selector','keyBox','keyFrame','keyInner','keyText','stateWidget'})
        add(instance.row,{'slider','wrapper','labelWidget','valueWidget'})
        if instance.pair then add(instance.pair,{'button','inner','nav','valueWidget','text'}) end
        for i in ipairs(instance.keyEdges or {}) do add(instance.keyEdges,{i}) end
        instance.liveRefs=refs
    end
    local function refresh(instance,allowed,routes,resolve)
        local fresh={}
        for i,ref in ipairs(instance.liveRefs) do
            if not allowed() then return false end
            local object=resolve(routes[ref.address])
            if not object then return false end
            fresh[i]=object
        end
        if not allowed() then return false end
        for i,ref in ipairs(instance.liveRefs) do ref.target[ref.key]=fresh[i] end
        return true
    end
    local function bindPage(state,rows,provider)
        local byId={}
        for i,setting in ipairs(provider.choices) do byId[setting.id]=rows[i] end
        for i,setting in ipairs(provider.choices) do
            local descriptor=registry.byProvider[provider.id] and registry.byProvider[provider.id][setting.id]
            local row=rows[i]
            if descriptor and row.kind=='slider' then
                local modeRow=descriptor.modeId and byId[descriptor.modeId]
                local ok,instance=pcall(KeySelector.adopt,row,descriptor,modeRow,clicks)
                if ok and not instance then
                    ok,instance=pcall(KeySelector.decorate,row,descriptor,log)
                    if ok and instance and modeRow then
                        local paired,result,err=pcall(KeySelector.mergePair,instance,modeRow,log,clicks)
                        if not paired or not result then
                            clicks:forget(instance)
                            log('PAIR_FAILED',tostring(paired and err or result))
                        end
                    end
                end
                if ok and instance then
                    ledger(instance)
                    instance.undo=nil;instance.pairUndo=nil -- rollback receipts are construction-only
                    state.instances[#state.instances+1]=instance
                else log('DECORATE_FAILED',provider.id..'.'..setting.id..': '..tostring(instance)) end
            end
        end
    end

    local function tick(path,epoch)
        local function allowed() return scope:matches(path,epoch) end
        if not allowed() then return end
        if not scope:ownerLive() then return end
        local host=StaticFindObject(path)
        if not allowed() then return end
        if not Discovery.valid(host) or not host:IsInViewport() or not host:IsActivated()
            or host:IsVisible()~=true or host:GetIsEnabled()~=true then
            scope:invalidate('host inactive');return
        end
        local state=active
        if not state then
            state={instances={},routes={}}
            active=state
            -- One event-driven discovery, after DMM finishes its synchronous row build.
            local snapshot=Discovery.activeTrees(host,allowed)[1]
            if not allowed() then return end
            if snapshot then
                for _,scroll in ipairs(snapshot.scrolls) do
                    if not allowed() then return end
                    local rows=Discovery.rowsFromScroll(scroll) or {}
                    local candidates=candidateProviders(registry,rows)
                    if #candidates==1 then bindPage(state,rows,candidates[1]) end
                end
                if #state.instances>0 and allowed() then
                    local rebuilt=Discovery.activeTrees(host,allowed)[1]
                    if rebuilt then state.routes=rebuilt.routes end
                end
            end
            if #state.instances==0 then scope:dormant();return end
        end
        local instances=state.instances
        local resolve=Discovery.routeResolver(host,allowed)
        if not resolve then scope:invalidate('tree root unavailable');return end
        for _,instance in ipairs(instances) do
            if not allowed() then return end
            if not instance.disabled then
                local freshOK,fresh=pcall(refresh,instance,allowed,state.routes,resolve)
                local ok,alive=false,false
                if freshOK and fresh and allowed() then ok,alive=pcall(KeySelector.tick,instance,log) end
                if ok and alive then instance.failures=0
                else
                    instance.failures=(instance.failures or 0)+1
                    if instance.failures==1 then log('SELECTOR_TICK_FAILED','temporarily unavailable') end
                    if instance.failures>=3 and allowed() then
                        instance.disabled=true
                        clicks:forget(instance)
                        log('SELECTOR_DISABLED','updates stopped until next page event')
                    end
                end
            end
        end
        if allowed() then schedule(path,epoch,100) end
    end
    local function fail(path,epoch,event,err)
        pending[epoch]=nil
        if scope:matches(path,epoch) then
            log(event,tostring(err))
            scope:invalidate(event)
        end
    end
    schedule=function(path,epoch,delay)
        if not scope or not scope:matches(path,epoch) or pending[epoch] then return end
        pending[epoch]=true
        local queued,queueError=pcall(ExecuteWithDelay,delay,function()
            if not scope:matches(path,epoch) then pending[epoch]=nil;return end
            local dispatched,dispatchError=pcall(function()
                local function work()
                    pending[epoch]=nil
                    if not scope:matches(path,epoch) then return end
                    if EngineTickAvailable==false then scope:invalidate('engine tick unavailable');return end
                    local ok,err=pcall(tick,path,epoch)
                    if not ok then fail(path,epoch,'DISCOVERY_FAILED',err) end
                end
                if EGameThreadMethod and EGameThreadMethod.EngineTick then ExecuteInGameThread(work,EGameThreadMethod.EngineTick)
                else ExecuteInGameThread(work) end
            end)
            if not dispatched then fail(path,epoch,'GAME_THREAD_DISPATCH_FAILED',dispatchError) end
        end)
        if not queued then fail(path,epoch,'SCHEDULING_FAILED',queueError) end
    end
    local err
    scope,err=MenuScope.install(log,function(path,epoch)
        -- Drop only temporary control routing. Decoration and state remain on rows.
        active=nil
        clicks:retire(nil)
        if not path then clicks:close();return end
        local clickOK,clickError=clicks:open(path)
        if not clickOK then log('CLICK_HOOK_FAILED',tostring(clickError)) end
        schedule(path,epoch,0)
    end,function(path)
        clicks:retire(path)
    end)
    if not scope then return false,err end
    return true
end
return M
