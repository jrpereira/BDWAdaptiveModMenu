-- Installed in DMM's own Lua state through DMM's startup extension API.
-- No second model, configuration writer, widget batch or polling loop.
local M={version=1}
local function trim(s) return (s or ''):match('^%s*(.-)%s*$') end
local function split(text,delimiter)
    local out={}
    for value in ((text or '')..delimiter):gmatch('(.-)'..delimiter) do out[#out+1]=trim(value) end
    return out
end
local function finite(value)
    local n=tonumber(value)
    return n and n==n and math.abs(n)<=1000000000 and n or nil
end

function M.parse(content,items,choices)
    local raw,current,count={},nil,0
    for line in (content..'\n'):gmatch('([^\n]*)\n') do
        local header=trim(line):match('^%[([^%]]+)%]$')
        if header then
            current=nil
            if header=='Setting' or header:match('^Setting%.') then
                count=count+1;current={fallback='setting_'..count};raw[#raw+1]=current
            end
        elseif current and not trim(line):match('^[;#]') then
            local key,value=line:match('^%s*([^=]+)=(.*)$')
            if key then current[trim(key)]=trim(value) end
        end
    end
    local byId,owners={},{ }
    for i,setting in ipairs(items) do byId[setting.id]=i end
    -- Do not compete with DMM's existing homogeneous linked presets.
    for i,s in ipairs(items) do
        if s.targets then for _,target in ipairs(s.targets) do owners[target]=i end end
    end
    for _,r in ipairs(raw) do
        if r.MappedPresetTargets or r.MappedPresetValues then
            local index=assert(byId[r.Id or r.fallback],'mapped preset has no supported setting')
            local setting=items[index]
            assert(setting.kind=='picker' and not setting.targets,'mapped preset requires an ordinary picker')
            assert(r.MappedPresetTargets and r.MappedPresetValues,'mapped preset requires targets and values')
            local custom=finite(r.CustomValue)
            assert(custom and choices.index(setting,custom),'mapped preset requires valid CustomValue')
            local mapping={custom=custom,targets={},values={}}
            for _,id in ipairs(split(r.MappedPresetTargets,'|')) do
                local target=assert(byId[id],'unknown mapped preset target '..id)
                assert(target~=index and not owners[target],'self, duplicate or overlapping mapped preset target')
                owners[target]=index;mapping.targets[#mapping.targets+1]=target
            end
            for _,entry in ipairs(split(r.MappedPresetValues,';')) do
                local key,payload=entry:match('^([^:]+):(.*)$')
                key=finite(key)
                assert(key and key~=custom and choices.index(setting,key) and not mapping.values[key],'invalid or duplicate mapped preset value')
                local values=split(payload,'|')
                assert(#values==#mapping.targets,'mapped preset target/value count differs')
                for n,target in ipairs(mapping.targets) do
                    local value=finite(values[n]);local child=items[target]
                    assert(value and choices.index(child,value),'mapped target value outside choices/range')
                    if child.kind=='slider' and value~=child.minimum and value~=child.maximum then
                        local snapped=choices.snap(child,value)
                        assert(math.abs(value-snapped)<0.000001,'mapped target value is off step')
                    end
                    values[n]=value
                end
                mapping.values[key]=values
            end
            for _,value in ipairs(setting.values) do
                assert(value==custom or mapping.values[value],'missing mapped preset values')
            end
            setting.kemMapping=mapping
        end
    end
    for i,s in ipairs(items) do
        if s.kemMapping then
            assert(not owners[i],'a mapped preset cannot itself be a linked target')
            for _,target in ipairs(s.kemMapping.targets) do
                assert(not items[target].kemMapping and not items[target].targets,'nested mapped presets are unsupported')
            end
        end
    end
    return items
end

function M.wrap(model,choices)
    if model.kemMappedVersion then return model end
    local owners,mappings={},{ }
    for i,s in ipairs(model.items) do
        if s.kemMapping then
            mappings[i]=s.kemMapping
            for _,target in ipairs(s.kemMapping.targets) do owners[target]=i end
        end
    end
    if next(mappings)==nil or model.error then return model end
    model.kemMappedVersion=M.version
    model.kemHiddenDirty={}
    model.kemVisualDirty={}
    local showDirty=true
    local set,reset,restore,apply,change=model.set,model.reset,model.restore,model.apply,model.change
    local baseline={}
    local function matches(owner)
        local mapping=mappings[owner];local values=mapping.values[model.pending[owner]]
        if not values then return model.pending[owner]==mapping.custom end
        for n,target in ipairs(mapping.targets) do if model.pending[target]~=values[n] then return false end end
        return true
    end
    function model:showDirty(show)
        assert(type(show)=='boolean','showDirty must be boolean')
        local previous=showDirty;showDirty=show;return previous
    end
    function model:set(index,value)
        if self.error or not self.items[index] or not choices.index(self.items[index],value) then return end
        local before=self.pending[index]
        local mapping=mappings[index]
        -- Custom describes unmatched bindings; it is never a user-selected preset.
        if mapping and value==mapping.custom then self.kemRejectedIndex=index;return end
        local snapshot,hidden
        if mapping then
            snapshot={};hidden={}
            for i,v in ipairs(self.pending) do snapshot[i]=v end
            for i,v in pairs(self.kemHiddenDirty) do hidden[i]=v end
        end
        set(self,index,value)
        if mapping then
            local values=mapping.values[self.pending[index]]
            if not values then return end
            -- One synchronous edit: DMM cannot refresh or Apply halfway through.
            local previous=self:showDirty(false)
            local ok,err=pcall(function()
                for n,target in ipairs(mapping.targets) do
                    set(self,target,values[n])
                    self.kemHiddenDirty[target]=self.pending[target]~=self.committed[target] or nil
                end
            end)
            self:showDirty(previous)
            if not ok then
                for i,v in ipairs(snapshot) do self.pending[i]=v end
                self.kemHiddenDirty=hidden
            end
            assert(ok,err)
            for _,target in ipairs(mapping.targets) do baseline[target]=self.pending[target];self.kemVisualDirty[target]=false end
        elseif before~=self.pending[index] then
            self.kemHiddenDirty[index]=not showDirty and self.pending[index]~=self.committed[index] or nil
            local owner=owners[index]
            if owner then
                local selected=mappings[owner].custom
                for _,candidate in ipairs(self.items[owner].values) do
                    local values=mappings[owner].values[candidate]
                    if values then
                        local equal=true
                        for n,target in ipairs(mappings[owner].targets) do
                            if self.pending[target]~=values[n] then equal=false;break end
                        end
                        if equal then selected=candidate;break end
                    end
                end
                set(self,owner,selected)
                self.kemHiddenDirty[index]=baseline[index]~=nil and self.pending[index]==baseline[index] or nil
                if baseline[index]~=nil then self.kemVisualDirty[index]=self.pending[index]~=baseline[index] end
            end
        end
    end
    function model:change(index,direction)
        local mapping=mappings[index]
        if not mapping then return change(self,index,direction) end
        local values=self.items[index].values
        local position=choices.index(self.items[index],self.pending[index])
        local delta=direction==1 and -1 or 1
        position=position+delta
        while position>=1 and position<=#values do
            if values[position]~=mapping.custom then return self:set(index,values[position]) end
            position=position+delta
        end
    end
    function model:restore()
        restore(self);self.kemHiddenDirty={};self.kemVisualDirty={};baseline={};showDirty=true
    end
    function model:reset(index)
        reset(self,index)
        if not index then
            self.kemHiddenDirty={};self.kemVisualDirty={};baseline={};showDirty=true
            for owner,mapping in pairs(mappings) do
                if not matches(owner) then set(self,owner,mapping.custom) end
            end
        end
    end
    function model:apply()
        local ok,err,event=apply(self)
        if ok then self.kemHiddenDirty={};self.kemVisualDirty={};baseline={};showDirty=true end
        return ok,err,event
    end
    -- A stale saved preset ID never overwrites saved custom keys on opening.
    for owner,mapping in pairs(mappings) do
        if not matches(owner) then set(model,owner,mapping.custom) end
    end
    return model
end

function M.install(choices,controls)
    assert(type(choices)=='table' and type(choices.parse)=='function' and type(choices.open)=='function'
        and type(choices.index)=='function' and type(choices.snap)=='function'
        and type(choices.format)=='function','unsupported DMM choices API')
    assert(type(controls)=='table' and type(controls.build)=='function','unsupported DMM controls API')
    if choices.kemMappedVersion then
        assert(choices.kemMappedVersion==M.version and controls.kemMappedVersion==M.version,'incompatible KEM mapping wrapper')
        return false
    end
    local parse,open,build=choices.parse,choices.open,controls.build
    choices.parse=function(content) return M.parse(content,parse(content),choices) end
    choices.open=function(provider) return M.wrap(open(provider),choices) end
    controls.build=function(tree,providers,api)
        local adapted={};for k,v in pairs(api) do adapted[k]=v end
        local ui,indices
        adapted.setText=function(widget,text)
            local index=indices and indices[widget]
            local visual=index and ui.model.kemVisualDirty and ui.model.kemVisualDirty[index]
            if visual~=nil then
                text=choices.format(ui.model.items[index],ui.model.pending[index])..(visual and ' *' or '')
            elseif index and ui.model.kemHiddenDirty and ui.model.kemHiddenDirty[index] then
                -- This changes presentation only; committed values are untouched.
                text=choices.format(ui.model.items[index],ui.model.pending[index])
            end
            return api.setText(widget,text)
        end
        ui=build(tree,providers,adapted)
        local refresh=ui.refresh
        function ui:refresh(...)
            indices={}
            local panel=self.panels[self.active]
            for i,row in ipairs(panel.rows) do
                indices[row.value]=i
                local hidden=self.model.kemHiddenDirty and self.model.kemHiddenDirty[i] or false
                local visual=self.model.kemVisualDirty and self.model.kemVisualDirty[i]
                if row.kemHiddenDirty~=hidden or row.kemVisualDirty~=visual or self.model.kemRejectedIndex==i then
                    row.rendered=false;row.renderText=nil;row.kemHiddenDirty=hidden
                    row.kemVisualDirty=visual
                end
            end
            self.model.kemRejectedIndex=nil
            return refresh(self,...)
        end
        return ui
    end
    choices.kemMappedVersion=M.version;controls.kemMappedVersion=M.version
    return true
end
return M
