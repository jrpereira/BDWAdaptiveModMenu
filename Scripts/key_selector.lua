local Codes=require('key_codes')
local Discovery=require('widget_discovery')
local M={}

local function valid(o) return Discovery.valid(o) end
local function need(o,label) assert(valid(o),label..' unavailable'); return o end

local classes={}
local function class(path)
    local c=classes[path]
    if not valid(c) then c=need(StaticFindObject(path),path); classes[path]=c end
    return c
end

local function construct(path,tree)
    return need(StaticConstructObject(class(path),tree),path..' construction')
end

local function chordFor(name)
    return {Key={KeyName=FName(name)},bShift=false,bCtrl=false,bAlt=false,bCmd=false}
end

local function keyNameFromChord(chord)
    if not chord then return nil end
    local ok,name=pcall(function()
        local key=chord.Key
        local keyName=key and key.KeyName
        if keyName and keyName.ToString then return keyName:ToString() end
        return tostring(keyName)
    end)
    if ok and name and name~='' then return name end
end

local function selectedName(selector)
    local ok,chord=pcall(function() return selector.SelectedKey end)
    if not ok then return nil,tostring(chord) end
    local name=keyNameFromChord(chord)
    if not name then return nil,'SelectedKey did not contain a readable FKey name' end
    return name
end

local textLib=nil
local function setText(widget,text,step)
    -- TextBlock:SetText expects FText. Never probe it with a raw Lua string:
    -- a native UE4SS access violation cannot reach a pcall fallback.
    local function call(name,fn)
        if step then return step(name,fn) end
        return fn()
    end
    local ok,result=pcall(function()
        if not call('validate_text_target',function() return valid(widget) end) then return false end
        if not valid(textLib) then
            textLib=call('resolve_text_library',function()
                return StaticFindObject('/Script/Engine.Default__KismetTextLibrary')
            end)
        end
        if not call('validate_text_library',function() return valid(textLib) end) then return false end
        local value=call('convert_string_to_ftext',function() return textLib:Conv_StringToText(text) end)
        if value==nil then return false end
        call('assign_ftext',function() widget:SetText(value) end)
        return true
    end)
    if not ok then return false,result end
    return result
end

local function dirtyText(widget)
    local text=Discovery.textOf(widget) or ''
    return text:match('%s%*%s*$')~=nil,text
end

local function stripDirtySuffix(text)
    return (text or ''):gsub('%s+%*%s*$','')
end

local function displayName(name)
    local aliases={None='Unbound',SpaceBar='Space',BackSpace='Backspace',ThumbMouseButton='Mouse 4',ThumbMouseButton2='Mouse 5',LeftMouseButton='LMB',RightMouseButton='RMB',MiddleMouseButton='MMB'}
    return aliases[name] or name or ''
end

local function styleNormal(instance)
    for _,edge in ipairs(instance.keyEdges or {}) do pcall(function() edge:SetBrushColor({R=0.55,G=0.52,B=0.46,A=0.85}) end) end
    if valid(instance.keyInner) then pcall(function() instance.keyInner:SetBrushColor({R=0.12,G=0.12,B=0.12,A=0.30}) end) end
end

local function styleSelecting(instance)
    for _,edge in ipairs(instance.keyEdges or {}) do pcall(function() edge:SetBrushColor({R=0.95,G=0.63,B=0.08,A=1.0}) end) end
    if valid(instance.keyInner) then pcall(function() instance.keyInner:SetBrushColor({R=0.95,G=0.63,B=0.08,A=0.16}) end) end
end

