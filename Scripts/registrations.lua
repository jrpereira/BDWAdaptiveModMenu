local M={}
local function trim(s) return (s or ''):match('^%s*(.-)%s*$') end

local function field(t,wanted)
    if type(t)~='table' then return nil end
    local lower=wanted:lower()
    for k,v in pairs(t) do if tostring(k):lower()==lower then return v end end
end

local function child(node,wanted)
    if type(node)~='table' then return nil end
    local target=wanted:lower()
    for key,value in pairs(node) do
        if type(value)=='table' and (tostring(key):lower()==target or tostring(value.__name or ''):lower()==target) then return value end
    end
end

local function read(path)
    local f,err=io.open(path,'rb'); if not f then return nil,err or 'open failed' end
    local data=f:read(262145); f:close()
    if not data then return nil,'read failed' end
    if #data>262144 then return nil,'file exceeds 256 KiB limit' end
    return data:gsub('^\239\187\191','')
end

local function labelsOf(setting)
    local labels={}
    local function add(v) v=trim(v); if v~='' then labels[v]=true end end
    add(field(setting,'Label') or setting.__id)
    for k,v in pairs(setting) do if tostring(k):lower():match('^label%.') then add(v) end end
    return labels
end

local function decorationOf(setting) return trim(field(setting,'Decoration')):lower() end
local function kindOf(setting) return trim(field(setting,'Type')):lower() end
local function dmmKind(kind)
    if kind=='slider' or kind=='integer' or kind=='percent' or kind=='stepped' then return 'slider' end
    if kind=='toggle' then return 'toggle' end
    if kind=='picker' or kind=='preset' then return 'picker' end
    return nil
end

