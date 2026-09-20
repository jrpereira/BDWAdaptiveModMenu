local Discovery=require('widget_discovery')
local KeySelector=require('key_selector')
local MenuScope=require('menu_scope')
local ClickDelivery=require('click_delivery')
local DirtyLabels=require('dirty_labels')
local M={}

function M.install(registry,log)
    if not registry.dmmEligible then return false,'DMM direct-folder dependency inactive' end
    for _,api in ipairs({'StaticFindObject','ExecuteWithDelay','ExecuteInGameThread'}) do
        if type(_G[api])~='function' then return false,api..' unavailable' end
    end
    local clicks=ClickDelivery.new(log)
    local dirty=DirtyLabels.new(log,registry)
    local providers,enabled={},{}
    for _,provider in ipairs(registry.configProviders or registry.providerList or {}) do providers[provider.id]=provider end
    for _,provider in ipairs(registry.providerList or {}) do enabled[provider.id]=true end
    function M.showDirty(show) return dirty:setShowDirty(show) end
    function M.setValue(providerId,settingId,value) return dirty:setValue(providerId,settingId,value) end
    local scope,schedule
    local active=nil
    local pending={}
    local eventTicket=nil
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
        add(instance.row,{'slider','wrapper','labelWidget','valueWidget','modeState'})
        if instance.pair then
            add(instance.pair,{'button','inner','nav','valueWidget','text'})
            if instance.pair.row then add(instance.pair.row,{'wrapper'}) end
        end
        for i in ipairs(instance.keyEdges or {}) do add(instance.keyEdges,{i}) end
        instance.liveRefs=refs
    end
    local function refresh(instance,allowed,routes,resolve)
        local fresh={}
        for i,ref in ipairs(instance.liveRefs) do
            if not allowed() then return false end
            local object=resolve(routes[ref.address])
            if not object then return false,'unavailable control: '..tostring(ref.key) end
            fresh[i]=object
        end
        if not allowed() then return false end
        for i,ref in ipairs(instance.liveRefs) do ref.target[ref.key]=fresh[i] end
        return true
    end
    local function bindPage(state,rows,provider,byId)
        for _,row in ipairs(rows) do
            local setting={id=row.settingId}
            local descriptor=registry.byProvider[provider.id] and registry.byProvider[provider.id][row.settingId]
            if descriptor and row.kind=='slider' then
                local modeRow=descriptor.modeId and byId[descriptor.modeId]
                local ok,instance,detail=pcall(KeySelector.adopt,row,descriptor,modeRow,clicks)
                if ok and not instance then
                    ok,instance,detail=pcall(KeySelector.decorate,row,descriptor,log)
                    if ok and instance then state.constructed=true end
                    if ok and instance and modeRow then
                        local paired,result,err=pcall(KeySelector.mergePair,instance,modeRow,log,clicks)
                        if not paired or not result then
                            clicks:forget(instance)
                            log('PAIR_FAILED',provider.id..'.'..setting.id..': '..tostring(paired and err or result))
                        end
                    end
                end
                if ok and instance then
                    local recorded,recordError=pcall(ledger,instance)
                    if recorded then
                        instance.id=provider.id..'.'..setting.id
                        instance.undo=nil;instance.pairUndo=nil -- rollback receipts are construction-only
                        state.instances[#state.instances+1]=instance
                        if modeRow and instance.pair then state.pairsByRow[row]=modeRow end
                    else
                        clicks:forget(instance)
                        -- Roll back only this just-constructed row, never an adopted
                        -- decoration whose lifetime belongs to the existing page.
                        if instance.undo then
                            local restored,result=pcall(KeySelector.restore,instance,function() return true end)
                            if not restored or not result then
                                log('RESTORE_FAILED',provider.id..'.'..setting.id..': '..tostring(restored and 'rollback incomplete' or result))
                            end
                        end
                        log('DECORATE_FAILED',provider.id..'.'..setting.id..': '..tostring(recordError))
                    end
                else log('DECORATE_FAILED',provider.id..'.'..setting.id..': '..tostring(ok and (detail or 'no decoration returned') or instance)) end
            end
        end
    end

    local function tick(path,epoch,selections)
        local tickStarted=os.clock()
        local timing={discovery=0,localize=0,decorate=0,routes=0,dirtyBind=0}
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
            state={instances={},routes={},pairsByRow={}}
            active=state
            -- One event-driven discovery, after DMM finishes its synchronous row build.
            local snapshots={}
            local stage=os.clock()
            if selections and #selections>0 then
                -- SetActiveWidgetIndex gives us the exact selected children. In
                -- the usual DMM flow one is the provider ScrollBox and the other
                -- is the surrounding detail page. Try only those objects.
                for _,selection in ipairs(selections) do
                    local candidate=StaticFindObject(selection.path)
                    if Discovery.valid(candidate) and Discovery.address(candidate)==selection.address then
                        local rows=Discovery.rowsFromScroll(candidate)
                        if rows and #rows>0 then snapshots[1]={scrolls={candidate},directRows=rows};break end
                    end
                end
            end
            if not snapshots[1] then
                -- Activation can arrive without a switcher event (for example,
                -- recovery after a load). An unrelated switcher can also fire
                -- inside the same host. Keep one bounded traversal as fallback.
                local snapshot=Discovery.activeTrees(host,allowed)[1]
                if snapshot then snapshots[1]=snapshot end
            end
            timing.discovery=(os.clock()-stage)*1000
            if not allowed() then return end
            local allRows={}
            local snapshot=snapshots[1]
            if snapshot then
                for _,scroll in ipairs(snapshot.scrolls) do
                    if not allowed() then return end
                    local rows=snapshot.directRows or Discovery.rowsFromScroll(scroll) or {}
                    local provider=rows[1] and providers[rows[1].identityProviderId]
                    local byId,consistent={},provider~=nil
                    for _,row in ipairs(rows) do
                        if not row.settingId or not provider or row.identityProviderId~=provider.id or byId[row.settingId] then consistent=false;break end
                        byId[row.settingId]=row
                    end
                    if consistent then
                        stage=os.clock();dirty:localize(provider);timing.localize=timing.localize+(os.clock()-stage)*1000
                        local settings={}
                        for _,setting in ipairs(provider.dmmSettings or {}) do settings[setting.id]=setting end
                        for _,row in ipairs(rows) do
                            local setting=settings[row.settingId]
                            if setting and setting.kind==row.kind then row.dmmSetting=setting;row.providerId=provider.id end
                            allRows[#allRows+1]=row
                        end
                        if enabled[provider.id] then
                            stage=os.clock();dirty:construct(function() bindPage(state,rows,provider,byId) end)
                            timing.decorate=timing.decorate+(os.clock()-stage)*1000
                        end
                    end
                end
                if allowed() then
                    local objects={}
                    local function add(value) if Discovery.valid(value) then objects[#objects+1]=value end end
                    for _,row in ipairs(allRows) do
                        for _,key in ipairs({'slider','nav','surface','surfaceBox','line','labelBox','labelButton','labelWidget',
                            'valueBox','valueWidget','overlay','wrapper','scroll','shell','content','lane','leftBox','centerBox',
                            'rightBox','leftButton','centerButton','rightButton','button','modeState'}) do add(row[key]) end
                    end
                    for _,instance in ipairs(state.instances) do
                        for _,ref in ipairs(instance.liveRefs or {}) do add(ref.target[ref.key]) end
                    end
                    stage=os.clock();state.routes=Discovery.routesFor(host,objects,allowed)
                    if not state.routes then
                        local rebuilt=Discovery.activeTrees(host,allowed)[1]
                        state.routes=rebuilt and rebuilt.routes or snapshot.routes or {}
                    end
                    timing.routes=(os.clock()-stage)*1000
                end
                stage=os.clock();dirty:bind(allRows,state.routes,state.pairsByRow)
                timing.dirtyBind=(os.clock()-stage)*1000
                log('PAGE_TIMING',string.format('rows=%d instances=%d discovery=%.1fms localize=%.1fms decorate=%.1fms routes=%.1fms dirty=%.1fms total=%.1fms',
                    #allRows,#state.instances,timing.discovery,timing.localize,timing.decorate,timing.routes,timing.dirtyBind,(os.clock()-tickStarted)*1000))
            end
            state.pairsByRow=nil -- Pair addresses now belong to the active presentation hook.
        end
        local instances=state.instances
        local resolve=Discovery.routeResolver(host,allowed)
        if not resolve then scope:invalidate('tree root unavailable');return end
        local usable=dirty:refresh(host)
        for _,instance in ipairs(instances) do
            if not allowed() then return end
            if not instance.disabled then
                local freshOK,fresh,refreshError=pcall(refresh,instance,allowed,state.routes,resolve)
                local ok,alive=false,false
                if freshOK and fresh and allowed() then
                    clicks:deliver(instance)
                    ok,alive=pcall(KeySelector.tick,instance,log)
                end
                if ok and alive then instance.failures=0
                else
                    instance.failures=(instance.failures or 0)+1
                    if instance.failures==1 then
                        local reason=not freshOK and fresh or (not fresh and refreshError) or (not ok and alive) or 'control unavailable'
                        log('SELECTOR_TICK_FAILED',instance.id..': '..tostring(reason))
                    end
                    if instance.failures>=3 and allowed() then
                        instance.disabled=true
                        clicks:forget(instance)
                        log('SELECTOR_DISABLED',instance.id..': updates stopped until next page event')
                    end
                end
            end
            if not instance.disabled then usable=usable+1 end
        end
        clicks:discard()
        if usable==0 then return end
        if allowed() then schedule(path,epoch,100) end
    end
    local function fail(path,epoch,event,err)
        pending[epoch]=nil
        if scope:matches(path,epoch) then
            log(event,tostring(err))
            scope:invalidate(event)
        end
    end
    schedule=function(path,epoch,delay,selections)
        if not scope or not scope:matches(path,epoch) or pending[epoch] then return end
        pending[epoch]=true
        local queued,queueError=pcall(ExecuteWithDelay,delay,function()
            if not scope:matches(path,epoch) then pending[epoch]=nil;return end
            local dispatched,dispatchError=pcall(function()
                local function work()
                    pending[epoch]=nil
                    if not scope:matches(path,epoch) then return end
                    if EngineTickAvailable==false then scope:invalidate('engine tick unavailable');return end
                    local ok,err=pcall(tick,path,epoch,selections)
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
    scope,err=MenuScope.install(log,function(path,epoch,selection)
        if not path then
            eventTicket=nil;active=nil;clicks:retire(nil);clicks:close();dirty:close();return
        end
        dirty:open(path,function() return scope:matches(path,epoch) end,function() return scope:ownerLive() end)
        -- Multiple DMM switcher calls in the same stack share one deferred refresh.
        -- Each event has already revoked the previous epoch synchronously.
        if eventTicket then
            eventTicket.path=path;eventTicket.epoch=epoch
            if selection then eventTicket.selections[#eventTicket.selections+1]=selection end
            return
        end
        local ticket={path=path,epoch=epoch,selections={}}
        if selection then ticket.selections[1]=selection end
        eventTicket=ticket
        local queued,queueError=pcall(ExecuteWithDelay,0,function()
            if eventTicket~=ticket then return end
            eventTicket=nil
            local currentPath,currentEpoch=ticket.path,ticket.epoch
            if not scope:matches(currentPath,currentEpoch) then return end
            active=nil;clicks:retire(nil)
            local clickOK,clickError=clicks:open(currentPath)
            if not clickOK then log('CLICK_INPUT_FAILED',tostring(clickError)) end
            schedule(currentPath,currentEpoch,0,#ticket.selections>0 and ticket.selections or nil)
        end)
        if not queued then eventTicket=nil;fail(path,epoch,'SCHEDULING_FAILED',queueError) end
    end,function(path)
        clicks:retire(path)
    end)
    if not scope then return false,err end
    return true
end
return M
