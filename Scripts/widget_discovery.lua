local M={}
local function valid(o)
    if o==nil or o==false then return false end
    local ok,result=pcall(function() return o:IsValid() end); return ok and result==true
end
M.valid=valid
-- Engine UClasses/CDOs have engine lifetime; do not cache runtime widget wrappers.
local classCache={}
local function isA(widget,name)
    local class=classCache[name]
    if not valid(class) then
        class=StaticFindObject('/Script/UMG.'..name)
        if not valid(class) then return false end
        classCache[name]=class
    end
    return widget:IsA(class)
end
function M.isTextBlock(widget) return valid(widget) and isA(widget,'TextBlock') end
local textLibrary
local knownClasses={'ScrollBox','SizeBox','HorizontalBox','Overlay','Button','TextBlock','Slider','WidgetTree'}
local function className(o)
    if not valid(o) then return '' end
    -- Never construct a UClass wrapper from a candidate's ClassPrivate pointer.
    -- Call only on widgets freshly obtained from the current live menu tree.
    for _,name in ipairs(knownClasses) do
        local ok,match=pcall(function() return isA(o,name) end)
        if ok and match then return name end
    end
    return ''
end
M.className=className
local function childAt(panel,index) local ok,v=pcall(function() return panel:GetChildAt(index) end); return ok and v or nil end
local function childCount(panel) local ok,v=pcall(function() return panel:GetChildrenCount() end); return ok and tonumber(v) or 0 end
local function contentOf(widget) local ok,v=pcall(function() return widget:GetContent() end); return ok and v or nil end
M.childAt=childAt; M.childCount=childCount; M.contentOf=contentOf
local function textOf(widget)
    if not valid(widget) then return nil end
    local ok,v=pcall(function()
        local t=widget:GetText(); if type(t)=='string' then return t end
        if t and t.ToString then return t:ToString() end
        if not valid(textLibrary) then textLibrary=StaticFindObject('/Script/Engine.Default__KismetTextLibrary') end
        return valid(textLibrary) and textLibrary:Conv_TextToString(t) or tostring(t)
    end)
    return ok and tostring(v) or nil
end
M.textOf=textOf
function M.cleanLabel(text)
    return (text or ''):gsub('^%*%s+',''):gsub('%s+%*%s*$','')
end
local function address(o) local ok,v=pcall(function() return o:GetAddress() end); return ok and tostring(v) or nil end
M.address=address

function M.ancestorOfClass(o,wanted,maxDepth)
    local cur=o
    for _=1,(maxDepth or 12) do
        if not valid(cur) then return nil end
        if className(cur)==wanted then return cur end
        local ok,parent=pcall(function() return cur:GetParent() end); if not ok then return nil end; cur=parent
    end
end

function M.numericRowFromSlider(slider)
    if not valid(slider) or className(slider)~='Slider' then return nil end
    local surface=M.ancestorOfClass(slider,'Overlay',2); if not surface then return nil end
    local surfaceBox=surface:GetParent(); if className(surfaceBox)~='SizeBox' then return nil end
    local line=surfaceBox:GetParent(); if className(line)~='HorizontalBox' or childCount(line)~=3 then return nil end
    local middle=childAt(line,1); if address(middle)~=address(surfaceBox) then return nil end
    local labelBox,valueBox=childAt(line,0),childAt(line,2); if className(labelBox)~='SizeBox' or className(valueBox)~='SizeBox' then return nil end
    local button=contentOf(labelBox); if className(button)~='Button' then return nil end
    local labelWidget=contentOf(button); if className(labelWidget)~='TextBlock' then return nil end
    local valueWidget=contentOf(valueBox); if className(valueWidget)~='TextBlock' then return nil end
    local overlay=line:GetParent(); if className(overlay)~='Overlay' then return nil end
    local wrapper=overlay:GetParent(); if className(wrapper)~='SizeBox' then return nil end
    local scroll=wrapper:GetParent(); if className(scroll)~='ScrollBox' then return nil end
    local tree=slider:GetOuter(); if className(tree)~='WidgetTree' then return nil end
    return {kind='slider',slider=slider,nav=slider,surface=surface,surfaceBox=surfaceBox,line=line,labelBox=labelBox,labelButton=button,labelWidget=labelWidget,label=textOf(labelWidget),valueBox=valueBox,valueWidget=valueWidget,overlay=overlay,wrapper=wrapper,scroll=scroll,tree=tree}
end

