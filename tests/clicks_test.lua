package.path='Scripts/?.lua;'..package.path
local callback,registered=nil,0
Key={LEFT_MOUSE_BUTTON=1}
RegisterKeyBind=function(key,fn) assert(key==Key.LEFT_MOUSE_BUTTON);callback=fn;registered=registered+1 end
FName=function(s) return s end
local errors={}
local router=require('click_delivery').new(function(e) errors[#errors+1]=e end)
local function button(id,name)
 local b={id=id,name=name or id}
 function b:GetAddress() return self.id end
 function b:GetFullName() return self.name end
 function b:IsValid() return self.alive~=false end
 function b:IsHovered() return self.hovered==true end
 return b
end
local function emit() callback() end
local i={};local b=button(1,'owned')
assert(router:open('hostA'));router:attach(i,b);i.pair={button=b};b.hovered=true
emit();router:deliver(i);assert(i.pendingClicks==1)
print('PASS one pointer press produces exactly one paired-picker change request')
i.pendingClicks=0
for n=1,3 do emit() end
router:deliver(i)
assert(i.pendingClicks==3)
print('PASS three clicks between monitor samples are queued and delivered on the game-thread sample')
b.hovered=false;emit();router:deliver(i);router:discard();assert(i.pendingClicks==3)
print('PASS clicks outside an owned hovered picker are discarded')
local j={};local other=button(2,'other');j.pair={button=other};other.hovered=true
router:attach(j,other);emit();router:deliver(i);router:deliver(j)
assert(i.pendingClicks==3 and j.pendingClicks==1)
print('PASS a click is delivered only to the different row that is currently hovered')
router:open('hostB');emit();assert(i.pendingClicks==0)
router:open('hostA');b.hovered=true;emit();router:deliver(i);assert(i.pendingClicks==1 and registered==1)
router:close();assert(i.pendingClicks==0)
callback()
assert(#errors==0)
print('PASS host changes discard old clicks; closed callback performs no native widget access')
router:open('hostA');router:deliver(i);assert(i.pendingClicks==0)
print('PASS a click queued before close is not delivered after reopen')
emit();router:deliver(i);assert(i.pendingClicks==1)
router:forget(i);emit();router:deliver(i);router:discard();assert(i.pendingClicks==0)
print('PASS surviving host reuses binding; forgotten instance cannot receive clicks')
router:attach(i,b);emit();router:deliver(i)
router:retire('foreign');assert(i.pendingClicks==1)
router:retire('hostA');emit();assert(i.pendingClicks==0 and next(router.owners)==nil)
router:open('hostA');router:attach(i,b);emit();router:deliver(i);router:retire(nil)
assert(i.pendingClicks==0 and next(router.owners)==nil)
print('PASS retired host/session releases receiver records and pending clicks')
router:close()
for _=1,32 do callback() end
assert(router.pointerClicks==0 and registered==1)
router:open('hostA');for _=1,32 do callback() end
assert(router.pointerClicks==16 and registered==1)
router:close();assert(router.pointerClicks==0)
print('PASS callback is bounded, inactive outside settings and registered only once across reopen')
Key=nil;RegisterKeyBind=nil
local unavailable=require('click_delivery').new(function(e) errors[#errors+1]=e end)
assert(not unavailable:open('hostA'))
assert(not pcall(unavailable.attach,unavailable,i,b))
print('PASS unavailable mouse callback fails closed before proxy ownership')
