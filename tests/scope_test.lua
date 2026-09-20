package.path='Scripts/?.lua;'..package.path
local shared,handler={},nil
ModRef={
 GetSharedVariable=function(_,key) return shared[key] end,
 SetSharedVariable=function(_,key,value) shared[key]=value end,
}
RegisterConsoleCommandHandler=function(command,callback)
 assert(command=='AMM_DMM_Lifecycle_v1');assert(not handler);handler=callback
end
local objects={}
local function object(class,name,address)
 local o={class=class,name=name,address=tostring(address),visible=true,active=true,viewport=true}
 function o:IsValid() return true end
 function o:GetFullName() return self.class..' /Transient.'..self.name end
 function o:GetAddress() return self.address end
 function o:IsVisible() return self.visible end
 function o:IsActivated() return self.active end
 function o:IsInViewport() return self.viewport end
 function o:IsA(wanted) return wanted=='/Script/Engine.GameViewportClient' end
 objects['/Transient.'..name]=o
 return o
end
local viewport=object('GameViewportClient','Viewport',90)
function viewport:ProcessConsoleExec(command) assert(command=='AMM_DMM_Lifecycle_v1');return handler() end
local pc=object('PlayerController','PC',91);pc.Player={IsValid=function() return true end,ViewportClient=viewport}
local host=object('CommonActivatableWidget','Host',1)
local tree=object('WidgetTree','Tree',2);host.WidgetTree=tree
function tree:GetOuter() return host end
local scroll=object('ScrollBox','Scroll',3)
StaticFindObject=function(path) return objects[path] end

local changes={}
local Lifecycle=require('dmm_lifecycle')
local scope=assert(Lifecycle.install(function(event,detail) error(event..': '..tostring(detail)) end,
 function(path,epoch,selection) changes[#changes+1]={path=path,epoch=epoch,selection=selection} end))
local publisher=Lifecycle.publisher(function(event,detail) error(event..': '..tostring(detail)) end)
local context={host=host,tree=tree,pc=pc,provider={id='Provider'},panel={scroll=scroll}}

assert(publisher:publish('providerPrepared',context));assert(#changes==1)
assert(changes[1].selection.path=='/Transient.Scroll' and changes[1].selection.address=='3')
local path,epoch=scope:current();assert(scope:matches(path,epoch) and scope:ownerLive())
assert(publisher:publish('providerRefreshed',context));assert(#changes==2 and select(2,scope:current())>epoch)
print('PASS DMM provider callbacks grant and refresh exact menu scope')

scope:invalidate();assert(changes[#changes].path==nil)
assert(publisher:publish('providerPrepared',context));assert(scope:current()==path)
assert(publisher:publish('hostClosing',context));assert(not scope:current() and changes[#changes].path==nil)
print('PASS close callback retires row-owned state and dormant scope can reopen')

assert(publisher:publish('providerPrepared',context))
host.visible=false;assert(not scope:ownerLive() and not scope:current());host.visible=true
print('PASS fresh host validation revokes stale callback state')

local calls=0
RegisterHook=function() calls=calls+1 end
assert(calls==0,'lifecycle transport must not register global UObject hooks')
print('PASS lifecycle transport registers no process-wide hooks')
