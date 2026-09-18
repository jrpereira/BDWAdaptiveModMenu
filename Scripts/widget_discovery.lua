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
    local shell=contentOf(wrapper); if className(shell)~='Overlay' or childCount(shell)~=2 then return nil end
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
        return {kind='picker',wrapper=wrapper,shell=shell,nav=nav,content=content,lane=lane,labelBox=labelBox,labelWidget=labelWidget,label=textOf(labelWidget),leftBox=leftBox,centerBox=centerBox,rightBox=rightBox,leftButton=leftButton,centerButton=centerButton,rightButton=rightButton,valueWidget=valueWidget}
    elseif className(content)=='Button' then
        local lane=contentOf(content); if className(lane)~='HorizontalBox' or childCount(lane)~=2 then return nil end
        local labelBox=childAt(lane,0); if className(labelBox)~='SizeBox' then return nil end
        local labelWidget=contentOf(labelBox); if className(labelWidget)~='TextBlock' then return nil end
        return {kind='toggle',wrapper=wrapper,shell=shell,nav=nav,button=content,lane=lane,labelWidget=labelWidget,label=textOf(labelWidget)}
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
        local child=childAt(scroll,i); local row=M.rowFromWrapper(child)
        if row then rows[#rows+1]=row end
    end
    return rows
end
-- The exact host was activated through the lifecycle hook. No global object
-- enumeration is used while idle, during gameplay, or during loading.
function M.activeTrees(host,allowed)
    if not allowed() or not valid(host) then return {} end
    if not host:IsInViewport() or not host:IsActivated() then return {} end
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
        if isA(widget,'PanelWidget') then
            for i=0,widget:GetChildrenCount()-1 do walk(widget:GetChildAt(i),depth+1,route,i) end
        end
    end
    walk(root,0)
    if complete and allowed() then return {snapshot} end
    return {}
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
