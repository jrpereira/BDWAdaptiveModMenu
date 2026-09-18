-- Lifecycle callbacks retain strings/numbers only, never a UObject for later use.
local M={}
function M.install(log,onChange,onRetire)
    if type(RegisterHook)~='function' or type(UnregisterHook)~='function' then return nil,'RegisterHook/UnregisterHook unavailable' end
    local scope={enabled=false,epoch=0,path=nil,address=nil,loading=false}
    local function revoke(reason,loading)
        scope.epoch=scope.epoch+1
        scope.path=nil;scope.address=nil;scope.treeAddress=nil
        if loading then scope.loading=true end
        if onChange then onChange(nil,scope.epoch) end
    end
    local function retireAll()
        if onRetire then onRetire(nil) end
    end
    local function closeOwner(loading)
        scope.owner=nil
        revoke('menu owner closed',loading)
        retireAll()
    end
    function scope:ownerLive()
        local identity=self.owner
        if not self.enabled or self.loading or not identity then return false end
        -- Resolve a fresh owner; a remembered activation is not permission to poll.
        local owner=StaticFindObject(identity.path)
        if not owner or not owner:IsValid() or tostring(owner:GetAddress())~=identity.address
            or not owner:IsVisible() or not owner:IsActivated() then
            closeOwner(false)
            return false
        end
        return true
    end
    local function liveContext(context)
        -- Invoked synchronously inside a native widget function, not a deferred
        -- construction notification. Do not retain the returned wrapper.
        return context:get()
    end
    local function activate(context)
        if not scope.enabled then return end
        local widget=liveContext(context)
        local name=widget:GetFName():ToString()
        local ownerName=name:match('^WBP_MainMenu_C_') or name:match('^WBP_PauseMenu_C_')
        if not ownerName and (scope.loading or not scope.owner or not name:match('^CommonActivatableWidget_')) then return end
        local full=widget:GetFullName()
        if full:match('^WBP_MainMenu_C ') or full:match('^WBP_PauseMenu_C ') then
            if not widget:IsVisible() or not widget:IsActivated() then return end
            local path=full:match('^%S+ (.+)$')
            local address=tostring(widget:GetAddress())
            if not scope.owner or scope.owner.path~=path or scope.owner.address~=address then
                closeOwner(false)
            end
            scope.loading=false
            scope.owner={path=path,address=address}
            return
        end
        if scope.loading or not scope.owner or not name:match('^CommonActivatableWidget_') then return end
        if not scope:ownerLive() then return end
        local path=full:match('^%S+ (.+)$')
        if not path then return end
        scope.epoch=scope.epoch+1
        scope.path=path;scope.address=tostring(widget:GetAddress())
        scope.treeAddress=tostring(widget.WidgetTree:GetAddress())
        if onChange then onChange(path,scope.epoch) end
    end
    local function pageChanged(context)
        if not scope.enabled or scope.loading or not scope.path then return end
        -- DMM constructs its switchers directly under the active host's WidgetTree.
        -- The callback context and its outer are synchronous fresh wrappers.
        local tree=liveContext(context):GetOuter()
        if tostring(tree:GetAddress())~=scope.treeAddress then return end
        if not scope:ownerLive() then return end
        scope.epoch=scope.epoch+1
        if onChange then onChange(scope.path,scope.epoch) end
    end
    local function deactivated(context)
        if not scope.enabled or not scope.owner then return end
        local address=tostring(liveContext(context):GetAddress())
        if address==scope.owner.address then closeOwner(false)
        elseif address==scope.address then revoke('host deactivated',false) end
    end
    local function removed(context)
        if not scope.enabled or not scope.owner then return end
        local widget=liveContext(context)
        local address=tostring(widget:GetAddress())
        if address==scope.owner.address then closeOwner(false);return end
        local path=widget:GetFullName():match('^%S+ (.+)$')
        if address==scope.address then revoke('host removed',false) end
        -- Also retire a host that was deactivated before RemoveFromParent.
        if path and onRetire then onRetire(path) end
    end
    local function load()
        if scope.enabled then closeOwner(true) end
    end
    local function protect(fn)
        return function(...)
            local ok,err=pcall(fn,...)
            if not ok then
                scope.enabled=false;closeOwner(true)
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
        if not self.enabled or self.loading then return nil end
        return self.path,self.epoch
    end
    function scope:matches(path,epoch)
        return self.enabled and not self.loading and self.owner~=nil and self.path==path and self.epoch==epoch
    end
    function scope:dormant()
        -- Retain the host identity for a later page event; retire all queued work.
        self.epoch=self.epoch+1
        if onChange then onChange(nil,self.epoch) end
    end
    function scope:invalidate(reason)
        if self.path then revoke(reason,false) end
    end
    return scope
end
return M
