-- Inert menu-fix template. The category host may bind the returned callbacks,
-- but loading this file registers no UE4SS events or hooks.
local M={
    name='Dawnwalker Settings Page Fixes',
    category='menu.fixes',
    settings={target='module',enabled=true},
    version=1,
}

local HEADER='/Game/_Dawnwalker/UI/_Unified/Settings/WBP_Settings_CategoryHeader.WBP_Settings_CategoryHeader_C'
local TEXT='/Script/Engine.Default__KismetTextLibrary'
local CONTROLS='UI.Settings.Controls'
local CONTROLLER='UI.Settings.Controller'

local function unwrap(value)
    local ok,result=pcall(function() return value:get() end)
    return ok and result or value
end

local function valid(value) return value and value:IsValid() end

local function name(value)
    local ok,result=pcall(function() return value:ToString() end)
    return ok and result or tostring(value)
end

local function address(value)
    local ok,result=pcall(function() return value:GetAddress() end)
    return ok and tostring(result) or nil
end

local function panelTag(panel)
    if not valid(panel) then return nil end
    local tag=panel['Panel Tag']
    return tag and name(tag.TagName) or nil
end

local function panelForBox(box)
    if not valid(box) or name(box:GetFName())~='SettingEntryBox' then return nil end
    local tree=box:GetOuter()
    local panel=valid(tree) and tree:GetOuter() or nil
    if not valid(panel) then return nil end
    local owned=panel.SettingEntryBox
    if not valid(owned) or address(owned)~=address(box) then return nil end
    return panel
end

local function sameDashboard(left,right)
    local a=valid(left) and left['Owning Dashboard'] or nil
    local b=valid(right) and right['Owning Dashboard'] or nil
    return valid(a) and valid(b) and address(a)==address(b)
end

local function values(array)
    local result={}
    if array and type(array.ForEach)=='function' then
        array:ForEach(function(_,item)
            local value=unwrap(item)
            if valid(value) then result[#result+1]=value end
        end)
    end
    return result
end

function M.createCallbacks(log,api)
    log=log or function() end
    api=api or _G
    assert(type(api.StaticFindObject)=='function','StaticFindObject unavailable')
    assert(type(api.ExecuteWithDelay)=='function','ExecuteWithDelay unavailable')
    local textLibrary=api.StaticFindObject(TEXT)
    assert(valid(textLibrary),'text library unavailable')
    local state={controls=nil,controller=nil,controlsTable=nil,rebuilding=false,injecting=false,
        inserted=false,pending=false,controllerRows={}}

    local function createHeader(box,label)
        local class=api.StaticFindObject(HEADER)
        assert(valid(class),'native category-header class unavailable')
        local header=box:BP_CreateEntryOfClass(class)
        assert(valid(header) and valid(header.Label),'native category-header creation failed')
        header.Label:SetText(textLibrary:Conv_StringToText(label))
        return header
    end

    local function rememberNewRows(panel,before)
        local known={}
        for _,widget in ipairs(before) do known[address(widget)]=true end
        for _,widget in ipairs(values(panel['Displayed Settings'])) do
            local id=address(widget)
            if id and not known[id] then state.controllerRows[id]=true end
        end
    end

    local function clearController(panel)
        local box=panel.SettingEntryBox
        if valid(box) then box:Reset(false) end
        local displayed=panel['Displayed Settings']
        if displayed and type(displayed.Empty)=='function' then displayed:Empty() end
        if valid(panel.MainBox) then panel.MainBox:SetVisibility(1) end
    end

    local function relocate()
        state.pending=false
        local controls,controller=state.controls,state.controller
        if state.rebuilding or not valid(controls) or not valid(controller) or not valid(state.controlsTable)
            or not sameDashboard(controls,controller) then return end
        local source=values(controller['Displayed Settings'])
        if #source~=3 then
            log('NATIVE_SETTINGS_DEFERRED','expected three Controller settings, found '..tostring(#source))
            return
        end
        state.rebuilding=true
        state.inserted=false
        state.controllerRows={}
        local ok,err=pcall(function() controls:SetupPanelFromTable(state.controlsTable) end)
        state.rebuilding=false
        if not ok then error(err) end
        assert(state.inserted,'Controller settings insertion point was not reached')
        clearController(controller)
    end

    local function queueRelocation()
        if state.pending or state.rebuilding then return end
        state.pending=true
        local queued,err=pcall(api.ExecuteWithDelay,0,function()
            local ok,why=pcall(relocate)
            if not ok then log('NATIVE_SETTINGS_FAILED',tostring(why)) end
        end)
        if not queued then state.pending=false;error(err) end
    end

    local function afterReset(context)
        local ok,err=pcall(function()
            local box=unwrap(context)
            local panel=panelForBox(box)
            if panelTag(panel)~=CONTROLS or box:GetNumEntries()~=0 then return end
            createHeader(box,'Mouse Settings')
        end)
        if not ok then log('NATIVE_SETTINGS_FAILED',tostring(err)) end
    end

    local function afterCreate(context)
        if not state.rebuilding or state.injecting or state.inserted then return end
        local ok,err=pcall(function()
            local panel=unwrap(context)
            if panel~=state.controls and address(panel)~=address(state.controls) then return end
            local box=panel.SettingEntryBox
            -- Mouse header plus the three original mouse settings are complete.
            if not valid(box) or box:GetNumEntries()~=4 then return end
            state.inserted=true
            createHeader(box,'Controller Settings')
            local before=values(panel['Displayed Settings'])
            state.injecting=true
            local injected,why=pcall(function()
                for _,widget in ipairs(values(state.controller['Displayed Settings'])) do
                    panel:CreateSettingWidget(widget.TargetEntry)
                end
            end)
            state.injecting=false
            if not injected then error(why) end
            rememberNewRows(panel,before)
        end)
        if not ok then state.injecting=false;log('NATIVE_SETTINGS_FAILED',tostring(err)) end
    end

    local function afterSetup(context,tableParam)
        if state.rebuilding then return end
        local ok,err=pcall(function()
            local panel=unwrap(context)
            local tag=panelTag(panel)
            if tag==CONTROLS then
                state.controls=panel
                state.controlsTable=unwrap(tableParam)
                if valid(state.controller) and sameDashboard(panel,state.controller) then queueRelocation() end
            elseif tag==CONTROLLER then
                state.controller=panel
                if valid(state.controls) and sameDashboard(state.controls,panel) then queueRelocation() end
            end
        end)
        if not ok then log('NATIVE_SETTINGS_FAILED',tostring(err)) end
    end

    local function afterSelect(context,selectedParam)
        local ok,err=pcall(function()
            local selected=unwrap(context)
            local isSelected=unwrap(selectedParam)
            if isSelected~=true or not valid(selected) or not state.controllerRows[address(selected)] then return end
            local panel=state.controls
            if panelTag(panel)~=CONTROLS then return end
            assert(valid(panel.DescriptionSwitcher) and valid(panel.ControllerPresetPanel),
                'Controls controller-description panel unavailable')
            panel.DescriptionSwitcher:SetActiveWidget(panel.ControllerPresetPanel)
        end)
        if not ok then log('NATIVE_SETTINGS_FAILED',tostring(err)) end
    end

    return {
        afterReset=afterReset,
        afterSetup=afterSetup,
        afterCreate=afterCreate,
        afterSelect=afterSelect,
    }
end

M._test={header=HEADER,text=TEXT,controls=CONTROLS,controller=CONTROLLER,panelForBox=panelForBox,
    values=values,sameDashboard=sameDashboard}
return M
