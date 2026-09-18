local Discovery=require('widget_discovery')
local KeySelector=require('key_selector')
local MenuScope=require('menu_scope')
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
    for _,api in ipairs({'StaticFindObject','ExecuteWithDelay','ExecuteInGameThread','UnregisterHook'}) do
        if type(_G[api])~='function' then return false,api..' unavailable' end
    end
    local scope,schedule
    local hosts,relayOwners={},{}
    local boundScrolls,decoratedSliders,instances
    local activePath
    local pending={}
    local eventHooks={}
    local function unhook()
        for _,h in ipairs(eventHooks) do pcall(UnregisterHook,h[1],h[2],h[3]) end
        eventHooks={}
    end
    local function event(kind,context)
        local path,epoch=scope:current()
        if not path then return end
        local receiver=context:get()
        local owner=relayOwners[tostring(receiver:GetAddress())]
        if not owner or owner.path~=path then return end
        local instance=owner.instance
        if receiver:GetFullName()~=instance.relayFullName then return end
        if kind=='click' then instance.pendingClicks=(instance.pendingClicks or 0)+1 end
        schedule(path,epoch,0)
    end
    local function hookEvents()
        if #eventHooks>0 then return true end
        for _,spec in ipairs({{'/Script/UMG.Widget:ForceLayoutPrepass','click'},
                              {'/Script/UMG.InputKeySelector:SetSelectedKey','key'}}) do
            local ok,pre,post=pcall(RegisterHook,spec[1],function() end,function(context)
                local success,err=pcall(event,spec[2],context)
                if not success then log('EVENT_FAILED',tostring(err)) end
            end)
            if not ok then unhook();return false end
            eventHooks[#eventHooks+1]={spec[1],pre,post}
        end
        return true
    end
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
        add(instance,{'selector','relay','keyBox','keyFrame','keyInner','keyText'})
        add(instance.row,{'slider','wrapper','labelWidget','valueWidget'})
        if instance.pair then add(instance.pair,{'button','inner','nav','valueWidget','text'}) end
        for i in ipairs(instance.keyEdges or {}) do add(instance.keyEdges,{i}) end
        instance.liveRefs=refs
        instance.relayId=Discovery.address(instance.relay)
        instance.relayFullName=instance.relay:GetFullName()
    end
    local function refresh(instance,allowed)
        local fresh={}
        for i,ref in ipairs(instance.liveRefs) do
            if not allowed() then return false end
            local object=StaticFindObject(ref.path)
            if not Discovery.valid(object) or Discovery.address(object)~=ref.address or object:GetFullName()~=ref.full then return false end
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
                                    local callOk,pairOk,pairErr=pcall(KeySelector.mergePair,instanceOrErr,modeBinding.row,log)
                                    if not callOk then
                                        log('PAIR_EXCEPTION',provider.id..'.'..binding.settingId..': '..tostring(pairOk))
                                    elseif not pairOk then
                                        log('PAIR_FAILED',provider.id..'.'..binding.settingId..': '..tostring(pairErr))
                                    end
                                else
                                    log('PAIR_FAILED',provider.id..'.'..binding.settingId..': mode binding unavailable')
                                end
                            end
                            ledger(instanceOrErr)
                            relayOwners[instanceOrErr.relayId]={instance=instanceOrErr,path=activePath}
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
        local host=StaticFindObject(path)
        if not allowed() then return end
        if not Discovery.valid(host) or not host:IsInViewport() or not host:IsActivated() then
            scope:invalidate('host inactive');return
        end
        local state=hosts[path]
        if not state then
            state={bound={},decorated={},instances={},ticks=10,attempts=0}
            hosts[path]=state
        end
        activePath=path
        boundScrolls,decoratedSliders,instances=state.bound,state.decorated,state.instances
        state.ticks=state.ticks+1
        if state.ticks>=10 then
            state.ticks=0
            local snapshots=Discovery.activeTrees(host,allowed)
            if not allowed() then return end
            local snapshot=snapshots[1]
            if snapshot then
                for i=#instances,1,-1 do
                    local instance=instances[i]
                    local wrapperRef
                    for _,ref in ipairs(instance.liveRefs) do
                        if ref.target==instance.row and ref.key=='wrapper' then wrapperRef=ref;break end
                    end
                    if wrapperRef and not snapshot.widgets[wrapperRef.address] then
                        relayOwners[instance.relayId]=nil
                        for _,ref in ipairs(instance.liveRefs) do
                            if ref.key=='slider' then decoratedSliders[ref.address]=nil end
                        end
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
            end
            if next(boundScrolls)==nil then
                state.attempts=state.attempts+1
                if state.attempts>=3 then scope:invalidate('no supported page');return end
            else state.attempts=0 end
        end
        for _,instance in ipairs(instances) do
            if not allowed() then return end
            if refresh(instance,allowed) then
                local ok,alive=pcall(KeySelector.tick,instance,log)
                if ok and alive then instance.failed=false
                elseif not instance.failed then
                    instance.failed=true
                    log('SELECTOR_TICK_FAILED',tostring(alive))
                end
                -- Keep ownership on failure: the next fresh update can recover.
            end
        end
        -- No UObject access or new work after this generation is revoked.
        if allowed() then schedule(path,epoch,100) end
    end
    schedule=function(path,epoch,delay)
        if not scope or not scope:matches(path,epoch) or pending[epoch] then return end
        pending[epoch]=true
        ExecuteWithDelay(delay,function()
            if not scope:matches(path,epoch) then pending[epoch]=nil;return end
            ExecuteInGameThread(function()
                pending[epoch]=nil
                if not scope:matches(path,epoch) then return end
                if EngineTickAvailable==false then scope:invalidate('engine tick unavailable');return end
                local ok,err=pcall(tick,path,epoch)
                if not ok then log('DISCOVERY_FAILED',tostring(err));scope:invalidate('discovery failed') end
            end,EGameThreadMethod and EGameThreadMethod.EngineTick or nil)
        end)
    end
    local err
    scope,err=MenuScope.install(log,function(path,epoch)
        if not path then
            unhook()
            for _,owner in pairs(relayOwners) do owner.instance.pendingClicks=0 end
            return
        end
        for _,owner in pairs(relayOwners) do owner.instance.pendingClicks=0 end
        if not hookEvents() then scope:invalidate('delegate relay hooks unavailable');return end
        local state=hosts[path]
        if state then state.ticks=10;state.attempts=0 end
        schedule(path,epoch,0)
    end)
    if not scope then unhook();return false,err end
    return true
end
return M
