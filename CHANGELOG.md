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
