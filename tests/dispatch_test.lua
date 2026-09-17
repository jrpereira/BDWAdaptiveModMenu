package.path='Scripts/?.lua;'..package.path
local inGame=false
local jobs,timers={},{}
local calls=0
local function gameOnly() assert(inGame,'UObject access from async/notification thread');calls=calls+1 end
local scroll={kind='scroll'};local slider={kind='slider'}
package.loaded.widget_discovery={
 valid=function() gameOnly();return true end,
 address=function(o) gameOnly();return o.kind end,
 ancestorOfClass=function() gameOnly();return scroll end,
 rowsFromScroll=function() gameOnly();return {} end,
}
package.loaded.key_selector={}
EGameThreadMethod={EngineTick=1}
ExecuteInGameThread=function(fn,method) assert(method==1);jobs[#jobs+1]=fn end
LoopAsync=function(ms,fn) timers[#timers+1]=fn end
local notify
NotifyOnNewObject=function(_,fn) notify=fn end
local errors={}
local M=require('dmm_binding')
assert(M.install({providerList={}},function(event) errors[#errors+1]=event end))
notify(slider);assert(calls==0 and #jobs==1)
local function drain()
 local current=jobs;jobs={}
 inGame=true;for _,fn in ipairs(current) do fn() end;inGame=false
end
drain();assert(calls>0)
local before=calls
for _,fn in ipairs(timers) do fn() end
local count=#jobs
for _,fn in ipairs(timers) do fn() end
assert(#jobs==count and calls==before,'duplicate queue or off-thread work')
drain()
for _,fn in ipairs(timers) do fn() end
drain()
for _,event in ipairs(errors) do assert(not event:find('FAILED',1,true),event) end
print('PASS notification/timer UObject work deferred to EngineTick with bounded queues')
