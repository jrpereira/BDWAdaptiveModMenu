Mod Menu Decorator v0.1.13 — capture and surface candidate

Reads reflected InputKeySelector.SelectedKey (GetSelectedKey is not reflected in this game).
Captured keys update only the stock DMM numeric slider. DMM owns dirty/Apply/save.
EscapeKeys contains Escape; cancel/unchanged capture does not write the slider or dirty state.
None maps to existing unbound numeric zero. Unsupported key mappings fail closed.
Outstanding writes are acknowledged from stock numeric text or time out; they are never
reasserted over Reset/Restore. Dirty label follows stock DMM state, not a guessed pending flag.

Normal key surface: 30% alpha dark fill, separate one-pixel outline; capture highlights edges.
Mode surface: 10% alpha dark fill, no outline, transparent button hit target.
Mode width measures supported labels with padding; logged font estimate if Slate size is unavailable.
Mode options come from the provider manifest. No metadata contract/config changes.
All timer-driven UObject discovery and updates are dispatched to the game thread.

Delete-to-clear and the Del footer hint are NOT implemented in this candidate. DMM has an
independent UE4SS DEL callback in addition to native CommonUI reset/hold actions. A safe
exclusive input route is required; adding another callback would risk clear and reset together.
Normal DMM Reset remains unchanged. COORDINATION is tracking the interception dependency.

COORDINATION owns deployment and native testing. Preserve current user configuration.
All six Lua files passed Lua 5.4 compilation. Mock tests cover capture/acknowledgement,
clean/dirty cancellation, Escape, Restore supersession, unsupported/unbound values,
bounded acknowledgement timeout, and game-thread dispatch. Native integration remains untested.
