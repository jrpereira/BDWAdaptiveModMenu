# 0.3.0

- Rename the runtime and DMM extension to KEngineMenu (KEM), packaged under `_KEngineMenu`.
- Use `kem*` manifest metadata and `KEM_` runtime markers without reading old `amm*` metadata or migrating old settings.
- Keep generated KEngineTemplates module-page title controls separate from its ordinary Templates page.

# 0.2.25

- Place the paired Tap/Hold control beside Key capture and use the same dark background as Default, including when Default is selected.

# 0.2.24

- Align the 75-pixel paired Tap/Hold control beside its key field at the same height and match the key's active dark background; retain its hover and Default-dimmed states.

# 0.2.23

- Soften the shared Tap/Hold background while Default is selected, including its hover glow.

# 0.2.22

- Reduce the shared paired Tap/Hold control to half of its reserved 150-pixel mode column without changing key or Default placement.

# 0.2.21

- Render paired Tap/Hold modes in one full-width control that toggles on click; keep an optional Default mode in its separate reserved column.
- Preserve declared numeric mode values and standalone tab pickers.

# 0.2.20

- Move the bundled `menu.fixes` template to `Scripts/fixes.lua` for TE's module registration path, preserving its identity and enabled default.
- Use normal left alignment for ordinary Mod Menu entries; keep explicit provider indentation.
- Correct paired-row and fixes-template regression expectations without changing those runtime behaviors.

# 0.2.19

- Apply paired-picker hover glow to the hovered tab individually instead of across the full tab row.
- Enable the bundled Dawnwalker settings-page fixes template by default.

# 0.2.18

- Keep paired key fields and Tap/Hold tabs in fixed columns; render an optional third `-1` Default tab in a reserved left column.

# 0.2.17

- Remove the native empty-key prompt and reject empty key capture; use a paired `Default` mode to disable capture.

# 0.2.16

- Place three-option `Pair` tabs to the left of their key field when the third value is `-1`.
- Disable and dim key capture while that `-1` option is selected without disabling the picker.
- Restore paired-tab hover feedback, hide the native empty-key prompt, and shift ordinary Mod Menu entries left by 20 pixels.

# 0.2.15

- Keep `Pair` pickers in the original 150-pixel mode column beside their 96-pixel key control.
- Add a subtle background behind paired tabs so their shared control surface remains visible.
- Reduce active-menu selector and dirty-label refresh latency from 100 ms to 50 ms.

# 0.2.14

- Restore key controls in `Pair` rows after the setting-identity schema gained the `ammTabsWidth` field.
- Parse the paired target, tab width, values, and labels from their current schema positions.

# 0.2.13

- Make the picker that declares `Pair` own the composite row and its visible label.
- Render the paired key inside that picker only while DMM considers the key setting visible.
- Keep arbitrary picker values, including negative defaults, independent from positional tab navigation.

# 0.2.12

- Center each horizontal picker label within its allocated option slot.

# 0.2.11

- Rename the template directory from `template` to the shared `templates` convention.

# 0.2.10

- Add `ammTabsWidth` so generated horizontal pickers can reserve up to 440 pixels for their options.
- Keep existing tab widths unchanged unless a provider explicitly requests the wider layout.

# 0.2.9

- Rename every public decoration metadata key from the old `Deco...` form to the `amm...` prefix.
- Remove compatibility parsing for the old prefix so manifests have one concise schema.

# 0.2.8

- Let generated provider pages request a smaller Mod Menu browser font and a bounded left indentation.
- Preserve level-two, left-aligned styling for ordinary modules and aggregate pages.

# 0.2.7

- Move the Dawnwalker settings-page fixes out of AMM startup and into `templates/fixes.lua` under `menu.fixes`.
- Leave the template without event declarations or runtime hook registration.

# 0.2.6

- Bind native settings reconstruction through `DogwoodUI.SettingTabWidget`, whose inherited functions are hookable before the settings Blueprint is loaded.
- Track relocated controller-row selection through `RebelSettingEntryWidgetBase:SetSettingSelected` so the Controls page can display its native controller panel.
- Remove the rejected Blueprint-hook registration path that prevented the v0.2.5 controller transfer from running.

# 0.2.5

- Add a native `Controller Settings` category after the three mouse settings on the Controls page.
- Move Preset, Controller Sensitivity and Vibrations into that category using the game's own live setting descriptors and widget factory.
- Show the native controller preset panel on the right when a relocated controller setting is selected.
- Empty the former Controller page after a successful transfer and rebuild native navigation without polling or config-order assumptions.

# 0.2.4

- Add `ammHeading=0` for categories whose rows should remain visible without rendering their category heading.
- Render the mod-browser selector as a level-one page header with a themed divider, and align its level-two mod names to the same left edge.
- Add a native `Mouse Settings` category header above the first three entries on the Controls page.
- Construct native header text through Unreal's text library in UE4SS Lua states where the convenience `FText` global is unavailable.

