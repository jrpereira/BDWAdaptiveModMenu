package.path='Scripts/?.lua;'..package.path
package.loaded.dirty_labels={new=function() return {open=function() end,close=function() end,bind=function() end,refresh=function() return 0 end,localize=function() end,construct=function(_,fn) return fn() end} end}
local queue,now={},0
local objects={}
local lifecycle
package.loaded.dmm_lifecycle={install=function(_,onChange)
 local scope={enabled=true,epoch=0}
 lifecycle={
  open=function(selection)
   scope.epoch=scope.epoch+1;scope.path='/Transient.CommonActivatableWidget_1';scope.address='CommonActivatableWidget_1';scope.treeAddress='HostTree'
   onChange(scope.path,scope.epoch,selection or {path='/Transient.scroll',address='scroll'})
  end,
  close=function()
   scope.epoch=scope.epoch+1;scope.path=nil;onChange(nil,scope.epoch)
  end,
 }
 function scope:current() return self.path,self.epoch end
 function scope:matches(path,epoch) return self.path==path and self.epoch==epoch end
 function scope:ownerLive()
  if not self.path then return false end
  local h=objects[self.path]
  if not h or h.visible==false or h.active==false or h.viewport==false or h.enabled==false then lifecycle.close();return false end
  return true
 end
 function scope:invalidate() if self.path then lifecycle.close() end end
 return scope
end}
local calls,scans,builds,ticks=0,0,0,0
local finds=0
local fail=false
Key={LEFT_MOUSE_BUTTON=1}
RegisterKeyBind=function(_,fn) pointerCallback=fn end
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
local row={kind='slider',label='Ability',wrapper=wrapper,slider=slider,identityProviderId='P',settingId='K',
 dmmSetting={id='K',kind='slider',minimum=0,maximum=254,step=1,decimals=0,prefix='',suffix='',kemKeybind=true}}
