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
    if type(NotifyOnNewObject)~='function' or type(LoopAsync)~='function' or type(ExecuteInGameThread)~='function' then
        return false,'NotifyOnNewObject/LoopAsync/ExecuteInGameThread unavailable'
    end

    -- Async timers only schedule work. All hierarchy access and widget mutation
    -- runs on the game thread; at most one job per timer may be outstanding.
    local function dispatch(fn)
        if EGameThreadMethod and EGameThreadMethod.EngineTick then
            ExecuteInGameThread(fn,EGameThreadMethod.EngineTick)
        else ExecuteInGameThread(fn) end
    end
    local function loopGameThread(interval,fn)
        local queued,done=false,false
        LoopAsync(interval,function()
            if done then return true end
            if queued then return false end
            queued=true
            local ok,err=pcall(dispatch,function()
                local success,finished=pcall(fn)
                queued=false
                if not success then
                    done=true; log('GAME_THREAD_JOB_FAILED',tostring(finished))
                elseif finished then done=true end
            end)
            if not ok then queued=false; done=true; log('GAME_THREAD_DISPATCH_FAILED',tostring(err)) end
            return done
        end)
    end

    local pendingSliders={}      -- physical Slider address -> true while waiting for parent hierarchy
    local pendingScrolls={}      -- physical ScrollBox address -> true while bounded discovery is active
    local boundScrolls={}        -- physical ScrollBox address -> semantic page binding
    local decoratedSliders={}   -- physical stock Slider address -> true
    local instances={}          -- one global monitor list, no per-row LoopAsync callbacks

    local function bindPage(scroll,rows,provider)
        local scrollAddr=Discovery.address(scroll); if not scrollAddr or boundScrolls[scrollAddr] then return true end
        local page={providerId=provider.id,scroll=scroll,rowsById={},ordered={},instances={}}

        -- Capture semantic identity for every DMM row before any visual pairing/mutation.
        for i,setting in ipairs(provider.choices) do
            local row=rows[i]
            local binding={providerId=provider.id,settingId=setting.id,sourceIndex=i,row=row,kind=row.kind}
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
                        else log('DECORATE_FAILED',provider.id..'.'..binding.settingId..': '..tostring(instanceOrErr)) end
                    else log('SKIP_ALREADY_DECORATED',provider.id..'.'..binding.settingId) end
                end
            end
        end
        return true
    end

    local function scheduleScroll(scroll)
        if not Discovery.valid(scroll) then return end
        local addr=Discovery.address(scroll); if not addr or pendingScrolls[addr] or boundScrolls[addr] then return end
        pendingScrolls[addr]=true
        local tries=0; local lastCount=-1; local stable=0
        loopGameThread(16,function()
            tries=tries+1
            if not Discovery.valid(scroll) then pendingScrolls[addr]=nil; return true end
            local rows=Discovery.rowsFromScroll(scroll) or {}
            if #rows==lastCount then stable=stable+1 else lastCount=#rows; stable=0 end
            local candidates=candidateProviders(registry,rows)
            if #candidates==1 then
                pendingScrolls[addr]=nil; bindPage(scroll,rows,candidates[1]); return true
            end
            -- Wait for populate() to finish. Reject only after the row count has settled.
            if tries>=40 or (stable>=8 and tries>=12) then
                pendingScrolls[addr]=nil
                if #rows>0 then log('PAGE_REJECTED','scroll='..addr..' rows='..#rows..' candidates='..#candidates) end
                return true
            end
            return false
        end)
    end

    local function scheduleSlider(slider)
        if not Discovery.valid(slider) then return end
        local sliderAddr=Discovery.address(slider)
        if not sliderAddr or pendingSliders[sliderAddr] or decoratedSliders[sliderAddr] then return end
        pendingSliders[sliderAddr]=true
        local tries=0
        loopGameThread(16,function()
            tries=tries+1
            if not Discovery.valid(slider) then pendingSliders[sliderAddr]=nil; return true end
            -- NotifyOnNewObject fires during UObject construction, before DMM has attached the
            -- Slider to its row/ScrollBox. Resolve ancestry only after the hierarchy exists.
            local scroll=Discovery.ancestorOfClass(slider,'ScrollBox',10)
            if scroll then
                pendingSliders[sliderAddr]=nil
                scheduleScroll(scroll)
                return true
            end
            if tries>=32 then pendingSliders[sliderAddr]=nil; return true end
            return false
        end)
    end

    NotifyOnNewObject('/Script/UMG.Slider',function(slider)
        -- Global observation only; no mutation occurs unless the eventual ScrollBox exactly
        -- matches a provider reconstructed from a real mod_settings.ini.
        local ok,err=pcall(dispatch,function() scheduleSlider(slider) end)
        if not ok then log('GAME_THREAD_DISPATCH_FAILED',tostring(err)) end
    end)

    loopGameThread(40,function()
        local keep={}
        for _,instance in ipairs(instances) do
            local ok,alive=pcall(KeySelector.tick,instance,log)
            if ok and alive then keep[#keep+1]=instance
            elseif not ok then log('SELECTOR_TICK_FAILED',tostring(alive)) end
        end
        instances=keep
        return false
    end)

    log('DMM_DISCOVERY_READY','deferred hierarchy + strict manifest-order page matching + non-reparenting paired proxy + protected merge enabled')
    return true
end
return M
