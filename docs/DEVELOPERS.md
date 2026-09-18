# Integrating ModMenuDecorator

ModMenuDecorator replaces explicitly marked Dawnwalker Mod Menu (DMM) numeric key
controls with key-capture controls. An optional mode picker is displayed on the same
row. Your mod continues to own its configuration and gameplay behavior; DMM owns
pending edits, dirty state, Apply, saving, Reset, and Restore.

The decorator does **not** register gameplay bindings, implement Tap/Hold timing,
or depend on UE4SSLuaEventBridge. A provider such as ExtendedControls uses the bridge
separately. Choosing a key in the menu only changes a setting.

## Requirements and installation

The current implementation targets Dawnwalker with UE4SS/Lua 5.4 and the tested DMM
widget layout. It is not a generic settings framework for every Unreal game or DMM
version. Install DMM and ModMenuDecorator as separate UE4SS mods. Do not copy DMM
source into your mod. The decorator package retains the directory name
`ModMenuDecorator` even though this repository is named `BDWModMenuDecorator`.

Your provider folder needs `mod_settings.ini` and its own configuration file, for example:

```text
Mods/
  DawnwalkerModMenu/
  ModMenuDecorator/
    enabled.txt
    Scripts/main.lua
  ExampleMod/
    enabled.txt
    mod_settings.ini
    config.ini
    Scripts/main.lua
```

Supply real config keys on first installation; do not rely on metadata defaults to
create keys in an existing config. Restart after adding/changing manifest metadata:
discovery runs at decorator startup and is not a manifest hot-reload API.

## Minimal integration

Copy the complete [example manifest](../examples/ExampleMod/mod_settings.ini) into
your provider and adapt its IDs, labels, config paths and defaults. The matching
[example config](../examples/ExampleMod/config.example.ini) starts with Q + Tap.
For that example, copy it to `config.ini` in the provider folder.

The key row's essential fields are:

```ini
[Setting.Interact]
Id = Interact
Type = integer
Decoration = keybind
Label = Interact key
Group = Controls
ConfigFile = config.ini
ConfigSection = Bindings
ConfigKey = Interact
Minimum = 0
Maximum = 254
Step = 1
Default = 81
```

The stored number is a Windows virtual-key code, not an Unreal FKey name or scan
code. `81` is Q; `0` means unbound. Use the 0–254 range and integer steps for this
representation. The registry accepts numeric `integer` or `slider` rows with valid
Minimum/Maximum, but capture only supports the mappings in
[key_codes.lua](../Scripts/key_codes.lua). Numeric range membership alone does not
make every key supported. Escape is reserved for cancellation; modifier chords and
gamepad capture are disabled. Unsupported captured keys are rejected rather than
silently substituted.

## Pairing a mode picker

Add a picker with `Id = InteractMode` and **its own** `Decoration = keybind`:

```ini
[Setting.InteractMode]
Id = InteractMode
Type = picker
Decoration = keybind
Label = Interact mode
Group = Controls
ConfigFile = config.ini
ConfigSection = Bindings
ConfigKey = InteractMode
PresetValues = 0|1
PresetLabels = Tap|Hold
Default = 0
```

By convention a primary ID `Interact` pairs with `InteractMode`. Keep these rows
adjacent and in the same group. IDs, not displayed labels, identify the settings.
The implementation also reads an optional `Pair = OtherModeId` on the primary row,
but the suffix convention is sufficient and is what ExtendedControls uses.

A picker without explicit decoration remains a stock control. No mode row is
required for a standalone keybind. Use matching ordered `PresetValues` and
`PresetLabels`; the provider defines their meaning. Tap and Hold are example labels,
not behavior supplied by the decorator. Your provider must interpret `InteractMode`
and apply it to its input implementation.

## Apply and persistence contract

1. Native capture updates the selector's reflected `SelectedKey` property.
2. The decorator converts the FKey name to the stored numeric representation and
   writes the stock numeric slider once.
3. DMM ingests that change, marks it dirty, and enables its normal Apply action.
4. The decorator mirrors the stock value and DMM's dirty label, without waiting for acknowledgement or retrying submission.
5. DMM saves on Apply; your provider must reload the saved config and update gameplay.

Do not save directly from the decorator or bypass DMM's pending state. Escape
cancels capture and should preserve both the previous key and any earlier unsaved
changes. A key write is submitted once: Restore/Reset must be able to
supersede it. Seeing a new key label alone is not proof that DMM ingested or saved it.

## Discovery and layout constraints

Discovery scans `mod_settings.ini` files in enabled direct mod folders in the UE4SS Mods tree exposed by
`IterateGameDirectories`; individual manifests are limited to 256 KiB. Give every
provider a unique `[Mod] Id` and every setting an explicit unique `Id`.
Manifest paths are sorted; the first parsed provider for a Mod Id wins, and later
duplicates are skipped in full with a startup diagnostic, matching DMM's duplicate policy.

