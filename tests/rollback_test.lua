package.path='Scripts/?.lua;'..package.path
local objects,serial={},0
local construction,failAt=0,nil
local constructed={}
local function widget()
 serial=serial+1
 local w={id=tostring(serial),children={},opacity=1,visibility=0,WidthOverride=100,bOverride_WidthOverride=true,Font={Size=18},text='Tap'}
 function w:IsValid() return true end
 function w:GetFullName() return 'Widget /Transient.W'..self.id end
 function w:GetAddress() return self.id end
 function w:GetRenderOpacity() return self.opacity end
 function w:SetRenderOpacity(v) self.opacity=v end
 function w:GetVisibility() return self.visibility end
 function w:SetVisibility(v) self.visibility=v end
 function w:SetWidthOverride(v) if self.failWidth then self.failWidth=false;error('width failure') end;self.WidthOverride=v;self.bOverride_WidthOverride=true end
 function w:ClearWidthOverride() self.bOverride_WidthOverride=false end
 function w:SetContent(c) self.children={c};c.parent=self;return widget() end
 function w:AddChildToOverlay(c) self.children[#self.children+1]=c;c.parent=self;return widget() end
 function w:RemoveFromParent() if self.parent then for i,c in ipairs(self.parent.children) do if c==self then table.remove(self.parent.children,i);break end end end;self.parent=nil end
 function w:SetText(v) assert(type(v)=='table');self.text=v.text end
 function w:GetDesiredSize() return {X=40} end
 function w:Conv_StringToText(v) return {text=v} end
 for _,method in ipairs({'SetHeightOverride','SetBrushColor','SetPadding','SetHorizontalAlignment','SetVerticalAlignment','SetJustification','SetTextOverflowPolicy','SetFont','SetRenderTransformPivot','SetRenderScale','SetAllowGamepadKeys','SetAllowModifierKeys','SetEscapeKeys','SetBackgroundColor','ForceLayoutPrepass'}) do w[method]=function() end end
 objects['/Transient.W'..w.id]=w
 return w
end
StaticFindObject=function(path) if path:match('^/Script/') then return widget() end;return objects[path] end
StaticConstructObject=function(class,outer) construction=construction+1;if construction==failAt then error('construction failure') end;local w=widget();w.outer=outer;constructed[#constructed+1]=w;return w end
FName=function(v) return v end
package.loaded.widget_discovery={valid=function(o) return o and o:IsValid() end,address=function(o) return o:GetAddress() end,
 contentOf=function(o) return o and o.children[1] end,childCount=function(o) return #o.children end,childAt=function(o,i) return o.children[i+1] end,textOf=function(o) return o.text end}
local M=require('key_selector')
local clicks={attach=function() end}
local descriptor={providerId='P',settingId='K',modeId='Mode',modeOptions={'Tap','Hold'}}
local function row()
 local r={}
 for _,name in ipairs({'slider','valueWidget','surface','labelBox','surfaceBox','valueBox','tree','wrapper','labelWidget'}) do r[name]=widget() end
 r.surface.children={r.slider};r.slider.parent=r.surface;r.label='Ability'
 r.valueBox.bOverride_WidthOverride=false
 return r
end
for failure=1,15 do
 construction=0;failAt=failure
 local r=row();local instance=M.decorate(r,descriptor,function() end)
 assert(not instance,'failure injection missed')
 assert(r.slider.opacity==1 and r.valueWidget.opacity==1 and #r.surface.children==1)
 assert(not r.valueBox.bOverride_WidthOverride)
end
print('PASS failures throughout key construction preserve stock opacity, roots and unset width override')
failAt=nil;construction=0
local r=row();r.labelBox.failWidth=true
assert(not M.decorate(r,descriptor,function() end))
assert(#r.surface.children==1 and r.slider.opacity==1 and r.valueWidget.opacity==1)
print('PASS failure after attachment removes replacement and restores stock visuals')
r=row();constructed={};local instance=assert(M.decorate(r,descriptor,function() end))
assert(instance.keyBox.opacity==1 and r.slider.opacity==0 and r.valueWidget.opacity==0,'replacement key box must remain visible')
print('PASS newly attached replacement parent stays opacity1 while stock controls are hidden')
local mode={kind='picker',wrapper=widget(),nav=widget(),valueWidget=widget()}
assert(M.mergePair(instance,mode,function() end,clicks))
assert(mode.wrapper.visibility==1 and #r.surface.children==3)
for _,w in ipairs(constructed) do
 assert(w.outer==r.tree,'decoration constructed outside the row WidgetTree')
 local current=w
 while current.parent and current.parent~=r.surface do current=current.parent end
 assert(current.parent==r.surface,'decoration not attached beneath the stock row')
end
print('PASS every constructed widget shares the row WidgetTree and attaches below its surface')
local concat=table.concat
local serialized=0
table.concat=function(...) serialized=serialized+1;return concat(...) end
for n=1,100 do M.save(instance) end
assert(serialized==0,'unchanged state was serialized')
instance.lastName='F7';M.save(instance);assert(serialized==1)
M.save(instance);assert(serialized==1)
table.concat=concat
print('PASS unchanged row state allocates no serialization buffer; changed state serializes once')
local beforeAdopt=construction
instance.lastName='ThumbMouseButton';instance.wasSelecting=true;instance.captureName='F1'
instance.pair.hovered=true;M.save(instance)
local adopted=M.adopt(r,descriptor,mode,{attach=function(_,_,button,existing)
 assert(button==instance.pair.button and existing,'adoption must not add a second delegate')
end})
assert(adopted and adopted~=instance and construction==beforeAdopt)
assert(adopted.lastName=='ThumbMouseButton' and adopted.wasSelecting and adopted.captureName=='F1')
assert(adopted.pair.hovered and adopted.selector==instance.selector)
assert(not M.adopt(row(),descriptor,mode,clicks),'new row inherited old decoration')
print('PASS row state survives discarded Lua bindings; new rows have no decoration')
assert(M.restore(instance,function() return true end))
assert(mode.wrapper.visibility==0 and #r.surface.children==1 and r.slider.opacity==1 and r.valueWidget.opacity==1)
assert(not r.valueBox.bOverride_WidthOverride and r.labelBox.WidthOverride==100)
print('PASS restoring a successful key/pair restores mode row, opacity, roots and exact width state')
r=row();instance=assert(M.decorate(r,descriptor,function() end))
construction=0;failAt=2
assert(not M.mergePair(instance,mode,function() end,clicks))
assert(#r.surface.children==2 and r.slider.opacity==0 and mode.wrapper.visibility==0)
print('PASS failed pair leaves working key and stock mode row intact')


failAt=nil;r=row();instance=assert(M.decorate(r,descriptor,function() end))
assert(not M.mergePair(instance,mode,function() end,{attach=function() error('delegate unsupported') end}))
assert(instance.pair==nil and #r.surface.children==2 and instance.keyBox.opacity==1 and mode.wrapper.visibility==0)
print('PASS unsupported native delegate rolls back proxy and preserves visible stock mode row')

-- A failure while recording a just-attached root must stay inside the transaction.
r=row()
local attach=r.surface.AddChildToOverlay
function r.surface:AddChildToOverlay(child)
 local slot=attach(self,child)
 function child:GetFullName() error('injected receipt identity failure') end
 return slot
end
local ok,failed,why=pcall(M.decorate,r,descriptor,function() end)
assert(ok and not failed and tostring(why):find('receipt identity failure',1,true))
assert(#r.surface.children==1 and r.slider.opacity==1 and r.valueWidget.opacity==1,
 'receipt failure left stock controls hidden')
print('PASS post-attachment receipt errors roll back roots and stock presentation')

r=row();r.labelBox.failWidth=true
local setOpacity=r.slider.SetRenderOpacity
function r.slider:SetRenderOpacity(value)
 if value==1 then error('injected rollback failure') end
 return setOpacity(self,value)
end
local failed,why=M.decorate(r,descriptor,function() end)
assert(not failed and tostring(why):find('rollback incomplete',1,true),
 'incomplete rollback was silently discarded')
print('PASS incomplete rollback is included in the construction diagnostic')

r=row();instance=assert(M.decorate(r,descriptor,function() end))
local priorText=instance.stateText
local attachPair=r.surface.AddChildToOverlay
function r.surface:AddChildToOverlay(child)
 local slot=attachPair(self,child)
 function child:GetFullName() error('injected pair receipt failure') end
 return slot
end
local paired,why=M.mergePair(instance,mode,function() end,clicks)
assert(not paired and tostring(why):find('pair receipt failure',1,true))
assert(#r.surface.children==2 and mode.wrapper.visibility==0 and instance.stateText==priorText)
local afterRollback=assert(M.adopt(r,descriptor,mode,clicks))
assert(not afterRollback.pair and not afterRollback.pairIndex)
print('PASS failed pair receipt restores row-owned state so later adoption remains valid')