function M.choiceRowFromWrapper(wrapper)
    if className(wrapper)~='SizeBox' then return nil end
    local shell=contentOf(wrapper); if className(shell)~='Overlay' or childCount(shell)<2 then return nil end
    local nav,content=childAt(shell,0),childAt(shell,1); if className(nav)~='Slider' then return nil end
    if className(content)=='Overlay' then
        local lane=nil
        for i=0,childCount(content)-1 do local c=childAt(content,i); if className(c)=='HorizontalBox' then lane=c; break end end
        if not lane or childCount(lane)~=4 then return nil end
        local labelBox,leftBox,centerBox,rightBox=childAt(lane,0),childAt(lane,1),childAt(lane,2),childAt(lane,3)
        if className(labelBox)~='SizeBox' or className(leftBox)~='SizeBox' or className(centerBox)~='SizeBox' or className(rightBox)~='SizeBox' then return nil end
        local button=contentOf(labelBox); if className(button)~='Button' then return nil end
        local labelWidget=contentOf(button); if className(labelWidget)~='TextBlock' then return nil end
        local leftButton,centerButton,rightButton=contentOf(leftBox),contentOf(centerBox),contentOf(rightBox)
        if className(leftButton)~='Button' or className(centerButton)~='Button' or className(rightButton)~='Button' then return nil end
        local valueWidget=contentOf(centerButton); if className(valueWidget)~='TextBlock' then return nil end
        local pairHost,pairHostBox
        for i=0,childCount(content)-1 do
            local box=childAt(content,i)
            local host=className(box)=='SizeBox' and contentOf(box) or nil
            if className(host)=='Overlay' then
                for n=0,childCount(host)-1 do
                    local marker=childAt(host,n)
                    if isA(marker,'TextBlock') and (textOf(marker) or ''):match('^AMM_PAIR_HOST_1\n') then
                        pairHost,pairHostBox=host,box;break
                    end
                end
            end
            if pairHost then break end
        end
        return {kind='picker',wrapper=wrapper,shell=shell,nav=nav,content=content,lane=lane,labelBox=labelBox,labelWidget=labelWidget,label=textOf(labelWidget),leftBox=leftBox,centerBox=centerBox,rightBox=rightBox,leftButton=leftButton,centerButton=centerButton,rightButton=rightButton,valueWidget=valueWidget,pairHost=pairHost,pairHostBox=pairHostBox}
    elseif className(content)=='Button' then
        local lane=contentOf(content); if className(lane)~='HorizontalBox' or childCount(lane)~=2 then return nil end
        local labelBox=childAt(lane,0); if className(labelBox)~='SizeBox' then return nil end
        local labelWidget=contentOf(labelBox); if className(labelWidget)~='TextBlock' then return nil end
        local valueBox=childAt(lane,1); if className(valueBox)~='SizeBox' then return nil end
        local valueWidget=contentOf(valueBox); if className(valueWidget)~='TextBlock' then return nil end
        return {kind='toggle',wrapper=wrapper,shell=shell,nav=nav,button=content,lane=lane,labelWidget=labelWidget,label=textOf(labelWidget),valueWidget=valueWidget}
    end
end

function M.rowFromWrapper(wrapper)
    if className(wrapper)~='SizeBox' then return nil end
    local inside=contentOf(wrapper)
    if className(inside)=='Overlay' then
        for i=0,childCount(inside)-1 do
            local c=childAt(inside,i)
            if className(c)=='HorizontalBox' and childCount(c)==3 then
                local mid=childAt(c,1); local surface=contentOf(mid)
                if className(mid)=='SizeBox' and className(surface)=='Overlay' then
                    for j=0,childCount(surface)-1 do
                        local s=childAt(surface,j)
                        if className(s)=='Slider' then return M.numericRowFromSlider(s) end
                    end
                end
            end
        end
    end
    return M.choiceRowFromWrapper(wrapper)
end