# 0.2.0

- Capture left/right Shift, Control, Alt and Windows keys as distinct Windows virtual-key values while rejecting modifier chords.
- Remove the unused key-code support wrapper and obsolete row-state fields.
- Rename Mod Menu Decorator to Adaptive Mod Menu across the runtime, package, repository, documentation and release workflow.
- Use the AdaptiveModMenu/AMM identity consistently across row metadata, DMM patch markers, backup artifacts and internal fields.
- Retire an enabled `ModMenuDecorator` installation during AMM bootstrap by deleting its `enabled.txt`, creating `deprecated.txt` containing `AdaptiveModMenu`, and attempting to unload it when UE4SS supports cross-mod unloading.
- Stage and verify every DMM replacement before moving the original modules to verified backups, and roll back the complete transaction if promotion fails.
- Remove unreleased legacy decoration aliases and row-marker formats; accept only the canonical AMM configuration and metadata contracts.
- Consolidate page retirement into the lifecycle close path and remove the redundant host-open event.
- Register the menu click callback lazily after DMM lifecycle installation succeeds.
- Restore ordinary provider configuration initialization through DMM's authoritative provider model.
- Recover interrupted DMM patch transactions from verified baselines and remove incomplete staging files.
- Keep failed Settings API handler registration from retaining a process-wide ownership claim.
- Leave `enabled.txt` under user or mod-manager control instead of including it in release archives.

# 0.1.52

- Fix DMM localization module loading in the standalone decorator state by
  passing only the rewritten path to `loadfile`. This restores localized dirty
  label matching without adding polling or UObject access during startup.

# 0.1.51

- Remove the process-wide `UTextBlock::SetText` hook implicated in crash AA40011448729B47EDFCB8846C95AF72.
- Observe dirty text only on bound DMM rows during the existing active-menu update; no dirty-label callback runs during gameplay.
- Add one `PAGE_TIMING` diagnostic per page build with discovery, localization, decoration, route and dirty-binding durations.
- Replace the native mapped-preset adapter with DMM extension API version 1 and ship a pure-Lua package with no DLL.

# 0.1.50

- Replace the unavailable `UButton:OnButtonClickedEvent` hook with one bounded left-mouse key callback.
- Deliver queued clicks to the hovered paired picker only from the existing menu-scoped game-thread update.
- Avoid sparse delegate access, repeated failed hook registrations and repeated pair-construction failures.
- Keep attribution of crash E880E96A4DB5418CA744558698206985 unresolved; its game-thread null dereference has a different signature from the earlier UE4SS delegate-reflection crashes.

# 0.1.49

- Remove reflected access to UButton's sparse multicast `OnClicked` property.
- Queue owned picker clicks through the hookable `UButton::OnButtonClickedEvent` function, retaining the same menu scope, receiver validation and teardown.
- Keep crash attribution unresolved: the supplied startup dump matches the delegate-reflection failure signature, while its log belongs to the following launch.

# 0.1.48

- Bind normal DMM page selections from the exact active provider `ScrollBox`, avoiding a full widget-tree traversal on first and repeated openings.
- Build refresh routes only for recognized setting and decoration controls; retain one bounded full-tree traversal for activation and unrelated-switcher recovery.
- Publish the versioned `settings_api.lua` consumer contract for event-driven notifications after successful durable Apply.

# 0.1.47

- Add reusable parent headings for related categories through `ammParent` and `ammParentLevel`.
- Keep subgroup ordering, navigation and page-ready rebinding intact beneath parent headings.
- Keep parent headings independent of picker values; providers control subgroup visibility through DMM's ordinary visibility metadata.

# 0.1.46

- Rebind decorators after a picker changes which settings rows are visible.
- Coalesce visibility and category-order changes into one deferred page-ready event.
- Reuse the active dirty-label hook across same-page rebinding instead of unregistering and registering it again.

# 0.1.45

- Bind decorations, paired Mode rows and dirty-label metadata directly by provider and setting IDs, independently of row or metadata order.
- Remove positional and label matching fallbacks; reject missing, duplicate or mixed-provider row identities.

# 0.1.44

- Attach provider and setting IDs to row-owned markers so grouped and repeated labels bind by identity.
- Align paired, fixed-mode and unpaired keybindings on the same grid, reserving blank mode space without creating controls.
- Remove per-option layout measurement when constructing mode controls.

# 0.1.43

- Add declarative numeric maps and ordered conditional source rules for migrating absent configuration keys from the original file.
- Preserve explicit destinations and original configuration bytes; validate migrated values before transactional replacement.
- Keep settings unavailable when a declared migration fails, preventing Apply from replacing legacy choices with defaults.

