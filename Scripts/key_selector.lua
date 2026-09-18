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
    if ok and name and name~='' and name~='None' then return name end
end

local function selectedName(selector)
    local ok,chord=pcall(function() return selector:GetSelectedKey() end)
    return ok and keyNameFromChord(chord) or nil
end

local textLib=nil
local function setText(widget,text)
    if not valid(widget) then return false end
    local ok=pcall(function() widget:SetText(text) end)
    if ok then return true end
    if not valid(textLib) then textLib=StaticFindObject('/Script/Engine.Default__KismetTextLibrary') end
    if valid(textLib) then
        return pcall(function() widget:SetText(textLib:Conv_StringToText(text)) end)
    end
    return false
end

local function dirtyText(widget)
    local text=Discovery.textOf(widget) or ''
    return text:match('%s%*%s*$')~=nil,text
end

local function stripDirtySuffix(text)
    return (text or ''):gsub('%s+%*%s*$','')
end

local function displayName(name)
    local aliases={SpaceBar='Space',BackSpace='Backspace',ThumbMouseButton='Mouse 4',ThumbMouseButton2='Mouse 5',LeftMouseButton='LMB',RightMouseButton='RMB',MiddleMouseButton='MMB'}
    return aliases[name] or name or ''
end

local function styleNormal(instance)
    if valid(instance.keyFrame) then pcall(function() instance.keyFrame:SetBrushColor({R=0.55,G=0.52,B=0.46,A=0.85}) end) end
    if valid(instance.keyInner) then pcall(function() instance.keyInner:SetBrushColor({R=0,G=0,B=0,A=0.0}) end) end
end

local function styleSelecting(instance)
    if valid(instance.keyFrame) then pcall(function() instance.keyFrame:SetBrushColor({R=0.95,G=0.63,B=0.08,A=1.0}) end) end
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
    keyFrame:SetBrushColor({R=0.55,G=0.52,B=0.46,A=0.85})
    keyFrame:SetPadding({Left=1,Top=1,Right=1,Bottom=1})
    local frameSlot=need(keyOverlay:AddChildToOverlay(keyFrame),'key frame slot')
    frameSlot:SetHorizontalAlignment(0); frameSlot:SetVerticalAlignment(0)

    local keyInner=construct('/Script/UMG.Border',tree)
    keyInner:SetBrushColor({R=0,G=0,B=0,A=0.0})
    local innerSlot=need(keyFrame:SetContent(keyInner),'key inner content')
    innerSlot:SetHorizontalAlignment(0); innerSlot:SetVerticalAlignment(0)

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
        descriptor=descriptor,row=row,selector=selector,keyBox=keyBox,keyFrame=keyFrame,keyInner=keyInner,keyText=keyText,
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
    pairFrame:SetBrushColor({R=0.55,G=0.52,B=0.46,A=0.85})
    pairFrame:SetPadding({Left=1,Top=1,Right=1,Bottom=1})
    local fs=need(pairOverlay:AddChildToOverlay(pairFrame),'pair frame slot')
    fs:SetHorizontalAlignment(0); fs:SetVerticalAlignment(0)

    local pairInner=construct('/Script/UMG.Border',tree)
    pairInner:SetBrushColor({R=0,G=0,B=0,A=0.0})
    local innerSlot=need(pairFrame:SetContent(pairInner),'pair inner content')
    innerSlot:SetHorizontalAlignment(0); innerSlot:SetVerticalAlignment(0)

    log('PAIR_PROXY_STEP',id..' construct_text')
    local pairText=construct('/Script/UMG.TextBlock',tree)
    pairText:SetJustification(1); pairText:SetTextOverflowPolicy(1)
    pcall(function() pairText:SetFont(modeRow.valueWidget.Font) end)
    pcall(function() pairText:SetRenderTransformPivot({X=0.5,Y=0.5}); pairText:SetRenderScale({X=0.88,Y=0.88}) end)
    local initial=stripDirtySuffix(Discovery.textOf(modeRow.valueWidget) or '')
    setText(pairText,initial)
    local ts=need(pairInner:SetContent(pairText),'pair text content')
    ts:SetHorizontalAlignment(0); ts:SetVerticalAlignment(2)
    ts:SetPadding({Left=4,Top=0,Right=4,Bottom=0})

    log('PAIR_PROXY_STEP',id..' construct_hit_target')
    local pairButton=construct('/Script/UMG.Button',tree)
    pairButton.IsFocusable=false
    pcall(function() pairButton:SetBackgroundColor({R=0,G=0,B=0,A=0}) end)
    pcall(function() pairButton:SetRenderOpacity(0.01) end)
    local bs=need(pairOverlay:AddChildToOverlay(pairButton),'pair hit target slot')
    bs:SetHorizontalAlignment(0); bs:SetVerticalAlignment(0)

    log('PAIR_PROXY_STEP',id..' attach_primary')
    -- Primary row becomes label | key+pair. The stock value box stays alive at width zero.
    instance.row.surfaceBox:SetWidthOverride(254)
    instance.row.valueBox:SetWidthOverride(0)
    local slot=need(instance.row.surface:AddChildToOverlay(pairBox),'pair proxy overlay slot')
    slot:SetHorizontalAlignment(3); slot:SetVerticalAlignment(2)

    instance.pair={row=modeRow,box=pairBox,overlay=pairOverlay,frame=pairFrame,inner=pairInner,
        button=pairButton,text=pairText,valueWidget=modeRow.valueWidget,nav=modeRow.nav,pressed=false,lastText=initial}
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
    local dirty=keyDirty or modeDirty or instance.awaitingDmm
    if dirty~=instance.labelDirty then
        setText(instance.row.labelWidget,instance.baseLabel..(dirty and ' *' or ''))
        instance.labelDirty=dirty
    end
    return keyDirty,modeDirty
