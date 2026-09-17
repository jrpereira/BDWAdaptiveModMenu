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
4. The decorator acknowledges the stock value and mirrors DMM's dirty label.
5. DMM saves on Apply; your provider must reload the saved config and update gameplay.

Do not save directly from the decorator or bypass DMM's pending state. Escape
cancels capture and should preserve both the previous key and any earlier unsaved
changes. A pending write is not endlessly retried: Restore/Reset must be able to
supersede it. Seeing a new key label alone is not proof that DMM ingested or saved it.

## Discovery and layout constraints

Discovery scans `mod_settings.ini` files beneath the UE4SS Mods tree exposed by
`IterateGameDirectories`; individual manifests are limited to 256 KiB. Give every
provider a unique `[Mod] Id` and every setting an explicit unique `Id`.

The current page matcher requires one unambiguous provider with the same supported
row count, order, widget kinds, and labels as the visible DMM page. Localized `Label.*`
values are considered. Ambiguous or mismatched pages are rejected rather than
decorating guessed rows. Changes to DMM hierarchy, dynamically hidden rows, or
unrecognized setting types can therefore require compatibility work.

Decoration uses proxy widgets while retaining stock controls as backing state.
UObject work is dispatched to the game thread. Do not import this mod's internal Lua
modules from a provider: there is no stable public Lua registration API; manifest
metadata is the integration surface.

## Diagnostics and integration checklist

In `UE4SS.log`, filter for `[ModMenuDecorator]`:

| Marker | Meaning |
| --- | --- |
| `MANIFEST_PARSED`, `KEYBIND_REGISTERED`, `MODE_PAIR` | Metadata discovered and registered |
| `PAGE_MATCH`, `ROW_BOUND` | DMM page matched to provider settings |
| `PAIR_PROXY_READY` | A paired control completed construction |
| `PAGE_REJECTED` | No unique matching page; inspect row count/order/kinds/labels |
| `CAPTURE_BEGIN`, `CAPTURE_END` | Capture observed across polling ticks |
| `KEY_SELECTED`, `DMM_VALUE_ACK` | Captured key submitted and backing value acknowledged |

Very fast capture can occur between polling ticks, so BEGIN/END alone is not a
reliable count of user input. Retain error details and the full log when diagnosing.

Before releasing your integration, test a key-only change, a mode-only change,
the dirty marker and Apply, persistence after reopening/restarting, clean and
already-dirty Escape cancellation, Reset/Restore, unrelated settings pages, and
the provider's actual gameplay behavior after Apply. Test transparent surfaces and
longest mode labels in the real UI. Automated mocks cannot validate those native paths.

## Known limitation: Delete

In v0.1.13, Delete-to-clear and its footer hint are not implemented. DMM separately
routes Delete to Reset through both Lua and CommonUI. Adding a second callback that
sets zero can race with Reset. Zero remains the unbound representation, but an
exclusive Delete input route is still required before advertising this shortcut.
