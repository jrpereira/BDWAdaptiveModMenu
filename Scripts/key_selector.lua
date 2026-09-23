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
        if type(keyName)=='string' and keyName~='' then return keyName end
    end)
    if ok and name and name~='' then return name end
end

local modifierKeys={LeftShift=true,RightShift=true,LeftControl=true,RightControl=true,
    LeftAlt=true,RightAlt=true,LeftCommand=true,RightCommand=true}
local function hasChordModifier(chord)
    for _,field in ipairs({'bShift','bCtrl','bAlt','bCmd'}) do
        local ok,value=pcall(function() return chord[field] end)
        if ok and (value==true or value==1) then return true end
    end
    return false
end

local function selectedName(selector)
    local ok,chord=pcall(function() return selector.SelectedKey end)
    if not ok then return nil,tostring(chord) end
    local name=keyNameFromChord(chord)
    if not name then return nil,'SelectedKey did not contain a readable FKey name' end
    return name,nil,hasChordModifier(chord) and not modifierKeys[name]
end

local textLib=nil
local function ftext(text)
    if not valid(textLib) then textLib=StaticFindObject('/Script/Engine.Default__KismetTextLibrary') end
    if not valid(textLib) then return end
    return textLib:Conv_StringToText(text)
end
local function setText(widget,text)
    -- SetText requires FText; Lua pcall cannot contain a native access violation.
    local ok,result=pcall(function()
        if not valid(widget) then return false end
        local value=ftext(text)
        if value==nil then return false end
        widget:SetText(value)
        return true
    end)
    if not ok then return false,result end
    return result
end

-- The collapsed child is the row's persistent state. No Lua row registry owns it.
local markerPrefix='KEM_ROW_1\n'
local stateKeys={'initialized','lastName','lastBackingName','wasSelecting','captureName',
    'keyHovered','readWarning','pairIndex','pairHovered','pairLastText'}
local function encode(value)
    if value==nil then return '-' end
    if type(value)=='boolean' then return value and 't' or 'f' end
    return 's'..tostring(value):gsub('%%','%%25'):gsub('\n','%%0A'):gsub('\r','%%0D')
end
local function decode(value)
    if value=='-' then return nil end
    if value=='t' then return true end
    if value=='f' then return false end
    assert(value:sub(1,1)=='s','invalid row state')
    return (value:sub(2):gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end))
end
function M.save(instance)
    if not instance.stateWidget then return end -- Standalone control test adapters.
    if instance.pair then
        instance.pairHovered=instance.pair.hovered
        instance.pairLastText=instance.pair.lastText
    end
    local saved=instance.savedState
    local changed=not saved
    if saved then
        for _,key in ipairs(stateKeys) do
            if saved[key]~=instance[key] then changed=true;break end
        end
    end
    if not changed then return end
    local fields={}
    for i,key in ipairs(stateKeys) do fields[i]=encode(instance[key]) end
    local text=markerPrefix..table.concat(fields,'\n')..'\n'
    if text~=instance.stateText then
        assert(setText(instance.stateWidget,text),'row state write failed')
        instance.stateText=text
    end
    saved=saved or {}
    for _,key in ipairs(stateKeys) do saved[key]=instance[key] end
    instance.savedState=saved
end

local function stripDirtySuffix(text)
    return (text or ''):gsub('^%*%s+',''):gsub('%s+%*%s*$','')
end

local function displayName(name)
    local aliases={None='Unbound',SpaceBar='Space',BackSpace='Backspace',ThumbMouseButton='Mouse 4',ThumbMouseButton2='Mouse 5',LeftMouseButton='LMB',RightMouseButton='RMB',MiddleMouseButton='MMB',
        LeftShift='Left Shift',RightShift='Right Shift',LeftControl='Left Ctrl',RightControl='Right Ctrl',
        LeftAlt='Left Alt',RightAlt='Right Alt',LeftCommand='Left Win',RightCommand='Right Win'}
    return aliases[name] or name or ''
end

