package.path='Scripts/?.lua;'..package.path
local callback,registered,unregistered=nil,0,0
RegisterHook=function(path,pre,post) assert(path=='/Script/UMG.Widget:ForceLayoutPrepass');callback=post;registered=registered+1;return 1,2 end
UnregisterHook=function() callback=nil;unregistered=unregistered+1 end
FName=function(s) return s end
local errors={}
local router=require('click_delivery').new(function(e) errors[#errors+1]=e end)
local function button(id,name)
 local b={id=id,name=name or id,OnClicked={}}
 function b:GetAddress() return self.id end
 function b:GetFullName() return self.name end
 function b.OnClicked:Add(target,fn) assert(target==b and fn=='ForceLayoutPrepass');self.target=target;self.fn=fn end
 return b
end
local function emit(b) callback({get=function() return b end}) end
local i={};local b=button(1,'owned')
assert(router:open('hostA'));router:attach(i,b)
for n=1,3 do emit(b) end
assert(i.pendingClicks==3)
print('PASS three clicks between monitor samples are queued, no state polling')
emit(button(2,'foreign'));emit(button(1,'reusedAddress'));assert(i.pendingClicks==3)
print('PASS foreign button and address reuse with changed identity rejected')
router:open('hostB');emit(b);assert(i.pendingClicks==0)
router:open('hostA');emit(b);assert(i.pendingClicks==1 and registered==1)
local oldCallback=callback
router:close();assert(i.pendingClicks==0 and unregistered==1)
oldCallback({get=function() error('closed callback touched widget') end})
assert(#errors==0)
print('PASS host changes discard old clicks; close clears queue and unhooks without native widget access')
router:open('hostA');emit(b);assert(i.pendingClicks==1)
router:forget(i);emit(b);assert(i.pendingClicks==0)
print('PASS surviving host reuses binding; forgotten instance cannot receive clicks')
router:attach(i,b);emit(b)
router:retire('foreign');assert(i.pendingClicks==1)
router:retire('hostA');emit(b);assert(i.pendingClicks==0 and next(router.owners)==nil)
router:attach(i,b);emit(b);router:retire(nil)
assert(i.pendingClicks==0 and next(router.owners)==nil)
print('PASS retired host/session releases receiver records and pending clicks')
router:close()
RegisterHook=function() error('not available') end
assert(not router:open('hostA'))
assert(not pcall(router.attach,router,i,b))
print('PASS unavailable event hook fails closed before proxy ownership')