end

function M.tick(instance,log)
    if not instance or not valid(instance.selector) or not valid(instance.row.slider) then return false end
    if not valid(instance.row.wrapper) then return false end
    local okParent,parent=pcall(function() return instance.row.wrapper:GetParent() end)
    if not okParent or not valid(parent) then return false end

    local d=instance.descriptor
    local normalized=instance.row.slider:GetValue()
    local backingValue=math.floor(d.minimum + normalized*(d.maximum-d.minimum) + 0.5)
    local backingName=Codes.toName(backingValue)
    local name=selectedName(instance.selector)

    if not instance.initialized then
        if backingName then pcall(function() instance.selector:SetSelectedKey(chordFor(backingName)) end); name=backingName end
        setText(instance.keyText,displayName(backingName or name))
        instance.initialized=true; instance.lastName=name; instance.lastBackingName=backingName
        updateDirtyPresentation(instance)
        return true
    end

    local selecting=false
    pcall(function() selecting=instance.selector:GetIsSelectingKey()==true end)
    if selecting then
        if not instance.wasSelecting then
            instance.wasSelecting=true; setText(instance.keyText,'...'); styleSelecting(instance)
        end
        updateDirtyPresentation(instance)
        return true
    elseif instance.wasSelecting then
        instance.wasSelecting=false; styleNormal(instance)
    end

    -- Reset/Restore/stock refresh changed the authoritative slider: mirror it into selector.
    if backingName~=instance.lastBackingName and name==instance.lastName and not instance.awaitingDmm then
        if backingName then pcall(function() instance.selector:SetSelectedKey(chordFor(backingName)) end); name=backingName end
        setText(instance.keyText,displayName(backingName or name))
        instance.lastBackingName=backingName; instance.lastName=name
        updateDirtyPresentation(instance)
        return true
    end

    -- Native capture completed. Push the corresponding numeric value into DMM's stock Slider.
    if name and name~=instance.lastName then
        local keyValue=Codes.toValue(name)
        if not keyValue or keyValue<d.minimum or keyValue>d.maximum then
            log(not keyValue and 'UNSUPPORTED_KEY' or 'KEY_OUT_OF_RANGE',name..(keyValue and ('='..keyValue) or ''))
            if backingName then pcall(function() instance.selector:SetSelectedKey(chordFor(backingName)) end) end
            setText(instance.keyText,displayName(backingName or name))
            instance.lastName=backingName or name; instance.lastBackingName=backingName
            updateDirtyPresentation(instance)
            return true
        end
        local newNormalized=(keyValue-d.minimum)/(d.maximum-d.minimum)
        instance.row.slider:SetValue(newNormalized)
        setText(instance.keyText,displayName(name))
        instance.lastName=name; instance.lastBackingName=name
        instance.awaitingDmm=true; instance.awaitingTicks=0; instance.targetValue=keyValue; instance.targetNormalized=newNormalized
        log('KEY_SELECTED',d.providerId..'.'..d.settingId..'='..keyValue..' ('..name..')')
    end

    -- Proxy Tap/Hold click: change the hidden stock picker navigation Slider.
    -- Stock DMM sees that nav value change in its own tick and updates pending/dirty state.
    if instance.pair and valid(instance.pair.button) and valid(instance.pair.nav) then
        local pressed=false; local hovered=false
        pcall(function() pressed=instance.pair.button:IsPressed()==true end)
        pcall(function() hovered=instance.pair.button:IsHovered()==true end)
        if pressed then
            instance.pair.pressed=true
        elseif instance.pair.pressed then
            instance.pair.pressed=false
            if hovered then
                local current=0; pcall(function() current=instance.pair.nav:GetValue() end)
                local target=(tonumber(current) or 0)<0.5 and 1 or 0
                pcall(function() instance.pair.nav:SetValue(target) end)
                log('PAIR_SELECTED',d.providerId..'.'..d.settingId..' modeIndex='..target)
            end
        end
    end

    local keyDirty=updateDirtyPresentation(instance)
    if instance.awaitingDmm then
        instance.awaitingTicks=instance.awaitingTicks+1
        if keyDirty then
            instance.awaitingDmm=false
            log('DMM_DIRTY_ACK',d.providerId..'.'..d.settingId..'='..tostring(instance.targetValue))
            updateDirtyPresentation(instance)
        else
            -- Reassert while waiting in case stock refresh raced the external capture write.
            if instance.targetNormalized~=nil then pcall(function() instance.row.slider:SetValue(instance.targetNormalized) end) end
            if instance.awaitingTicks==25 then log('DMM_DIRTY_WAIT',d.providerId..'.'..d.settingId..' target='..tostring(instance.targetValue)) end
        end
    end

    instance.lastName=name or instance.lastName
    if not instance.awaitingDmm then instance.lastBackingName=backingName end
    return true
end

return M
