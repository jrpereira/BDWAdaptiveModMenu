package.path='Scripts/?.lua;'..package.path
local function obj(fields)
    fields=fields or {}
    function fields:IsValid() return self.alive~=false end
    return fields
end
local function fName(name) return {ToString=function() return name end} end
FName=fName
local function chord(name,flags)
    flags=flags or {}
    return {Key={KeyName=fName(name)},bShift=flags.shift or false,bCtrl=flags.ctrl or false,
        bAlt=flags.alt or false,bCmd=flags.cmd or false}
end
local function textWidget(text)
    local w=obj({text=text})
    function w:SetRenderOpacity(value) self.opacity=value end
    function w:SetText(value) assert(type(value)=='table' and value.ftext,'raw string sent to SetText'); self.text=value.value end
    return w
end
local lib=obj()
function lib:Conv_StringToText(text) return {ftext=true,value=text} end
StaticFindObject=function() return lib end
package.loaded.widget_discovery={valid=function(o) return o and o:IsValid() end,textOf=function(w) return w.text end}
local M=require('key_selector')
local events={}
local function log(event,detail) events[#events+1]=event..' '..detail end
local function fixture(value,dirty)
    events={}
    local slider=obj({value=value/254,writes=0})
    function slider:GetValue() return self.value end
    function slider:SetValue(v) self.value=v;self.writes=self.writes+1 end
    local selector=obj({SelectedKey=chord('None'),selecting=false})
    function selector:SetSelectedKey(c) self.SelectedKey=c end
    function selector:GetIsSelectingKey() return self.selecting end
    function selector:IsHovered() return self.hovered==true end
    -- Deliberately no GetSelectedKey: match the reflected UE 5.5 API.
    local wrapper=obj();function wrapper:GetParent() return obj() end
    local surface=obj();function surface:SetBrushColor(c) self.color=c end
    local instance={row={slider=slider,wrapper=wrapper,valueWidget=textWidget(tostring(value)..(dirty and ' *' or '')),labelWidget=textWidget('Ability')},
        selector=selector,keyText=textWidget(''),keyInner=surface,keyEdges={},baseLabel='Ability',
        descriptor={providerId='Test',settingId='Ability',minimum=0,maximum=254}}
    assert(M.tick(instance,log));assert(slider.writes==0,'initialization changed stock state')
    return instance,selector,slider
end
local function capture(i,s,name,flags)
    s.selecting=true;assert(M.tick(i,log))
    s.selecting=false;s.SelectedKey=chord(name,flags);assert(M.tick(i,log))
end
local i,s,slider=fixture(82,false)
capture(i,s,'K')
assert(slider.writes==1 and math.abs(slider.value-75/254)<1e-8)
assert(i.row.labelWidget.text=='Ability','invented dirty state before DMM acknowledgement')
i.row.valueWidget.text='75 *';assert(M.tick(i,log))
assert(i.row.labelWidget.text=='Ability','key capture must leave dirty styling to dirty_labels')
print('PASS reflected capture writes stock slider once; global dirty presentation has one owner')
for _,dirty in ipairs({false,true}) do
    i,s,slider=fixture(82,dirty)
    local label=i.row.labelWidget.text
    capture(i,s,'R') -- native EscapeKeys leaves previous SelectedKey untouched
    assert(slider.writes==0 and i.row.labelWidget.text==label)
    assert(i.keyText.text=='R')
end
print('PASS cancellation preserves clean and pre-existing dirty state')
i,s,slider=fixture(82,true);capture(i,s,'Escape')
assert(slider.writes==0 and i.keyText.text=='R')
print('PASS defensive Escape never becomes a binding')
i,s,slider=fixture(82,false);capture(i,s,'K')
slider.value=82/254;i.row.valueWidget.text='82';M.tick(i,log)
assert(slider.writes==1 and i.keyText.text=='R')
print('PASS Restore supersedes outstanding capture without stale reassertion')
i,s,slider=fixture(82,false);capture(i,s,'F24')
assert(slider.writes==0 and i.keyText.text=='R')
print('PASS unsupported capture fails closed')
for _,case in ipairs({
    {'LeftShift',0xA0,'Left Shift'},{'RightShift',0xA1,'Right Shift'},
    {'LeftControl',0xA2,'Left Ctrl'},{'RightControl',0xA3,'Right Ctrl'},
    {'LeftAlt',0xA4,'Left Alt'},{'RightAlt',0xA5,'Right Alt'},
    {'LeftCommand',0x5B,'Left Win'},{'RightCommand',0x5C,'Right Win'},
}) do
    i,s,slider=fixture(82,false);capture(i,s,case[1],{ctrl=true})
    assert(slider.writes==1 and math.abs(slider.value-case[2]/254)<1e-8 and i.keyText.text==case[3])
end
print('PASS left/right modifier keys are captured as distinct virtual-key values')
i,s,slider=fixture(82,false);capture(i,s,'K',{ctrl=true})
assert(slider.writes==0 and i.keyText.text=='R' and events[#events]:find('UNSUPPORTED_KEY_CHORD',1,true))
print('PASS modifier chords are rejected instead of silently storing their primary key')
i,s,slider=fixture(0,false)
assert(i.keyText.text=='Unbound' and slider.writes==0)
capture(i,s,'K');assert(slider.writes==1)
print('PASS zero/unbound initializes without writes and can be rebound')
i,s,slider=fixture(82,false);capture(i,s,'K')
for n=1,30 do M.tick(i,log) end
assert(slider.writes==1 and i.keyText.text=='K' and i.row.labelWidget.text=='Ability')
assert(#events==0,'unchanged DMM text triggered an acknowledgement diagnostic')
slider.value=84/254 -- Stock Restore/Reset wins even while displayed text is stale.
M.tick(i,log)
assert(slider.writes==1 and i.keyText.text=='T')
capture(i,s,'R');assert(slider.writes==2 and i.keyText.text=='R')
print('PASS stale DMM text neither blocks stock synchronization nor retries submission')
i,s,slider=fixture(254,false)
M.tick(i,log);assert(slider.writes==0,'unmapped backing value was automatically overwritten')
print('PASS unsupported existing backing value is not overwritten')

i,s,slider=fixture(82,false)
local edge=obj();function edge:SetBrushColor(c) self.color=c end
i.keyEdges={edge}
s.hovered=true;M.tick(i,log)
assert(i.keyInner.color.R==0.95 and i.keyInner.color.A==0.22)
assert(edge.color.A==0.85 and slider.writes==0)
s.selecting=true;M.tick(i,log)
assert(i.keyInner.color.A==0.16 and edge.color.A==1)
s.hovered=false;M.tick(i,log)
assert(i.keyInner.color.A==0.16 and edge.color.A==1,'hover exit overwrote capture styling')
s.selecting=false;M.tick(i,log)
assert(i.keyInner.color.A==0.30 and edge.color.A==0.85)
s.hovered=true;s.selecting=true;M.tick(i,log)
s.selecting=false;M.tick(i,log)
assert(i.keyInner.color.A==0.22 and edge.color.A==0.85)
s.hovered=false;M.tick(i,log)
assert(i.keyInner.color.A==0.30 and slider.writes==0)
print('PASS key hover matches Mode fill, preserves outline, defers to capture, restores pointer state')

i,s,slider=fixture(82,false)
local nav=obj({value=0,writes=0})
function nav:GetValue() return self.value end
function nav:SetValue(v) self.value=v;self.writes=self.writes+1 end
local button=obj();function button:IsHovered() return false end
function button:IsPressed() error('press-state polling forbidden') end
local inner=obj();function inner:SetBrushColor() end
i.pair={button=button,inner=inner,nav=nav,valueWidget=textWidget('Tap'),text=textWidget('Tap'),lastText='Tap',count=2}
i.pendingClicks=3;M.tick(i,log);assert(nav.value==1 and nav.writes==1 and i.pendingClicks==0)
M.tick(i,log);assert(nav.writes==1)
print('PASS queued short clicks consumed exactly once without IsPressed; net mode preserved')
function button:SetIsEnabled(value) self.enabled=value end
i.descriptor.fixedMode='Tap';i.row.modeState=textWidget('AMM_MODE\nfixed')
i.pair.valueWidget.text='Hold';i.pendingClicks=2
assert(M.tick(i,log) and i.pair.text.text=='Tap' and button.enabled==false)
assert(i.pair.text.opacity==0.45,'fixed mode must appear unavailable')
assert(nav.value==1 and nav.writes==1 and i.pendingClicks==0)
capture(i,s,'K');assert(slider.writes==1,'Fixed-mode display must not block key capture')
i.row.modeState.text='AMM_MODE\neditable';i.pendingClicks=1
assert(M.tick(i,log) and button.enabled and i.pair.text.text=='Hold' and nav.writes==1,'Transition discards stale clicks')
assert(i.pair.text.opacity==1,'editable mode must regain normal contrast')
i.pendingClicks=1;assert(M.tick(i,log) and nav.value==0 and nav.writes==2)
i.row.modeState.text='AMM_MODE\nfixed';i.pendingClicks=1
assert(M.tick(i,log) and nav.writes==2 and i.pair.text.text=='Tap')
assert(i.pair.text.opacity==0.45)
i.row.modeState.alive=false;i.pendingClicks=1
assert(not M.tick(i,log) and nav.writes==2 and i.pendingClicks==0,'Stale ownership must not submit clicks')
print('PASS fixed/editable mode switches preserve saved mode, discard stale clicks and allow key capture')

i,s,slider=fixture(82,false)
s.SelectedKey={Key={}}
for attempt=1,3 do
    assert(M.tick(i,log)==false and slider.writes==0)
end
assert(events[1]:find('SELECTED_KEY_READ_FAILED',1,true),'missing FKey name was treated as a literal key')
assert(#events==1,'persistent unreadable key repeated its warning')
s.SelectedKey=chord('R')
assert(M.tick(i,log) and not i.readWarning and slider.writes==0)
print('PASS unreadable key reports failure without writes; readable key recovers')

local function failNextText(widget)
    local original=widget.SetText
    local fail=true
    function widget:SetText(value)
        if fail then fail=false;error('transient text failure') end
        return original(self,value)
    end
end
i,s,slider=fixture(82,false)
failNextText(i.keyText)
s.SelectedKey=chord('K')
assert(not pcall(M.tick,i,log))
assert(i.keyText.text=='R' and slider.writes==1)
assert(M.tick(i,log) and i.keyText.text=='K' and slider.writes==1)
assert(M.tick(i,log) and slider.writes==1)
print('PASS failed key presentation recovers without resubmitting the accepted key')

i,s,slider=fixture(82,false)
failNextText(i.keyText)
s.SelectedKey=chord('K');assert(not pcall(M.tick,i,log))
slider.value=84/254
assert(M.tick(i,log) and i.keyText.text=='T' and slider.writes==1)
print('PASS stock Restore supersedes a failed key presentation without stale resubmission')

i,s,slider=fixture(82,false)
slider.value=254/254
assert(M.tick(i,log) and i.keyText.text=='254' and slider.writes==0)
slider.value=253/254
assert(M.tick(i,log) and i.keyText.text=='253' and slider.writes==0)
s.selecting=true;assert(M.tick(i,log) and i.keyText.text=='...')
s.selecting=false;assert(M.tick(i,log) and i.keyText.text=='253' and slider.writes==0)
slider.value=84/254
assert(M.tick(i,log) and i.keyText.text=='T' and slider.writes==0)
capture(i,s,'K');assert(i.keyText.text=='K' and slider.writes==1)
print('PASS unmapped backing values display numerically through changes and cancellation')

i,s,slider=fixture(82,false)
i.row.valueWidget.text='82 *'
assert(M.tick(i,log) and i.row.labelWidget.text=='Ability','key capture must not compete with global dirty styling')
i.pair={valueWidget=textWidget('Hold'),text=textWidget('Tap'),lastText='Tap'}
failNextText(i.pair.text)
assert(not pcall(M.tick,i,log) and i.pair.lastText=='Tap')
assert(M.tick(i,log) and i.pair.text.text=='Hold' and i.pair.lastText=='Hold')
print('PASS mode label writes remain retryable; dirty styling has one owner')

-- Minimal owned subtree, exercising the production save/adopt implementation.
local function ownRow(instance)
    instance.stateWidget=textWidget('')
    local discovery=package.loaded.widget_discovery
    discovery.childCount=function(w) return #(w.children or {}) end
    discovery.childAt=function(w,n) return (w.children or {})[n+1] end
    discovery.contentOf=function(w) return w and w.content end
    instance.keyInner.content=instance.keyText
    local overlay={children={{content=instance.keyInner},{content=obj()},
        {content=obj()},{content=obj()},{content=obj()},instance.selector,instance.stateWidget}}
    instance.row.surface={children={{content=overlay}}}
    instance.row.label='Ability'
    M.save(instance)
end
do
    i,s,slider=fixture(82,false)
    ownRow(i)
    failNextText(i.keyText)
    s.SelectedKey=chord('K');assert(not pcall(M.tick,i,log))
    assert(slider.writes==1)
    slider.value=84/254;i.row.valueWidget.text='84'
    local adopted=assert(M.adopt(i.row,i.descriptor,nil,{}))
    assert(adopted.lastName=='K','rendering failure lost accepted row state')
    assert(M.tick(adopted,log))
    assert(slider.writes==1 and math.abs(slider.value-84/254)<1e-8 and adopted.keyText.text=='T')
end
print('PASS failed key rendering followed by Restore and real row adoption never replays a stale key')

for _,cancel in ipairs({false,true}) do
    i,s,slider=fixture(82,false)
    ownRow(i)
    slider.value=254/254;assert(M.tick(i,log))
    assert(s.SelectedKey.Key.KeyName:ToString()=='None' and slider.writes==0)
    local adopted=assert(M.adopt(i.row,i.descriptor,nil,{}))
    assert(adopted.lastName=='None')
    if cancel then
        capture(adopted,s,'None') -- Native Escape leaves the neutral key unchanged.
        assert(slider.writes==0 and slider.value==1 and adopted.keyText.text=='254')
        capture(adopted,s,'Escape') -- Defensive explicit Escape path.
        assert(slider.writes==0 and slider.value==1)
    end
    capture(adopted,s,'R')
    assert(slider.writes==1 and math.abs(slider.value-82/254)<1e-8 and adopted.keyText.text=='R')
end
print('PASS unmapped row adoption preserves cancellation and allows recapturing its previous key')
