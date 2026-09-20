package.path='Scripts/?.lua;'..package.path
local M=require('mapped_presets')
local choices={}
function choices.index(s,v)
    if s.kind=='slider' then return type(v)=='number' and v>=s.minimum and v<=s.maximum end
    for i,value in ipairs(s.values) do if value==v then return i end end
end
function choices.snap(s,v) return math.floor(v+0.5) end
function choices.format(s,v) return s.kind=='slider' and tostring(v) or s.labels[choices.index(s,v)] end
local function items()
    return {
        {id='Preset',kind='picker',values={0,1,2},labels={'Custom','Reduced','Numbers'},default=1},
        {id='Key',kind='slider',minimum=0,maximum=255,step=1,default=82},
        {id='Mode',kind='picker',values={0,1},labels={'Tap','Hold'},default=0},
    }
end
local schema=[[
[Setting.Preset]
Id=Preset
MappedPresetTargets=Key|Mode
MappedPresetValues=1:82|0;2:49|1
CustomValue=0
]]
local function fail(fn,pattern)
    local ok,err=pcall(fn);assert(not ok and tostring(err):find(pattern,1,true),tostring(err))
end
local parsed=M.parse(schema,items(),choices)
assert(parsed[1].ammMapping.values[2][1]==49)
fail(function() M.parse(schema:gsub('Key|Mode','Key|Key'),items(),choices) end,'overlapping')
fail(function() M.parse(schema:gsub('49|1','999|1'),items(),choices) end,'outside')
fail(function() M.parse(schema:gsub(';2:49|1',''),items(),choices) end,'missing mapped')
fail(function() M.parse(schema:gsub('49|1','49'),items(),choices) end,'count differs')
fail(function() M.parse(schema:gsub('Key|Mode','Unknown|Mode'),items(),choices) end,'unknown mapped')

local function model(saved)
    local m={items=M.parse(schema,items(),choices),pending={},committed={}}
    for i,s in ipairs(m.items) do m.pending[i]=(saved or {})[i] or s.default;m.committed[i]=m.pending[i] end
    function m:set(i,v)
        if self.failSet==i then error('injected setter failure') end
        if choices.index(self.items[i],v) then self.pending[i]=v end
    end
    function m:dirty() for i,v in ipairs(self.pending) do if v~=self.committed[i] then return true end end;return false end
    function m:restore() for i,v in ipairs(self.committed) do self.pending[i]=v end end
    function m:reset(i)
        if i then self:set(i,self.items[i].default)
        else for n,s in ipairs(self.items) do self.pending[n]=s.default end end
    end
    function m:apply()
        if self.failApply then return false,'disk denied' end
        local event={values={},changes={}}
        for i,s in ipairs(self.items) do
            event.values[s.id]=self.pending[i]
            if self.pending[i]~=self.committed[i] then event.changes[s.id]={old=self.committed[i],new=self.pending[i]} end
            self.committed[i]=self.pending[i]
        end
        return true,nil,event
    end
    return M.wrap(m,choices)
end
local m=model()
m:set(1,2)
assert(m.pending[1]==2 and m.pending[2]==49 and m.pending[3]==1 and m:dirty())
assert(m.committed[2]==82 and m.ammHiddenDirty[2] and m.ammHiddenDirty[3])
m:set(2,50)
assert(m.pending[1]==0 and m.pending[2]==50 and m.pending[3]==1)
assert(not m.ammHiddenDirty[2] and m.ammHiddenDirty[3],'Manual edits must retain untouched preset suppression')
m:set(2,49)
assert(m.pending[1]==2 and m.ammHiddenDirty[2],'Returning to the visual baseline restores its preset and hides its marker')
m:restore();assert(not m:dirty() and m.pending[2]==82 and next(m.ammHiddenDirty)==nil)
m:set(1,2);m.failApply=true
local ok,err=m:apply();assert(not ok and err=='disk denied' and m:dirty() and m.ammHiddenDirty[2])
m.failApply=false
local _,_,event=m:apply()
assert(not m:dirty() and event.values.Key==49 and event.changes.Mode.new==1)
assert(next(m.ammHiddenDirty)==nil)
local reopened=model(m.committed);assert(reopened.pending[1]==2 and reopened.pending[2]==49 and not reopened:dirty())
reopened:reset();assert(reopened.pending[1]==1 and reopened.pending[2]==82 and reopened:dirty())
local inconsistent=model({1,50,1})
assert(inconsistent.pending[1]==0 and inconsistent.pending[2]==50 and inconsistent.committed[1]==1)
m=model();m:set(1,2);m:set(1,0)
assert(m.pending[1]==2 and m.pending[2]==49 and m.ammHiddenDirty[2],'Custom cannot be selected manually')
m:change(1,1);assert(m.pending[1]==1)
m:change(1,1);assert(m.pending[1]==1,'Navigation skips Custom')
assert(M.wrap(m,choices)==m)
local failed=model();failed.failSet=3
fail(function() failed:set(1,2) end,'injected setter failure')
assert(failed.pending[1]==1 and failed.pending[2]==82 and failed.pending[3]==0)
assert(not failed:dirty() and next(failed.ammHiddenDirty)==nil)
assert(failed:showDirty(false)==true,'failed expansion must restore showDirty')
failed:showDirty(true);failed.failSet=nil;failed:set(1,2)
assert(failed.pending[2]==49 and failed.pending[3]==1)

-- The UI wrapper invalidates only presentation caches when suppression changes.
choices.parse=function() return items() end
choices.open=function() return model() end
local emitted={}
local controls={build=function(_,_,api)
    local ui={active=1,model=model(),panels={{rows={{value={}},{value={}},{value={}}}}}}
    function ui:refresh()
        for i,row in ipairs(self.panels[1].rows) do
            local text=choices.format(self.model.items[i],self.model.pending[i])..(self.model.pending[i]~=self.model.committed[i] and ' *' or '')
            if row.renderText~=text then api.setText(row.value,text);row.renderText=text end
            row.rendered=true
        end
    end
    return ui
end}
assert(M.install(choices,controls));assert(not M.install(choices,controls))
local ui=controls.build(nil,{}, {setText=function(widget,text) emitted[widget]=text end})
ui.model:set(1,2);ui:refresh()
assert(emitted[ui.panels[1].rows[2].value]=='49')
assert(ui.model.committed[2]==82,'presentation must not alter committed values')
ui.model:set(2,50);ui:refresh()
assert(emitted[ui.panels[1].rows[2].value]=='50 *' and emitted[ui.panels[1].rows[3].value]=='Hold')
ui.model:set(2,82);ui:refresh()
assert(emitted[ui.panels[1].rows[2].value]=='82 *','A manual change from preset baseline stays marked even at its committed value')
ui.model:restore();ui:refresh();assert(emitted[ui.panels[1].rows[3].value]=='Tap')
print('PASS mapped preset validation, atomic model expansion, Custom, Apply/Restore/reopen and suppression refresh')