# 0.1.42

- Dim fixed Tap/Hold labels without disabling key capture; restore normal text contrast when the paired mode becomes editable.

# 0.1.41

- Skip dirty-label row discovery for MMD's own synchronous decoration text during page binding, preserving DMM value notifications and restoring handling after construction failures.

# 0.1.40

- Add ammMode=Tap|Hold as a fixed presentation fallback for key bindings without a logically visible paired mode.
- Follow DMM model visibility when switching between fixed labels and editable Tap/Hold controls, preserving saved modes and discarding stale clicks.
- Retain key capture, row ownership and existing menu-scoped updates without adding timers.

# 0.1.39

- Standardize metadata on ammType=tab|keybind, ammLevel=0–6 and the Deco prefix; retain legacy read compatibility.
- Add tab pickers, six font levels, a header toggle, category help, conditional labels and category ordering through metadata.
- Preserve row identity when categories move and use DMM's existing menu tick for new controls.
- Keep preset-derived keys visually clean after a manual edit; select Custom automatically and skip it during preset navigation.
- Support DefaultFrom for missing configuration values, preserving explicit values and validated legacy defaults.

# 0.1.38

- Reduce preset refresh overhead: validate the menu owner once per value callback, ignore unrelated text after binding, and skip unchanged label styling.

- Render dirty stars as separate row-owned widgets in the existing left gutter, keeping label text and position unchanged. Preserve italic styling and preset suppression.

# 0.1.37

- Display dirty settings with a left-hand star and italic label across recognized DMM sliders, pickers and toggles, replacing visible value-side stars.
- Restore original label styling when changes are applied or restored; combine key and Tap/Hold dirty presentation.
- Add panel-wide dirty-display suppression for MMD value changes, including deferred DMM refreshes, without changing Apply/Restore state.
- Expand MappedPresetTargets/MappedPresetValues synchronously in DMM's pending model; update visible keys and modes together and select Custom after a manual target edit.
- Hide preset-derived dirty indicators while preserving Apply/Restore state; reveal actual target differences when switching to Custom.
- Install the mapping adapter through UE4SS's native DMM startup callback, without editing DMM files or adding gameplay polling.

# 0.1.36

- Initialize provider INI files from metadata defaults at startup, with existing values taking precedence.
- Preserve existing configuration bytes and add missing assignments before DMM opens settings; validate with DMM and protect writes with transaction recovery.
- Include disabled direct providers and settings without decorations; add no gameplay polling.

# 0.1.35

- Reject release manifests that would place a Tools directory anywhere in the ZIP, regardless of capitalization.
- Cover nested, mixed-case and root-directory exclusions with packaging regression tests.
- Runtime behavior is unchanged from 0.1.34.

# 0.1.34

- Preserve accepted row input state before rendering, so a failed label update followed by reopening cannot overwrite Restore with an old key.
- Use a neutral capture baseline for unmapped backing values, allowing the previous key to be selected again while preserving cancellation.
- Recover failed key, mode and dirty-label writes; display unmapped values numerically.
- Report inactive DMM and invalid decoration metadata at startup; remove stale workspace notes and normalize changelog encoding.

# 0.1.33

- Include the updated developer README in the downloadable package, covering features, integration examples, known limitations and documentation links.
- Clarify that Mod Menu Decorator provides GUI upgrades and pairs with UE4SSLuaEventBridge for input behavior.
- Runtime behavior is unchanged from 0.1.32; only the version label changes.

# 0.1.32

Unreadable selected keys now count toward the existing three-failure limit, stopping updates to broken controls until the next page event. Successful reads reset consecutive failures. Deployment tooling never creates enabled.txt, including on fresh installs, and preserves existing enablement. Regression coverage verifies failure shutdown, recovery and enablement preservation. Native gameplay-impact verification remains pending.

# 0.1.31

Promote the rc.2 runtime fixes to stable. Runtime behavior is unchanged apart from the version label. Keep diagnostic inspection tooling and evidence outside public source and history. Automated regression and packaging checks pass; native gameplay-impact verification remains pending.

# 0.1.31-rc.2

Fix audited construction failure paths: restore stock controls if initial binding bookkeeping fails; contain post-attachment receipt errors inside the transaction; restore row-owned picker metadata on rollback; and report incomplete rollback explicitly. Automated fault-injection regressions cover each case and ensure adoption failure does not dismantle existing rows. No polling, dependency or configuration changes. Native integration validation remains separate.

# 0.1.31-rc.1

Local testing release candidate including all completed work through 0.1.30: row-owned decoration state, event-driven construction, duplicate-ID handling and all six post-deployment audit improvements. Distinct RC startup/version identity; packaging validates RC suffixes. Native functional and gameplay-impact verification remain pending. No new runtime dependency or configuration migration.

# 0.1.30

