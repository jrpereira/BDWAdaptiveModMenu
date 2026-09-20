package.path='Scripts/?.lua;'..package.path
local shared,handlers={},{}
ModRef={
 GetSharedVariable=function(_,key) return shared[key] end,
 SetSharedVariable=function(_,key,value) shared[key]=value end,
}
RegisterConsoleCommandHandler=function(command,callback)
 assert(not handlers[command],'duplicate native handler')
 handlers[command]=callback;return true
end
local api=require('settings_api')
assert(api.version==1)
local command='DMM_SettingsApplied_v1_'..('Provider'):gsub('.',function(c) return string.format('%02x',c:byte()) end)
local received={}
local unsubscribe=api.subscribe('Provider',function(event) received[#received+1]=event end)
shared[command..'.data']='1\n4b6579 1 2\n53616d65 4 4\n'
assert(handlers[command]())
assert(#received==1 and received[1].providerId=='Provider' and received[1].revision==1)
assert(received[1].values.Key==2 and received[1].values.Same==4)
assert(received[1].changes.Key.old==1 and received[1].changes.Key.new==2 and received[1].changes.Same==nil)
handlers[command]();assert(#received==1,'duplicate revision delivered twice')
local replacement
api.subscribe('Provider',function(event) replacement=event end)
shared[command..'.data']='2\n4b6579 2 3\n'
handlers[command]();assert(#received==1 and replacement.revision==2 and replacement.values.Key==3)
unsubscribe();shared[command..'.data']='3\n4b6579 3 4\n';handlers[command]()
assert(replacement.revision==3,'obsolete unsubscribe removed the replacement callback')
local stop=api.subscribe('Provider',function(event) replacement=event end)
stop();shared[command..'.data']='4\n4b6579 4 5\n';handlers[command]()
assert(replacement.revision==3,'unsubscribe did not stop delivery')
print('PASS versioned Apply event, duplicate suppression, callback replacement and unsubscribe')
