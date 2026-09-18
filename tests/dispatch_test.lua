package.path='Scripts/?.lua;'..package.path
local hooks,queue,now={}, {},0
local objects={}
local calls,scans,builds,ticks=0,0,0,0
local finds=0
local fail=false
local function obj(name)
 local o={name=name}
 function o:IsValid() calls=calls+1;return true end
 function o:GetAddress() calls=calls+1;return self.name end
 function o:GetFName() calls=calls+1;return {ToString=function() return self.name end} end
 function o:GetFullName() calls=calls+1;return 'Widget /Transient.'..self.name end
 function o:IsInViewport() calls=calls+1;return true end
 function o:IsActivated() calls=calls+1;return self.active~=false end
 function o:IsVisible() calls=calls+1;return self.visible~=false end
 function o:GetIsEnabled() calls=calls+1;return self.enabled~=false end
 objects['/Transient.'..name]=o;return o
end
local owner=obj('WBP_PauseMenu_C_1')
function owner:GetFullName() return 'WBP_PauseMenu_C /Transient.'..self.name end
local host=obj('CommonActivatableWidget_1')
host.WidgetTree=obj('HostTree')
function host.WidgetTree:GetOuter() return host end
local other=obj('CommonActivatableWidget_2')
other.WidgetTree=obj('OtherTree')
local scroll,wrapper,slider,relay=obj('scroll'),obj('wrapper'),obj('slider'),obj('relay')
local browser=true
local row={kind='slider',label='Ability',wrapper=wrapper,slider=slider}
local routes={}
for _,o in ipairs({scroll,wrapper,slider,relay}) do routes[o.name]={path='/Transient.'..o.name} end
local snapshot={routes=routes,widgets={scroll=scroll,wrapper=wrapper,slider=slider,relay=relay},names={scroll='scroll',wrapper='wrapper',slider='slider',relay='relay'},scrolls={scroll}}
StaticFindObject=function(path) calls=calls+1;finds=finds+1;return objects[path] end
FindAllOf=function(name) assert(name=='WBP_MainMenu_C' or name=='WBP_PauseMenu_C');return {} end
LoopAsync=function() error('permanent timer forbidden') end
ExecuteWithDelay=function(delay,fn) queue[#queue+1]={time=now+delay,fn=fn} end
ExecuteInGameThread=function(fn) fn() end
EGameThreadMethod={EngineTick=1};EngineTickAvailable=true
RegisterHook=function(path,pre,post) hooks[path]={pre=pre,post=post};return 1,2 end
UnregisterHook=function(path) hooks[path]=nil end
package.loaded.widget_discovery={valid=function(o) return o and o:IsValid() end,address=function(o) return o:GetAddress() end,
 activeTrees=function(h) scans=scans+1;if h==other or browser then return {{widgets={},names={},scrolls={}}} end;return {snapshot} end,
 routeResolver=function() return function(route) return route and objects[route.path] end end,
 rowsFromScroll=function() return {row} end}
local instance
package.loaded.key_selector={adopt=function(r) return r.decoration end,decorate=function(r,d)
 builds=builds+1
 local selector=obj('selector'..builds);local box=obj('keyBox'..builds)
 for _,w in ipairs({selector,box}) do
  snapshot.widgets[w.name]=w;snapshot.names[w.name]=w.name;snapshot.routes[w.name]={path='/Transient.'..w.name}
 end
 instance={row=r,selector=selector,keyBox=box};r.decoration=instance;return instance
 end,
 restore=function(i)
 i.restored=true
 for _,w in ipairs({i.selector,i.keyBox}) do
  snapshot.widgets[w.name]=nil;snapshot.names[w.name]=nil;snapshot.routes[w.name]=nil
 end
 return true end,
 tick=function() ticks=ticks+1;if fail then error('injected transient error') end;return true end}
local registry={dmmEligible=true,providerList={{id='P',choices={{id='K',kind='slider',labels={Ability=true}}}}},byProvider={P={K={}}}}
local diagnostics={}
assert(require('dmm_binding').install(registry,function(event,detail) diagnostics[#diagnostics+1]=event..':'..detail end))
local function emit(path,phase,o) hooks[path][phase]({get=function() return o or host end}) end
local function untilTime(target)
 while true do
  table.sort(queue,function(a,b) return a.time<b.time end)
  if not queue[1] or queue[1].time>target then break end
  local task=table.remove(queue,1);now=task.time;task.fn()
 end
 now=target
end
local activate='/Script/CommonUI.CommonActivatableWidget:ActivateWidget'
local deactivate='/Script/CommonUI.CommonActivatableWidget:DeactivateWidget'
local load='/Script/DogwoodUI.SaveWindowBase:RequestLoadSave'
assert(#queue==0 and calls==0)
untilTime(60000);assert(#queue==0 and calls==0)
print('PASS 60 seconds idle: zero queued timers, zero UObject calls, zero scans')
emit(activate,'post');untilTime(now+60000)
assert(#queue==0 and finds==0 and scans==0,'gameplay activation started discovery')
print('PASS generic widget activation outside main/pause menu starts no searches or timers')
emit(activate,'post',owner)
emit(activate,'post');untilTime(now+15000)
assert(builds==0 and #queue==0)
local atRest=calls;untilTime(now+60000);assert(calls==atRest)
local switcher=obj('PageSwitcher')
function switcher:GetOuter() return host.WidgetTree end
browser=false
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher)
untilTime(now);assert(builds==1)
print('PASS lazy provider opens after browser dormancy: page event wakes dormant host without timers')
local firstScans=scans
local firstFinds=finds
untilTime(now+900);assert(scans==firstScans)
assert(finds-firstFinds==18,'steady updates resolve one owner and one host, never each control')
print('PASS fresh owner and host lookup per update, no per-control global lookup')
untilTime(now+100);assert(scans==firstScans)
print('PASS active menu: no periodic structural scans; fresh control updates only')
local freshSlider=obj('slider')
slider.IsValid=function() error('stale slider wrapper accessed') end
untilTime(now+100);assert(instance.row.slider==freshSlider)
print('PASS control wrappers freshly resolved before use; stale cached wrapper untouched')
for _,field in ipairs({'visible','enabled'}) do
 host[field]=false
 local beforeTicks=ticks;local beforeScans=scans
 untilTime(now+100)
 local afterGuard=calls
 assert(ticks==beforeTicks and scans==beforeScans,'hidden/disabled host updated controls')
 assert(not hooks['/Script/UMG.Widget:ForceLayoutPrepass'])
 untilTime(now+60000)
 assert(calls==afterGuard and #queue==0,'hidden/disabled host kept timers alive')
 host[field]=true;emit(activate,'post');untilTime(now)
 assert(builds==1,'reopening surviving host duplicated controls')
end
print('PASS hidden/disabled but activated viewport host stops updates before tree/control work')
emit('/Script/UMG.Widget:RemoveFromParent','pre',obj('UnrelatedChild'))
untilTime(now+100);assert(builds==1,'foreign removal invalidated decoration')
emit(deactivate,'pre');untilTime(now+1000)
emit('/Script/UMG.Widget:RemoveFromParent','pre',host)
row.decoration=nil -- model DMM destroying this page
local beforeRecreate=builds
emit(activate,'post');untilTime(now)
assert(builds==beforeRecreate+1,'removed host metadata was retained')
print('PASS foreign removal preserves state; removal after deactivation retires host')
fail=true;untilTime(now+100);local previous=ticks
fail=false;untilTime(now+100);assert(ticks==previous+1 and builds==2)
print('PASS transient tick error recovers without redecorating')
emit(activate,'post',other);untilTime(now)
emit(activate,'post',host);untilTime(now)
assert(builds==2)
print('PASS A -> unrelated B -> A retains original decoration')
emit(deactivate,'pre');local stoppedCalls=calls;local stoppedScans=scans
assert(not hooks['/Script/UMG.Widget:ForceLayoutPrepass'])
untilTime(now+60000)
assert(calls==stoppedCalls and scans==stoppedScans and #queue==0)
print('PASS close: obsolete callbacks drain with zero UObject calls and no rescheduling; event hooks removed')
emit(activate,'post');untilTime(now);emit(load,'pre')
stoppedCalls=calls;untilTime(now+60000)
assert(calls==stoppedCalls and #queue==0)
row.decoration=nil -- the load destroyed the page
emit(activate,'post');untilTime(now)
emit(activate,'post',owner);emit(activate,'post');untilTime(now)
assert(builds==3)
print('PASS load suspension blocks work; new owner session rebuilds released metadata')
emit(deactivate,'pre');untilTime(now+1000)
emit(activate,'post',other);untilTime(now+5000)
local stopped=calls;untilTime(now+60000)
assert(calls==stopped and #queue==0)
print('PASS unmatched host becomes dormant without discovery retries')

emit(deactivate,'pre',owner);untilTime(now+1000)
local noMenuFinds,noMenuScans=finds,scans
for n=1,5 do emit(activate,'post',other) end
untilTime(now+60000)
assert(finds==noMenuFinds and scans==noMenuScans and #queue==0)
print('PASS menu owner closure blocks unrelated activations and recurring work')
emit(activate,'post',owner);emit(activate,'post');untilTime(now)
local beforeHidden=ticks
owner.visible=false;untilTime(now+100)
local afterHidden=calls;untilTime(now+60000)
assert(ticks==beforeHidden and calls==afterHidden and #queue==0)
owner.visible=true
print('PASS fresh owner visibility stops work even without a close notification')
emit(activate,'post',owner);emit(activate,'post');untilTime(now)
fail=true;untilTime(now+500)
assert(instance.disabled and not instance.restored)
local finalTicks=ticks;untilTime(now+1000);assert(ticks==finalTicks)
print('PASS repeated control errors stop this control without tearing apart its row')
emit(deactivate,'pre');untilTime(now+1100)
ExecuteInGameThread=function() error('injected dispatch failure') end
emit(activate,'post');untilTime(now+60000);assert(#queue==0)
print('PASS dispatch failure terminates scheduled updates')
ExecuteWithDelay=function() error('injected scheduling failure') end
row.decoration=nil -- the load destroyed the page
emit(activate,'post');untilTime(now)
print('PASS scheduling failure closes scope without recursion or retries')

local jobs={}
ExecuteWithDelay=function(delay,fn) queue[#queue+1]={time=now+delay,fn=fn} end
ExecuteInGameThread=function(fn) jobs[#jobs+1]=fn end
emit(activate,'post');untilTime(now);assert(#jobs==1)
emit(deactivate,'pre');local before=calls
jobs[1]();untilTime(now+60000)
assert(calls==before and #queue==0)
print('PASS revocation after dispatch but before game-thread execution prevents native access')

-- A replacement with the same number of rows must still rebuild new-widget routes.
ExecuteInGameThread=function(fn) fn() end
emit(activate,'post',owner);emit(activate,'post');untilTime(now)
local replacementWrapper=obj('replacementWrapper')
local replacementSlider=obj('replacementSlider')
row={kind='slider',label='Ability',wrapper=replacementWrapper,slider=replacementSlider}
snapshot={routes={replacementWrapper={path='/Transient.replacementWrapper'},replacementSlider={path='/Transient.replacementSlider'}},
 widgets={scroll=scroll,replacementWrapper=replacementWrapper,replacementSlider=replacementSlider},
 names={scroll='scroll',replacementWrapper='replacementWrapper',replacementSlider='replacementSlider'},scrolls={scroll}}
local beforeReplacementScans,beforeReplacementBuilds=scans,builds
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher)
untilTime(now)
assert(builds==beforeReplacementBuilds+1 and scans==beforeReplacementScans+2,
 'same-count replacement skipped post-construction route scan')
print('PASS same-count row replacement rebuilds routes for new controls')

local oldBuilds=builds
row.label='Ability *'
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(builds==oldBuilds,'intact row decoration duplicated on repeated page event')
print('PASS row-owned decoration survives discarded scope bindings and dirty labels')
-- Model load followed by page readiness with no owner/host activation callback.
FindAllOf=function(name) return name=='WBP_PauseMenu_C' and {owner} or {} end
for n=1,10 do
 emit(load,'pre');untilTime(now+1000)
 row.decoration=nil -- new native row in the rebuilt page
 local count=builds
 emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
 assert(builds==count+1)
end
print('PASS repeated load-to-page completion restarts decoration without wake-event dependency')

local eventScans,eventBuilds=scans,builds
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher)
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher)
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher)
untilTime(now)
assert(scans==eventScans+1 and builds==eventBuilds,'adoption/event burst repeated discovery or construction')
print('PASS same-stack page events coalesce; adopted page needs only one traversal')
local healthyTick=package.loaded.key_selector.tick
fail=false
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
package.loaded.key_selector.tick=function() return false end
untilTime(now+200)
assert(instance.failures==2 and not instance.disabled)
package.loaded.key_selector.tick=healthyTick
untilTime(now+100)
assert(instance.failures==0 and not instance.disabled,'successful update did not reset consecutive failures')
package.loaded.key_selector.tick=function() return false end
untilTime(now+300)
assert(instance.disabled and instance.failures==3)
local stoppedCalls=calls
untilTime(now+60000)
assert(calls==stoppedCalls and #queue==0,'failed controls kept scheduling updates')
package.loaded.key_selector.tick=healthyTick
row.decoration=nil
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(not instance.disabled and instance.failures==0)
print('PASS false-return failures stop after three updates; page readiness recovers')
fail=true;untilTime(now+500)
assert(instance.disabled)
local stoppedNative=calls
untilTime(now+60000)
assert(calls==stoppedNative and #queue==0,'all-disabled menu kept polling')
local foundReason,foundDisabled=false,false
for _,entry in ipairs(diagnostics) do
 if entry:find('P.K',1,true) and entry:find('injected transient error',1,true) then foundReason=true end
 if entry:find('SELECTOR_DISABLED:P.K',1,true) then foundDisabled=true end
end
assert(foundReason and foundDisabled,'actionable error context was discarded')
print('PASS all-disabled scope sleeps; diagnostics preserve setting and original exception')
fail=false
row.decoration=nil
package.loaded.key_selector.decorate=function() return nil,'injected construction cause' end
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(diagnostics[#diagnostics]:find('P.K: injected construction cause',1,true))
print('PASS construction error second return retained with setting identity')

package.loaded.key_selector.decorate=function(r)
 instance={row=r,selector=obj('badLedgerSelector'),keyBox=obj('badLedgerBox'),undo={}}
 function instance.selector:GetFullName() error('injected ledger failure') end
 return instance
end
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(instance.restored,'binding setup failure left a constructed row without updates or stock controls')
assert(diagnostics[#diagnostics]:find('injected ledger failure',1,true))
print('PASS new-row ledger failure rolls back construction before reporting failure')

instance.restored=nil;instance.undo=nil;row.decoration=instance
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(not instance.restored,'adoption failure dismantled an existing row')
print('PASS failed adoption bookkeeping does not dismantle an existing decoration')