function M.decorate(row,descriptor,log)
    if not row or not valid(row.slider) then return nil,'invalid numeric row' end
    local tree=row.tree
    log('DECORATE_PREFLIGHT',descriptor.providerId..'.'..descriptor.settingId)

    -- Keep the stock Slider UObject as DMM's authoritative numeric control, but make its
    -- visuals invisible. The decorator adds a styled capture surface above it.
    pcall(function() row.slider:SetRenderOpacity(0) end)
    pcall(function() row.valueWidget:SetRenderOpacity(0) end)

    local existing=Discovery.childCount(row.surface)
    for i=0,existing-1 do
        local child=Discovery.childAt(row.surface,i)
        if valid(child) and Discovery.address(child)~=Discovery.address(row.slider) then pcall(function() child:SetRenderOpacity(0) end) end
    end

    local keyBox=construct('/Script/UMG.SizeBox',tree)
    keyBox:SetWidthOverride(96); keyBox:SetHeightOverride(32)
    local keyOverlay=construct('/Script/UMG.Overlay',tree)
    need(keyBox:SetContent(keyOverlay),'key box content')

    local keyFrame=construct('/Script/UMG.Border',tree)
    keyFrame:SetBrushColor({R=0,G=0,B=0,A=0})
    keyFrame:SetPadding({Left=1,Top=1,Right=1,Bottom=1})
    local frameSlot=need(keyOverlay:AddChildToOverlay(keyFrame),'key frame slot')
    frameSlot:SetHorizontalAlignment(0); frameSlot:SetVerticalAlignment(0)

    local keyInner=construct('/Script/UMG.Border',tree)
    keyInner:SetBrushColor({R=0.12,G=0.12,B=0.12,A=0.30})
    local innerSlot=need(keyFrame:SetContent(keyInner),'key inner content')
    innerSlot:SetHorizontalAlignment(0); innerSlot:SetVerticalAlignment(0)

    -- Separate one-pixel edges: a filled outer Border would remain opaque behind
    -- the translucent inner surface, making the whole key field look solid.
    local keyEdges={}
    for _,edge in ipairs({{1,32,1,2},{1,32,3,2},{96,1,0,1},{96,1,0,3}}) do
        local box=construct('/Script/UMG.SizeBox',tree)
        box:SetWidthOverride(edge[1]); box:SetHeightOverride(edge[2])
        local border=construct('/Script/UMG.Border',tree)
        border:SetBrushColor({R=0.55,G=0.52,B=0.46,A=0.85})
        border:SetVisibility(3)
        need(box:SetContent(border),'key outline edge')
        box:SetVisibility(3)
        local slot=need(keyOverlay:AddChildToOverlay(box),'key outline slot')
        slot:SetHorizontalAlignment(edge[3]); slot:SetVerticalAlignment(edge[4])
        keyEdges[#keyEdges+1]=border
    end

    local keyText=construct('/Script/UMG.TextBlock',tree)
    keyText:SetJustification(1); keyText:SetTextOverflowPolicy(1)
    -- Reuse the stock DMM text font. Scale down slightly rather than inventing a font.
    pcall(function() keyText:SetFont(row.valueWidget.Font) end)
    pcall(function() keyText:SetRenderTransformPivot({X=0.5,Y=0.5}); keyText:SetRenderScale({X=0.84,Y=0.84}) end)
    local textSlot=need(keyInner:SetContent(keyText),'key text content')
    textSlot:SetHorizontalAlignment(0); textSlot:SetVerticalAlignment(2)
    textSlot:SetPadding({Left=4,Top=0,Right=4,Bottom=0})

    local selector=construct('/Script/UMG.InputKeySelector',tree)
    log('SELECTOR_CREATED',descriptor.providerId..'.'..descriptor.settingId)
    selector:SetAllowGamepadKeys(false); selector:SetAllowModifierKeys(false)
    selector:SetEscapeKeys({{KeyName=FName('Escape')}})
    selector:SetRenderOpacity(0.0)
    local ss=need(keyOverlay:AddChildToOverlay(selector),'selector slot')
    ss:SetHorizontalAlignment(0); ss:SetVerticalAlignment(0)

    local hostSlot=need(row.surface:AddChildToOverlay(keyBox),'key host slot')
    hostSlot:SetHorizontalAlignment(1); hostSlot:SetVerticalAlignment(2)
    log('SELECTOR_ATTACHED',descriptor.providerId..'.'..descriptor.settingId)

    -- Reserve the stock three-column row for: label | key | optional pair.
    if descriptor.modeId then
        row.labelBox:SetWidthOverride(330); row.surfaceBox:SetWidthOverride(96); row.valueBox:SetWidthOverride(158)
    else
        row.labelBox:SetWidthOverride(488); row.surfaceBox:SetWidthOverride(96); row.valueBox:SetWidthOverride(0)
    end

    return {
        descriptor=descriptor,row=row,selector=selector,keyBox=keyBox,keyFrame=keyFrame,keyInner=keyInner,keyText=keyText,keyEdges=keyEdges,
        baseLabel=row.label or descriptor.settingId,initialized=false,lastName=nil,lastBackingName=nil,wasSelecting=false,
        awaitingDmm=false,awaitingTicks=0,targetValue=nil,targetNormalized=nil,pair=nil,labelDirty=nil,
    }
end

function M.mergePair(instance,modeRow,log)
    if not instance or not modeRow or modeRow.kind~='picker' then return false,'mode row is not a picker' end
    if not valid(modeRow.wrapper) or not valid(modeRow.nav) or not valid(modeRow.valueWidget) or not valid(instance.row.surface) then return false,'pair widgets unavailable' end
    local tree=instance.row.tree
    local id=instance.descriptor.providerId..'.'..instance.descriptor.settingId

    -- Keep the stock picker row and every stock child UObject in place. Build the visible
    -- proxy from widgets whose composition paths are already proven elsewhere in MMD:
    -- SizeBox -> Overlay -> Border -> TextBlock, plus a transparent sibling Button used
    -- only as a hit target. In particular, never call Button:SetContent(); v0.1.9 showed
    -- a native UE4SS failure immediately after constructing the TextBlock on that path.
    log('PAIR_PROXY_STEP',id..' construct_box')
    local pairBox=construct('/Script/UMG.SizeBox',tree)
    pairBox:SetWidthOverride(150); pairBox:SetHeightOverride(32)

    log('PAIR_PROXY_STEP',id..' construct_overlay')
    local pairOverlay=construct('/Script/UMG.Overlay',tree)
    need(pairBox:SetContent(pairOverlay),'pair box content')

    log('PAIR_PROXY_STEP',id..' construct_frame')
    local pairFrame=construct('/Script/UMG.Border',tree)
    pairFrame:SetBrushColor({R=0,G=0,B=0,A=0})
    pairFrame:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
    local fs=need(pairOverlay:AddChildToOverlay(pairFrame),'pair frame slot')
    fs:SetHorizontalAlignment(0); fs:SetVerticalAlignment(0)

    local pairInner=construct('/Script/UMG.Border',tree)
    pairInner:SetBrushColor({R=0.12,G=0.12,B=0.12,A=0.10})
    local innerSlot=need(pairFrame:SetContent(pairInner),'pair inner content')
    innerSlot:SetHorizontalAlignment(0); innerSlot:SetVerticalAlignment(0)

    -- Each BEGIN is emitted before crossing into UE4SS; END proves that call returned.
    -- pcall reports Lua errors only. It cannot contain a native access violation.
    local function textStep(name,fn)
        log('PAIR_TEXT_BEGIN',id..' '..name)
        local ok,result=pcall(fn)
        if not ok then
            log('PAIR_TEXT_LUA_ERROR',id..' '..name..' '..tostring(result))
            error(result,0)
        end
        log('PAIR_TEXT_END',id..' '..name)
        return result
    end
    log('PAIR_PROXY_STEP',id..' construct_text')
    local textClass=textStep('resolve_class',function() return class('/Script/UMG.TextBlock') end)
    local pairText=textStep('construct_object',function() return StaticConstructObject(textClass,tree) end)
    textStep('validate_object',function() return need(pairText,'pair TextBlock construction') end)
    textStep('set_justification',function() pairText:SetJustification(1) end)
    textStep('set_overflow',function() pairText:SetTextOverflowPolicy(1) end)
    pcall(function()
        local font=textStep('read_mode_font',function() return modeRow.valueWidget.Font end)
        textStep('set_font',function() pairText:SetFont(font) end)
    end)
    pcall(function()
        textStep('set_pivot',function() pairText:SetRenderTransformPivot({X=0.5,Y=0.5}) end)
        textStep('set_scale',function() pairText:SetRenderScale({X=0.88,Y=0.88}) end)
    end)
    local initial=stripDirtySuffix(textStep('read_mode_text',function() return Discovery.textOf(modeRow.valueWidget) end) or '')
    local textSet=textStep('set_initial_text',function()
        local ok,err=setText(pairText,initial,textStep)
        if not ok then error('pair initial text unavailable: '..tostring(err or 'invalid widget, library, or FText'),0) end
        return true
    end)
    local rawSlot=textStep('attach_text',function() return pairInner:SetContent(pairText) end)
    local ts=textStep('validate_slot',function() return need(rawSlot,'pair text content') end)
    textStep('slot_horizontal',function() ts:SetHorizontalAlignment(0) end)
    textStep('slot_vertical',function() ts:SetVerticalAlignment(2) end)
    textStep('slot_padding',function() ts:SetPadding({Left=4,Top=0,Right=4,Bottom=0}) end)

    log('PAIR_PROXY_STEP',id..' construct_hit_target')
    local pairButton=construct('/Script/UMG.Button',tree)
    pairButton.IsFocusable=false
    pcall(function() pairButton:SetBackgroundColor({R=0,G=0,B=0,A=0}) end)
    pcall(function() pairButton:SetRenderOpacity(0) end)
    local bs=need(pairOverlay:AddChildToOverlay(pairButton),'pair hit target slot')
    bs:SetHorizontalAlignment(0); bs:SetVerticalAlignment(0)

    log('PAIR_PROXY_STEP',id..' attach_primary')
    -- Primary row becomes label | key+pair. The stock value box stays alive at width zero.
    instance.row.surfaceBox:SetWidthOverride(254)
    instance.row.valueBox:SetWidthOverride(0)
    local slot=need(instance.row.surface:AddChildToOverlay(pairBox),'pair proxy overlay slot')
    slot:SetHorizontalAlignment(3); slot:SetVerticalAlignment(2)

    -- Measure every supported label after attaching the Slate widget. If desired
    -- size is unavailable, estimate from the same font and report the fallback.
    local labels=instance.descriptor.modeOptions or {initial}
    local maxWidth=0
    local measured=true
    for _,label in ipairs(labels) do
        setText(pairText,label)
        local ok,width=pcall(function()
            pairText:ForceLayoutPrepass()
            return tonumber(pairText:GetDesiredSize().X)
        end)
        if not ok or not width or width<=0 then
            measured=false
            local fontSize=18
            pcall(function() fontSize=tonumber(modeRow.valueWidget.Font.Size) or fontSize end)
            width=(utf8.len(label) or #label)*fontSize*0.7
        end
        maxWidth=math.max(maxWidth,width)
    end
    setText(pairText,initial)
    local pairWidth=math.max(36,math.ceil(maxWidth+16))
    pairBox:SetWidthOverride(pairWidth)
    instance.row.surfaceBox:SetWidthOverride(96+8+pairWidth)
    log('PAIR_WIDTH',id..' width='..pairWidth..' measured='..tostring(measured))

    instance.pair={row=modeRow,box=pairBox,overlay=pairOverlay,frame=pairFrame,inner=pairInner,
        button=pairButton,text=pairText,valueWidget=modeRow.valueWidget,nav=modeRow.nav,pressed=false,lastText=initial,count=math.max(1,#labels)}
    log('PAIR_PROXY_READY',id..' + '..instance.descriptor.modeId)

    -- Collapse only the source wrapper after the proxy exists. No child is removed/reparented.
    local okCollapse,collapseErr=pcall(function() modeRow.wrapper:SetVisibility(1) end)
    if not okCollapse then log('PAIR_COLLAPSE_FAILED',id..': '..tostring(collapseErr)) end
    return true
end

local function updateDirtyPresentation(instance)
    local keyDirty=dirtyText(instance.row.valueWidget)
    local modeDirty=false
    if instance.pair and valid(instance.pair.valueWidget) then
        local dirty,text=dirtyText(instance.pair.valueWidget); modeDirty=dirty
        local clean=stripDirtySuffix(text)
        if valid(instance.pair.text) and clean~=instance.pair.lastText then
            setText(instance.pair.text,clean); instance.pair.lastText=clean
        end
    end
    local dirty=keyDirty or modeDirty
    if dirty~=instance.labelDirty then
        setText(instance.row.labelWidget,instance.baseLabel..(dirty and ' *' or ''))
        instance.labelDirty=dirty
    end
    return keyDirty,modeDirty
end

local function syncSelector(instance,name)
    if not name then return end
    instance.selector:SetSelectedKey(chordFor(name))
    setText(instance.keyText,displayName(name))
    instance.lastName=name
    instance.lastBackingName=name
end

local function submit(instance,name,keyValue,log)
    local d=instance.descriptor
    local normalized=(keyValue-d.minimum)/(d.maximum-d.minimum)
    local previous=instance.row.slider:GetValue()
    if math.abs(previous-normalized)<0.000001 then
        syncSelector(instance,name)
        return
    end
    -- This is the only state write: stock DMM observes it on EngineTick and
    -- remains responsible for pending/dirty/Apply. Never write its config.
    instance.row.slider:SetValue(normalized)
    syncSelector(instance,name)
    instance.awaitingDmm=true; instance.awaitingTicks=0
    instance.targetValue=keyValue; instance.targetNormalized=normalized
    log('KEY_SELECTED',d.providerId..'.'..d.settingId..'='..keyValue..' ('..name..')')
end

function M.tick(instance,log)
    if not instance or not valid(instance.selector) or not valid(instance.row.slider) then return false end
    if not valid(instance.row.wrapper) then return false end
    local okParent,parent=pcall(function() return instance.row.wrapper:GetParent() end)
    if not okParent or not valid(parent) then return false end

    -- Highlight only the paired picker's surface when its hit target is hovered.
    -- Keep the stock row highlight and key-capture styling independently owned.
    local pair=instance.pair
    if pair and valid(pair.button) and valid(pair.inner) then
        local hovered=pair.button:IsHovered()==true
        if hovered~=pair.hovered then
            pair.inner:SetBrushColor(hovered
                and {R=0.95,G=0.63,B=0.08,A=0.22}
                or {R=0.12,G=0.12,B=0.12,A=0.10})
            pair.hovered=hovered
        end
    end

    local d=instance.descriptor
    local id=d.providerId..'.'..d.settingId
    local normalized=instance.row.slider:GetValue()
    local backingValue=math.floor(d.minimum+normalized*(d.maximum-d.minimum)+0.5)
    local backingName=Codes.toName(backingValue)
    local name,readError=selectedName(instance.selector)
    if not name then
        if not instance.readWarning then log('SELECTED_KEY_READ_FAILED',id..' '..tostring(readError)); instance.readWarning=true end
        return true
    end
    instance.readWarning=false
    if not instance.initialized then
        if backingName then syncSelector(instance,backingName)
        else
            instance.lastName=name; instance.lastBackingName=nil
            setText(instance.keyText,tostring(backingValue))
        end
        instance.initialized=true
        log('KEY_INITIALIZED',id..'='..backingValue)
        updateDirtyPresentation(instance)
        return true
    end

    local selecting=instance.selector:GetIsSelectingKey()==true
    if selecting then
        if not instance.wasSelecting then
            instance.wasSelecting=true
            instance.captureName=instance.lastName
            setText(instance.keyText,'...'); styleSelecting(instance)
            log('CAPTURE_BEGIN',id..' previous='..tostring(instance.captureName))
        end
        updateDirtyPresentation(instance)
        return true
    end

    local ended=instance.wasSelecting
    if ended then
        instance.wasSelecting=false; styleNormal(instance)
        if name=='Escape' or name==instance.captureName then
            -- EscapeKeys cancels natively without changing SelectedKey. No slider,
            -- pending acknowledgement or dirty state is changed by cancellation.
            syncSelector(instance,instance.captureName)
            instance.captureName=nil
            log('CAPTURE_CANCEL_OR_UNCHANGED',id)
            updateDirtyPresentation(instance)
            return true
        end
        log('CAPTURE_END',id..' selected='..name)
        instance.captureName=nil
    elseif name=='Escape' then
        -- Defensive path if native cancellation was missed between monitor ticks.
        syncSelector(instance,instance.lastName)
        log('CAPTURE_CANCEL',id)
        updateDirtyPresentation(instance)
        return true
    end

    if instance.awaitingDmm then
        instance.awaitingTicks=instance.awaitingTicks+1
        local text=stripDirtySuffix(Discovery.textOf(instance.row.valueWidget) or '')
        local observed=tonumber(text)
        if backingValue~=instance.targetValue then
            -- Restore/Reset/other stock action superseded the request. Never
            -- reassert a stale captured value over a subsequent DMM operation.
            instance.awaitingDmm=false
            log('DMM_WRITE_SUPERSEDED',id..' backing='..backingValue)
        elseif observed==instance.targetValue then
            instance.awaitingDmm=false
            log('DMM_VALUE_ACK',id..'='..backingValue)
        elseif instance.awaitingTicks>=25 then
            instance.awaitingDmm=false
            log('DMM_DIRTY_WAIT',id..' target='..tostring(instance.targetValue)..' stockText='..text)
        end
    end

    if name~=instance.lastName then
        local keyValue=Codes.toValue(name)
        if keyValue==nil or keyValue<d.minimum or keyValue>d.maximum then
            log('UNSUPPORTED_KEY',id..' '..name)
            syncSelector(instance,backingName or instance.lastName)
        else
            submit(instance,name,keyValue,log)
        end
    elseif backingName~=instance.lastBackingName and not instance.awaitingDmm then
        syncSelector(instance,backingName)
    end

    if instance.pair and valid(instance.pair.button) and valid(instance.pair.nav) then
        local pressed=instance.pair.button:IsPressed()==true
        if pressed then instance.pair.pressed=true
        elseif instance.pair.pressed then
            instance.pair.pressed=false
            if instance.pair.button:IsHovered()==true then
                local current=tonumber(instance.pair.nav:GetValue()) or 0
                local target=(math.floor(current+0.5)+1)%instance.pair.count
                instance.pair.nav:SetValue(target)
                log('PAIR_SELECTED',id..' modeIndex='..target)
            end
        end
    end
    updateDirtyPresentation(instance)
    return true
end

return M
