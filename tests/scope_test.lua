package.path='Scripts/?.lua;'..package.path
local hooks,removed={},0
RegisterHook=function(path,pre,post) hooks[path]={pre,post};return 1,2 end
UnregisterHook=function(path) hooks[path]=nil;removed=removed+1 end
local function object(name,address,kind)
 local o={name=name,address=address,active=true,visible=true,enabled=true,viewport=true}
 function o:IsValid() return true end
 function o:GetFName() return {ToString=function() return self.name end} end
 function o:GetFullName() return (kind or 'Widget')..' /Transient.'..self.name end
 function o:GetAddress() return self.address end
 function o:IsVisible() return self.visible end
 function o:IsActivated() return self.active end
 function o:IsInViewport() return self.viewport end
 function o:GetIsEnabled() return self.enabled end
 return o
end
local owner=object('WBP_PauseMenu_C_1',55,'WBP_PauseMenu_C')
local host=object('CommonActivatableWidget_1',1)
local tree=object('WidgetTree_1',123)
host.WidgetTree=tree
function tree:GetOuter() return host end
local switcher=object('WidgetSwitcher_1',124)
function switcher:GetOuter() return tree end
StaticFindObject=function(path) assert(path=='/Transient.'..owner.name);return owner end
local available=false
FindAllOf=function(name) assert(name=='WBP_MainMenu_C' or name=='WBP_PauseMenu_C');return available and {owner} or {} end
local retired,changes={},0
local scope=assert(require('menu_scope').install(function(e,err) error(e..': '..err) end,
 function() changes=changes+1 end,function(path) retired[#retired+1]=path or 'ALL' end))
local function emit(path,phase,o) hooks[path][phase]({get=function() return o or host end}) end
local a='/Script/CommonUI.CommonActivatableWidget:ActivateWidget'
local d='/Script/CommonUI.CommonActivatableWidget:DeactivateWidget'
local load='/Script/DogwoodUI.SaveWindowBase:RequestLoadSave'
local switch='/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex'
local remove='/Script/UMG.Widget:RemoveFromParent'
emit(a,2);assert(not scope:current())
emit(a,2,owner);emit(a,2)
local path,epoch=scope:current();assert(path=='/Transient.CommonActivatableWidget_1')
emit(d,1);assert(not scope:current() and not scope:matches(path,epoch))
emit(a,2);assert(not scope:matches(path,epoch))
scope:dormant();local dormantEpoch=select(2,scope:current())
emit(switch,2,switcher);assert(select(2,scope:current())>dormantEpoch)
print('PASS owned page events wake dormancy; temporary deactivation revokes old work')
emit(load,1);assert(not scope:current() and retired[#retired]=='ALL')
owner.active=false;emit(a,2);emit(switch,2,switcher);assert(not scope:current())
available=true;owner.active=true
-- No parent ActivateWidget or ShowPauseMenu: page completion must recover on its own.
for n=1,10 do
 emit(load,1);assert(not scope:current())
 emit(switch,2,switcher);assert(scope:current() and scope:ownerLive())
end
print('PASS ten load/page-open cycles recover without parent activation or pause notification')
emit(d,1);emit(remove,1);assert(retired[#retired]=='/Transient.CommonActivatableWidget_1')
emit(d,1,owner);assert(retired[#retired]=='ALL')
for _,field in ipairs({'visible','active','viewport','enabled'}) do
 host[field]=false;emit(switch,2,switcher);assert(not scope:current())
 host[field]=true
end
print('PASS construction-time, hidden, disabled and inactive hosts cannot start work')
local foreignHost=object('InventoryWidget_1',2)
local foreignTree=object('WidgetTree_2',999)
function foreignTree:GetOuter() return foreignHost end
local foreignSwitcher={GetOuter=function() return foreignTree end}
emit(switch,2,foreignSwitcher);assert(not scope:current())
print('PASS unrelated page switch cannot grant menu scope')
emit(switch,2,switcher);assert(scope:current())
owner.visible=false;assert(not scope:ownerLive() and not scope:current());owner.visible=true
print('PASS fresh owner loss cancels scope without close event')
local errors={}
local recovering=assert(require('menu_scope').install(function(event,detail) errors[#errors+1]=event..':'..detail end))
hooks[switch][2]({get=function() error('injected lifecycle failure') end})
assert(recovering.enabled and not recovering:current() and #errors==1)
emit(switch,2,switcher)
assert(recovering:current(),'valid page event failed to recover after callback exception')
print('PASS lifecycle exception cancels current work; next valid page event recovers')
RegisterHook=function(path,pre,post) if path==load then error('missing hook') end;hooks[path]={pre,post};return 1,2 end
removed=0;assert(not require('menu_scope').install(function() end));assert(removed==3)
print('PASS partial installation unregisters successful hooks')
