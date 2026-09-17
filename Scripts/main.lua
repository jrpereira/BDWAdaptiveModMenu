local VERSION='0.1.13'
local Registrations=require('registrations')
local Binding=require('dmm_binding')
local function log(event,detail) print(string.format('[ModMenuDecorator] %s %s\n',event,detail or '')) end
log('LOAD',VERSION)
local registry=Registrations.discover(log)
log('REGISTRY',string.format('%d keybind primary(s), %d paired mode(s), %d manifest(s)',#registry.decorations,registry.modes or 0,registry.manifests or 0))
if #registry.decorations==0 then return end
local ok,err=Binding.install(registry,log)
if not ok then log('DMM_BINDING_UNAVAILABLE',tostring(err)); return end
log('READY','manifest-order DMM page binding installed')
