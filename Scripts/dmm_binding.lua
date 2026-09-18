local Discovery=require('widget_discovery')
local KeySelector=require('key_selector')
local MenuScope=require('menu_scope')
local ClickDelivery=require('click_delivery')
local M={}

local function labelMatches(setting,row)
    return type(setting.labels)=='table' and row.label and setting.labels[row.label]==true
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
    local hosts={}
    local boundScrolls,decoratedSliders,instances
    local pending={}
    local function ledger(instance)
        local refs={}
        local function add(target,keys)
            for _,key in ipairs(keys) do
                local object=target[key]
                if object then
                    local full=object:GetFullName()
                    refs[#refs+1]={target=target,key=key,address=Discovery.address(object),full=full,path=assert(full:match('^%S+ (.+)$'))}
                end
            end
        end
        add(instance,{'selector','keyBox','keyFrame','keyInner','keyText'})
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
    local function bindPage(scroll,rows,provider)
        local scrollAddr=Discovery.address(scroll); if not scrollAddr or boundScrolls[scrollAddr] then return true end
        local page={providerId=provider.id,scrollName=scroll:GetFName():ToString(),rowsById={},ordered={},instances={}}

        -- Capture semantic identity for every DMM row before any visual pairing/mutation.
        for i,setting in ipairs(provider.choices) do
            local row=rows[i]
            local binding={providerId=provider.id,settingId=setting.id,sourceIndex=i,row=row,kind=row.kind,wrapperAddr=Discovery.address(row.wrapper),wrapperName=row.wrapper:GetFName():ToString()}
            page.rowsById[setting.id]=binding; page.ordered[i]=binding
        end

        boundScrolls[scrollAddr]=page

        for _,binding in ipairs(page.ordered) do
            local descriptor=registry.byProvider[provider.id] and registry.byProvider[provider.id][binding.settingId]
            if descriptor then
                if binding.kind~='slider' or not Discovery.valid(binding.row.slider) then
                    log('DECORATE_SKIPPED',provider.id..'.'..binding.settingId..': decorated keybind is not a numeric DMM row')
                else
                    local sliderAddr=Discovery.address(binding.row.slider)
                    if sliderAddr and not decoratedSliders[sliderAddr] then
                        local ok,instanceOrErr=pcall(KeySelector.decorate,binding.row,descriptor,log)
                        if ok and instanceOrErr then
                            decoratedSliders[sliderAddr]=true; binding.instance=instanceOrErr; page.instances[#page.instances+1]=instanceOrErr; instances[#instances+1]=instanceOrErr
                            if descriptor.modeId then
                                local modeBinding=page.rowsById[descriptor.modeId]
                                if modeBinding and modeBinding.kind=='picker' then
                                    local callOk,pairOk,pairErr=pcall(KeySelector.mergePair,instanceOrErr,modeBinding.row,log,clicks)
                                    if not callOk then
                                        log('PAIR_EXCEPTION',provider.id..'.'..binding.settingId..': '..tostring(pairOk))
                                    elseif not pairOk then
                                        log('PAIR_FAILED',provider.id..'.'..binding.settingId..': '..tostring(pairErr))
                                    end
                                else
                                    log('PAIR_FAILED',provider.id..'.'..binding.settingId..': mode binding unavailable')
                                end
                            end
                            local recorded,recordError=pcall(ledger,instanceOrErr)
                            if not recorded then
                                instanceOrErr.disabled=true
                                clicks:forget(instanceOrErr)
                                pcall(KeySelector.restore,instanceOrErr,function() return true end)
                                instanceOrErr.liveRefs={}
                                log('DECORATE_FAILED',tostring(recordError))
                            end
                        else log('DECORATE_FAILED',provider.id..'.'..binding.settingId..': '..tostring(instanceOrErr)) end
                    else log('SKIP_ALREADY_DECORATED',provider.id..'.'..binding.settingId) end
                end
            end
        end
        return true
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
        local state=hosts[path]
        if not state then
            state={bound={},decorated={},instances={},scanDue=true,attempts=0,routes={}}
            hosts[path]=state
        end
        boundScrolls,decoratedSliders,instances=state.bound,state.decorated,state.instances
        if state.scanDue then
            state.scanDue=false
            local snapshots=Discovery.activeTrees(host,allowed)
            if not allowed() then return end
            local snapshot=snapshots[1]
            if snapshot then
                state.routes=snapshot.routes
                local beforeCount=#instances
                for i=#instances,1,-1 do
                    local instance=instances[i]
                    local wrapperRef
                    for _,ref in ipairs(instance.liveRefs) do
                        if ref.target==instance.row and ref.key=='wrapper' then wrapperRef=ref;break end
                    end
                    if wrapperRef and not snapshot.widgets[wrapperRef.address] then
                        for _,ref in ipairs(instance.liveRefs) do
                            if ref.key=='slider' then decoratedSliders[ref.address]=nil end
                        end
                        clicks:forget(instance)
                        table.remove(instances,i)
                    end
                end
                for addr,page in pairs(boundScrolls) do
                    local alive=snapshot.names[addr]==page.scrollName
                    for _,binding in ipairs(page.ordered) do
                        if snapshot.names[binding.wrapperAddr]~=binding.wrapperName then alive=false;break end
                    end
                    if not alive then boundScrolls[addr]=nil end
                end
                for _,scroll in ipairs(snapshot.scrolls) do
                    if not allowed() then return end
                    local addr=Discovery.address(scroll)
                    if not boundScrolls[addr] then
                        local rows=Discovery.rowsFromScroll(scroll) or {}
                        local candidates=candidateProviders(registry,rows)
                        if #candidates==1 then bindPage(scroll,rows,candidates[1]) end
                    end
                end
                if #instances~=beforeCount and allowed() then
                    -- New controls were not in the pre-decoration snapshot. Record their
                    -- routes once after all construction, not once per control or update.
                    local rebuilt=Discovery.activeTrees(host,allowed)[1]
                    if rebuilt then state.routes=rebuilt.routes end
                end
            end
            if next(boundScrolls)==nil then
                state.attempts=state.attempts+1
                if state.attempts>=3 then scope:dormant();return end
            else state.attempts=0 end
        end
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
                        local restored,result=pcall(KeySelector.restore,instance,allowed)
                        if not restored or not result then log('RESTORE_FAILED','control recovery incomplete') end
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
    -- Structural fallback has its own elapsed-delay schedule; updates cannot speed it up.
    local function structural(path,epoch)
        local ok,err=pcall(ExecuteWithDelay,1000,function()
            if not scope:matches(path,epoch) then return end
            local state=hosts[path]
            if state then state.scanDue=true end
            structural(path,epoch)
        end)
        if not ok then fail(path,epoch,'SCHEDULING_FAILED',err) end
    end
    local err
    scope,err=MenuScope.install(log,function(path,epoch)
        if not path then clicks:close();return end
        local clickOK,clickError=clicks:open(path,epoch)
        if not clickOK then log('CLICK_HOOK_FAILED',tostring(clickError)) end
        local state=hosts[path]
        if state then
            state.scanDue=true;state.attempts=0
            for _,instance in ipairs(state.instances) do
                instance.wasSelecting=false
                if instance.pair then instance.pair.pressed=false end
            end
        end
        schedule(path,epoch,0)
        if scope:matches(path,epoch) then structural(path,epoch) end
    end,function(path)
        if path and not hosts[path] then return end
        if path then hosts[path]=nil else hosts={} end
        boundScrolls,decoratedSliders,instances=nil,nil,nil
        clicks:retire(path)
    end)
    if not scope then return false,err end
    return true
end
return M
