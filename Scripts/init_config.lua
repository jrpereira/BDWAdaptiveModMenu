-- Startup-only compatibility for DMM's existing-file configuration contract.
-- DMM still owns pending values, Apply, Reset and Restore.
local M={}
local LIMIT=1048576
local function trim(s) return s:match('^%s*(.-)%s*$') end

M.fs={}
function M.fs.read(path)
    local f,err,code=io.open(path,'rb')
    if not f then
        -- Do not mistake denied access or an I/O error for a missing file.
        if code==2 then return nil end
        error(err or ('cannot read '..path))
    end
    local text,why=f:read(LIMIT+1)
    local closed,closeError=f:close()
    assert(text and closed,why or closeError or 'read failed')
    assert(#text<=LIMIT,'config exceeds 1 MiB')
    return text
end
function M.fs.write(path,text)
    local f,err=io.open(path,'wb'); assert(f,err)
    local wrote,why=f:write(text)
    local closed,closeError=f:close()
    assert(wrote and closed,why or closeError or 'write failed')
end
function M.fs.rename(a,b) local ok,err=os.rename(a,b); assert(ok,err) end
function M.fs.remove(path) local ok,err=os.remove(path); assert(ok,err) end

local function configPath(manifest,setting)
    local f=setting.file
    assert(type(f)=='string' and #f>0 and #f<=240,'choice requires ConfigFile')
    f=f:gsub('\\','/')
    assert(not f:find('[:%c<>"|?*]') and not f:match('^/') and not f:match('/$'),'invalid ConfigFile')
    for part in (f..'/'):gmatch('(.-)/') do
        assert(part~='' and part~='.' and part~='..' and not part:match('[ .]$'),'invalid ConfigFile component')
        local stem=part:match('^[^.]+'):upper()
        assert(stem~='CON' and stem~='PRN' and stem~='AUX' and stem~='NUL'
            and not stem:match('^COM[1-9]$') and not stem:match('^LPT[1-9]$'),'reserved ConfigFile component')
    end
    -- Automatic creation is deliberately restricted to INI data, never code.
    assert(f:lower():match('%.ini$') and not f:lower():match('mod_settings%.ini$'),'ConfigFile must name a configuration INI')
    local base=assert(manifest:match('^(.*)[/\\][^/\\]+$'),'provider directory unavailable')
    return base..'/'..f
end

local function validateName(value,label)
    assert(type(value)=='string' and value~='' and value==trim(value)
        and not value:find('[%c%[%]=;#]'), 'invalid '..label)
end
local function number(value,label)
    local n=tonumber(value)
    assert(n and n==n and math.abs(n)<=1000000000,'invalid numeric '..label)
    return n
end
local function reference(value,label)
    local section,key=value:match('^([^/]+)/([^/]+)$')
    validateName(section,label..' section');validateName(key,label..' key')
    return section..'\0'..key
end

function M.overlay(defaults,existing)
    local merged={}
    for key,value in pairs(defaults) do merged[key]=value end
    for key,value in pairs(existing) do merged[key]=value end
    return merged
end

function M.defaultSources(manifest,settings)
    local byId,seen,current,count={},{},nil,0
    local rules,names={},{}
    for _,setting in ipairs(settings) do
        if setting.id then byId[setting.id]=setting end
        setting.ammDefaultFrom=nil;setting.ammDefaultMap=nil;setting.ammDefaultRules=nil
    end
    local function finish()
        if not current then return end
        if current.rule then
            assert(not names[current.rule],'duplicate DefaultRule section')
            names[current.rule]=true;rules[#rules+1]=current;return
        end
        local id=current.Id or 'setting_'..count
        local setting=byId[id]
        if setting and not seen[id] then
            seen[id]=true
            if current.DefaultFrom then
                validateName(current.DefaultFrom,'DefaultFrom')
                assert(setting.section,'DefaultFrom requires explicit ConfigSection')
                setting.ammDefaultFrom=current.DefaultFrom
                if current.DefaultFromMap then
                    local map={}
                    for entry in (current.DefaultFromMap..';'):gmatch('(.-);') do
                        local a,b=entry:match('^%s*([^:]+):([^:]+)%s*$')
                        local source=number(a,'DefaultFromMap source')
                        assert(map[source]==nil,'duplicate DefaultFromMap source')
                        map[source]=number(b,'DefaultFromMap destination')
                    end
                    setting.ammDefaultMap=map
                end
            else
                assert(not current.DefaultFromMap,'DefaultFromMap requires DefaultFrom')
            end
        end
    end
    for line in (manifest..'\n'):gmatch('([^\n]*)\n') do
        local header=trim(line):match('^%[([^%]]+)%]$')
        if header then
            finish();current=nil
            if header=='Setting' or header:match('^Setting%.') then count=count+1;current={} end
            if header:match('^DefaultRule%.') then current={rule=header} end
        elseif current and not trim(line):match('^[;#]') then
            local key,value=line:match('^%s*([^=]+)=(.*)$')
            if key then
                key=trim(key)
                assert(key~='rule','reserved migration field')
                if current.rule or key=='DefaultFrom' or key=='DefaultFromMap' then
                    assert(current[key]==nil,'duplicate migration field '..key)
                end
                current[key]=trim(value)
            elseif current.rule and trim(line)~='' then error('malformed DefaultRule field') end
        end
    end
    finish()
    for _,raw in ipairs(rules) do
        local setting=assert(byId[raw.Target],'unknown DefaultRule target')
        assert(setting.section,'DefaultRule requires explicit ConfigSection')
        assert(not setting.ammDefaultFrom,'DefaultRule and DefaultFrom cannot share a target')
        local fields={rule=true,Target=true,SourceSection=true,SourceKey=true,SourceDefault=true,WhenAbsent=true,WhenZero=true}
        for field in pairs(raw) do assert(fields[field],'unknown DefaultRule field '..field) end
        validateName(raw.SourceSection,'source section');validateName(raw.SourceKey,'source key')
        local rule={source=raw.SourceSection..'\0'..raw.SourceKey}
        if raw.SourceDefault then rule.default=number(raw.SourceDefault,'SourceDefault') end
        if raw.WhenAbsent then rule.absent=reference(raw.WhenAbsent,'WhenAbsent') end
        if raw.WhenZero then rule.zero=reference(raw.WhenZero,'WhenZero') end
        setting.ammDefaultRules=setting.ammDefaultRules or {}
        assert(#setting.ammDefaultRules<32,'too many DefaultRules per setting')
        table.insert(setting.ammDefaultRules,rule)
    end
end

-- Preserve all original bytes. Insert only absent declared assignments into
-- their section (or the global section for an unqualified missing key).
function M.merge(original,settings,choices)
    local text=original or ''
    assert(not text:find('[%z\1-\8\11\12\14-\31\127]'),'invalid config control character')
    assert(not text:match('^\239\187\191'),'DMM does not support a config BOM')
    local entries,sections={}, {['']={finish=#text+1}}
    local section,offset='',1
    for full in (text..'\n'):gmatch('([^\n]*\n)') do
        local line=full:gsub('\r?\n$','')
        local clean=trim(line)
        if clean~='' and not clean:match('^[;#]') then
            local header=clean:match('^%[([^%]]+)%]$')
            if header then
                header=trim(header);validateName(header,'config section')
                assert(not sections[header],'duplicate config section '..header)
                sections[section].finish=offset
                sections[header]={finish=#text+1};section=header
            else
                local key,value=line:match('^%s*([^=]+)=(.*)$')
                assert(key,'malformed config line')
                key=trim(key);validateName(key,'config key')
                entries[#entries+1]={key=key,section=section,value=trim(value:match('^[^;#]*'))}
            end
        end
        offset=offset+#full
    end
    local defaults,existing,targets,addresses={},{},{},{}
    for _,entry in ipairs(entries) do
        local target=entry.section..'\0'..entry.key
        assert(existing[target]==nil,'duplicate config key '..entry.key)
        existing[target]=entry.value
    end
    for _,setting in ipairs(settings) do
        validateName(setting.key,'ConfigKey')
        if setting.section~=nil then validateName(setting.section,'ConfigSection') end
        assert(choices.index(setting,setting.default),'invalid schema default')
        local found
        for i,entry in ipairs(entries) do
            if entry.key==setting.key and (setting.section==nil or setting.section==entry.section) then
                assert(not found,'duplicate or ambiguous config key '..setting.key)
                found=i
            end
        end
        local targetSection=found and entries[found].section or setting.section or ''
        local target=targetSection..'\0'..setting.key
        assert(not targets[target],'multiple settings target one config key')
        targets[target]=true
        local default=setting.default
        local migrated=false
        if existing[target]==nil and setting.ammDefaultFrom then
            local source=existing[targetSection..'\0'..setting.ammDefaultFrom]
            if source~=nil then
                default=number(source,'DefaultFrom source')
                if setting.ammDefaultMap then default=assert(setting.ammDefaultMap[default],'unmapped DefaultFrom value') end
                migrated=true
            end
        end
        if existing[target]==nil then
            for _,rule in ipairs(setting.ammDefaultRules or {}) do
                local matches=not rule.absent or existing[rule.absent]==nil
                if matches and rule.zero then
                    local value=existing[rule.zero]
                    value=value~=nil and number(value,'WhenZero source') or 0
                    assert(value==math.floor(value),'WhenZero requires an integer')
                    matches=value==0
                end
                if matches then
                    local value=existing[rule.source]
                    if value~=nil then value=number(value,'DefaultRule source') else value=rule.default end
                    if value~=nil then default=value;migrated=true;break end
                end
            end
        end
        if migrated then
            assert(choices.index(setting,default),'DefaultFrom value outside destination range')
            if choices.snap and setting.kind=='slider' then
                assert(math.abs(choices.snap(setting,default)-default)<0.000001,'DefaultFrom value is off step')
            end
        end
        defaults[target]=string.format('%.17g',default)
        addresses[#addresses+1]={target=target,section=targetSection,key=setting.key}
    end
    -- Merge precedence is unconditional. Schema validity is checked separately
    -- by DMM in plan(), never by substituting defaults for user values.
    local merged=M.overlay(defaults,existing)
    local additions,order={},{}
    for _,address in ipairs(addresses) do
        -- Serialization only: existing assignments retain their original bytes.
        if existing[address.target]==nil then
            local targetSection=address.section
            if not additions[targetSection] then additions[targetSection]={};order[#order+1]=targetSection end
            additions[targetSection][#additions[targetSection]+1]=address.key..'='..merged[address.target]
        end
    end
    local newline=text:find('\r\n',1,true) and '\r\n' or '\n'
    local inserts={}
    local tail=''
    for _,name in ipairs(order) do
        local body=table.concat(additions[name],newline)..newline
        if sections[name] then
            local at=sections[name].finish
            if at>1 and text:sub(at-1,at-1)~='\n' then body=newline..body end
            inserts[#inserts+1]={at=at,text=body}
        else
            tail=tail..'['..name..']'..newline..body
        end
    end
    table.sort(inserts,function(a,b) return a.at>b.at end)
    for _,insert in ipairs(inserts) do text=text:sub(1,insert.at-1)..insert.text..text:sub(insert.at) end
    if tail~='' then
        if text~='' and text:sub(-1)~='\n' then text=text..newline end
        text=text..tail
    end
    assert(#text<=LIMIT,'merged config exceeds 1 MiB')
    return text
end

-- Windows rename refuses an existing destination. Preserve recovery files if
-- rollback cannot safely restore the original; never overwrite a new file.
function M.commit(plan,fs)
    if plan.original==plan.content then return false end
    local path=plan.path
    local tmp,backup=path..'.amm-init.tmp',path..'.amm-init.bak'
    for _,suffix in ipairs({'.amm-init.tmp','.amm-init.bak','.dmm-toggle.tmp','.dmm-toggle.bak'}) do
        assert(fs.read(path..suffix)==nil,'previous config transaction needs review: '..path..suffix)
    end
    assert(fs.read(path)==plan.original,'config changed before initialization')
    local staged,stageError=pcall(function()
        fs.write(tmp,plan.content)
        assert(fs.read(tmp)==plan.content,'temporary write verification failed')
        assert(fs.read(path)==plan.original,'config changed during initialization')
    end)
    if not staged then
        pcall(fs.remove,tmp)
        error(stageError)
    end
    local moved=false
    local installed,installError=pcall(function()
        if plan.original~=nil then
            fs.rename(path,backup);moved=true
            assert(fs.read(backup)==plan.original,'config changed during replacement')
        end
        assert(fs.read(path)==nil,'config appeared during initialization')
        fs.rename(tmp,path)
    end)
    if not installed then
        if moved then
            local restored,restoreError=pcall(function()
                assert(fs.read(path)==nil,'destination occupied')
                fs.rename(backup,path)
            end)
            if not restored then error(tostring(installError)..'; rollback failed: '..tostring(restoreError)..'; original backup: '..backup) end
        end
        pcall(fs.remove,tmp)
        error(installError)
    end
    if moved then fs.remove(backup) end
    return true
end

function M.plan(provider,manifest,choices,fs,settings)
    settings=settings or choices.parse(manifest:gsub('^\239\187\191',''))
    M.defaultSources(manifest,settings)
    if #settings==0 then return nil end
    local path
    for _,setting in ipairs(settings) do
        local target=configPath(provider.path,setting)
        assert(not path or target==path,'DMM requires one config file per provider')
        path=target
    end
    local original=fs.read(path)
    local content=M.merge(original,settings,choices)
    -- Validate the result through DMM itself before any filesystem mutation.
    -- This module instance is private, never DMM's live require() state.
    local saved=choices.fs
    choices.fs={read=function(requested) assert(requested==path,'unexpected DMM config path');return content end}
    local ok,model=pcall(choices.open,{id=provider.id,path=provider.path,choices=settings})
    choices.fs=saved
    assert(ok,model)
    assert(not model.error,model.error)
    return {path=path,original=original,content=content}
end

-- Runs in DMM's own Lua state. Keep migration failures on DMM's existing error
-- path, where set/reset/apply are disabled, instead of opening writable defaults.
function M.install(choices,fs)
    if choices.ammConfigVersion then return false end
    fs=fs or M.fs
    local parse,open=choices.parse,choices.open
    local planning=false
    choices.parse=function(content)
        local settings=parse(content)
        if settings[1] and (content:match('DefaultFrom%s*=') or content:match('DefaultFromMap%s*=') or content:match('%[DefaultRule%.')) then
            settings[1].ammMigrationDeclared=true
        end
        return settings
    end
    choices.open=function(provider)
        if planning or provider.testOnly or not (provider.choices and provider.choices[1]) then
            return open(provider)
        end
        local ok,err=pcall(function()
            local manifest=assert(fs.read(provider.path),'configuration metadata unavailable')
            planning=true
            local planned,plan=pcall(M.plan,provider,manifest,choices,fs,provider.choices)
            planning=false
            assert(planned,plan)
            if plan then M.commit(plan,fs) end
        end)
        planning=false
        local model=open(provider)
        if not ok then model.error='Configuration initialization failed; settings unavailable: '..tostring(err) end
        return model
    end
    choices.ammConfigVersion=1
    return true
end
return M
