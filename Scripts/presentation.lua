-- Runs in DMM's Lua state. Uses its existing menu tick and model, never a timer.
local M={version=1}
local function trim(s) return (s or ''):match('^%s*(.-)%s*$') end
local function identityText(value)
    return tostring(value):gsub('%%','%%25'):gsub('\n','%%0A'):gsub('\r','%%0D')
end
local styles={
    [1]={22,'title'},[2]={16,'muted'},[3]={15,'muted'},
    [4]={14,'body'},[5]={12,'muted'},[6]={11,'muted'},
}
function M.parse(content,items)
    local sections,current={},nil
    for line in (content..'\n'):gmatch('([^\n]*)\n') do
        local header=trim(line):match('^%[([^%]]+)%]$')
        if header then current={name=header};sections[#sections+1]=current
        elseif current and not trim(line):match('^[;#]') then
            local key,value=line:match('^%s*([^=]+)=(.*)$')
            if key then current[trim(key)]=trim(value) end
        end
    end
    local byId,groups,parents,seen,count={},{},{},{},0
    -- Read legacy names only for migration; canonical fields always win.
    for _,r in ipairs(sections) do
        for _,suffix in ipairs({'Help','LabelWhen','Labels','OrderWhen','Orders'}) do
            if r['Deco'..suffix]~=nil then r['Decoration'..suffix]=r['Deco'..suffix] end
        end
    end
    for _,s in ipairs(items) do byId[s.id]=s end
    local function level(raw,canonical)
        if canonical~=nil then
            return assert(tonumber(canonical:match('^[0-6]$')),'DecoLevel must be an integer from 0 through 6')
        end
        if not raw then return nil end
        return assert(tonumber(raw:match('^Level([0-6])$')),'DecorationFont must be Level0 through Level6')
    end
    local function labelRule(r)
        if not r.DecorationLabelWhen and not r.DecorationLabels then return nil end
        local source=assert(byId[r.DecorationLabelWhen],'unknown DecorationLabelWhen')
        assert(source.kind~='slider','DecorationLabelWhen requires a picker or toggle')
        local result={source=source,values={}}
        for entry in ((r.DecorationLabels or '')..';'):gmatch('(.-);') do
            local value,label=entry:match('^%s*([^:]+):(.+)$')
            value=tonumber(value)
            assert(value and label and not result.values[value],'invalid DecorationLabels')
            local valid=false
            for _,v in ipairs(source.values) do if v==value then valid=true end end
            assert(valid,'DecorationLabels value outside source choices')
            result.values[value]=trim(label)
        end
        return result
    end
    for _,r in ipairs(sections) do
        local group=r.name:match('^Category%.(.+)$')
        if group then
            local order=labelRule({DecorationLabelWhen=r.DecorationOrderWhen,DecorationLabels=r.DecorationOrders})
            if order then
                for value,rank in pairs(order.values) do
                    rank=tonumber(rank)
                    assert(rank and rank==rank and math.abs(rank)<=1000000,'invalid DecorationOrders rank')
                    order.values[value]=rank
                end
            end
            local parent
            if r.DecoParent~=nil then
                local label=trim(r.DecoParent)
                assert(label~='','DecoParent requires a non-empty label')
                local font=level(nil,r.DecoParentLevel) or 2
                parent=parents[label]
                if parent then assert(parent.font==font,'categories sharing DecoParent must use the same DecoParentLevel')
                else parent={key=label,label=label,font=font};parents[label]=parent end
            elseif r.DecoParentLevel~=nil then error('DecoParentLevel requires DecoParent') end
            groups[group]={font=level(r.DecorationFont,r.DecoLevel~=nil and r.DecoLevel or r.DecoFont),help=r.DecorationHelp,labelRule=labelRule(r),order=order,parent=parent}
        end
        if r.name=='Setting' or r.name:match('^Setting%.') then
            count=count+1
            local id=r.Id or 'setting_'..count
            local s=byId[id]
            if s and not seen[id] then
                seen[id]=true
                s.mmdFont=level(r.DecorationFont,r.DecoLevel~=nil and r.DecoLevel or r.DecoFont)
                if r.DecoMode~=nil then
                    assert(r.DecoMode=='Tap' or r.DecoMode=='Hold','DecoMode must be Tap or Hold')
                    assert((r.DecoType or r.Decoration)=='keybind' and s.kind=='slider','DecoMode requires a keybind setting')
                    s.mmdFixedMode=r.DecoMode
                    s.mmdPairId=r.Pair or (id..'Mode')
                end
                s.mmdLabelRule=labelRule(r)
                s.mmdTabs,s.mmdHeader=nil,nil
                local hasLevel=r.DecoLevel~=nil or r.DecoFont~=nil or r.DecorationFont~=nil
                local decoration=r.Decoration
                if r.DecoType~=nil then
                    assert(r.DecoType=='tab' or r.DecoType=='keybind','DecoType must be tab or keybind')
                    decoration=r.DecoType=='tab' and 'tabs' or 'keybind'
                end
                if (hasLevel or r.DecoHeader~=nil) and decoration=='header' then decoration=nil end
                s.mmdKeybind=decoration=='keybind'
                if decoration=='tabs' then
                    assert(s.kind=='picker','DecoType=tab requires a picker')
                    assert(#s.values<=8,'DecoType=tab supports at most eight choices')
                    s.mmdTabs=true
                elseif decoration=='header' then
                    assert(s.kind=='toggle','Decoration=header requires a toggle')
                    s.mmdHeader=true
                end
                if r.DecoHeader~=nil and not hasLevel then
                    assert(r.DecoHeader=='0' or r.DecoHeader=='1','DecoHeader must be 0 or 1')
                    assert(r.DecoHeader=='0' or s.kind=='toggle','DecoHeader=1 requires a toggle')
                    s.mmdHeader=r.DecoHeader=='1'
                end
                if hasLevel then s.mmdHeader=s.mmdFont==1 end
            end
        end
    end
    local headers=0
    for _,s in ipairs(items) do
        s.mmdGroup=groups[s.group]
        if s.mmdFixedMode then
            local pair=byId[s.mmdPairId]
            if pair and pair.mmdKeybind then
                assert(pair.kind=='picker','DecoMode paired setting must be a picker')
                for i,candidate in ipairs(items) do if candidate==pair then s.mmdPairIndex=i;break end end
            end
        end
        if s.mmdHeader then headers=headers+1 end
    end
    assert(headers<=1,'only one level-one setting per provider')
    return items
end
function M.style(label,level,api)
    local style=styles[level]
    if not style then return end
    api.Theme.font(label,api.theme,style[1])
    api.Theme.textColor(label,style[2])
    if level==5 then label:SetRenderOpacity(0.85) end
end
function M.install(choices,controls,pages)
    if controls.mmdPresentationVersion then return false end
    local parse,build=choices.parse,controls.build
    choices.parse=function(content) return M.parse(content,parse(content)) end
    controls.build=function(tree,providers,api)
        local adapted,labels,helpWidgets={},{},{}
        local constructing,pendingHelp
        for k,v in pairs(api) do adapted[k]=v end
        adapted.caption=function(owner,text)
            local label=api.caption(owner,text)
            if constructing then
                for _,s in ipairs(providers[constructing].choices or {}) do
                    if text==s.group and s.mmdGroup and s.mmdGroup.help then
                        pendingHelp={heading=label,text=s.mmdGroup.help};break
                    end
                end
            end
            return label
        end
        adapted.button=function(...)
            if pendingHelp then
                local help=api.caption(tree,pendingHelp.text);help:SetAutoWrapText(true)
                M.style(help,5,api)
                local slot=api.need(pendingHelp.heading:GetParent():AddChild(help),'MMD group help')
                slot:SetPadding({Left=20,Top=0,Right=20,Bottom=8})
                helpWidgets[pendingHelp.heading]=help;pendingHelp=nil
            end
            local button,label=api.button(...);labels[button]=label;return button,label
        end
        local ui=build(tree,providers,adapted)
        local prepare,show,refresh,tick,clearPresses,isPressed=ui.prepare,ui.show,ui.refresh,ui.tick,ui.clearPresses,ui.isPressed
        local function new(kind) return api.construct('/Script/UMG.'..kind,tree) end
        local function add(parent,child) return api.need(parent:AddChild(child),'MMD presentation child') end
        local function sized(child,width)
            local box=new('SizeBox');box:SetWidthOverride(width);box:SetHeightOverride(40)
            local slot=api.need(box:SetContent(child),'MMD presentation size')
            slot:SetHorizontalAlignment(0);slot:SetVerticalAlignment(0)
            return box
        end
        local function decorate(index)
            local panel=ui.panels[index]
            if panel.mmdPresented then return end
            for i,row in ipairs(panel.rows) do
                local setting=providers[index].choices[i]
                row.mmdLabel=labels[row.widget]
                local identity=api.caption(tree,'MMD_SETTING_INDEX\n'..i..'\n'
                    ..identityText(providers[index].id)..'\n'..identityText(setting.id))
                identity:SetVisibility(1)
                add(row.wrapper:GetContent(),identity)
                if setting.mmdFixedMode then
                    row.mmdModeState=api.caption(tree,'MMD_MODE\nfixed')
                    row.mmdModeState:SetVisibility(1)
                    add(row.wrapper:GetContent(),row.mmdModeState)
                end
                M.style(row.mmdLabel,setting.mmdFont,api)
                if setting.mmdHeader and ui.mmdHeaderHost then
                    assert(not panel.mmdHeader,'only one level-one setting per provider')
                    local placeholder=new('SizeBox')
                    local path=assert(row.wrapper:GetFullName():match('^%S+ (.+)$'))
                    local marker=api.caption(tree,'MMD_HEADER_ROW\n'..path)
                    api.need(placeholder:SetContent(marker),'MMD header identity')
                    placeholder:SetVisibility(1)
                    local children={}
                    for n=0,panel.scroll:GetChildrenCount()-1 do
                        local child=panel.scroll:GetChildAt(n)
                        local padding=child.Slot.Padding
                        children[#children+1]={widget=child:GetFullName()==row.wrapper:GetFullName() and placeholder or child,
                            padding={Left=padding.Left,Top=padding.Top,Right=padding.Right,Bottom=padding.Bottom}}
                    end
                    panel.scroll:ClearChildren()
                    for _,child in ipairs(children) do add(panel.scroll,child.widget):SetPadding(child.padding) end
                    add(ui.mmdHeaderHost,row.wrapper)
                    row.mmdHeader=true;row.mmdPlaceholder=placeholder;panel.mmdHeader=row
                end
                if setting.mmdTabs then
                    -- Keep DMM's original controls alive for navigation, dirty
                    -- notifications and reconstruction. No stock reparenting.
                    local tabs=new('HorizontalBox')
                    row.mmdTabs={}
                    local count=#setting.values
                    local width=math.min(110,384/count)
                    for n,value in ipairs(setting.values) do
                        local button,label=api.button(tree,setting.labels[n]);button.IsFocusable=false
                        label:SetJustification(1);label:SetTextOverflowPolicy(1)
                        add(tabs,sized(button,width))
                        row.mmdTabs[n]={widget=button,label=label,value=value,pressed=false,pointer=false}
                    end
                    local overlay=row.background:GetParent()
                    local slot=add(overlay,tabs);slot:SetHorizontalAlignment(3);slot:SetVerticalAlignment(2)
                    row.widget:GetParent():SetWidthOverride(584-width*count)
                    for _,part in ipairs(row.parts) do part.widget:GetParent():SetVisibility(1) end
                end
            end
            local parentWidgets={}
            for _,heading in ipairs(panel.headings) do
                local setting=providers[index].choices[heading.first]
                if setting.mmdGroup then
                    M.style(heading.widget,setting.mmdGroup.font,api)
                    local parent=setting.mmdGroup.parent
                    if parent then
                        heading.mmdParent=parent
                        if not parentWidgets[parent.key] then
                            local label=api.caption(tree,parent.label);M.style(label,parent.font,api)
                            local slot=add(panel.scroll,label)
                            slot:SetPadding({Left=0,Top=18,Right=0,Bottom=6})
                            parentWidgets[parent.key]={widget=label,parent=parent}
                        end
                    end
                end
            end
            -- Capture existing scroll children only once, after construction.
            -- Ordering moves whole category blocks; rows retain their children.
            local ordered=false
            for _,s in ipairs(providers[index].choices) do if s.mmdGroup and s.mmdGroup.order then ordered=true end end
            if ordered or next(parentWidgets) then
                panel.mmdBlocks={}
                local known={}
                local function capture(block,child)
                    local p=child.Slot.Padding
                    block.children[#block.children+1]={widget=child,padding={Left=p.Left,Top=p.Top,Right=p.Right,Bottom=p.Bottom}}
                    known[child]=true
                end
                for _,heading in ipairs(panel.headings) do
                    local block={heading=heading,parent=heading.mmdParent,children={}};panel.mmdBlocks[#panel.mmdBlocks+1]=block
                    capture(block,heading.widget)
                    if helpWidgets[heading.widget] then capture(block,helpWidgets[heading.widget]) end
                    for i=heading.first,heading.last do capture(block,panel.rows[i].mmdPlaceholder or panel.rows[i].wrapper) end
                end
                local extra={children={}}
                -- Parent headings were added only to obtain real UMG widgets.
                -- They are rebuilt from mmdLayout and must not become extras.
                for _,entry in pairs(parentWidgets) do known[entry.widget]=true end
                for n=0,panel.scroll:GetChildrenCount()-1 do
                    local child=panel.scroll:GetChildAt(n)
                    if not known[child] then capture(extra,child) end
                end
                panel.mmdLayout={}
                local entriesByParent={}
                local unparented
                for _,block in ipairs(panel.mmdBlocks) do
                    local entry
                    if block.parent then
                        entry=entriesByParent[block.parent.key]
                        if not entry then
                            entry={parent=block.parent,parentWidget=parentWidgets[block.parent.key].widget,blocks={}}
                            entriesByParent[block.parent.key]=entry;panel.mmdLayout[#panel.mmdLayout+1]=entry
                        end
                        unparented=nil
                    else
                        if not unparented then unparented={blocks={}};panel.mmdLayout[#panel.mmdLayout+1]=unparented end
                        entry=unparented
                    end
                    entry.blocks[#entry.blocks+1]=block
                end
                if #extra.children>0 then panel.mmdLayout[#panel.mmdLayout+1]={blocks={extra},extra=true} end
                panel.mmdParentWidgets=parentWidgets
            end
            panel.mmdPresented=true
        end
        function ui:prepare(index)
            constructing=index;prepare(self,index);constructing=nil;decorate(index)
        end
        function ui:show(index) self:prepare(index);return show(self,index) end
        local function dynamic(rule,model,fallback)
            if not rule then return fallback end
            for i,s in ipairs(model.items) do
                if s.id==rule.source.id then return rule.values[model.pending[i]] or fallback end
            end
            return fallback
        end
        function ui:refresh(...)
            if self.active then decorate(self.active) end
            local result=refresh(self,...)
            local pageReady=false
            local logicalVisibility
            for i,row in ipairs(self.panels[self.active].rows) do
                local setting=self.model.items[i]
                if row.mmdModeState then
                    logicalVisibility=logicalVisibility or self.model:visibility()
                    local target=setting.mmdPairIndex
                    local editable=target and logicalVisibility[target]==true or false
                    if row.mmdModeEditable~=editable then
                        api.setText(row.mmdModeState,'MMD_MODE\n'..(editable and 'editable' or 'fixed'))
                        row.mmdModeEditable=editable
                    end
                end
                if row.mmdHeader then row.wrapper:SetVisibility(row.visible and 0 or 1) end
                if setting.mmdLabelRule then
                    local text=dynamic(setting.mmdLabelRule,self.model,setting.label)
                    if text~=row.mmdLabelText then api.setText(row.mmdLabel,text);row.mmdLabelText=text end
                end
                for _,tab in ipairs(row.mmdTabs or {}) do
                    local mapping=self.model.items[i].mmdMapping
                    local enabled=not self.model.error and (not mapping or tab.value~=mapping.custom)
                    local selected=self.model.pending[i]==tab.value
                    if tab.selected~=selected or tab.enabled~=enabled then
                        api.Theme.textColor(tab.label,selected and 'menuActive' or 'body')
                        tab.widget:SetIsEnabled(enabled)
                        tab.widget:SetRenderOpacity((enabled or selected) and 1 or 0.45)
                        tab.selected,tab.enabled=selected,enabled
                    end
                    tab.pressed,tab.pointer=false,false
                end
            end
            if self.mmdHeaderTitle then self.mmdHeaderTitle:SetVisibility(self.panels[self.active].mmdHeader and 1 or 4) end
            for index,panel in ipairs(self.panels) do
                if index~=self.active and panel.mmdHeader then panel.mmdHeader.wrapper:SetVisibility(1) end
            end
            for _,heading in ipairs(self.panels[self.active].headings) do
                local setting=self.model.items[heading.first]
                local shown=false
                for i=heading.first,heading.last do
                    local row=self.panels[self.active].rows[i]
                    if row.visible and not row.mmdHeader then shown=true;break end
                end
                if not shown and heading.visible then heading.widget:SetVisibility(1);heading.visible=false end
                local group=setting.mmdGroup
                if group and group.labelRule then
                    local text=dynamic(group.labelRule,self.model,setting.group)
                    if heading.mmdText~=text then api.setText(heading.widget,text);heading.mmdText=text end
                end
                local help=helpWidgets[heading.widget]
                if help and heading.mmdHelpVisible~=heading.visible then
                    help:SetVisibility(heading.visible and 4 or 1);heading.mmdHelpVisible=heading.visible
                end
            end
            local panel=self.panels[self.active]
            local visible={}
            for i,row in ipairs(panel.rows) do visible[i]=row.visible and '1' or '0' end
            local visibilitySignature=table.concat(visible)
            if panel.mmdVisibility and panel.mmdVisibility~=visibilitySignature then pageReady=true end
            panel.mmdVisibility=visibilitySignature
            if panel.mmdBlocks then
                local signatureParts,orderedFlat={},{}
                local function reorder(blocks)
                    local slots,candidates,result={},{},{}
                    for n,block in ipairs(blocks) do
                        result[n]=block
                        local s=block.heading and self.model.items[block.heading.first]
                        local rule=s and s.mmdGroup and s.mmdGroup.order
                        local rank=dynamic(rule,self.model,n)
                        signatureParts[#signatureParts+1]=(block.heading and tostring(block.heading.first) or 'extra')..'='..tostring(rank)
                        if rule then
                            slots[#slots+1]=n;candidates[#candidates+1]={block=block,rank=rank,original=n}
                        end
                    end
                    table.sort(candidates,function(a,b) return a.rank==b.rank and a.original<b.original or a.rank<b.rank end)
                    for n,position in ipairs(slots) do result[position]=candidates[n].block end
                    return result
                end
                for _,entry in ipairs(panel.mmdLayout) do
                    signatureParts[#signatureParts+1]='parent='..(entry.parent and entry.parent.key or '')
                    entry.orderedBlocks=reorder(entry.blocks)
                    for _,block in ipairs(entry.orderedBlocks) do
                        if block.heading then orderedFlat[#orderedFlat+1]=block end
                    end
                end
                local signature=table.concat(signatureParts,':')
                if signature~=panel.mmdOrder or not panel.mmdLayoutBuilt then
                    panel.scroll:ClearChildren()
                    for _,entry in ipairs(panel.mmdLayout) do
                        if entry.parentWidget then
                            add(panel.scroll,entry.parentWidget):SetPadding({Left=0,Top=18,Right=0,Bottom=6})
                        end
                        for _,block in ipairs(entry.orderedBlocks) do
                            for _,child in ipairs(block.children) do add(panel.scroll,child.widget):SetPadding(child.padding) end
                        end
                    end
                    if panel.mmdLayoutBuilt then pageReady=true end
                    panel.mmdOrder=signature
                    panel.mmdLayoutBuilt=true
                end
                panel.mmdOrderedBlocks=orderedFlat
                for _,entry in ipairs(panel.mmdLayout) do
                    if entry.parentWidget then
                        local shown=false
                        for _,block in ipairs(entry.blocks) do
                            if block.heading and block.heading.visible then shown=true;break end
                        end
                        if entry.parentVisible~=shown then
                            entry.parentWidget:SetVisibility(shown and 4 or 1);entry.parentVisible=shown
                        end
                    end
                end
                if self.visibleRows then
                    local visible={}
                    -- Header controls precede scroll content for navigation.
                    for i,row in ipairs(panel.rows) do if row.mmdHeader and row.visible then visible[#visible+1]=i end end
                    for _,block in ipairs(panel.mmdOrderedBlocks or panel.mmdBlocks) do
                        if block.heading then
                            for i=block.heading.first,block.heading.last do
                                if panel.rows[i].visible and not panel.rows[i].mmdHeader then visible[#visible+1]=i end
                            end
                        end
                    end
                    self.visibleRows=visible;self:wireNavigation(self.footer)
                end
            end
            if pageReady then
                -- Visibility changes do not reconstruct DMM's page or change its
                -- active index, but they can expose a row after MMD's initial pass.
                -- Reuse the existing deferred page-ready seam once per refresh.
                self.root:SetActiveWidgetIndex(self.active-1)
            end
            return result
        end
        function ui:tick(queued,released,controller)
            if self.active and not self.model.error then
                for i,row in ipairs(self.panels[self.active].rows) do
                    if row.visible then
                        for _,tab in ipairs(row.mmdTabs or {}) do
                            local clicked
                            clicked,tab.pressed,tab.pointer=released(tab.widget,tab.pressed,tab.pointer,tab.widget:IsHovered())
                            if clicked and tab.enabled then
                                self:select(i,false);self.model:set(i,tab.value);self:refresh()
                                if api.feedback then api.feedback('Change') end
                                return tick(self,queued,released,controller)
                            end
                        end
                    end
                end
            end
            return tick(self,queued,released,controller)
        end
        function ui:clearPresses()
            clearPresses(self)
            if self.active then
                for _,row in ipairs(self.panels[self.active].rows) do
                    for _,tab in ipairs(row.mmdTabs or {}) do tab.pressed,tab.pointer=false,false end
                end
            end
        end
        function ui:isPressed()
            if isPressed(self) then return true end
            if self.active then
                for _,row in ipairs(self.panels[self.active].rows) do
                    if row.visible then
                        for _,tab in ipairs(row.mmdTabs or {}) do if tab.widget:IsPressed() then return true end end
                    end
                end
            end
            return false
        end
        return ui
    end
    controls.mmdPresentationVersion=M.version
    if pages then
        local buildPages=pages.build
        pages.build=function(tree,providers,status,api)
            local adapted={};for k,v in pairs(api) do adapted[k]=v end
            local title,host
            adapted.caption=function(owner,text)
                local label=api.caption(owner,text)
                if not title and text==(api.t and api.t('Mod Settings') or 'Mod Settings') then title=label end
                return label
            end
            adapted.construct=function(...)
                if title and not host then
                    local parent=title:GetParent()
                    if parent and parent:IsValid() then
                        -- At this point the title is the area's only child;
                        -- compose its header before DMM constructs any rows.
                        local line=api.construct('/Script/UMG.HorizontalBox',tree)
                        host=api.construct('/Script/UMG.HorizontalBox',tree)
                        assert(parent:RemoveChild(title),'MMD header title detach')
                        api.need(parent:AddChild(line),'MMD header')
                    local slot=api.need(line:AddChild(title),'MMD header title')
                        slot:SetSize({SizeRule=1,Value=1});slot:SetVerticalAlignment(2)
                        api.need(line:AddChild(host),'MMD header controls')
                        M.style(title,1,api)
                    end
                end
                return api.construct(...)
            end
            local page=buildPages(tree,providers,status,adapted)
            page.controls.mmdHeaderHost=host
            page.controls.mmdHeaderTitle=title
            return page
        end
    end
    return true
end
return M