-- Reconstruct the parts of choices.parse() that matter for row identity.
-- DMM preserves supported Setting sections in manifest order.
local function parseManifest(path,content)
    local provider={path=path,settings={},choices={},byId={}}
    local section,current,index=nil,nil,0
    local mod={}
    for raw in (content..'\n'):gmatch('([^\n]*)\n') do
        local line=trim((raw or ''):gsub('\r$',''))
        local header=line:match('^%[([^%]]+)%]%s*$')
        if header then
            section=trim(header); current=nil
            if section:lower()=='mod' then current=mod
            elseif section:lower()=='setting' or section:lower():match('^setting%.') then
                index=index+1; current={__index=index,__section=section}; provider.settings[#provider.settings+1]=current
            end
        elseif current and line~='' and not line:match('^[;#]') then
            local k,v=line:match('^([^=]+)=(.*)$'); if k then current[trim(k)]=trim(v) end
        end
    end
    provider.id=trim(field(mod,'Id')); provider.name=trim(field(mod,'Name'))
    if provider.id=='' then return nil,'missing [Mod] Id' end
    if provider.name=='' then provider.name=provider.id end

    local ids={}
    for _,s in ipairs(provider.settings) do
        local id=trim(field(s,'Id')); s.__id=(id~='' and id or ('setting_'..s.__index))
        if ids[s.__id] then return nil,'duplicate setting Id '..s.__id end
        ids[s.__id]=true; provider.byId[s.__id]=s
        local kind=dmmKind(kindOf(s))
        if kind then
            provider.choices[#provider.choices+1]={
                id=s.__id, kind=kind, labels=labelsOf(s), raw=s, sourceIndex=s.__index,
            }
        end
    end
    return provider
end

local function fileNodePath(file)
    if type(file)=='table' then
        local name=tostring(file.__name or ''); local path=file.__absolute_path
        if name:lower()=='mod_settings.ini' and type(path)=='string' and path~='' then return path end
    elseif type(file)=='string' and file:lower():match('mod_settings%.ini$') then return file end
end

local function collectManifestPaths(node,paths,seen)
    local function add(file)
        local path=fileNodePath(file)
        if not path or path=='' then return end
        local key=path:lower()
        if seen[key] then return end
        seen[key]=true; paths[#paths+1]=path
    end
    add(node)
    for _,file in pairs(type(node.__files)=='table' and node.__files or {}) do add(file) end
end

function M.discover(log)
    local result={decorations={},byProvider={},providerModels={},providerList={},providers=0,manifests=0,modes=0}
    if type(IterateGameDirectories)~='function' then log('REGISTRY_UNAVAILABLE','IterateGameDirectories unavailable'); return result end
    local ok,tree=pcall(IterateGameDirectories)
    if not ok or type(tree)~='table' then log('REGISTRY_UNAVAILABLE','IterateGameDirectories failed: '..tostring(tree)); return result end

    local game=child(tree,'Game')
    if not game then for _,candidate in pairs(tree) do if type(candidate)=='table' and child(candidate,'Binaries') then game=candidate; break end end end
    local binaries=child(game,'Binaries'); local win64=child(binaries,'Win64'); local ue4ss=child(win64,'ue4ss') or child(win64,'UE4SS'); local mods=child(ue4ss,'Mods')
    if not mods then log('REGISTRY_UNAVAILABLE','Mods directory unavailable'); return result end

    -- Loader eligibility, not proof of runtime initialization. Never search an
    -- archived/nested folder for the DMM dependency or start UI work without it.
    local function fileNamed(node,wanted)
        for _,file in pairs(type(node)=='table' and node.__files or {}) do
            if type(file)=='table' and tostring(file.__name):lower()==wanted:lower() then return file end
        end
    end
    local flags={}
    local modsFile=fileNamed(mods,'mods.txt')
    if modsFile and modsFile.__absolute_path then
        local contents=read(modsFile.__absolute_path)
        for line in ((contents or '')..'\n'):gmatch('([^\n]*)\n') do
            local name,on=trim(line):match('^([^;#][^:]-)%s*:%s*([01])%s*[;#]?.*$')
            if name then flags[trim(name):lower()]=on=='1' end
        end
    end
    local function enabled(node,name)
        return fileNamed(node,'enabled.txt')~=nil or flags[name:lower()]==true
    end
    local dmm=child(mods,'DawnwalkerModMenu')
    result.dmmEligible=dmm~=nil and enabled(dmm,'DawnwalkerModMenu')
        and fileNamed(child(dmm,'Scripts'),'main.lua')~=nil
    if not result.dmmEligible then
        log('DMM_DEPENDENCY_INACTIVE','no enabled direct Mods/DawnwalkerModMenu with Scripts/main.lua; no UI discovery installed')
        return result
    end

    local paths,seen={},{}
    for name,node in pairs(mods) do
        if name~='__files' and type(node)=='table' and enabled(node,tostring(node.__name or name)) then
            collectManifestPaths(node,paths,seen)
        end
    end
    table.sort(paths)

    for _,path in ipairs(paths) do
        local content,readErr=read(path)
        if not content then log('MANIFEST_READ_FAILED',path..': '..tostring(readErr))
        else
            local provider,parseErr=parseManifest(path,content)
            if not provider then log('MANIFEST_PARSE_FAILED',path..': '..tostring(parseErr))
            elseif result.providerModels[provider.id] then
                -- DMM sorts manifest paths and keeps the first provider for each Id.
                -- Skip the entire duplicate, including settings with different Ids.
                log('DUPLICATE_PROVIDER_SKIPPED',path..': duplicate Mod Id '..provider.id)
            else
                result.manifests=result.manifests+1; result.providers=result.providers+1
                result.providerModels[provider.id]=provider; result.providerList[#result.providerList+1]=provider
                for _,setting in ipairs(provider.settings) do
                    local decoration=decorationOf(setting)
                    if decoration=='keybind' then
                        local kind=kindOf(setting)
                        if kind=='integer' or kind=='slider' then
                            local minimum=tonumber(field(setting,'Minimum')); local maximum=tonumber(field(setting,'Maximum'))
                            if minimum and maximum and minimum<maximum then
                                local d={providerId=provider.id,providerName=provider.name,settingId=setting.__id,type='keybind',minimum=minimum,maximum=maximum,labels=labelsOf(setting),path=path}
                                local pairId=trim(field(setting,'Pair'))
                                if pairId=='' then pairId=setting.__id..'Mode' end
                                local mode=provider.byId[pairId]
                                if mode and decorationOf(mode)=='keybind' and kindOf(mode)=='picker' then
                                    d.modeId=mode.__id; d.modeLabels=labelsOf(mode); d.modeType='picker'; result.modes=result.modes+1
                                    d.modeOptions={}
                                    for label in ((field(mode,'PresetLabels') or field(mode,'PresetValues') or '')..'|'):gmatch('(.-)|') do
                                        d.modeOptions[#d.modeOptions+1]=trim(label)
                                    end
                                    if #d.modeOptions==0 then d.modeOptions={''} end
                                end
                                result.decorations[#result.decorations+1]=d
                                result.byProvider[provider.id]=result.byProvider[provider.id] or {}; result.byProvider[provider.id][d.settingId]=d
                            else log('DECORATION_SKIPPED',provider.id..'.'..setting.__id..': keybind requires valid Minimum/Maximum') end
                        end
                    end
                end
            end
        end
    end
    return result
end

function M.get(registry,providerId,settingId)
    local provider=registry.byProvider and registry.byProvider[providerId]; return provider and provider[settingId] or nil
end
return M
