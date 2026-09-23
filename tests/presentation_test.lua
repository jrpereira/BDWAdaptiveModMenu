package.path='Scripts/?.lua;'..package.path
local M=require('presentation')
local items={
    {id='Primary',kind='picker',group='General',label='Primary',values={0,1},labels={'Consumables','Abilities'}},
    {id='Ability',kind='picker',group='Abilities',label='Ability',values={0,1},labels={'Tap','Hold'}},
    {id='Consumable',kind='picker',group='Consumables',label='Consumable',values={0,1},labels={'Tap','Hold'}},
    {id='Enabled',kind='toggle',group='General',label='Enabled',values={0,1},labels={'Off','On'}},
    {id='Key',kind='slider',group='Keys',label='Key'},
    {id='KeyMode',kind='picker',group='Keys',label='Mode',values={0,3,-1},labels={'Tap','Hold','Default'}},
}
local schema=[[
[Setting.Primary]
Id=Primary
ammType=tab
ammLevel=2
ammTabsWidth=440
[Setting.Ability]
Id=Ability
ammLabelWhen=Primary
ammLabels=0:Slot 5;1:Slot 1
[Category.Abilities]
ammHelp=Ability explanation
ammHeading=0
ammParent=Interaction: Independent
ammParentLevel=2
ammLevel=3
ammLabelWhen=Primary
ammLabels=0:Secondary Wheel;1:Primary Wheel
ammOrderWhen=Primary
ammOrders=0:20;1:10
[Category.Consumables]
ammParent=Interaction: Independent
ammParentLevel=2
ammLabelWhen=Primary
ammLabels=0:Primary Wheel;1:Secondary Wheel
ammOrderWhen=Primary
ammOrders=0:10;1:20
[Category.Keys]
ammParent=Interaction: Selective
ammParentLevel=2
ammLevel=3
[Setting.Enabled]
Id=Enabled
ammLevel=1
[Setting.Key]
Id=Key
ammType=keybind
[Setting.KeyMode]
Id=KeyMode
ammType=tab
Pair=Key
]]
M.parse(schema,items)
assert(items[1].ammTabs and items[1].ammFont==2 and items[1].ammTabsWidth==440)
assert(items[2].ammLabelRule.values[0]=='Slot 5')
assert(items[2].ammGroup.parent==items[3].ammGroup.parent,'Shared parent labels must share one descriptor')
assert(items[2].ammGroup.parent.label=='Interaction: Independent' and items[2].ammGroup.parent.font==2)
assert(not items[2].ammGroup.heading and items[3].ammGroup.heading)
assert(items[5].ammGroup.parent.label=='Interaction: Selective')
M.parse(schema:gsub('ammType=tab','DecoType=tab'):gsub('ammLevel=2','DecoLevel=2')
    :gsub('ammTabsWidth=440','DecoTabsWidth=440'):gsub('Pair=Key\n',''),items)