local pageRows={row}
local routes={}
for _,o in ipairs({scroll,wrapper,slider,relay}) do routes[o.name]={path='/Transient.'..o.name} end
local snapshot={routes=routes,widgets={scroll=scroll,wrapper=wrapper,slider=slider,relay=relay},names={scroll='scroll',wrapper='wrapper',slider='slider',relay='relay'},scrolls={scroll}}
StaticFindObject=function(path) calls=calls+1;finds=finds+1;return objects[path] end
LoopAsync=function() error('permanent timer forbidden') end
ExecuteWithDelay=function(delay,fn) queue[#queue+1]={time=now+delay,fn=fn} end
ExecuteInGameThread=function(fn) fn() end
EGameThreadMethod={EngineTick=1};EngineTickAvailable=true
RegisterHook=function() error('global lifecycle hooks forbidden') end
package.loaded.widget_discovery={valid=function(o) return o and o:IsValid() end,address=function(o) return o:GetAddress() end,
 activeTrees=function(h) scans=scans+1;if h==other or browser then return {{widgets={},names={},scrolls={}}} end;return {snapshot} end,
 routesFor=function() return snapshot.routes end,
 routeResolver=function() return function(route) return route and objects[route.path] end end,
 rowsFromScroll=function(target) if target==scroll then return pageRows end end}
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
local diagnostics={}
assert(require('dmm_binding').install(function(event,detail) diagnostics[#diagnostics+1]=event..':'..detail end))
local function emit(path,phase,o)
 o=o or host
 if path:find('SetActiveWidgetIndex',1,true) then
  local selection={path='/Transient.scroll',address='scroll'}
  if o.GetActiveWidgetIndex and o.GetChildAt then
   local child=o:GetChildAt(o:GetActiveWidgetIndex())
   selection={path=child:GetFullName():match('^%S+ (.+)$'),address=tostring(child:GetAddress())}
  end
  lifecycle.open(selection)
 elseif path:find('RequestLoadSave',1,true) or path:find('NotifyLoadingScreenStarted',1,true)
  or path:find('DeactivateWidget',1,true) or (path:find('RemoveFromParent',1,true) and o==host) then lifecycle.close()
 elseif path:find('ActivateWidget',1,true) and o==host and not browser then lifecycle.open() end
end
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
row.identityProviderId='P';row.settingId='K';row.label='Repeated or localized label'
local priorTicks=ticks
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(ticks>priorTicks,'explicit row identity must not depend on label text')
row.settingId='WrongSetting';priorTicks=ticks
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(ticks==priorTicks,'foreign setting identity must not fall back to label matching')
row.identityProviderId='P';row.settingId='K';row.label='Ability'
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
print('PASS explicit row identity accepts repeated/localized labels and rejects mismatched settings')
print('PASS lazy provider opens after browser dormancy: page event wakes dormant host without timers')
local firstScans=scans
local firstFinds=finds
untilTime(now+900);assert(scans==firstScans)
assert(finds-firstFinds==18,'50 ms steady updates resolve one host, never each control')
print('PASS fresh host lookup per update, no owner scan or per-control global lookup')
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
fail=true;untilTime(now+50);local previous=ticks
fail=false;untilTime(now+50);assert(ticks==previous+1 and builds==2)
print('PASS transient tick error recovers without redecorating')
emit(activate,'post',other);untilTime(now)
emit(activate,'post',host);untilTime(now)
assert(builds==2)
print('PASS A -> unrelated B -> A retains original decoration')
emit(deactivate,'pre');local stoppedCalls=calls;local stoppedScans=scans
untilTime(now+60000)
assert(calls==stoppedCalls and scans==stoppedScans and #queue==0)
print('PASS close: obsolete callbacks drain with zero UObject calls and no rescheduling')
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
print('PASS close callback blocks unrelated activations and recurring work')
emit(activate,'post',owner);emit(activate,'post');untilTime(now)
local beforeHidden=ticks
host.visible=false;untilTime(now+100)
local afterHidden=calls;untilTime(now+60000)
assert(ticks==beforeHidden and calls==afterHidden and #queue==0)
host.visible=true
print('PASS fresh host visibility stops work even without a close notification')
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
row={kind='slider',label='Ability',wrapper=replacementWrapper,slider=replacementSlider,identityProviderId='P',settingId='K',
 dmmSetting={id='K',kind='slider',minimum=0,maximum=254,step=1,decimals=0,prefix='',suffix='',kemKeybind=true}}
pageRows={row}
snapshot={routes={replacementWrapper={path='/Transient.replacementWrapper'},replacementSlider={path='/Transient.replacementSlider'}},
 widgets={scroll=scroll,replacementWrapper=replacementWrapper,replacementSlider=replacementSlider},
 names={scroll='scroll',replacementWrapper='replacementWrapper',replacementSlider='replacementSlider'},scrolls={scroll}}
local beforeReplacementScans,beforeReplacementBuilds=scans,builds
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher)
untilTime(now)
assert(builds==beforeReplacementBuilds+1 and scans==beforeReplacementScans,
 'same-count replacement skipped targeted post-construction routes')
print('PASS same-count row replacement rebuilds from DMM exact-scroll callback without a tree scan')

local oldBuilds=builds
row.label='Ability *'
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(builds==oldBuilds,'intact row decoration duplicated on repeated page event')
print('PASS row-owned decoration survives discarded scope bindings and dirty labels')
-- Model load followed by page readiness with no owner/host activation callback.
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
assert(scans==eventScans and builds==eventBuilds,'adoption/event burst repeated discovery or construction')
print('PASS same-stack DMM callbacks coalesce; adopted page needs no tree traversal')
local directSwitcher=obj('DirectSwitcher')
function directSwitcher:GetOuter() return host.WidgetTree end
function directSwitcher:GetActiveWidgetIndex() return 0 end
function directSwitcher:GetChildAt(index) assert(index==0);return scroll end
local directScans,directBuilds=scans,builds
fail=false
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',directSwitcher);untilTime(now)
assert(scans==directScans and builds==directBuilds,'exact selected ScrollBox fell back to a full tree scan')
print('PASS page selection binds the exact provider ScrollBox with zero full-tree scans')
local healthyTick=package.loaded.key_selector.tick
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
package.loaded.key_selector.tick=function() return false end
untilTime(now+100)
assert(instance.failures==2 and not instance.disabled,'failures='..tostring(instance.failures)..' disabled='..tostring(instance.disabled))
package.loaded.key_selector.tick=healthyTick
untilTime(now+50)
assert(instance.failures==0 and not instance.disabled,'successful update did not reset consecutive failures')
package.loaded.key_selector.tick=function() return false end
untilTime(now+150)
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
local constructionDiagnostic=false
for _,entry in ipairs(diagnostics) do
 if entry:find('P.K: injected construction cause',1,true) then constructionDiagnostic=true end
end
assert(constructionDiagnostic)
print('PASS construction error second return retained with setting identity')

package.loaded.key_selector.decorate=function(r)
 instance={row=r,selector=obj('badLedgerSelector'),keyBox=obj('badLedgerBox'),undo={}}
 function instance.selector:GetFullName() error('injected ledger failure') end
 return instance
end
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(instance.restored,'binding setup failure left a constructed row without updates or stock controls')
local ledgerDiagnostic=false
for _,entry in ipairs(diagnostics) do
 if entry:find('injected ledger failure',1,true) then ledgerDiagnostic=true end
end
assert(ledgerDiagnostic)
print('PASS new-row ledger failure rolls back construction before reporting failure')

instance.restored=nil;instance.undo=nil;row.decoration=instance
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(not instance.restored,'adoption failure dismantled an existing row')
print('PASS failed adoption bookkeeping does not dismantle an existing decoration')

-- Row order, descriptor order and formatting metadata order are independent.
local peer={kind='picker',label='Same',wrapper=obj('peerWrapper'),nav=obj('peerNav'),valueWidget=obj('peerValue'),pairHost=obj('peerHost'),identityProviderId='P',settingId='Mode',
 dmmSetting={id='Mode',kind='picker',values={0,3,-1},labels={'Tap','Hold','Default'},kemPairTargetId='K'}}
row.label='Same';row.decoration=nil
pageRows={peer,row}
local keySetting={id='K',kind='slider',minimum=0,maximum=254,step=1,decimals=0,prefix='',suffix='',kemKeybind=true,kemPairId='Mode'}
local modeSetting={id='Mode',kind='picker',values={0,3,-1},labels={'Tap','Hold','Default'},kemPairTargetId='K'}
row.dmmSetting=keySetting;peer.dmmSetting=modeSetting
local matched,bound=0,nil
package.loaded.key_selector.adopt=function() return nil end
package.loaded.key_selector.decorate=function(r,d,_,host)
 assert(r==row and d.providerId=='P' and d.settingId=='K' and d.modeId=='Mode'
  and d.minimum==0 and d.maximum==254 and d.modeOptions==modeSetting.labels
  and d.modeValues==modeSetting.values and d.disabledMode==-1 and host==peer.pairHost);matched=matched+1
 bound={row=r,selector=relay,keyBox=wrapper};return bound
end
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(matched==1 and bound.modeNav==peer.nav and row.dmmSetting==keySetting and peer.dmmSetting==modeSetting)
pageRows={row,peer}
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(matched==2 and row.dmmSetting==keySetting and peer.dmmSetting==modeSetting)
pageRows={row,row}
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(matched==2,'duplicate row identity must not bind')
pageRows={row,peer};peer.identityProviderId='Other'
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(matched==2,'mixed-provider rows must not bind')
peer.identityProviderId='P';row.settingId=nil
emit('/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex','post',switcher);untilTime(now)
assert(matched==2,'missing row identity must not fall back to text/order')
print('PASS row-owned DMM metadata binds by ID with independent visual order; ambiguous identities rejected')