function M.rowsFromScroll(scroll)
    if className(scroll)~='ScrollBox' then return nil end
    local rows={}
    for i=0,childCount(scroll)-1 do
        local child=childAt(scroll,i)
        local content=contentOf(child)
        if M.isTextBlock(content) then
            local path=(textOf(content) or ''):match('^AMM_HEADER_ROW\n(.+)$')
            if path then
                local promoted=StaticFindObject(path)
                if valid(promoted) then child=promoted end
            end
        end
        local row=M.rowFromWrapper(child)
        if row then
            local shell=contentOf(child)
            for n=0,childCount(shell)-1 do
                local marker=childAt(shell,n)
                if valid(marker) and isA(marker,'TextBlock') then
                    local text=textOf(marker) or ''
                    local function decode(value) return (value:gsub('%%(%x%x)',function(hex) return string.char(tonumber(hex,16)) end)) end
                    if text:sub(1,14)=='AMM_SETTING_3\n' then
                        local fields={}
                        for value in (text..'\n'):gmatch('(.-)\n') do fields[#fields+1]=value end
                        local count=tonumber(fields[17])
                        if count and count>=0 and count<=64 and #fields==17+count*2 then
                            local setting={id=decode(fields[4]),kind=fields[5],minimum=tonumber(fields[6]),
                                maximum=tonumber(fields[7]),step=tonumber(fields[8]),decimals=tonumber(fields[9]),
                                prefix=decode(fields[10]),suffix=decode(fields[11]),ammKeybind=fields[12]=='1',
                                ammFixedMode=decode(fields[13]),ammPairId=decode(fields[14]),
                                ammTabsWidth=tonumber(fields[15]),ammPairTargetId=decode(fields[16]),values={},labels={}}
                            if setting.ammFixedMode=='' then setting.ammFixedMode=nil end
                            if setting.ammPairId=='' then setting.ammPairId=nil end
                            if setting.ammPairTargetId=='' then setting.ammPairTargetId=nil end
                            for item=1,count do setting.values[item]=assert(tonumber(decode(fields[17+item])),'invalid setting identity value') end
                            for item=1,count do setting.labels[item]=decode(fields[17+count+item]) end
                            row.settingIndex=tonumber(fields[2]);row.identityProviderId=decode(fields[3]);row.settingId=setting.id
                            row.dmmSetting=setting
                        end
                    end
                    if text:match('^AMM_MODE\n') then row.modeState=marker end
                end
            end
            rows[#rows+1]=row
        end
    end
    -- Preserve visual traversal order. Binding uses provider/setting IDs,
    -- never a reconstructed ordering from the independently parsed metadata.
    return rows
end
-- The exact host was activated through the lifecycle hook. No global object
-- enumeration is used while idle, during gameplay, or during loading.
function M.activeTrees(host,allowed)
    if not allowed() or not valid(host) then return {} end
    if not host:IsInViewport() or not host:IsActivated() or host:IsVisible()~=true or host:GetIsEnabled()~=true then return {} end
    if not allowed() then return {} end
    local tree=host.WidgetTree
    if not valid(tree) or not allowed() then return {} end
    local root=tree.RootWidget
    if not valid(root) then return {} end
    local snapshot={widgets={},names={},scrolls={},routes={},count=0}
    local complete=true
    local function walk(widget,depth,parentRoute,index)
        if not allowed() then complete=false;return end
        if depth>40 or snapshot.count>=4096 then complete=false;return end
        if not valid(widget) then return end
        local addr=address(widget)
        if not addr or snapshot.widgets[addr] then return end
        snapshot.widgets[addr]=widget
        snapshot.names[addr]=widget:GetFName():ToString()
        local route={parent=parentRoute,index=index,address=addr,name=snapshot.names[addr]}
        snapshot.routes[addr]=route
        snapshot.count=snapshot.count+1
        if not allowed() then complete=false;return end
        if isA(widget,'ScrollBox') then snapshot.scrolls[#snapshot.scrolls+1]=widget end
        if isA(widget,'WidgetSwitcher') then
            local selected=widget:GetActiveWidgetIndex()
            if selected>=0 then walk(widget:GetChildAt(selected),depth+1,route,selected) end
        elseif isA(widget,'PanelWidget') then
            for i=0,widget:GetChildrenCount()-1 do walk(widget:GetChildAt(i),depth+1,route,i) end
        end
    end
    walk(root,0)
    if complete and allowed() then return {snapshot} end
    return {}
end
-- Build fresh-child routes only for controls already identified by the DMM
-- page event. This avoids walking unrelated help, footer and decoration trees.
function M.routesFor(host,objects,allowed)
    if not allowed() or not valid(host) then return nil end
    local tree=host.WidgetTree
    if not allowed() or not valid(tree) then return nil end
    local root=tree.RootWidget
    if not allowed() or not valid(root) then return nil end
    local rootAddress=address(root)
    local routes={}
    local building={}
    local function route(widget,depth)
        if not allowed() or not valid(widget) or depth>40 then return nil end
        local addr=address(widget)
        if not addr then return nil end
        if routes[addr] then return routes[addr] end
        if building[addr] then return nil end
        building[addr]=true
        local result
        if addr==rootAddress then
            result={address=addr,name=widget:GetFName():ToString()}
        else
            local ok,parent=pcall(function() return widget:GetParent() end)
            if ok and valid(parent) then
                local parentRoute=route(parent,depth+1)
                if parentRoute then
                    local index
                    for i=0,childCount(parent)-1 do
                        local child=childAt(parent,i)
                        if valid(child) and address(child)==addr then index=i;break end
                    end
                    if index then result={parent=parentRoute,index=index,address=addr,name=widget:GetFName():ToString()} end
                end
            end
        end
        building[addr]=nil
        if result then routes[addr]=result end
        return result
    end
    for _,widget in ipairs(objects or {}) do
        if not route(widget,0) then return nil end
    end
    return routes
end
-- Resolve through current widget ownership, never through retained native wrappers.
-- Routes contain only primitive identities/indices. The cache lives for one update.
function M.routeResolver(host,allowed)
    if not allowed() or not valid(host) then return nil end
    local tree=host.WidgetTree
    if not allowed() or not valid(tree) then return nil end
    local root=tree.RootWidget
    if not allowed() or not valid(root) then return nil end
    local cache={}
    local function resolve(route)
        if not route or not allowed() then return nil end
        if cache[route]~=nil then return cache[route] or nil end
        local widget
        if route.parent then
            local parent=resolve(route.parent)
            if parent and allowed() then widget=parent:GetChildAt(route.index) end
        else widget=root end
        if not allowed() then return nil end
        if valid(widget) and address(widget)==route.address and widget:GetFName():ToString()==route.name then
            cache[route]=widget;return widget
        end
        cache[route]=false
    end
    return resolve
end
return M