The current page matcher requires one unambiguous provider with the same supported
row count, order, widget kinds, and labels as the visible DMM page. Localized `Label.*`
values are considered. Ambiguous or mismatched pages are rejected rather than
decorating guessed rows. Changes to DMM hierarchy, dynamically hidden rows, or
unrecognized setting types can therefore require compatibility work.

Decoration uses proxy widgets while retaining stock controls as backing state.
UObject work is dispatched to the game thread. Do not import this mod's internal Lua
modules from a provider: there is no stable public Lua registration API; manifest
metadata is the integration surface.

## Release logging and integration checklist

`UE4SS.log` contains one ready message plus actionable failures under `[ModMenuDecorator]`.
Verbose construction, binding and capture traces are removed; there is no debug-mode toggle.
Discovery runs once per coalesced activation/page-switch burst, deferred until DMM completes row construction. WidgetSwitcher traversal follows only selected children, while preserving collapsed backing controls within the selected provider. A second traversal is needed only after constructing controls.
There is no periodic tree scan or timed discovery retry. An unmatched browser immediately becomes dormant; selecting a provider wakes it through
the host-owned WidgetSwitcher event, without background retry timers.
Control synchronization remains at 100 ms within that scope and stops when no usable controls remain, using fresh child-path traversal
from the current host root rather than repeated global lookups for each control. Each eligible update performs exact owner/host lookups; there is no global widget enumeration
or permanently running discovery timer. Closing/loading revokes deferred work;
obsolete queued callbacks drain without UObject access or rescheduling.
Picker clicks use a menu-scoped OnClicked relay on owned proxy buttons and are queued
until the next update. No press-state sampling is used. Basic native click delivery passed earlier checks; current lifecycle integration still needs
in-game validation; failed event attachment leaves the stock mode row available.

Before releasing your integration, test a key-only change, a mode-only change,
the dirty marker and Apply, persistence after reopening/restarting, clean and
already-dirty Escape cancellation, Reset/Restore, unrelated settings pages, and
the provider's actual gameplay behavior after Apply. Test transparent surfaces and
longest mode labels in the real UI. Automated mocks cannot validate those native paths.

## Known limitation: Delete

Delete-to-clear and its footer hint are not implemented. DMM separately
routes Delete to Reset through both Lua and CommonUI. Adding a second callback that
sets zero can race with Reset. Zero remains the unbound representation, but an
exclusive Delete input route is still required before advertising this shortcut.


## Menu scope and row ownership (0.1.29)

Decoration requires a visible, active main/pause-menu owner and fresh owner validation on each update. If activation was missed, a host/page event can recover the owner using the same two owner classes as DMM. Loading cancels queued work without a sticky wait-for-reactivation flag. A lifecycle callback exception cancels the current scope; the next valid event can recover. Hook installation failure still disables the mod. Actionable errors include the setting and original failure reason; disabled controls report once.

A collapsed TextBlock inside the key overlay stores versioned scalar control state. Every created widget uses the row's WidgetTree as outer and attaches beneath its surface. Row presence determines decoration presence. Reopening an intact page adopts the existing subtree and reconnects click routing without adding another native delegate. A new row has no marker and receives a new decoration. No persistent host/row decorated registry or partial-child repair scan exists.

Lua bindings and primitive traversal routes are temporary, discarded on scope changes. They support active input updates and never determine whether a row has been decorated. Capture/presentation state is compared with the last successfully saved scalars in the temporary binding; unchanged state is neither serialized nor written. Persistent state remains on the row. Pending click delivery is transient and cleared on scope changes. Construction failures roll back mutations; repeated update failures stop that control until the next page event rather than dismantling its decoration. Attached widgets leave the page with their row; final UObject reclamation follows Unreal garbage collection.

## Optional live inspection helper — UEBridge

UE4SS Bridge – Live Lua MCP (littleRabbit94/ue4ss-bridge, Nexus mod 198) is an optional development/debugging helper, separate from UE4SSLuaEventBridge. ModMenuDecorator must work fully with UEBridge absent or disabled. Do not add production imports, IPC calls, startup checks, bundled helper files, installer requirements, CI/release requirements, or features that depend on it. Keep any diagnostic scripts and setup instructions separate from production artifacts and explicitly optional.

Use only bounded, targeted inspections and before/after snapshots to test concrete hypotheses about settings widget identity, key/Mode selection, DMM dirty/Apply state, and menu lifecycle. Do not start automatic watches or hooks. Ask the user before taking computer control; helper availability is not permission to interact with the game. Preserve configuration. Disable the helper for performance baselines and verify final fixes with it absent or disabled.

Workspace setup is documented separately at tools/ue4ss-bridge-review/SETUP.md under the Codex workspace. The reviewed staging is v1.2.0 with allow_writes=false, allow_eval=false and poll_ms=250, using an isolated CLI environment. Installation and live verification were still pending when this boundary was recorded; staging is not evidence of either.
