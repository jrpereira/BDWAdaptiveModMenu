# Adaptive Mod Menu

Adaptive Mod Menu is a developer tool that extends Dawnwalker Mod Menu with key-binding controls.

Keep using Mod Menu's normal configuration system. Add a little metadata, and Adaptive Mod Menu turns an integer setting into a key picker, optionally combining it with a Tap/Hold selector. Mod Menu continues handling Apply, Reset, and saving.

The source also serves as a practical example of extending existing Unreal UI: finding existing controls, adding widgets to their owning page, and connecting custom presentation to the original settings system.

## Features

- Upgrades Dawnwalker Mod Menu integer settings into interactive key-binding pickers.
- Combines key bindings with optional Tap/Hold selectors.
- Expands mapped presets into their target keys and modes; manual target edits select Custom.
- Shows changed settings with a left-hand star and italic label. Preset selection establishes a visual baseline; subsequent edits mark only the targets changed by the user.
- Renders pickers as right-aligned tabs and applies six typography levels. A level-one setting replaces the default mod header.
- Supports conditional group help, value-dependent labels and category ordering while preserving existing setting IDs.
- Supports metadata-based integration through `mod_settings.ini`—no registration code required.
- Preserves Mod Menu's Apply, Reset, and configuration-saving behavior.
- Adds separate hover feedback for key and mode pickers, plus highlighting during key capture.
- Supports Escape cancellation and displays unbound keys.
- Captures left/right Shift, Control, Alt and Windows keys individually; modifier chords remain unsupported.
- Keeps decorations attached to their owning rows and recreates them when pages rebuild.
- Uses menu-scoped updates without a permanent gameplay polling loop.
- Provides example configurations and source code for learning how to extend existing Unreal UI.
- Pairs with UE4SSLuaEventBridge for implementing Enhanced Input and Tap/Hold behavior.

## Known Issues / Improvements

- Menu updates use 100 ms polling, so visual feedback can lag slightly.
- Depends on Mod Menu's structure: changes to its widget layout or lifecycle can break decoration.
- The lifecycle bootstrap currently supports Dawnwalker Mod Menu 1.0.7; restart the game after it installs or updates the callback patch.

## Documentation

See the [documentation on GitHub](https://github.com/jrpereira/BDWAdaptiveModMenu/tree/main/docs) and the [developer integration guide](https://github.com/jrpereira/BDWAdaptiveModMenu/blob/main/docs/DEVELOPERS.md).

## Installation

Install the package as `Mods/AdaptiveModMenu`, then enable it through your mod
manager or UE4SS configuration. The archive does not create `enabled.txt`.
Restart the game after installing or updating it.

## Add a key-binding control

In your mod's `mod_settings.ini`, define an integer setting and add `DecoType = keybind`:

```ini
[Setting.MyAction]
Id = MyAction
Type = integer
DecoType = keybind
Label = My action
Group = Controls
ConfigFile = config.ini
ConfigSection = Bindings
ConfigKey = MyAction
Minimum = 0
Maximum = 254
Step = 1
Default = 75
```

The stored value is a Windows virtual-key code. In this example, `75` means K; `0` means unbound.

## Add an optional Tap/Hold selector

Immediately after the key setting, add a picker whose ID uses the same name followed by `Mode`. Give it its own decoration flag:

```ini
[Setting.MyActionMode]
Id = MyActionMode
Type = picker
DecoType = keybind
Label = My action mode
Group = Controls
ConfigFile = config.ini
ConfigSection = Bindings
ConfigKey = MyActionMode
PresetValues = 0|1
PresetLabels = Tap|Hold
Default = 0
```

Keep both settings in the same group.

That's it—magic! The key picker and Tap/Hold selector appear together. No registration code is required.

Your mod still implements what the binding does and interprets `0` as Tap and `1` as Hold. Adaptive Mod Menu provides the GUI upgrades, not the input behavior.

It also pairs well with [UE4SSLuaEventBridge](https://github.com/jrpereira/UE4SSLuaEventBridge), which exposes Unreal's Enhanced Input to Lua, including support for Tap/Hold bindings.

## Developer links

- [Integration guide](https://github.com/jrpereira/BDWAdaptiveModMenu/blob/main/docs/DEVELOPERS.md)
- [Complete example provider](https://github.com/jrpereira/BDWAdaptiveModMenu/tree/main/examples/ExampleMod)
- [UI implementation](https://github.com/jrpereira/BDWAdaptiveModMenu/tree/main/Scripts)
- [QuickslotsForever](https://github.com/jrpereira/BDWQuickslotsForever)
- [UE4SSLuaEventBridge](https://github.com/jrpereira/UE4SSLuaEventBridge)
