-- Lifecycle callbacks retain strings/numbers only, never a UObject for later use.
local M={}
function M.install(log,onChange,onRetire)
    if type(RegisterHook)~='function' or type(UnregisterHook)~='function' then return nil,'RegisterHook/UnregisterHook unavailable' end
    local scope={enabled=false,epoch=0,path=nil,address=nil}
    local function revoke(reason)
        scope.epoch=scope.epoch+1
        scope.path=nil;scope.address=nil;scope.treeAddress=nil
        if onChange then onChange(nil,scope.epoch) end
    end
    local function retireAll()
        if onRetire then onRetire(nil) end
    end
    local function closeOwner()
        scope.owner=nil
        revoke('menu owner closed')
        retireAll()
    end
    function scope:ownerLive()
        local identity=self.owner
        if not self.enabled or not identity then return false end
        -- Resolve a fresh owner; a remembered activation is not permission to poll.
        local owner=StaticFindObject(identity.path)
        if not owner or not owner:IsValid() or tostring(owner:GetAddress())~=identity.address
            or not owner:IsVisible() or not owner:IsActivated() then
            closeOwner()
            return false
        end
        return true
    end
    local function liveContext(context)
        -- Invoked synchronously inside a native widget function, not a deferred
        -- construction notification. Do not retain the returned wrapper.
        return context:get()
    end
    local function discoverOwner()
        if type(FindAllOf)~='function' then return false end
        local found
        -- Event-only recovery: native owner activation can bypass the reflected hook.
        -- Use the same two owner classes as DMM; never enumerate generic widgets.
        for _,className in ipairs({'WBP_MainMenu_C','WBP_PauseMenu_C'}) do
            for _,candidate in ipairs(FindAllOf(className) or {}) do
                if candidate and candidate:IsValid() and candidate:IsVisible() and candidate:IsActivated() then
                    local full=candidate:GetFullName()
                    if not full:find('Default__',1,true) and full:match('^'..className..' ') then
                        local path=full:match('^%S+ (.+)$')
                        local address=tostring(candidate:GetAddress())
                        if found and found.address~=address then return false end
                        found={path=path,address=address}
                    end
                end
            end
        end
        if not found then return false end
        scope.owner=found
        return true
    end
    local function openHost(widget,expectedTree)
        if not widget or not widget:IsValid() then return end
        if not widget:GetFName():ToString():match('^CommonActivatableWidget_') then return end
        if not widget:IsInViewport() or not widget:IsActivated() or not widget:IsVisible()
            or not widget:GetIsEnabled() then return end
        local tree=widget.WidgetTree
        if not tree or not tree:IsValid() then return end
        local treeAddress=tostring(tree:GetAddress())
        if expectedTree and treeAddress~=expectedTree then return end
        if scope.owner then scope:ownerLive() end
        if not scope.owner and not discoverOwner() then return end
        if not scope:ownerLive() then return end
        local path=widget:GetFullName():match('^%S+ (.+)$')
        if not path then return end
        scope.epoch=scope.epoch+1
        scope.path=path;scope.address=tostring(widget:GetAddress());scope.treeAddress=treeAddress
        if onChange then onChange(path,scope.epoch) end
    end
    local function activate(context)
        if not scope.enabled then return end
        local widget=liveContext(context)
        local name=widget:GetFName():ToString()
        if name:match('^WBP_MainMenu_C_') or name:match('^WBP_PauseMenu_C_') then
            local full=widget:GetFullName()
            if not (full:match('^WBP_MainMenu_C ') or full:match('^WBP_PauseMenu_C ')) then return end
            if not widget:IsVisible() or not widget:IsActivated() then return end
            local path=full:match('^%S+ (.+)$')
            local address=tostring(widget:GetAddress())
            if not scope.owner or scope.owner.path~=path or scope.owner.address~=address then closeOwner() end
            scope.owner={path=path,address=address}
        elseif name:match('^CommonActivatableWidget_') then openHost(widget) end
    end
    local function pageChanged(context)
        if not scope.enabled then return end
        -- DMM finishes populate() before switching the page. The queued update runs
        -- after the enclosing showDetail()/show() completes, never in this callback.
        local tree=liveContext(context):GetOuter()
        if not tree or not tree:IsValid() then return end
        local address=tostring(tree:GetAddress())
        openHost(tree:GetOuter(),address)
    end
    local function deactivated(context)
        if not scope.enabled or not scope.owner then return end
        local address=tostring(liveContext(context):GetAddress())
        if address==scope.owner.address then closeOwner()
        elseif address==scope.address then revoke('host deactivated') end
    end
    local function removed(context)
        if not scope.enabled or not scope.owner then return end
        local widget=liveContext(context)
        local address=tostring(widget:GetAddress())
        if address==scope.owner.address then closeOwner();return end
        local path=widget:GetFullName():match('^%S+ (.+)$')
        if address==scope.address then revoke('host removed') end
        -- Also retire a host that was deactivated before RemoveFromParent.
        if path and onRetire then onRetire(path) end
    end
    local function load()
        if scope.enabled then closeOwner() end
    end
    local function protect(fn)
        return function(...)
            local ok,err=pcall(fn,...)
            if not ok then
                scope.enabled=false;closeOwner()
                log('MENU_SCOPE_FAILED',tostring(err))
            end
        end
    end
    local noop=function() end
    -- These native signatures are present in the installed CXXHeaderDump. Any
    -- missing registration disables this candidate; there is no polling fallback.
    local specs={
        {'/Script/CommonUI.CommonActivatableWidget:ActivateWidget',noop,protect(activate)},
        {'/Script/CommonUI.CommonActivatableWidget:DeactivateWidget',protect(deactivated),noop},
        {'/Script/UMG.Widget:RemoveFromParent',protect(removed),noop},
        {'/Script/DogwoodUI.SaveWindowBase:RequestLoadSave',protect(load),noop},
        {'/Script/DogwoodUI.DWLoadingScreenWidget:NotifyLoadingScreenStarted',protect(load),noop},
        {'/Script/UMG.WidgetSwitcher:SetActiveWidgetIndex',noop,protect(pageChanged)},
    }
    local registered={}
    for _,spec in ipairs(specs) do
        local ok,pre,post=pcall(RegisterHook,spec[1],spec[2],spec[3])
        if not ok or type(pre)~='number' or type(post)~='number' then
            scope.enabled=false
            for _,hook in ipairs(registered) do pcall(UnregisterHook,hook[1],hook[2],hook[3]) end
            return nil,spec[1]..': '..tostring(pre)
        end
        registered[#registered+1]={spec[1],pre,post}
    end
    scope.enabled=true
    function scope:current()
        if not self.enabled then return nil end
        return self.path,self.epoch
    end
    function scope:matches(path,epoch)
        return self.enabled and self.owner~=nil and self.path==path and self.epoch==epoch
    end
    function scope:dormant()
        -- Retain the host identity for a later page event; retire all queued work.
        self.epoch=self.epoch+1
        if onChange then onChange(nil,self.epoch) end
    end
    function scope:invalidate(reason)
        if self.path then revoke(reason) end
    end
    return scope
end
return M
