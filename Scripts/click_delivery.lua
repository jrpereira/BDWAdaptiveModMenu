-- Own buttons only: native OnClicked invokes an existing no-argument UWidget
-- function. The scoped hook queues Lua counts; it never updates stock widgets.
local M={}
function M.new(log)
    local self={owners={},path=nil,hook=nil}
    function self:close()
        self.path=nil
        for _,owner in pairs(self.owners) do owner.instance.pendingClicks=0 end
        if self.hook then
            local ok,err=pcall(UnregisterHook,'/Script/UMG.Widget:ForceLayoutPrepass',self.hook[1],self.hook[2])
            if ok then self.hook=nil else log('CLICK_HOOK_FAILED',tostring(err)) end
        end
    end
    function self:open(path)
        self.path=path
        for _,owner in pairs(self.owners) do owner.instance.pendingClicks=0 end
        if self.hook then return true end
        local ok,pre,post=pcall(RegisterHook,'/Script/UMG.Widget:ForceLayoutPrepass',function() end,function(context)
            if not self.path then return end
            local success,err=pcall(function()
                local button=context:get()
                local owner=self.owners[tostring(button:GetAddress())]
                if not owner or owner.path~=self.path or owner.instance.disabled then return end
                if button:GetFullName()~=owner.full then return end
                owner.instance.pendingClicks=(owner.instance.pendingClicks or 0)+1
            end)
            if not success then log('CLICK_EVENT_FAILED',tostring(err)) end
        end)
        if not ok or type(pre)~='number' or type(post)~='number' then
            self.path=nil
            return false,tostring(pre)
        end
        self.hook={pre,post}
        return true
    end
    function self:attach(instance,button,existing)
        assert(self.path and self.hook,'click hook unavailable')
        local address=tostring(button:GetAddress())
        local full=button:GetFullName()
        -- Add only to our newly constructed button. Never touch DMM delegates.
        if not existing then button.OnClicked:Add(button,FName('ForceLayoutPrepass')) end
        self.owners[address]={instance=instance,path=self.path,full=full}
    end
    function self:retire(path)
        for address,owner in pairs(self.owners) do
            if not path or owner.path==path then
                owner.instance.pendingClicks=0
                self.owners[address]=nil
            end
        end
    end
    function self:forget(instance)
        instance.pendingClicks=0
        for address,owner in pairs(self.owners) do
            if owner.instance==instance then self.owners[address]=nil end
        end
    end
    return self
end
return M