assert(not items[1].ammTabs and items[1].ammFont==nil,'noncanonical metadata must be ignored')
assert(not pcall(M.parse,schema:gsub('ammType=tab','ammType=tabs'),items))
assert(not pcall(M.parse,schema:gsub('ammTabsWidth=440','ammTabsWidth=441'),items))
assert(not pcall(M.parse,schema:gsub('ammType=tab','ammType=keybind'),items))
assert(not pcall(M.parse,schema:gsub('ammLevel=1','ammLevel=9'),items))
M.parse(schema,items)
assert(not pcall(M.parse,schema:gsub('ammLevel=2','ammLevel=9'),items))
assert(not pcall(M.parse,schema:gsub('ammHeading=0','ammHeading=true'),items))
assert(not pcall(M.parse,schema:gsub('ammLabelWhen=Primary','ammLabelWhen=Missing'),items))
local parentItems={{id='One',kind='toggle',group='One',values={0,1}},{id='Two',kind='toggle',group='Two',values={0,1}}}
assert(not pcall(M.parse,'[Category.One]\nammParent=\n',parentItems))
assert(not pcall(M.parse,'[Category.One]\nammParentLevel=2\n',parentItems))
assert(not pcall(M.parse,'[Category.One]\nammParent=Shared\nammParentLevel=2\n[Category.Two]\nammParent=Shared\nammParentLevel=3\n',parentItems))
M.parse(schema,items)
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
    function w:SetWidthOverride(v) self.WidthOverride=v end
    function w:SetBrushColor(v) self.BrushColor=v end
    function w:SetRenderTranslation(v) self.RenderTranslation=v end
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
local choices={parse=function() return items end,format=function(setting,value)
    for i,candidate in ipairs(setting.values or {}) do
        if candidate==value then return setting.labels[i] end
    end
    return tostring(value)
end}
local pages={build=function(tree,providers,status,a)
    local filterButton,filterLabel=a.button(tree,'Compatible Mods')
    local browserList=widget()
    local filterWrapper=widget();filterWrapper:SetContent(filterButton);browserList:AddChild(filterWrapper)
    local parent=widget()
    local title=a.caption(tree,'Mod Settings');parent:AddChild(title)
    local divider=widget();parent:AddChild(divider)
    parent:AddChild(widget())
    -- UE4SS may return another Lua wrapper for the same UMG widget.
    local titleWrapper={Slot=title.Slot,GetFullName=function() return title:GetFullName() end}
    local getChildAt,addChild=parent.GetChildAt,parent.AddChild
    function parent:GetChildAt(n)
        local child=getChildAt(self,n)
        return child==title and titleWrapper or child
    end
    function parent:AddChild(child)
        return addChild(self,child==titleWrapper and title or child)
    end
    local allRows={}
    for index,provider in ipairs(providers) do
        local button,label=a.button(tree,provider.name)
        label.Slot:SetPadding({Left=20,Top=4,Right=12,Bottom=4})
        allRows[#allRows+1]={widget=button,providerIndex=index}
    end
    local page={filterButton=filterButton,filterLabel=filterLabel,browserList=browserList,allRows=allRows,
        controls={},modTitle=title,ammTestControlArea=parent,ammTestDivider=divider}
    function page:refresh(compatibleOnly)
        a.setText(self.filterLabel,compatibleOnly and 'Compatible Mods' or 'All Mods')
    end
    return page
end}
local controls={build=function(tree,providers,a)
    local ui={root=widget(),panels={{rows={},headings={},scroll=widget()}},model={items=items,pending={0,0,0,1,49,-1},committed={0,0,0,1,49,-1}}}
    ui.ammTestSetText=a.setText
    function ui.model:visibility() return {true,true,true,true,self.pending[1]==1,true} end
    function ui.root:SetActiveWidgetIndex() self.readyEvents=(self.readyEvents or 0)+1 end
    function ui.model:set(i,v) self.pending[i]=v end
    function ui.model:change(i) self.pending[i]=1-self.pending[i] end
    function ui:prepare()
        local p=self.panels[1];if p.built then return end
        for i,s in ipairs(items) do
            local heading=a.caption(tree,s.group);p.scroll:AddChild(heading)
            p.headings[i]={widget=heading,first=i,last=i,visible=true}
            local b,l=a.button(tree,s.label);l.Slot:SetPadding({Left=20,Top=0,Right=8,Bottom=0})
            local box=widget();box:SetContent(b)
            local bg=widget();local overlay=widget();overlay:AddChild(bg);overlay:AddChild(box)
            local value=a.caption(tree,'');overlay:AddChild(value)
            local parts={}
            for n=1,3 do local b2=a.button(tree,'');local size=widget();size:SetContent(b2);overlay:AddChild(size);parts[n]={widget=b2} end
            local wrapper=widget();wrapper:SetContent(overlay);p.scroll:AddChild(wrapper)
            p.rows[i]={widget=b,value=value,background=bg,parts=parts,wrapper=wrapper,nav=widget(),visible=true}
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
assert(M.install(choices,controls,pages));assert(not M.install(choices,controls,pages))
local browserProviders={
    {name='Templates',choices=items},
    {name='Menu Controls',choices=items,ammBrowserLevel=4,ammBrowserIndent=20},
}
local page=pages.build(widget(),browserProviders,nil,api)
assert(#page.browserList.children==2 and page.browserList.children[2]:GetContent(),
    'Mod-browser title must have a themed divider immediately beneath it')
assert(page.filterLabel.Font.Size==page.controls.ammHeaderTitle.Font.Size and
    page.filterLabel.color==page.controls.ammHeaderTitle.color,'Compatible Mods must use the mod-title style')
assert(page.ammTestControlArea.children[1]==page.controls.ammHeaderHost
    and page.ammTestControlArea.children[2]==page.ammTestDivider
    and page.controls.ammHeaderHost.children[1]==page.modTitle
    and page.modTitle.visible==4,
    'Mod title must share the first row with the picker above the divider')
page:refresh(false)
assert(page.filterLabel.text=='All Mods' and page.filterLabel.Font.Size==22 and page.filterLabel.color=='title',
    'Filter text changes must retain the mod-title style')
local modLabel=page.allRows[1].widget:GetContent()
assert(modLabel.text=='Templates' and modLabel.Font.Size==16 and modLabel.color=='muted',
    'Mod-list labels must use level-two styling')
assert(page.filterLabel.Slot.Padding.Left==0 and modLabel.Slot.Padding.Left==0,
    'Regular Mod Menu entries must use normal left alignment')
local categoryLabel=page.allRows[2].widget:GetContent()
assert(categoryLabel.text=='Menu Controls' and categoryLabel.Font.Size==14 and categoryLabel.color=='body',
    'Category modules must accept level-four browser styling')
assert(categoryLabel.Slot.Padding.Left==20,
    'Category modules must accept a small browser indentation')
local ui=controls.build(widget(),{{id='UE4SSTemplatingEngine.module.ActionFandango',choices=items}},api)
ui.ammHeaderHost=widget()
ui:show(1)
local row=ui.panels[1].rows[1]
assert(#row.ammTabs==2 and row.ammLabel.Font.Size==16)
assert(row.ammTabs[1].label.Slot.HorizontalAlignment==0 and row.ammTabs[1].label.Slot.VerticalAlignment==2,
    'Tab labels must fill their allocated button slots for centered text justification')
assert(row.ammTabs[1].selected and not row.ammTabs[2].selected)
local keyRow,modeRow=ui.panels[1].rows[5],ui.panels[1].rows[6]
assert(modeRow.ammPairHost and modeRow.ammPairHostBox.visible==1 and keyRow.ammPairOwner==6,
    'The mode row must own the composite and hide its key host while the key is logically hidden')
assert(modeRow.ammTabsWidth==150,
    'Paired pickers must use the original 150-pixel mode column')
assert(#modeRow.ammTabs==2 and modeRow.ammTabs[1].toggleValues[1]==0
    and modeRow.ammTabs[1].toggleValues[2]==3 and modeRow.ammTabs[1].label.text=='Tap'
    and modeRow.ammTabs[2].selected,
    'Tap and Hold must share one control while Default remains separate')
assert(modeRow.ammTabs[1].background:GetParent().WidthOverride==75,
    'The shared Tap/Hold control must occupy half of the paired mode column')
local toggleBox=modeRow.ammTabs[1].background:GetParent()
local toggleContainer=toggleBox:GetParent()
assert(toggleBox.HeightOverride==modeRow.ammPairHostBox.HeightOverride
    and toggleContainer.RenderTranslation.X==-75
    and toggleContainer.RenderTranslation.X-toggleBox.WidthOverride
        -modeRow.ammPairHostBox.RenderTranslation.X==8,
    'The shared mode control must match key height and sit eight pixels to its right')
assert(modeRow.ammPairHostBox.RenderTranslation and modeRow.ammPairHostBox.RenderTranslation.X==-158,
    'All paired rows must keep the key control in the same fixed column')
assert(modeRow.ammDefaultBackground.RenderTranslation and modeRow.ammDefaultBackground.RenderTranslation.X==-262
    and modeRow.ammPairDisablesKey,
    'Default-capable pairs must render only their Default option in the reserved left column')
assert(modeRow.ammTabs[1].background and modeRow.ammTabs[1].background.BrushColor.A==0.18
    and modeRow.ammTabs[2].background.BrushColor.A==0.18,
    'The shared Tap/Hold button must match the Default background')
modeRow.ammTabs[1].widget.hovered=true
ui:tick({},function() return false,false,false end,false)
assert(modeRow.ammTabs[1].background.BrushColor.R==0.95
    and modeRow.ammTabs[1].background.BrushColor.A==0.22
    and modeRow.ammTabs[2].background.BrushColor.R==0.12,
    'The shared control must retain its hover glow')
modeRow.ammTabs[1].widget.hovered=false
ui:tick({},function() return false,false,false end,false)
assert(modeRow.ammTabs[1].background.BrushColor.A==0.18,
    'Individual paired-tab hover styling must clear on pointer exit')
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
assert(ui.panels[1].headings[2].widget.visible==1,'ammHeading=0 must collapse only the category heading')
assert(ui.panels[1].rows[2].visible and independent.visible==4,'Hidden subgroup heading must retain rows and visible parent')
local count=scroll:GetChildrenCount()
row.ammTabs[2].widget.clicked=true
ui:tick({},function(w) local clicked=w.clicked;w.clicked=false;return clicked,false,false end,false)
assert(ui.model.pending[1]==1 and row.ammTabs[2].selected)
assert(modeRow.ammPairHostBox.visible==0 and keyRow.wrapper.visible==1
    and modeRow.widget:GetParent().WidthOverride==330,
    'A visible paired key must render inside the mode row while its original row remains collapsed')
assert(modeRow.ammTabs[2].selected,
    'The mode owner must preserve the negative Default value')
modeRow.ammTabs[1].widget.clicked=true
ui:tick({},function(w) local clicked=w.clicked;w.clicked=false;return clicked,false,false end,false)
assert(ui.model.pending[6]==0 and modeRow.ammTabs[1].selected and modeRow.ammTabs[1].label.text=='Tap',
    'Clicking the shared mode control from Default must select Tap')
assert(modeRow.ammTabs[1].background.BrushColor.A==0.18,
    'Selecting Tap must keep the Default background opacity')
modeRow.ammTabs[1].widget.hovered=true
ui:tick({},function() return false,false,false end,false)
assert(modeRow.ammTabs[1].background.BrushColor.R==0.95
    and modeRow.ammTabs[1].background.BrushColor.A==0.22,
    'The active paired mode must match the key hover background')
modeRow.ammTabs[1].widget.hovered=false
ui:tick({},function() return false,false,false end,false)
modeRow.ammTabs[1].widget.clicked=true
ui:tick({},function(w) local clicked=w.clicked;w.clicked=false;return clicked,false,false end,false)
assert(ui.model.pending[6]==3 and modeRow.ammTabs[1].selected and modeRow.ammTabs[1].label.text=='Hold',
    'Clicking the same control must select and display the declared Hold value')
modeRow.ammTabs[1].widget.clicked=true
ui:tick({},function(w) local clicked=w.clicked;w.clicked=false;return clicked,false,false end,false)
assert(ui.model.pending[6]==0 and modeRow.ammTabs[1].label.text=='Tap',
    'Another click must return to Tap without creating another control')
modeRow.ammTabs[2].widget.clicked=true
ui:tick({},function(w) local clicked=w.clicked;w.clicked=false;return clicked,false,false end,false)
assert(ui.model.pending[6]==-1 and modeRow.ammTabs[2].selected and modeRow.ammTabs[1].label.text=='Tap',
    'Default must remain selectable without losing the shared control')
assert(modeRow.ammTabs[1].background.BrushColor.A==0.18,
    'Selecting Default again must retain the matching background')
modeRow.ammTabs[1].widget.clicked=true
ui:tick({},function(w) local clicked=w.clicked;w.clicked=false;return clicked,false,false end,false)
modeRow.ammTabs[1].widget.clicked=true
ui:tick({},function(w) local clicked=w.clicked;w.clicked=false;return clicked,false,false end,false)
assert(ui.model.pending[6]==3,'Repeated shared-mode clicks must still reach Hold')
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
assert(header.ammLabel.Slot.Padding.Left==0 and ui.panels[1].rows[1].ammLabel.Slot.Padding.Left==20,
    'Level-one setting labels must have no stock left indent')
ui.model.pending[4]=0
ui.ammTestSetText(header.value,'Off *')
assert(header.value.text=='Off','Dirty suffix must never flicker in the value text')
local signal
for _,child in ipairs(header.wrapper:GetContent().children) do
    if child.text and child.text:match('^AMM_VALUE_DIRTY_1\n') then signal=child end
end
assert(signal and signal.text=='AMM_VALUE_DIRTY_1\n1\nOff')
ui.model.committed[4]=0
ui.ammTestSetText(header.value,'Off')
assert(signal.text=='AMM_VALUE_DIRTY_1\n0\nOff',
    'Apply must signal clean state even when the displayed value text is unchanged')
ui.model:set(1,0);ui:refresh()
assert(modeRow.ammPairHostBox.visible==1 and ui.model.pending[6]==3,
    'Hiding the paired key must preserve the mode picker and its saved value')
assert(ui.root.readyEvents==2,'Visibility and ordering changes must coalesce into one page-ready event')
ui.model.visibilityOverride=true
function ui.model:visibility() return {true,true,true,true,self.visibilityOverride,true} end
ui:refresh()
assert(ui.root.readyEvents==3,'Visibility-only changes must notify decorators after DMM refresh')
ui:refresh();assert(ui.root.readyEvents==3,'Stable visibility must not repeat page-ready events')
ui.active=nil;local calls=0
ui:tick({},function() calls=calls+1 end,false);assert(calls==0,'Closed menus never inspect tabs')
items[6].values,items[6].labels={0,3},{'Tap','Hold'}
local twoMode=controls.build(widget(),{{choices=items}},api)
twoMode.model.pending[6],twoMode.model.committed[6]=0,0
twoMode:show(1)
local toggle=twoMode.panels[1].rows[6].ammTabs
assert(#toggle==1 and not twoMode.panels[1].rows[6].ammDefaultBackground
    and toggle[1].label.text=='Tap' and toggle[1].background:GetParent().WidthOverride==75
    and toggle[1].background:GetParent():GetParent().RenderTranslation.X==-75,
    'A paired mode without Default must render one full-width Tap/Hold control')
toggle[1].widget.clicked=true
twoMode:tick({},function(w) local clicked=w.clicked;w.clicked=false;return clicked,false,false end,false)
assert(twoMode.model.pending[6]==3 and toggle[1].label.text=='Hold',
    'The two-value pair must toggle to its declared Hold value')
items[1].group='Player';items[1].label='Quickslots'
local pickerHeaderSchema=schema:gsub('Id=Primary\nammType=tab\nammLevel=2',
    'Id=Primary\nammType=tab\nammLevel=1'):gsub('Id=Enabled\nammLevel=1',
    'Id=Enabled\nammLevel=2')
M.parse(pickerHeaderSchema,items)
local templatePage=controls.build(widget(),{{id='UE4SSTemplatingEngine',choices=items}},api)
templatePage.ammHeaderHost=page.controls.ammHeaderHost
templatePage.ammHeaderTitle=page.modTitle
templatePage:show(1)
assert(not templatePage.panels[1].rows[1].ammHeader
    and templatePage.panels[1].rows[1].wrapper:GetParent()==templatePage.panels[1].scroll
    and templatePage.panels[1].rows[1].ammLabel.visible~=1,
    'Template page must keep its level-one picker in the settings list')
local pickerHeader=controls.build(widget(),{{id='UE4SSTemplatingEngine.module.ActionFandango',choices=items}},api)
pickerHeader.ammHeaderHost=page.controls.ammHeaderHost
pickerHeader.ammHeaderTitle=page.modTitle
pickerHeader:show(1)
assert(pickerHeader.panels[1].rows[1].ammHeader
    and pickerHeader.panels[1].rows[1].ammLabel.Slot.Padding.Left==0
    and pickerHeader.panels[1].rows[1].ammLabel.visible==1
    and page.controls.ammHeaderHost.children[1]==pickerHeader.panels[1].rows[1].wrapper
    and page.controls.ammHeaderHost.children[2]==page.modTitle
    and pickerHeader.panels[1].rows[4].ammLabel.Slot.Padding.Left==20,
    'Level-one picker must share the title row above the divider without a second label')
print('PASS nested headings, tab clicks, selected state, font levels, dynamic labels/order, page reuse and closed-menu inactivity')