Recover on the next valid page event after lifecycle callback errors. Traverse and update only the selected provider, retaining collapsed backing controls. Stop scheduling when every control is disabled. Preserve setting IDs and original construction/update errors, including the terminal disabled message. Coalesce page events and reuse discovery routes when adopting unchanged rows. Skip serialization for unchanged row state. Automated regression coverage includes each change; native gameplay impact verification remains pending.

# 0.1.29

Move persistent decoration state into a collapsed child of the decorated row. Adopt surviving controls from their subtree on page events; newly built rows decorate without any cached host/row flag. Keep WidgetTree ownership and row attachment for all created widgets. Remove periodic structural scans and discovery retries. DMM page-switch completion queues discovery after row construction; load recovery no longer depends on a specific activation callback. Construction rollback remains; periodic partial-decoration repair is removed. Native repeat-cycle validation pending.

# 0.1.28

Skip later duplicate Mod Id manifests in sorted path order, matching DMM. Duplicate settings can neither overwrite nor merge into the first provider, including when that provider has no decorations. Emit one startup diagnostic per skipped duplicate. Eight Lua suites and three package checks pass.

# 0.1.27

Recover an already-active menu owner when its reflected activation was missed. Event-triggered discovery queries only the two DMM owner classes; no live owner means no polling. User subsequently reported decorations and the complete functional checklist working in v0.1.27.

# 0.1.26

Fix post-construction route refresh when row replacement leaves the count unchanged. Remove stale diagnostic wrappers, unused press/reset/click-epoch state, suppressed discovery-log formatting and duplicate row references. Make binding state local to its host; reject missing FKey names and avoid owner searches for foreign switcher events. Refresh current documentation.

# 0.1.25

Gate polling on a fresh visible, active main/pause-menu owner. Retire removed-host and closed-session records; retain temporary Back-navigation state. Includes acknowledgement-wait removal. Eight Lua suites and three package checks pass; native integration pending.

# ModMenuDecorator 0.1.24

Removed DMM acknowledgement polling, pending acknowledgement state, the 25-update timeout and its diagnostic. Key submission still writes the stock slider once. Normal slider synchronization and DMM dirty-label mirroring continue; DMM owns processing, Apply and persistence. Includes the 0.1.23 hidden/disabled-host guards.

Eight Lua syntax checks and eight regression suites pass, including stale DMM text, stock Restore/Reset synchronization without resubmission, cancellation and subsequent capture. git diff --check passed. Native interaction verification remains pending. Source and candidate only; not deployed by this task. No batch or ZIP delivery.

# ModMenuDecorator 0.1.23 candidate

Adds visibility and enabled-state checks before host traversal or control updates. A host that remains activated and in the viewport but becomes hidden or disabled now invalidates the menu scope, clears pending clicks, and stops both scheduling chains. No new timer or hook is introduced. If no close event arrives, detection occurs on the next scheduled update; 100 ms is the nominal interval, not a latency guarantee.

Retains 0.1.22 queued native picker clicks and stock DMM ownership of pending/dirty/Apply state. Basic short-click, Apply and reopen persistence passed in the prior native run. This new guard is mock-tested; native shutdown and gameplay performance acceptance remain outstanding.

No shipped debug mode, batch installer or ZIP delivery. COORDINATION owns deployment and native verification.

# ModMenuDecorator 0.1.22 native-click test candidate

Replaces picker IsPressed sampling with queued native OnClicked delivery on MMD-owned proxy buttons. No polling frequency increase.

Each new proxy binds OnClicked to its own inherited no-argument ForceLayoutPrepass function. A temporary native-function hook checks the fresh callback receiver against registered primitive address/full-name and active host identity, then increments a Lua count. The existing game-thread update consumes that count once through the stock mode slider. This avoids entering DMM state mutation from the click callback and does not retain callback UObject wrappers.

The hook is installed only while a candidate menu scope is active. Close/load/dormancy clears pending counts and unregisters it. Native self-delegate bindings refer only to a live widget and an engine function; no pointer into a mod DLL or Lua function is bound to the delegate. Surviving widgets reuse their binding. Failed registration/attachment preserves or restores the stock mode row.

The installed UE4SS DLL has AddDelegate export and delegate GetBindings/Broadcast strings; official UE4SS docs specify multicast Add(target,FName). Actual event delivery and teardown on this native runtime remain a test gate. This candidate does not require or modify the Enhanced Input bridge. No unverified ABI offsets or synthetic UFunctions are used.

0.1.21 native results remain recorded separately: delayed provider opening, visible keys, key-only dirty/Apply/cancel passed; settings FPS observed about200–218 versus7–12 on0.1.20, not a controlled benchmark. Stock DMM Apply mouse-click reliability remains outside this patch.

No deployment or publication by this task. COORDINATION owns native testing.
