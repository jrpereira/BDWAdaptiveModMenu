local captured={}
local initialized=false
local originalPrint=print
print=function(value) captured[#captured+1]=value end
package.loaded.registrations={discover=function(log)
    log('DMM_DEPENDENCY_INACTIVE','missing enabled DMM')
    log('DECORATION_SKIPPED','invalid Minimum/Maximum')
    log('REGISTRY','verbose trace')
    return {decorations={}}
end}
package.loaded.dmm_binding={install=function() error('no decorations must not install hooks') end}
package.loaded.init_config={initConfig=function() initialized=true end}
dofile('Scripts/main.lua')
print=originalPrint
assert(#captured==2,'startup failures must be visible without enabling verbose logging')
assert(captured[1]:find('DMM_DEPENDENCY_INACTIVE',1,true))
assert(captured[2]:find('DECORATION_SKIPPED',1,true))
assert(initialized,'configuration initialization must run even without decorations')
print('PASS startup explains missing DMM and invalid decoration metadata without verbose logging')
local installed=false
package.loaded.registrations={discover=function() return {dmmEligible=true,decorations={}} end}
package.loaded.dmm_binding={install=function() installed=true;return true end}
dofile('Scripts/main.lua')
assert(installed,'ordinary settings pages need dirty-label hooks even without key decorations')
print('PASS ordinary settings pages install presentation without key decorations')
