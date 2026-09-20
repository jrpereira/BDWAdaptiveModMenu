package.path='Scripts/?.lua;'..package.path
local M=require('presentation')
local items={
    {id='Primary',kind='picker',group='General',label='Primary',values={0,1},labels={'Consumables','Abilities'}},
    {id='Ability',kind='picker',group='Abilities',label='Ability',values={0,1},labels={'Tap','Hold'}},
    {id='Consumable',kind='picker',group='Consumables',label='Consumable',values={0,1},labels={'Tap','Hold'}},
    {id='Enabled',kind='toggle',group='General',label='Enabled',values={0,1},labels={'Off','On'}},
    {id='Key',kind='slider',group='Keys',label='Key'},
    {id='KeyMode',kind='picker',group='Keys',label='Mode',values={0,1},labels={'Tap','Hold'}},
}
local schema=[[
[Setting.Primary]
Id=Primary
DecoType=tab
DecoLevel=2
[Setting.Ability]
Id=Ability
DecoLabelWhen=Primary
DecoLabels=0:Slot 5;1:Slot 1
[Category.Abilities]
DecoHelp=Ability explanation
DecoParent=Interaction: Independent
DecoParentLevel=2
DecoLevel=3
DecoLabelWhen=Primary
DecoLabels=0:Secondary Wheel;1:Primary Wheel
DecoOrderWhen=Primary
DecoOrders=0:20;1:10
[Category.Consumables]
DecoParent=Interaction: Independent
DecoParentLevel=2
DecoLabelWhen=Primary
DecoLabels=0:Primary Wheel;1:Secondary Wheel
DecoOrderWhen=Primary
DecoOrders=0:10;1:20
[Category.Keys]
DecoParent=Interaction: Selective
DecoParentLevel=2
DecoLevel=3
[Setting.Enabled]
Id=Enabled
DecoLevel=1
[Setting.Key]
Id=Key
DecoType=keybind
DecoMode=Tap
[Setting.KeyMode]
Id=KeyMode
DecoType=keybind
]]
M.parse(schema,items)
assert(items[1].ammTabs and items[1].ammFont==2)
assert(items[2].ammLabelRule.values[0]=='Slot 5')
assert(items[2].ammGroup.parent==items[3].ammGroup.parent,'Shared parent labels must share one descriptor')
assert(items[2].ammGroup.parent.label=='Interaction: Independent' and items[2].ammGroup.parent.font==2)
assert(items[5].ammGroup.parent.label=='Interaction: Selective')
M.parse(schema:gsub('DecoType=tab','Decoration=tabs'):gsub('DecoLevel=2','DecorationFont=Level2'),items)
assert(not items[1].ammTabs and items[1].ammFont==nil,'noncanonical metadata must be ignored')
assert(not pcall(M.parse,schema:gsub('DecoType=tab','DecoType=tabs'),items))
assert(not pcall(M.parse,schema:gsub('DecoLevel=1','DecoLevel=9'),items))
M.parse(schema,items)
assert(not pcall(M.parse,schema:gsub('DecoLevel=2','DecoLevel=9'),items))
assert(not pcall(M.parse,schema:gsub('DecoLabelWhen=Primary','DecoLabelWhen=Missing'),items))
local parentItems={{id='One',kind='toggle',group='One',values={0,1}},{id='Two',kind='toggle',group='Two',values={0,1}}}
assert(not pcall(M.parse,'[Category.One]\nDecoParent=\n',parentItems))
assert(not pcall(M.parse,'[Category.One]\nDecoParentLevel=2\n',parentItems))
assert(not pcall(M.parse,'[Category.One]\nDecoParent=Shared\nDecoParentLevel=2\n[Category.Two]\nDecoParent=Shared\nDecoParentLevel=3\n',parentItems))
local function widget()
    local w={children={},Font={SkewAmount=0},enabled=true,position=0,visible=0}
    function w:GetFullName() return 'Widget '..tostring(self) end
    function w:IsValid() return true end
    function w:GetParent() return self.parent end
    function w:GetChildrenCount() return #self.children end
    function w:GetChildAt(n) return self.children[n+1] end
    function w:GetContent() return self.children[1] end
    function w:AddChild(child)
        child.parent=self;self.children[#self.children+1]=child
        child.Slot={Padding={Left=0,Top=0,Right=0,Bottom=0}}
        setmetatable(child.Slot,{__index=function(_,key)
            return function(slot,value) slot[key:sub(4)]=value end
        end})
        return child.Slot
    end
    function w:RemoveChild(child)
        for n,v in ipairs(self.children) do if v==child then table.remove(self.children,n);child.parent=nil;return true end end
        return false
    end
    function w:ClearChildren() for _,child in ipairs(self.children) do child.parent=nil end;self.children={} end
    function w:SetContent(child) self:ClearChildren();return self:AddChild(child) end
    function w:SetVisibility(v) self.visible=v end
    function w:SetValue(v) self.position=v end
    function w:GetValue() return self.position end
    function w:SetIsEnabled(v) self.enabled=v end
    function w:GetIsEnabled() return self.enabled end
    function w:IsPressed() return self.pressed or false end
    function w:IsHovered() return self.hovered or false end
    function w:HasUserFocus() return false end
    function w:SetRenderOpacity(v) assert(type(v)=='number');self.opacity=v end
    function w:SetFont(v) self.Font=v end
    return setmetatable(w,{__index=function(_,key)
        if key:match('^Set') or key=='ForceVolatile' or key=='ScrollToStart' or key=='ScrollWidgetIntoView' then return function() end end
    end})
end
local noop=function() end
local theme={font=function(label,_,size) label.Font.Size=size end,textColor=function(label,color) label.color=color end,
    selectionState=function() return 0 end,image=widget,sliderTrack=function() return widget(),widget() end}
setmetatable(theme,{__index=function() return noop end})
local api={construct=widget,need=assert,Theme=theme,theme={assets={}},caption=function(_,text) local w=widget();w.text=text;return w end,
    setText=function(w,text) w.text=text end,describe=noop,actions=noop,status=noop,log=noop}
api.button=function(tree,text) local b=widget();local l=api.caption(tree,text);b:SetContent(l);return b,l end
local choices={parse=function() return items end}
local controls={build=function(tree,providers,a)
    local ui={root=widget(),panels={{rows={},headings={},scroll=widget()}},model={items=items,pending={0,0,0,1,49,1},committed={0,0,0,1,49,1}}}
    function ui.model:visibility() return {true,true,true,true,true,self.pending[1]==1} end
    function ui.root:SetActiveWidgetIndex() self.readyEvents=(self.readyEvents or 0)+1 end
    function ui.model:set(i,v) self.pending[i]=v end
    function ui.model:change(i) self.pending[i]=1-self.pending[i] end
    function ui:prepare()
        local p=self.panels[1];if p.built then return end
        for i,s in ipairs(items) do
            local heading=a.caption(tree,s.group);p.scroll:AddChild(heading)
            p.headings[i]={widget=heading,first=i,last=i,visible=true}
            local b,l=a.button(tree,s.label);local box=widget();box:SetContent(b)
            local bg=widget();local overlay=widget();overlay:AddChild(bg);overlay:AddChild(box)
            local parts={}
            for n=1,3 do local b2=a.button(tree,'');local size=widget();size:SetContent(b2);overlay:AddChild(size);parts[n]={widget=b2} end
            local wrapper=widget();wrapper:SetContent(overlay);p.scroll:AddChild(wrapper)
            p.rows[i]={widget=b,background=bg,parts=parts,wrapper=wrapper,nav=widget(),visible=true}
        end
        p.built=true
    end
    function ui:show(i) self.active=i;self:prepare(i);self:refresh() end
    function ui:refresh()
        local visible=self.model:visibility()
        for i,row in ipairs(self.panels[self.active].rows) do row.visible=visible[i] end
    end
    function ui:tick() self.ticks=(self.ticks or 0)+1;return false end
    function ui:clearPresses() end
    function ui:isPressed() return false end
    function ui:select(i) self.current=i end
    return ui
end}
assert(M.install(choices,controls));assert(not M.install(choices,controls))
local ui=controls.build(widget(),{{choices=items}},api)
ui.ammHeaderHost=widget()
ui:show(1)
local row=ui.panels[1].rows[1]
assert(#row.ammTabs==2 and row.ammLabel.Font.Size==16)
assert(row.ammTabs[1].selected and not row.ammTabs[2].selected)
assert(ui.panels[1].rows[5].ammModeState.text=='AMM_MODE\nfixed')
assert(ui.panels[1].rows[2].ammLabel.text=='Slot 5')
local scroll=ui.panels[1].scroll
local function position(target)
    for n,child in ipairs(scroll.children) do if child==target then return n end end
end
local function textCount(text)
    local count=0;for _,child in ipairs(scroll.children) do if child.text==text then count=count+1 end end;return count
end
assert(textCount('Interaction: Independent')==1 and textCount('Interaction: Selective')==1,'Each parent heading renders once')
local independent
for _,child in ipairs(scroll.children) do if child.text=='Interaction: Independent' then independent=child end end
assert(position(independent)<position(ui.panels[1].headings[3].widget),'Parent must precede its subgroup headings')
assert(position(ui.panels[1].headings[3].widget)<position(ui.panels[1].headings[2].widget),'Primary category must precede secondary')
local count=scroll:GetChildrenCount()
row.ammTabs[2].widget.clicked=true
ui:tick({},function(w) local clicked=w.clicked;w.clicked=false;return clicked,false,false end,false)
assert(ui.model.pending[1]==1 and row.ammTabs[2].selected)
assert(ui.panels[1].rows[5].ammModeState.text=='AMM_MODE\neditable')
ui.panels[1].rows[6].wrapper:SetVisibility(1);ui:refresh()
assert(ui.panels[1].rows[5].ammModeState.text=='AMM_MODE\neditable','Backing wrapper collapse must not determine logical editability')
assert(ui.panels[1].rows[2].ammLabel.text=='Slot 1')
assert(position(independent)<position(ui.panels[1].headings[2].widget))
assert(position(ui.panels[1].headings[2].widget)<position(ui.panels[1].headings[3].widget))
assert(ui.root.readyEvents==1,'Reordering must notify existing decorators that row paths changed')
ui:refresh();ui:prepare(1);assert(scroll:GetChildrenCount()==count,'No duplicate widgets on reuse')
assert(textCount('Interaction: Independent')==1 and textCount('Interaction: Selective')==1,'Reuse must not duplicate parent headings')
assert(ui.root.readyEvents==1,'Unchanged refresh must not repeat page events')
local header=ui.panels[1].rows[4]
assert(header.ammHeader and header.wrapper:GetParent()==ui.ammHeaderHost)
assert(header.ammPlaceholder.visible==1 and header.ammLabel.Font.Size==22)
ui.model:set(1,0);ui:refresh()
assert(ui.panels[1].rows[5].ammModeState.text=='AMM_MODE\nfixed' and ui.model.pending[6]==1,'Hidden mode preserves saved Hold')
assert(ui.root.readyEvents==2,'Visibility and ordering changes must coalesce into one page-ready event')
ui.model.visibilityOverride=true
function ui.model:visibility() return {true,true,true,true,true,self.visibilityOverride} end
ui:refresh()
assert(ui.root.readyEvents==3,'Visibility-only changes must notify decorators after DMM refresh')
ui:refresh();assert(ui.root.readyEvents==3,'Stable visibility must not repeat page-ready events')
ui.active=nil;local calls=0
ui:tick({},function() calls=calls+1 end,false);assert(calls==0,'Closed menus never inspect tabs')
print('PASS nested headings, tab clicks, selected state, font levels, dynamic labels/order, page reuse and closed-menu inactivity')
