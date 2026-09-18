local Discovery=require('widget_discovery')
local KeySelector=require('key_selector')
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
    if type(FindAllOf)~='function' or type(LoopAsync)~='function' or type(ExecuteInGameThread)~='function' then
        return false,'FindAllOf/LoopAsync/ExecuteInGameThread unavailable'
    end
    -- Instance identities are strings/addresses captured while fresh. Replace
    -- every widget used by tick with the current snapshot's wrapper before use.
    local function ledger(instance)
        local refs={}
        local function add(target,keys)
            for _,key in ipairs(keys) do
                local object=target[key]
                if object then refs[#refs+1]={target=target,key=key,address=Discovery.address(object),name=object:GetFName():ToString()} end
            end
        end
        add(instance,{'selector','keyBox','keyFrame','keyInner','keyText'})
        add(instance.row,{'slider','wrapper','labelWidget','valueWidget'})
        if instance.pair then add(instance.pair,{'button','inner','nav','valueWidget','text'}) end
        for index,edge in ipairs(instance.keyEdges or {}) do
            refs[#refs+1]={target=instance.keyEdges,key=index,address=Discovery.address(edge),name=edge:GetFName():ToString()}
        end
        instance.liveRefs=refs
    end
    local function refresh(instance,widgets,names)
        for _,ref in ipairs(instance.liveRefs) do
            if not widgets[ref.address] or names[ref.address]~=ref.name then return false end
        end
        for _,ref in ipairs(instance.liveRefs) do ref.target[ref.key]=widgets[ref.address] end
        return true
    end
    local boundScrolls={}
    local decoratedSliders={}
    local instances={}

    local function bindPage(scroll,rows,provider)
        local scrollAddr=Discovery.address(scroll); if not scrollAddr or boundScrolls[scrollAddr] then return true end
        local page={providerId=provider.id,scrollName=scroll:GetFName():ToString(),rowsById={},ordered={},instances={}}

        -- Capture semantic identity for every DMM row before any visual pairing/mutation.
        for i,setting in ipairs(provider.choices) do
            local row=rows[i]
            local binding={providerId=provider.id,settingId=setting.id,sourceIndex=i,row=row,kind=row.kind,wrapperAddr=Discovery.address(row.wrapper),wrapperName=row.wrapper:GetFName():ToString()}
            page.rowsById[setting.id]=binding; page.ordered[i]=binding
            log('ROW_BOUND',provider.id..'.'..setting.id..' index='..i..' kind='..row.kind)
        end

        boundScrolls[scrollAddr]=page
        log('PAGE_MATCH',provider.id..' rows='..#rows)

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
                            log('DECORATED_ONCE',provider.id..'.'..binding.settingId..' slider='..sliderAddr)
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
                        else log('DECORATE_FAILED',provider.id..'.'..binding.settingId..': '..tostring(instanceOrErr)) end
                    else log('SKIP_ALREADY_DECORATED',provider.id..'.'..binding.settingId) end
                end
            end
        end
        return true
    end

    local queued,stopped=false,false
    local function tick()
        local widgets,names,scrolls={},{},{}
        for _,snapshot in ipairs(Discovery.activeTrees()) do
            for addr,widget in pairs(snapshot.widgets) do widgets[addr]=widget; names[addr]=snapshot.names[addr] end
            for _,scroll in ipairs(snapshot.scrolls) do scrolls[#scrolls+1]=scroll end
        end
        -- Closed/absent menus provide no current wrappers. Keep only dormant Lua
        -- identities; do not dereference them or redecorate a surviving reopened tree.
        if next(widgets)==nil then return end
        local recognized=false
        for _,scroll in ipairs(scrolls) do
            local addr=Discovery.address(scroll)
            local page=boundScrolls[addr]
            if page and names[addr]==page.scrollName then recognized=true;break end
            if #candidateProviders(registry,Discovery.rowsFromScroll(scroll) or {})==1 then recognized=true;break end
        end
        -- An unrelated CommonUI host is not evidence that our dormant page died.
        if not recognized then return end
        for addr,page in pairs(boundScrolls) do
            local alive=widgets[addr] and names[addr]==page.scrollName
            for _,binding in ipairs(page.ordered) do
                if not widgets[binding.wrapperAddr] or names[binding.wrapperAddr]~=binding.wrapperName then alive=false;break end
            end
            if not alive then boundScrolls[addr]=nil end
        end
        local keep={}
        decoratedSliders={}
        for _,instance in ipairs(instances) do
            if refresh(instance,widgets,names) then
                local ok,alive=pcall(KeySelector.tick,instance,log)
                if ok and alive then
                    keep[#keep+1]=instance
                    decoratedSliders[Discovery.address(instance.row.slider)]=true
                elseif not ok then log('SELECTOR_TICK_FAILED',tostring(alive)) end
            end
        end
        instances=keep
        for _,scroll in ipairs(scrolls) do
            local addr=Discovery.address(scroll)
            if not boundScrolls[addr] then
                local rows=Discovery.rowsFromScroll(scroll) or {}
                local candidates=candidateProviders(registry,rows)
                if #candidates==1 then bindPage(scroll,rows,candidates[1]) end
            end
        end
    end
    LoopAsync(100,function()
        if stopped then return true end
        if queued then return false end
        if EngineTickAvailable==false then return false end
        queued=true
        local function work()
            if EngineTickAvailable==false then queued=false;return end
            local ok,err=pcall(tick)
            queued=false
            if not ok then stopped=true; log('DISCOVERY_STOPPED',tostring(err)) end
        end
        local ok,err=pcall(function()
            if EGameThreadMethod and EGameThreadMethod.EngineTick then ExecuteInGameThread(work,EGameThreadMethod.EngineTick)
            else ExecuteInGameThread(work) end
        end)
        if not ok then queued=false;stopped=true;log('GAME_THREAD_DISPATCH_FAILED',tostring(err)) end
        return stopped
    end)
    log('DMM_DISCOVERY_READY','fresh active host trees; no Slider notifications; live identity refresh; strict provider page matching')
    return true
end
return M
