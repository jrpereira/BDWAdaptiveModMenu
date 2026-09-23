-- A presentation-only picker can drive DMM visibility without owning a config key.
local M={version=1}
local function trim(value) return (value or ''):match('^%s*(.-)%s*$') end

function M.parse(content,items)
    local current,marked,sections=nil,0,0
    local byId={}
    for _,item in ipairs(items) do byId[item.id]=item end
    local function finish()
        if not current or current.ammNavigation==nil then return end
        assert(current.ammNavigation=='1','ammNavigation must be 1')
        local item=assert(byId[current.Id or ('setting_'..sections)],
            'navigation picker setting unavailable')
        assert(item.kind=='picker','ammNavigation requires a picker')
        assert(not item.targets and not current.MappedPresetTargets,
            'navigation picker cannot own preset targets')
        marked=marked+1
        assert(marked<=1,'only one navigation picker per provider')
        item.ammNavigation=true
    end
    for line in (content..'\n'):gmatch('([^\n]*)\n') do
        local section=trim(line):match('^%[([^%]]+)%]$')
        if section then
            finish()
            current=(section=='Setting' or section:match('^Setting%.')) and {} or nil
            if current then sections=sections+1 end
        elseif current then
            local key,value=line:match('^%s*([^=]+)=(.*)$')
            if key then current[trim(key)]=trim(value) end
        end
    end
    finish()
    return items
end

function M.open(provider,open)
    local index
    for i,setting in ipairs(provider.choices or {}) do
        if setting.ammNavigation then index=i;break end
    end
    if not index then return open(provider) end
    local items={}
    for i,setting in ipairs(provider.choices) do
        if i~=index then
            local copy={}
            for key,value in pairs(setting) do copy[key]=value end
            if copy.targets then
                local targets={}
                for n,target in ipairs(copy.targets) do
                    assert(target~=index,'navigation picker cannot be a preset target')
                    targets[n]=target>index and target-1 or target
                end
                copy.targets=targets
            end
            items[#items+1]=copy
        end
    end
    local filtered={}
    for key,value in pairs(provider) do filtered[key]=value end
    filtered.choices=items
    local model=open(filtered)
    if model.error then return model end
    local navigation=provider.choices[index]
    table.insert(model.items,index,navigation)
    table.insert(model.pending,index,navigation.default)
    table.insert(model.committed,index,navigation.default)
    -- Restore original indices, including visibility and native linked presets.
    for i,setting in ipairs(model.items) do model.items[i]=provider.choices[i] end
    model.provider=provider
    local set,reset,apply=model.set,model.reset,model.apply
    function model:set(i,value)
        set(self,i,value)
        if i==index then self.committed[index]=self.pending[index] end
    end
    function model:reset(i)
        local view=i==nil and self.pending[index]
        reset(self,i)
        if view~=nil then self.pending[index]=view end
        if i==nil or i==index then self.committed[index]=self.pending[index] end
    end
    function model:apply()
        local item=table.remove(self.items,index)
        local pending=table.remove(self.pending,index)
        local committed=table.remove(self.committed,index)
        local ok,success,why,event=pcall(apply,self)
        table.insert(self.items,index,item)
        table.insert(self.pending,index,pending)
        table.insert(self.committed,index,committed)
        if not ok then error(success) end
        return success,why,event
    end
    return model
end

function M.install(choices)
    if choices.ammNavigationVersion then return false end
    local parse,open=choices.parse,choices.open
    choices.parse=function(content) return M.parse(content,parse(content)) end
    choices.open=function(provider) return M.open(provider,open) end
    choices.ammNavigationVersion=M.version
    return true
end
return M