local function styleNormal(instance)
    if instance.keyEnabled==false then
        for _,edge in ipairs(instance.keyEdges or {}) do
            pcall(function() edge:SetBrushColor({R=0.35,G=0.34,B=0.32,A=0.45}) end)
        end
        if valid(instance.keyInner) then instance.keyInner:SetBrushColor({R=0.12,G=0.12,B=0.12,A=0.12}) end
        return
    end
    for _,edge in ipairs(instance.keyEdges or {}) do pcall(function() edge:SetBrushColor({R=0.55,G=0.52,B=0.46,A=0.85}) end) end
    if valid(instance.keyInner) then
        instance.keyInner:SetBrushColor(instance.keyHovered
            and {R=0.95,G=0.63,B=0.08,A=0.22}
            or {R=0.12,G=0.12,B=0.12,A=0.30})
    end
end

local function styleSelecting(instance)
    for _,edge in ipairs(instance.keyEdges or {}) do pcall(function() edge:SetBrushColor({R=0.95,G=0.63,B=0.08,A=1.0}) end) end
    if valid(instance.keyInner) then pcall(function() instance.keyInner:SetBrushColor({R=0.95,G=0.63,B=0.08,A=0.16}) end) end
end

function M.decorate(row,descriptor,log,host)
    if not row or not valid(row.slider) then return nil,'invalid numeric row' end
    local tree=row.tree

    -- Keep the stock Slider UObject as DMM's authoritative numeric control, but make its
    -- visuals invisible. The decorator adds a styled capture surface above it.
    local existing=Discovery.childCount(row.surface) -- stock children only, before attaching replacement
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
    selector:SetAllowGamepadKeys(false); selector:SetAllowModifierKeys(true)
    selector:SetEscapeKeys({{KeyName=FName('Escape')}})
    local noKeyText=ftext('')
    assert(noKeyText~=nil,'empty key text unavailable')
    selector:SetNoKeySpecifiedText(noKeyText)
    selector:SetRenderOpacity(0.0)
    local ss=need(keyOverlay:AddChildToOverlay(selector),'selector slot')
    ss:SetHorizontalAlignment(0); ss:SetVerticalAlignment(0)

    local keyHost=host or row.surface
    local hostSlot=need(keyHost:AddChildToOverlay(keyBox),'key host slot')
    hostSlot:SetHorizontalAlignment(1); hostSlot:SetVerticalAlignment(2)

    pcall(function() row.slider:SetRenderOpacity(0) end)
    pcall(function() row.valueWidget:SetRenderOpacity(0) end)

    for i=0,existing-1 do
        local child=Discovery.childAt(row.surface,i)
        if valid(child) and Discovery.address(child)~=Discovery.address(row.slider) then pcall(function() child:SetRenderOpacity(0) end) end
    end

    -- Every key uses the same 584px row: label | key | gap | mode.
    -- An absent mode leaves blank space, without creating an input widget.
    if not host then
        row.labelBox:SetWidthOverride(330);row.surfaceBox:SetWidthOverride(254);row.valueBox:SetWidthOverride(0)
    end

    local stateWidget=construct('/Script/UMG.TextBlock',tree)
    stateWidget:SetVisibility(1)
    need(keyOverlay:AddChildToOverlay(stateWidget),'row state slot')
    if descriptor.fixedMode and not descriptor.modeId then
        local fixed=construct('/Script/UMG.TextBlock',tree)
        fixed:SetJustification(1);fixed:SetVisibility(3)
        fixed:SetRenderOpacity(0.45)
        pcall(function() fixed:SetFont(row.valueWidget.Font) end)
        assert(setText(fixed,descriptor.fixedMode),'fixed mode text unavailable')
        local box=construct('/Script/UMG.SizeBox',tree)
        box:SetWidthOverride(150);box:SetHeightOverride(32)
        need(box:SetContent(fixed),'fixed mode content')
        box:SetRenderTranslation({X=104,Y=0})
        local slot=need(keyOverlay:AddChildToOverlay(box),'fixed mode slot')
        slot:SetHorizontalAlignment(1);slot:SetVerticalAlignment(2)
    end
    local instance={
        stateWidget=stateWidget,descriptor=descriptor,row=row,selector=selector,keyBox=keyBox,keyFrame=keyFrame,keyInner=keyInner,keyText=keyText,keyEdges=keyEdges,
        baseLabel=row.label or descriptor.settingId,initialized=false,lastName=nil,lastBackingName=nil,wasSelecting=false,
        pair=nil,
    }
    M.save(instance)
    return instance
