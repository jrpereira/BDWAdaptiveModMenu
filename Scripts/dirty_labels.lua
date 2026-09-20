-- Presentation only: DMM owns dirty state, pending values, Apply and Restore.
local Discovery=require('widget_discovery')
local M={}
local PREFIX='MMD_DIRTY_3\n'
local function encode(s) return (s:gsub('%%','%%25'):gsub('\n','%%0A'):gsub('\r','%%0D')) end
local function decode(s) return (s:gsub('%%(%x%x)',function(h) return string.char(tonumber(h,16)) end)) end
local function name(value) return type(value)=='string' and value or value:ToString() end

function M.signal(text,setting)
    local function clean(value)
        if not setting then return false end
        if setting.kind=='slider' then
            local prefix,suffix=setting.prefix or '',setting.suffix or ''
            if value:sub(1,#prefix)~=prefix or (#suffix>0 and value:sub(-#suffix)~=suffix) then return false end
            local number=tonumber(value:sub(#prefix+1,#value-#suffix))
            return number and number==number and math.abs(number)<=1000000000
                and prefix..string.format('%.'..setting.decimals..'f',number)..suffix==value
        end
        for _,label in ipairs(setting.labels or {}) do if value==label then return true end end
        return false
    end
    if clean(text) then return false,text end -- Literal '*' in a schema label/suffix.
    local value=text:gsub('%s+%*%s*$','')
    if value~=text and clean(value) then return true,value end
    return false,text -- Unknown/unavailable/localized text is never guessed dirty.
end
local function readMarker(shell)
    for i=0,Discovery.childCount(shell)-1 do
        local child=Discovery.childAt(shell,i)
        if Discovery.isTextBlock(child) then
            local text=Discovery.textOf(child) or ''
            if text:sub(1,#PREFIX)==PREFIX then
                local fields={}
                for line in text:sub(#PREFIX+1):gmatch('([^\n]*)\n') do fields[#fields+1]=line end
                assert(#fields==9 or #fields==10,'invalid dirty-label state')
                return child,{dirty=fields[1]=='1',base=decode(fields[2]),face=decode(fields[3]),
                    skew=assert(tonumber(fields[4])),italic=decode(fields[5]),italicSkew=assert(tonumber(fields[6])),suppressed=fields[7]=='1',pending=decode(fields[8]),lastValue=decode(fields[9]),rendered=fields[10]}
            end
        end
    end
end
local function starOf(shell)
    for i=0,Discovery.childCount(shell)-1 do
        local child=Discovery.childAt(shell,i)
        if Discovery.isTextBlock(child) and Discovery.textOf(child)=='*' then return child end
    end
end
local function serialized(state)
    return PREFIX..table.concat({state.dirty and '1' or '0',encode(state.base),encode(state.face),
        tostring(state.skew),encode(state.italic),tostring(state.italicSkew),state.suppressed and '1' or '0',encode(state.pending or ''),encode(state.lastValue or ''),state.rendered or ''},'\n')..'\n'
end
local function styleState(label,dirty)
    local font=label.Font
    local state={dirty=dirty,base=Discovery.textOf(label),
        face=name(font.TypefaceFontName),skew=tonumber(font.SkewAmount) or 0,italic=''}
    -- Prefer a real italic face in the existing font. Some fonts provide only a
    -- regular face; Slate's font skew supplies the same slanted presentation.
    pcall(function()
        local entries=font.FontObject.CompositeFont.DefaultTypeface.Fonts
        local best=0
        local function inspect(entry)
            pcall(function() entry=entry:get() end)
            local face=name(entry.Name)
            local key=face:lower()
            if key:find('italic',1,true) or key:find('oblique',1,true) then
                local rank=(key:find('bold',1,true) or key:find('black',1,true)) and 1 or 2
                if rank>best then best=rank;state.italic=face end
            end
        end
        if type(entries)=='table' then for _,entry in ipairs(entries) do inspect(entry) end
        else entries:ForEach(function(_,entry) inspect(entry) end) end
    end)
    state.italicSkew=state.italic~='' and state.skew or state.skew+0.2
    return state
end

function M.new(log,registry)
    local controller={records={},settings={},busy=false,showDirty=true}
    -- This gates newly received dirty signals, not DMM's dirty state. Turning
    -- it back on never retroactively reveals changes made under suppression.
    function controller:setShowDirty(show)
        assert(type(show)=='boolean','showDirty must be boolean')
        local previous=self.showDirty;self.showDirty=show;return previous
    end
    -- Our decoration construction writes presentation text, never DMM values.
    -- Do not rediscover rows for those synchronous SetText notifications.
    function controller:construct(fn)
        local previous=self.busy
        self.busy=true
        local result=table.pack(pcall(fn))
        self.busy=previous
        if not result[1] then error(result[2],0) end
        return table.unpack(result,2,result.n)
    end
    local function displayed(state) return state.dirty and not state.suppressed end
    local localization
    if registry and registry.dmmChoicesPath then
        local ok,result=pcall(function()
            -- gsub returns both the rewritten path and its replacement count.
            -- Keep only the path so the count is not passed as loadfile's mode.
            local path=(registry.dmmChoicesPath:gsub('choices%.lua$','localization.lua'))
            return assert(loadfile(path))()
        end)
        if ok and type(result)=='table' and type(result.initialize)=='function' and type(result.provider)=='function' then
            localization=result
        else log('DIRTY_LABEL_FAILED','DMM localization API unavailable: '..tostring(result)) end
    end
    function controller:localize(provider)
        if not localization then return end
        local ok,err=pcall(function()
            local read=require('init_config').fs.read
            localization.initialize(read,log)
            local view=provider.dmmPresentation
            if not view then
                view={id=provider.id,name=provider.name,choices=provider.dmmSettings}
                localization.provider(view,assert(read(provider.path),'metadata unavailable'))
                provider.dmmPresentation=view
            else localization.provider(view) end
        end)
        if not ok then log('DIRTY_LABEL_FAILED','localization: '..tostring(err)) end
    end
    local textLibrary
    local function setText(widget,text)
        if Discovery.textOf(widget)==text then return end
        if not Discovery.valid(textLibrary) then textLibrary=StaticFindObject('/Script/Engine.Default__KismetTextLibrary') end
        assert(Discovery.valid(textLibrary),'text library unavailable')
        widget:SetText(textLibrary:Conv_StringToText(text))
    end
    local function render(label,state,dirty,shell)
        -- Presentation metadata may change a label while the same row lives.
        state.base=Discovery.textOf(label) or state.base
        local presentation=dirty and '1' or '0'
        if state.rendered==presentation then return end
        setText(label,state.base)
        local star=assert(starOf(shell),'dirty star unavailable')
        star:SetVisibility(dirty and 4 or 2) -- Hit-test invisible / hidden; label layout never changes.
        local face=dirty and state.italic~='' and state.italic or state.face
        local skew=dirty and state.italicSkew or state.skew
        local font=label.Font
        if name(font.TypefaceFontName)~=face or tonumber(font.SkewAmount)~=skew then
            local previousFace,previousSkew=font.TypefaceFontName,font.SkewAmount
            font.TypefaceFontName=FName(face);font.SkewAmount=skew
            local ok,err=pcall(label.SetFont,label,font)
            if not ok then font.TypefaceFontName=previousFace;font.SkewAmount=previousSkew;error(err) end
        end
        state.rendered=presentation
        setText(assert(readMarker(shell)),serialized(state))
    end
    local function protected(fn)
        if controller.busy then return end
        controller.busy=true
        local ok,result=pcall(fn)
        controller.busy=false
        if not ok then log('DIRTY_LABEL_FAILED',tostring(result)) end
        return ok,result
    end
    local function renderRecord(resolve,record)
        local primary=record.primary or record
        local shell,label=resolve(primary.shell),resolve(primary.label)
        if not shell or not label then return end
        local _,state=readMarker(shell)
        if not state then return end
        local combined=displayed(state)
        if primary.peer then
            local peerShell=resolve(primary.peer.shell)
            if peerShell then local _,peer=readMarker(peerShell);combined=combined or (peer and displayed(peer)) end
        end
        render(label,state,combined,shell)
        if record.primary then
            local ownShell,ownLabel=resolve(record.shell),resolve(record.label)
            if ownShell and ownLabel then local _,own=readMarker(ownShell);if own then render(ownLabel,own,displayed(own),ownShell) end end
        end
    end
    function controller:setValue(providerId,settingId,value)
        assert(self.allowed and self.allowed() and (not self.live or self.live()),'no active settings panel')
        local record=self.settings[providerId..'\0'..settingId]
        assert(record and record.setting,'setting is not on the active panel')
        assert(type(value)=='number' and value==value and math.abs(value)<=1000000000,'invalid setting value')
        local setting=record.setting
        local position,text
        if setting.kind=='slider' then
            assert(value>=setting.minimum and value<=setting.maximum,'value outside setting range')
            if value>setting.minimum and value<setting.maximum then
                value=math.max(setting.minimum,math.min(setting.maximum,tonumber(string.format('%.6f',
                    setting.minimum+math.floor((value-setting.minimum)/setting.step+0.5)*setting.step))))
            end
            position=(value-setting.minimum)/(setting.maximum-setting.minimum)
            text=(setting.prefix or '')..string.format('%.'..setting.decimals..'f',value)..(setting.suffix or '')
        else
            for i,v in ipairs(setting.values) do if value==v then position=i-1;text=setting.labels[i];break end end
            assert(position,'value is not a declared choice')
        end
        return protected(function()
            local resolve=assert(Discovery.routeResolver(StaticFindObject(self.path),self.allowed),'panel unavailable')
            local control=assert(resolve(record.control),'control unavailable')
            local marker,state=readMarker(assert(resolve(record.shell),'row unavailable'))
            assert(marker,'row state unavailable')
            local changed=control:GetValue()~=position
            state.pending=changed and not self.showDirty and text or ''
            if not changed then state.suppressed=state.dirty and not self.showDirty end
            setText(marker,serialized(state))
            if changed then
                local ok,err=pcall(control.SetValue,control,position)
                if not ok then state.pending='';setText(marker,serialized(state));error(err) end
            else renderRecord(resolve,record) end
        end)
    end
    function controller:close()
        self.records={};self.settings={};self.path=nil;self.allowed=nil;self.routes=nil;self.live=nil;self.bound=false;self.showDirty=true
    end
    function controller:open(path,allowed,live)
        if self.path==path then
            self.records={};self.settings={};self.allowed=allowed;self.live=live
            self.routes=nil;self.bound=false;self.showDirty=true
            return true
        end
        self:close();self.path=path;self.allowed=allowed;self.live=live
        return true
    end
    function controller:bind(rows,routes,pairsByRow)
        protected(function()
            local byRow={}
            for _,row in ipairs(rows) do
                local shell=row.overlay or row.shell
                if Discovery.valid(shell) and Discovery.valid(row.labelWidget) and Discovery.valid(row.valueWidget) then
                    local valueId=Discovery.address(row.valueWidget)
                    local record={value=routes[valueId],label=routes[Discovery.address(row.labelWidget)],shell=routes[Discovery.address(shell)],
                        control=routes[Discovery.address(row.slider or row.nav)],setting=row.dmmSetting}
                    if record.value and record.label and record.shell then
                        local marker,state=readMarker(shell)
                        local dirty,clean=M.signal(Discovery.textOf(row.valueWidget) or '',row.dmmSetting)
                        if not marker then
                            state=styleState(row.labelWidget,dirty)
                            state.suppressed=dirty and not self.showDirty;state.lastValue=clean
                            local tree=shell:GetOuter()
                            marker=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),tree)
                            assert(Discovery.valid(marker),'dirty marker construction failed')
                            marker:SetVisibility(1)
                            setText(marker,serialized(state))
                            assert(shell:AddChildToOverlay(marker),'dirty marker attachment failed')
                        else
                            if dirty then
                                state.dirty=true;state.suppressed=not self.showDirty;state.lastValue=clean
                            elseif clean~=state.lastValue then
                                state.dirty=false;state.suppressed=false;state.lastValue=clean
                            end
                            state.pending='';setText(marker,serialized(state))
                        end
                        if not starOf(shell) then
                            local star=StaticConstructObject(StaticFindObject('/Script/UMG.TextBlock'),shell:GetOuter())
                            assert(Discovery.valid(star),'dirty star construction failed')
                            local ok,err=pcall(function()
                                star:SetVisibility(2)
                                star:SetFont(row.labelWidget.Font)
                                setText(star,'*')
                                local slot=assert(shell:AddChildToOverlay(star),'dirty star attachment failed')
                                slot:SetHorizontalAlignment(1);slot:SetVerticalAlignment(2)
                                -- Stock DMM labels start at 20px. Use their existing left gutter.
                                slot:SetPadding({Left=4,Top=0,Right=0,Bottom=0})
                            end)
                            if not ok then pcall(star.RemoveFromParent,star);error(err) end
                        end
                        self.records[valueId]=record;byRow[row]=record
                        if row.providerId and record.setting then self.settings[row.providerId..'\0'..record.setting.id]=record end
                        setText(row.valueWidget,clean)
                        render(row.labelWidget,state,displayed(state),shell)
                    end
                end
            end
            self.bound=true
            for primary,peer in pairs(pairsByRow or {}) do
                local a,b=byRow[primary],byRow[peer]
                if a and b then
                    a.peer=b;b.primary=a
                    local _,sa=readMarker(primary.overlay or primary.shell)
                    local _,sb=readMarker(peer.overlay or peer.shell)
                    render(primary.labelWidget,sa,displayed(sa) or displayed(sb),primary.overlay or primary.shell)
                end
            end
            self.routes=routes
        end)
    end
    -- DMM encodes dirty state in the value text. Observe only the rows already
    -- bound on the active settings page; never hook the process-wide SetText path.
    function controller:refresh(host)
        if not self.bound or not self.allowed or self.busy then return 0 end
        local ok,count=protected(function()
            if not self.allowed() or (self.live and not self.live()) then return 0 end
            local resolve=Discovery.routeResolver(host,self.allowed)
            if not resolve then return 0 end
            local refreshed=0
            for _,record in pairs(self.records) do
                if not self.allowed() then return refreshed end
                local widget=resolve(record.value)
                local shell=resolve(record.shell)
                if widget and shell then
                    local marker,state=readMarker(shell)
                    if marker and state then
                        local raw=Discovery.textOf(widget) or ''
                        local dirty,clean=M.signal(raw,record.setting)
                        -- MMD writes the clean value back. Seeing that same clean
                        -- value on the next tick is not a new DMM notification.
                        if raw~=state.lastValue then
                            state.dirty=dirty
                            state.suppressed=dirty and (not self.showDirty or (state.pending~='' and state.pending==clean)
                                or (state.suppressed and state.lastValue==clean))
                            state.pending='';state.lastValue=clean
                            setText(marker,serialized(state));setText(widget,clean)
                            renderRecord(resolve,record)
                        end
                        refreshed=refreshed+1
                    end
                end
            end
            return refreshed
        end)
        return ok and count or 0
    end
    return controller
end
return M
