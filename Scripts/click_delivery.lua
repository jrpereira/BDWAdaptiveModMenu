-- Queue left-button input as primitive Lua state. The key callback performs no
-- UObject work; the existing menu-only game-thread update resolves the current
-- button and delivers the click to the hovered paired picker.
local M={}
function M.new(log)
    local self={owners={},path=nil,pointerClicks=0,available=false}
    local ok,err=pcall(function()
        assert(type(RegisterKeyBind)=='function','RegisterKeyBind unavailable')
        assert(type(Key)=='table' and Key.LEFT_MOUSE_BUTTON~=nil,'left mouse key unavailable')
        RegisterKeyBind(Key.LEFT_MOUSE_BUTTON,function()
            if self.path and self.pointerClicks<16 then self.pointerClicks=self.pointerClicks+1 end
        end)
    end)
    if ok then self.available=true else log('CLICK_INPUT_FAILED',tostring(err)) end
    function self:close()
        self.path=nil;self.pointerClicks=0
        for _,owner in pairs(self.owners) do owner.instance.pendingClicks=0 end
    end
    function self:open(path)
        self.path=path;self.pointerClicks=0
        for _,owner in pairs(self.owners) do owner.instance.pendingClicks=0 end
        if not self.available then self.path=nil;return false,'left mouse callback unavailable' end
        return true
    end
    function self:attach(instance,button)
        assert(self.path and self.available,'click input unavailable')
        local address=tostring(button:GetAddress())
        self.owners[address]={instance=instance,path=self.path,full=button:GetFullName()}
    end
    function self:deliver(instance)
        if self.pointerClicks==0 or not self.path or not instance or not instance.pair then return end
        local button=instance.pair.button
        if not button or not button:IsValid() then return end
        local owner=self.owners[tostring(button:GetAddress())]
        if not owner or owner.instance~=instance or owner.path~=self.path or button:GetFullName()~=owner.full then return end
        if button:IsHovered()~=true then return end
        instance.pendingClicks=(instance.pendingClicks or 0)+self.pointerClicks
        self.pointerClicks=0
    end
    function self:discard() self.pointerClicks=0 end
    function self:retire(path)
        for address,owner in pairs(self.owners) do
            if not path or owner.path==path then
                owner.instance.pendingClicks=0
                self.owners[address]=nil
            end
        end
        if not path or path==self.path then self.pointerClicks=0 end
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
