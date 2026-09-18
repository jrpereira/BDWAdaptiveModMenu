package.path='Scripts/?.lua;'..package.path
local function obj(fields)
    fields=fields or {}
    function fields:IsValid() return self.alive~=false end
    return fields
end
local function fName(name) return {ToString=function() return name end} end
FName=fName
local function chord(name) return {Key={KeyName=fName(name)}} end
local function textWidget(text)
    local w=obj({text=text})
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
local function has(event)
    for _,s in ipairs(events) do if s:find(event,1,true) then return true end end
end
local function fixture(value,dirty)
    events={}
    local slider=obj({value=value/254,writes=0})
    function slider:GetValue() return self.value end
    function slider:SetValue(v) self.value=v;self.writes=self.writes+1 end
    local selector=obj({SelectedKey=chord('None'),selecting=false})
    function selector:SetSelectedKey(c) self.SelectedKey=c end
    function selector:GetIsSelectingKey() return self.selecting end
    -- Deliberately no GetSelectedKey: match the reflected UE 5.5 API.
    local wrapper=obj();function wrapper:GetParent() return obj() end
    local surface=obj();function surface:SetBrushColor(c) self.color=c end
    local instance={row={slider=slider,wrapper=wrapper,valueWidget=textWidget(tostring(value)..(dirty and ' *' or '')),labelWidget=textWidget('Ability')},
        selector=selector,keyText=textWidget(''),keyInner=surface,keyEdges={},baseLabel='Ability',
        descriptor={providerId='Test',settingId='Ability',minimum=0,maximum=254}}
    assert(M.tick(instance,log));assert(slider.writes==0,'initialization changed stock state')
    return instance,selector,slider
end
local function capture(i,s,name)
    s.selecting=true;assert(M.tick(i,log))
    s.selecting=false;s.SelectedKey=chord(name);assert(M.tick(i,log))
end
local i,s,slider=fixture(82,false)
capture(i,s,'K')
assert(slider.writes==1 and math.abs(slider.value-75/254)<1e-8)
assert(has('KEY_SELECTED Test.Ability=75'),'capture not submitted')
assert(i.row.labelWidget.text=='Ability','invented dirty state before DMM acknowledgement')
i.row.valueWidget.text='75 *';assert(M.tick(i,log))
assert(i.row.labelWidget.text=='Ability *' and has('DMM_VALUE_ACK'),'DMM dirty presentation not mirrored')
print('PASS reflected capture -> one stock slider write -> DMM acknowledgement')
for _,dirty in ipairs({false,true}) do
    i,s,slider=fixture(82,dirty)
    local label=i.row.labelWidget.text
    capture(i,s,'R') -- native EscapeKeys leaves previous SelectedKey untouched
    assert(slider.writes==0 and i.row.labelWidget.text==label)
    assert(i.keyText.text=='R' and has('CAPTURE_CANCEL_OR_UNCHANGED'))
end
print('PASS cancellation preserves clean and pre-existing dirty state')
i,s,slider=fixture(82,true);capture(i,s,'Escape')
assert(slider.writes==0 and i.keyText.text=='R')
print('PASS defensive Escape never becomes a binding')
i,s,slider=fixture(82,false);capture(i,s,'K')
slider.value=82/254;i.row.valueWidget.text='82';M.tick(i,log)
assert(slider.writes==1 and i.keyText.text=='R' and not i.awaitingDmm)
print('PASS Restore supersedes outstanding capture without stale reassertion')
i,s,slider=fixture(82,false);capture(i,s,'F24')
assert(slider.writes==0 and i.keyText.text=='R' and has('UNSUPPORTED_KEY'))
print('PASS unsupported capture fails closed')
i,s,slider=fixture(0,false)
assert(i.keyText.text=='Unbound' and slider.writes==0)
capture(i,s,'K');assert(slider.writes==1)
print('PASS zero/unbound initializes without writes and can be rebound')
i,s,slider=fixture(82,false);capture(i,s,'K')
for n=1,30 do M.tick(i,log) end
assert(slider.writes==1 and not i.awaitingDmm and has('DMM_DIRTY_WAIT'))
print('PASS acknowledgement timeout is bounded and never reasserts slider')
i,s,slider=fixture(254,false)
M.tick(i,log);assert(slider.writes==0,'unmapped backing value was automatically overwritten')
print('PASS unsupported existing backing value is not overwritten')
