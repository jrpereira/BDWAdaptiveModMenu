local captured={}
local installed=false
local originalPrint=print
print=function(value) captured[#captured+1]=value end
package.loaded.dmm_binding={install=function() installed=true;return true end}
package.loaded.dmm_bootstrap={run=function(log) log('DMM_REQUIRED','missing DMM') end}
dofile('Scripts/main.lua')
print=originalPrint
assert(#captured==1 and captured[1]:find('DMM_REQUIRED',1,true))
assert(not installed,'DMM readiness must gate AMM initialization')
print('PASS startup explains missing DMM and remains inactive')
package.loaded.dmm_binding={install=function() installed=true;return true end}
package.loaded.dmm_bootstrap={run=function(_,start) return start() end}
dofile('Scripts/main.lua')
assert(installed,'ready DMM handshake must initialize presentation')
print('PASS ready DMM handshake initializes presentation')
