-- Lifecycle callbacks retain strings/numbers only, never a UObject for later use.
local M={}
function M.install(log,onChange)
    if type(RegisterHook)~='function' then return nil,'RegisterHook unavailable' end
    local scope={enabled=false,epoch=0,path=nil,address=nil,loading=false,reset=0}
    local function revoke(reason,loading)
        scope.epoch=scope.epoch+1
        scope.path=nil;scope.address=nil
        if loading then scope.loading=true;scope.reset=scope.reset+1 end
        if onChange then onChange(nil,scope.epoch,scope.reset) end
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
        if name:match('^WBP_MainMenu_') then
            scope.loading=false
            log('MENU_SCOPE_REARMED','main menu')
            return
        end
        if scope.loading or not name:match('^CommonActivatableWidget_') then return end
        local full=widget:GetFullName()
        local path=full:match('^%S+ (.+)$')
        if not path then return end
        scope.epoch=scope.epoch+1
        scope.path=path;scope.address=tostring(widget:GetAddress())
        if onChange then onChange(path,scope.epoch,scope.reset) end
    end
    local function removed(context)
        if not scope.enabled or not scope.path then return end
        if tostring(liveContext(context):GetAddress())==scope.address then revoke('host deactivated/removed',false) end
    end
    local function load()
        if scope.enabled then revoke('load requested/started',true) end
    end
    local function rearm()
        if not scope.enabled then return end
        scope.loading=false
        log('MENU_SCOPE_REARMED','pause menu')
    end
    local function protect(fn)
        return function(...)
            local ok,err=pcall(fn,...)
            if not ok then
                scope.enabled=false;revoke('lifecycle callback failed',true)
                log('MENU_SCOPE_FAILED',tostring(err))
            end
        end
    end
    local noop=function() end
    -- These native signatures are present in the installed CXXHeaderDump. Any
    -- missing registration disables this candidate; there is no polling fallback.
    local specs={
        {'/Script/CommonUI.CommonActivatableWidget:ActivateWidget',noop,protect(activate)},
        {'/Script/CommonUI.CommonActivatableWidget:DeactivateWidget',protect(removed),noop},
        {'/Script/UMG.Widget:RemoveFromParent',protect(removed),noop},
        {'/Script/DogwoodUI.SaveWindowBase:RequestLoadSave',protect(load),noop},
        {'/Script/DogwoodUI.DWLoadingScreenWidget:NotifyLoadingScreenStarted',protect(load),noop},
        {'/Script/DogwoodUI.UIFrontend:ShowPauseMenu',noop,protect(rearm)},
    }
    for _,spec in ipairs(specs) do
        local ok,err=pcall(RegisterHook,spec[1],spec[2],spec[3])
        if not ok then
            scope.enabled=false
            return nil,spec[1]..': '..tostring(err)
        end
    end
    scope.enabled=true
    function scope:current()
        if not self.enabled or self.loading then return nil end
        return self.path,self.epoch,self.reset
    end
    function scope:matches(path,epoch)
        return self.enabled and not self.loading and self.path==path and self.epoch==epoch
    end
    function scope:invalidate(reason)
        if self.path then revoke(reason,false) end
    end
    return scope
end
return M