end

function M.mergePair(instance,modeRow,log,clicks)
    if not instance or not modeRow or modeRow.kind~='picker' then return false,'mode row is not a picker' end
    if not valid(modeRow.wrapper) or not valid(modeRow.nav) or not valid(modeRow.valueWidget) or not valid(instance.row.surface) then return false,'pair widgets unavailable' end
    local tree=instance.row.tree
    local id=instance.descriptor.providerId..'.'..instance.descriptor.settingId

    -- Keep the stock picker row and every stock child UObject in place. Build the visible
    -- proxy from widgets whose composition paths are already proven elsewhere in KEM:
    -- SizeBox -> Overlay -> Border -> TextBlock, plus a transparent sibling Button used
    -- only as a hit target. Keep text in the sibling border composition.
    local pairBox=construct('/Script/UMG.SizeBox',tree)
    pairBox:SetWidthOverride(150); pairBox:SetHeightOverride(32)

    local pairOverlay=construct('/Script/UMG.Overlay',tree)
    need(pairBox:SetContent(pairOverlay),'pair box content')

    local pairFrame=construct('/Script/UMG.Border',tree)
    pairFrame:SetBrushColor({R=0,G=0,B=0,A=0})
    pairFrame:SetPadding({Left=0,Top=0,Right=0,Bottom=0})
    local fs=need(pairOverlay:AddChildToOverlay(pairFrame),'pair frame slot')
    fs:SetHorizontalAlignment(0); fs:SetVerticalAlignment(0)

    local pairInner=construct('/Script/UMG.Border',tree)
    pairInner:SetBrushColor({R=0.12,G=0.12,B=0.12,A=0.10})
    local innerSlot=need(pairFrame:SetContent(pairInner),'pair inner content')
    innerSlot:SetHorizontalAlignment(0); innerSlot:SetVerticalAlignment(0)

    local pairText=construct('/Script/UMG.TextBlock',tree)
    pairText:SetJustification(1); pairText:SetTextOverflowPolicy(1)
    pcall(function() pairText:SetFont(modeRow.valueWidget.Font) end)
    pcall(function()
        pairText:SetRenderTransformPivot({X=0.5,Y=0.5})
        pairText:SetRenderScale({X=0.88,Y=0.88})
    end)
    local initial=stripDirtySuffix(Discovery.textOf(modeRow.valueWidget) or '')
    local textSet,textError=setText(pairText,initial)
    if not textSet then error('pair initial text unavailable: '..tostring(textError or 'invalid widget, library, or FText'),0) end
    local ts=need(pairInner:SetContent(pairText),'pair text content')
    ts:SetHorizontalAlignment(0); ts:SetVerticalAlignment(2)
    ts:SetPadding({Left=4,Top=0,Right=4,Bottom=0})

    local pairButton=construct('/Script/UMG.Button',tree)
    pairButton.IsFocusable=false
    pcall(function() pairButton:SetBackgroundColor({R=0,G=0,B=0,A=0}) end)
    pcall(function() pairButton:SetRenderOpacity(0) end)
    local bs=need(pairOverlay:AddChildToOverlay(pairButton),'pair hit target slot')
    bs:SetHorizontalAlignment(0); bs:SetVerticalAlignment(0)

    -- Primary row becomes label | key+pair. The stock value box stays alive at width zero.
    instance.row.surfaceBox:SetWidthOverride(254)
    instance.row.valueBox:SetWidthOverride(0)
    local pairIndex=Discovery.childCount(instance.row.surface)
    local slot=need(instance.row.surface:AddChildToOverlay(pairBox),'pair proxy overlay slot')
    slot:SetHorizontalAlignment(3); slot:SetVerticalAlignment(2)

    -- Fixed column width avoids layout prepasses for each option and keeps
    -- editable, fixed and absent modes aligned across the page.
    local labels=instance.descriptor.modeOptions or {initial}

    instance.pair={row=modeRow,box=pairBox,overlay=pairOverlay,frame=pairFrame,inner=pairInner,
        button=pairButton,text=pairText,valueWidget=modeRow.valueWidget,nav=modeRow.nav,lastText=initial,count=math.max(1,#labels)}

    assert(clicks,'click delivery unavailable'):attach(instance,pairButton)

    -- Collapse only the source wrapper after the proxy exists. No child is removed/reparented.
    local okCollapse,collapseErr=pcall(function() modeRow.wrapper:SetVisibility(1) end)
    if not okCollapse then error('pair collapse failed: '..tostring(collapseErr),0) end
    instance.pairIndex=pairIndex
    M.save(instance)
    return true
end

-- Called only after page readiness. Existing children are the authority for
-- decoration presence; runtime bindings can be discarded at every scope change.
function M.adopt(row,descriptor,modeRow,clicks)
    local keyHost=modeRow and modeRow.pairHost or row.surface
    for i=0,Discovery.childCount(keyHost)-1 do
        local box=Discovery.childAt(keyHost,i)
        local overlay=Discovery.contentOf(box)
        local marker=overlay and Discovery.childAt(overlay,6)
        local text=marker and Discovery.textOf(marker)
        if text and text:sub(1,#markerPrefix)==markerPrefix then
            local frame=Discovery.childAt(overlay,0)
            local inner=Discovery.contentOf(frame)
            local instance={descriptor=descriptor,row=row,keyBox=box,keyFrame=frame,
                keyInner=inner,keyText=Discovery.contentOf(inner),selector=Discovery.childAt(overlay,5),
                stateWidget=marker,stateText=text,keyEdges={},baseLabel=stripDirtySuffix(row.label)}
            local n=0
            for field in text:sub(#markerPrefix+1):gmatch('(.-)\n') do
                n=n+1
                if stateKeys[n] then instance[stateKeys[n]]=decode(field) end
            end
            assert(n==#stateKeys,'incompatible row state')
            instance.savedState={}
            for _,key in ipairs(stateKeys) do instance.savedState[key]=instance[key] end
            for edge=1,4 do instance.keyEdges[edge]=Discovery.contentOf(Discovery.childAt(overlay,edge)) end
            if instance.pairIndex then
                assert(modeRow,'paired row unavailable')
                local pairBox=Discovery.childAt(row.surface,assert(tonumber(instance.pairIndex)))
                local pairOverlay=Discovery.contentOf(pairBox)
                local pairFrame=Discovery.childAt(pairOverlay,0)
                local pairInner=Discovery.contentOf(pairFrame)
                instance.pair={row=modeRow,box=pairBox,overlay=pairOverlay,frame=pairFrame,inner=pairInner,
                    button=Discovery.childAt(pairOverlay,1),text=Discovery.contentOf(pairInner),
                    valueWidget=modeRow.valueWidget,nav=modeRow.nav,
                    count=math.max(1,#(descriptor.modeOptions or {})),
                    hovered=instance.pairHovered,lastText=instance.pairLastText}
                clicks:attach(instance,instance.pair.button,true)
            end
            return instance
        end
    end
end

local function updateModePresentation(instance)
    if instance.pair and valid(instance.pair.valueWidget) then
        local text=Discovery.textOf(instance.pair.valueWidget) or ''
        local clean=instance.modeEditable==false and instance.descriptor.fixedMode or stripDirtySuffix(text)
        if valid(instance.pair.text) and clean~=instance.pair.lastText then
            assert(setText(instance.pair.text,clean),'mode text write failed')
            instance.pair.lastText=clean
        end
    end
    -- All setting-label styling belongs to dirty_labels, including paired modes.
end

local function syncSelector(instance,name)
    -- Unmapped backing values have no native key. A neutral capture baseline lets
    -- the previously selected key be chosen again without looking like Escape.
    instance.selector:SetSelectedKey(chordFor(name or 'None'))
    if name then instance.keyDisplayText=displayName(name) end
    instance.lastName=name or 'None'
    instance.lastBackingName=name
end

local function submit(instance,name,keyValue)
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
end

function M.tick(instance,log)
    if not instance or not valid(instance.selector) or not valid(instance.row.slider) then return false end
    if not valid(instance.row.wrapper) then return false end
    local okParent,parent=pcall(function() return instance.row.wrapper:GetParent() end)
    if not okParent or not valid(parent) then return false end
    if instance.descriptor.fixedMode and instance.pair then
        if not valid(instance.row.modeState) then instance.pendingClicks=0;return false end
        local state=Discovery.textOf(instance.row.modeState)
        if state~='KEM_MODE\nfixed' and state~='KEM_MODE\neditable' then instance.pendingClicks=0;return false end
        local editable=state=='KEM_MODE\neditable'
        if instance.modeEditable~=editable then
            instance.pendingClicks=0
            instance.pair.button:SetIsEnabled(editable)
            instance.pair.text:SetRenderOpacity(editable and 1 or 0.45)
            instance.modeEditable=editable
        end
        if not editable then instance.pendingClicks=0 end
        -- DMM can reveal its backing row when logical visibility changes.
        -- Collapse it only after our paired control exists successfully.
        local source=instance.pair.row and instance.pair.row.wrapper
        if valid(source) and source:GetVisibility()~=1 then source:SetVisibility(1) end
    end

    local d=instance.descriptor
    if d.disabledMode~=nil and type(d.modeValues)=='table' and valid(instance.modeNav) then
        local position=math.floor((tonumber(instance.modeNav:GetValue()) or 0)+0.5)+1
        local enabled=d.modeValues[position]~=d.disabledMode
        if instance.keyEnabled~=enabled then
            instance.keyEnabled=enabled
            instance.selector:SetIsEnabled(enabled)
            if valid(instance.keyBox) then instance.keyBox:SetRenderOpacity(enabled and 1 or 0.45) end
            if not enabled then
                instance.wasSelecting=false;instance.captureName=nil;instance.keyHovered=false
            end
            styleNormal(instance)
        end
    end

    -- Pointer feedback belongs to the key hit target, not the whole stock row.
    -- Capture styling wins until capture ends, even if the pointer moves away.
    local keyHovered=instance.selector:IsHovered()==true
    if keyHovered~=instance.keyHovered then
        instance.keyHovered=keyHovered
        if not instance.wasSelecting then styleNormal(instance) end
    end

    -- Highlight only the paired picker's surface when its hit target is hovered.
    -- Keep the stock row highlight and key-capture styling independently owned.
    local pair=instance.pair
    if pair and valid(pair.button) and valid(pair.inner) then
        local hovered=instance.modeEditable~=false and pair.button:IsHovered()==true
        if hovered~=pair.hovered then
            pair.inner:SetBrushColor(hovered
                and {R=0.95,G=0.63,B=0.08,A=0.22}
                or {R=0.12,G=0.12,B=0.12,A=0.10})
            pair.hovered=hovered
        end
    end

    local id=d.providerId..'.'..d.settingId
    local normalized=instance.row.slider:GetValue()
    local backingValue=math.floor(d.minimum+normalized*(d.maximum-d.minimum)+0.5)
    local backingName=Codes.toName(backingValue)
    -- Presentation follows the current backing value, including unsupported codes.
    -- Keep its successful-write cache separate from accepted input state.
    instance.keyDisplayText=backingName and displayName(backingName) or tostring(backingValue)
    if instance.keyEnabled==false then
        if not instance.initialized or backingName~=instance.lastBackingName then syncSelector(instance,backingName) end
        instance.initialized=true
        return true
    end
    local name,readError,hasModifiers=selectedName(instance.selector)
    if not name then
        if not instance.readWarning then log('SELECTED_KEY_READ_FAILED',id..' '..tostring(readError)); instance.readWarning=true end
        return false
    end
    instance.readWarning=false
    if not instance.initialized then
        syncSelector(instance,backingName)
        instance.initialized=true
        return true
    end

    local selecting=instance.selector:GetIsSelectingKey()==true
    if selecting then
        instance.keyDisplayText='...'
        if not instance.wasSelecting then
            instance.wasSelecting=true
            instance.captureName=instance.lastName
            styleSelecting(instance)
        end
        return true
    end

    local ended=instance.wasSelecting
    if ended then
        instance.wasSelecting=false; styleNormal(instance)
        if name=='Escape' or name==instance.captureName then
            -- EscapeKeys cancels natively without changing SelectedKey. No slider,
            -- pending acknowledgement or dirty state is changed by cancellation.
            syncSelector(instance,backingName)
            instance.keyDisplayText=backingName and displayName(backingName) or tostring(backingValue)
            instance.captureName=nil
            return true
        end
        instance.captureName=nil
    elseif name=='Escape' then
        -- Defensive path if native cancellation was missed between monitor ticks.
        syncSelector(instance,backingName)
        instance.keyDisplayText=backingName and displayName(backingName) or tostring(backingValue)
        return true
    end

    if ended and name=='None' then
        -- Empty is not a user-selectable binding. Paired controls use their
        -- explicit Default mode to disable capture without clearing the key.
        syncSelector(instance,backingName)
        instance.keyDisplayText=backingName and displayName(backingName) or tostring(backingValue)
        return true
    end

    if hasModifiers then
        log('UNSUPPORTED_KEY_CHORD',id..' modifier chords are not supported')
        syncSelector(instance,backingName)
        instance.keyDisplayText=backingName and displayName(backingName) or tostring(backingValue)
    elseif name~=instance.lastName then
        local keyValue=Codes.toValue(name)
        if keyValue==nil or keyValue<d.minimum or keyValue>d.maximum then
            log('UNSUPPORTED_KEY',id..' '..name)
            syncSelector(instance,backingName)
            instance.keyDisplayText=backingName and displayName(backingName) or tostring(backingValue)
        else
            submit(instance,name,keyValue)
        end
    elseif backingName~=instance.lastBackingName then
        syncSelector(instance,backingName)
    end

    if instance.modeEditable~=false and instance.pair and valid(instance.pair.nav) then
        local count=instance.pendingClicks or 0
        if count>0 then
            local current=tonumber(instance.pair.nav:GetValue()) or 0
            instance.pair.nav:SetValue((math.floor(current+0.5)+count)%instance.pair.count)
            instance.pendingClicks=0
        end
    end
    return true
end

local tick=M.tick
function M.tick(instance,log)
    local result=tick(instance,log)
    -- Persist accepted input before fallible label rendering. Reopening a row
    -- must never replay a key merely because its previous display update failed.
    M.save(instance)
    if not result then return result end
    updateModePresentation(instance)
    if instance and instance.keyDisplayText and instance.keyDisplayText~=instance.renderedKeyText then
        assert(setText(instance.keyText,instance.keyDisplayText),'key text write failed')
        instance.renderedKeyText=instance.keyDisplayText
    end
    M.save(instance)
    return result
end

local function identity(widget)
    local full=widget:GetFullName()
    return {path=assert(full:match('^%S+ (.+)$')),full=full,address=Discovery.address(widget)}
end
local function resolve(ref)
    local widget=StaticFindObject(ref.path)
    if valid(widget) and Discovery.address(widget)==ref.address and widget:GetFullName()==ref.full then return widget end
end
local function undo(receipt,allowed)
    if not receipt then return true end
    local complete=true
    for i=#receipt.roots,1,-1 do
        if not allowed() then return false end
        local ok=pcall(function()
            local widget=resolve(receipt.roots[i])
            if widget then widget:RemoveFromParent() end
        end)
        if not ok then complete=false end
    end
    for _,entry in ipairs(receipt.saved) do
        if not allowed() then return false end
        local ok=pcall(function()
            local widget=resolve(entry.ref)
            if widget then
                if entry.clear then widget[entry.clear](widget)
                else widget[entry.set](widget,entry.value) end
            end
        end)
        if not ok then complete=false end
    end
    return complete
end
local function transactional(fn,rowOf,isPair)
    return function(...)
        local args={...}
        local row=rowOf(args)
        local root=row.surface
        if not isPair and valid(args[4]) then root=args[4] end
        local receipt={saved={},roots={}}
        local priorState,priorText
        if isPair then
            priorState={}
            for _,key in ipairs(stateKeys) do priorState[key]=args[1][key] end
            priorText=args[1].stateText
        end
        local function save(widget,get,set)
            if not valid(widget) then return end
            receipt.saved[#receipt.saved+1]={ref=identity(widget),set=set,value=widget[get](widget)}
        end
        save(row.slider,'GetRenderOpacity','SetRenderOpacity')
        save(row.valueWidget,'GetRenderOpacity','SetRenderOpacity')
        for _,key in ipairs({'labelBox','surfaceBox','valueBox'}) do
            local widget=row[key]
            if valid(widget) then
                local override=widget.bOverride_WidthOverride
                receipt.saved[#receipt.saved+1]={ref=identity(widget),set='SetWidthOverride',value=widget.WidthOverride,
                    clear=(override==false or override==0) and 'ClearWidthOverride' or nil}
            end
        end
        if isPair then save(args[2].wrapper,'GetVisibility','SetVisibility') end
        local count=Discovery.childCount(root)
        for i=0,count-1 do save(Discovery.childAt(row.surface,i),'GetRenderOpacity','SetRenderOpacity') end
        local ok,result,err=pcall(fn,table.unpack(args))
        local recorded,recordError=pcall(function()
            for i=count,Discovery.childCount(root)-1 do
                receipt.roots[#receipt.roots+1]=identity(Discovery.childAt(root,i))
            end
        end)
        if ok and result and recorded then
            if isPair then args[1].pairUndo=receipt else result.undo=receipt end
            return result,err
        end
        -- Still inside this synchronous construction transaction: remove attached
        -- roots directly even if recording their primitive identities failed.
        local removed=true
        for i=Discovery.childCount(root)-1,count,-1 do
            local clean=pcall(function() Discovery.childAt(root,i):RemoveFromParent() end)
            if not clean then removed=false end
        end
        receipt.roots={}
        local restored=undo(receipt,function() return true end)
        if isPair then
            local instance=args[1]
            instance.pair=nil
            for _,key in ipairs(stateKeys) do instance[key]=priorState[key] end
            if instance.stateWidget and priorText then
                if not setText(instance.stateWidget,priorText) then restored=false end
            end
            instance.stateText=priorText;instance.savedState=priorState
        end
        local reason=not recorded and recordError or (ok and err or result)
        if not removed or not restored then reason=tostring(reason)..'; rollback incomplete' end
        return nil,reason
    end
end
M.decorate=transactional(M.decorate,function(args) return args[1] end,false)
M.mergePair=transactional(M.mergePair,function(args) return args[1].row end,true)
function M.restore(instance,allowed)
    local pairOK=undo(instance.pairUndo,allowed)
    local keyOK=undo(instance.undo,allowed)
    if allowed() then
        for _,ref in ipairs(instance.liveRefs or {}) do
            if ref.key=='labelWidget' then
                local label=resolve(ref)
                if label then setText(label,instance.baseLabel) end
            end
        end
    end
    return pairOK and keyOK
end
return M
