# Learnings, dead ends and open gaps

## 2026-10-03 - PR #7 merged during verification

The final check refresh found PR #7 already merged on GitHub. The REST merge
record identifies `EduardoKenji`, `c7cf1da` and 21:35:06 UTC; the agent's actions
were PR creation/editing and read/fetch/pull, not a feature merge command.
Refresh local main and correct current "open/unmerged" guidance. Keep dated
publication records as history and keep game acceptance pending: a GitHub
merge is not evidence that native rendering or multiplayer was tested.

## 2026-10-03 - Synchronizing the appearance PR

- Push `feature/enemy-appearance` and open PR #7 with the authenticated account's
  write permission, as requested. GitHub reports no merge conflicts. Its first
  hosted PR reports match local counts/scores on both runtimes: 1,916 assertions,
  Lua 5.5 81.80% and LuaJIT 2.1 78.54%, with no coverage failures;
  native acceptance remains separate from publication and CI.
- GitHub confirms PRs #5 and #6 are merged; `origin/main` is `06c2b3a`.
  Pulling main in a dedicated worktree leaves the other agent's branch intact.
  Merge main into the feature branch so publication retains both ancestries;
  merging the feature into main still needs the user's in-game confirmation.
- The only merge conflict was the changelog's top entries. Retain both the
  appearance history and the CI publication record. Runtime/tests are unchanged;
  both full runners still pass 1,916 assertions and every coverage gate.
- Guessed workflow reads (`ci.yml`, `tests.yml`) failed; `rg --files .github`
  identifies `.github/workflows/verify.yml`. It runs on pushes and PRs, so
  publication produces two independent runtime matrices. A documentation patch
  also rejected an incorrect title anchor without changing files; read the
  actual heading before applying the corrected patch.

## 2026-10-03 — Enemy colour implementation

- Worktree `feature/enemy-appearance` avoids touching the concurrent CI branch,
  its Python helper/refactor changes or installed mods. Copy the earlier research
  into this worktree rather than altering the original untracked reports.
- The known stimm/outline APIs are RGB. Keep an explicit A-as-strength label;
  stimm zero is the vanilla reset, so a black swatch is not a black surface.
- Natural stimm needs both a breed `use_stim` action and a writable blackboard
  stim component. A keyword alone does not prove that an arbitrary breed can
  perform the animation. The normal buff/particles retain their gameplay effects.
- Source reads found no verified generic material getter/clone or colour key
  for all enemy surfaces. Surface/private patch choices remain prerequisite
  entries, not successful no-op substitutes for those methods.
- A direct setter's preceding value is unknown without engine getter support.
  Cleanup can restore the current tracked buff vector or zero; unrelated direct
  writes and actual private material instances still require game investigation.
- Recipe merging can shorten/reorder the edited parts. Preserve the selected
  group by its canonical key, otherwise a second identical colour could leave
  the editor pointing past the merged list.
- Native spawns/loadouts and mod RPCs can arrive in either order. Bound pending
  IDs and retry readiness; validate the unit breed and reset token. Refresh the
  normal handshake after host entry/reload/re-enable. Lease remote colours so a
  vanished host cannot leave visual ownership indefinitely.
- A synchronous send can tear down owners. Build a bounded snapshot before
  sending and stop later batches if its generation changes.
- First regression run: logic's exact RPC-count assertion still expected six;
  update it for the single new appearance endpoint. This was the sole failure.
- First render attempt: a zero-width G fill caused Pillow's rectangle assertion.
  Hiding the fill at zero fixes it. The first visibility guard read a missing
  style `size` in the engine-rule test; use a content flag instead. Regenerated
  real-English panel/dropdown previews were visually inspected without clipping.

Current implementation, limits and live checklist: [enemy-appearance.md](enemy-appearance.md).

### CI integration follow-up

Integrate the CI branch at `fd56262` into this feature branch, leaving its
checkout and `main` alone. Resolve README/changelog conflicts by preserving
both histories and using the aggregate runner. Its protocol failure fixture
lacked DMF's `io_dofile` loader and expected six RPC failures; extend that fixture
for the actual schema and seventh endpoint. Its first integrated run failed
there; the fixture repair passes without changing production protocol behaviour.

The collector counts printed `PASS` lines, so emit the focused schema/runtime
assertions as well as the UI/entry ones. Eight additional checks cover unsupported
natural breeds, a missing component, expired stim colour, late loadout readiness,
default cleanup, original outline-map restoration and zero-strength outlines.
The appearance suite now has 79 focused assertions.

Trial floor 80 for the new runtime passed Lua 5.5 but exceeded LuaJIT's initial
77.69 source-line score. After the extra checks LuaJIT measures 79.34; schema
84.44 and editor 90.14. Assign new-module floors 79/84/90 from both backends'
measurements. Existing thresholds stay unchanged. Many uncovered lines are
function declarations/closing delimiters under this source-line proxy; these
scores must not be represented as branch or native rendering coverage.

The journal the user asked for (2026-10-01): every attempt and error, discovery, actionable gap and insight, so a later session does not repeat a dead end. Newest entries first inside each section. The CHANGELOG says WHAT changed per commit; the results log in `06` says what was tested; this file says what we LEARNED and what is still missing. Keep it under 100 KB (`python tools/check_docs.py`); at 100 KB split by section into `docs/learnings/` and keep this file as the index.

Entry format: `date, short title: what happened / what was found. Evidence (file:line or test). Consequence.`

## 1. Open gaps (actionable)
Things we know are missing or unverified, each with the next concrete step.

| Gap | Next step | Since |
|---|---|---|
| The 2.1 batch (`feature/heresy-card-and-ui-pass`: exact custom health, card-coloured pages, `/rw_test_close`, HERESY, 100 cards, the last-card window, the Deck cooldown row) has never run in the game | the user plays matrix rows 114-121 in `06`; fixes go on the branch | 2026-10-03 |
| "Give admin to EduardoKenji" on the GitHub repository could not be done | The repository is owned by a personal account: GitHub gives collaborators there only write access (an Admin role exists only for repositories owned by an organization), and no `gh` CLI or token was available. The owner can add the collaborator in Settings > Collaborators (write), or move the repository to an organization and give the Admin role there | 2026-10-03 |
| Adversarial audit F01–F07 plus two surviving mutations | Fixed and detected offline in six approved [remediation batches](audits/2026-10-03/remediation.md); native/multiplayer/eight-hour acceptance remains open | 2026-10-03 |
| Nothing of 2.0.0 (Spread HUD options, Deck look, card builder, custom mods) has been checked in a real two-player game | the user plays; matrix rows 91-96 in `06` | 2026-10-01 |
| Per-unit **animation speed** of attacks ("Animation attack speed") | CLOSED 2026-10-02 as not possible cleanly: `/rw_anim` found no speed variable on three breeds and the engine's speed functions are for simple animations only (docs/03). Reopen only if someone finds a state-machine variable by another route | 2026-10-01 |
| **Gunner fire rate and shots per burst do nothing** on riflemen and scab gunners (the user, 2026-10-02) | FIXED offline 2026-10-02 (the recompute hook never reached `MinionBuffExtension`; see section 2). Waiting for the in-game run of matrix row 103 (fire 25 / burst 500 under Havoc and without): the log line "started shooting" must read x0.325 / x0.25 and the shots must be multiplied | 2026-10-02 |
| Time between attacks, the chain fix and `/rw_anim` are untested in game | matrix rows 94 and 97-101 in `06`; the user's "100 percent working" merges `feature/attack-timing` into `main` | 2026-10-01 |
| (closed 2026-10-02) Does DMF apply a string-class hook when the class loads after the mod? | Yes: the console log shows "needs to be delayed" at load and "Hooking ..." at mission start | 2026-10-01 |
| Size of a custom-mod enemy on a client without RealmsWaves is the normal size | by design (see doc 03, "Custom mods per group"); only a mod on every machine can fix it | 2026-10-01 |
| The Cauldron, its shelf, the 1.4 times card, the quick face and the preview have only been seen in the offline drawing | the user opens a card in game; matrix rows 104-109 in `06` | 2026-10-01 |
| `CHANGELOG.md` is 86 KB (limit 100) | split into `docs/changelog/` per major version when it passes 100 KB (`check_docs.py` warns from 80) | 2026-10-01 |

## 2. Discoveries (things the source or the game taught us)

- **2026-10-03, PR #3/#4 synchronization:** the original brief commit `8c81c1b` and its cherry-pick `505924c` have identical trees but different ancestry. Merging PR #3 into main therefore conflicted with completed audit additions in the plan, changelog and index. Preserve those newer records and merge main into the remediation branch; rewriting the six published fix commits is unnecessary. Runtime/tests remain byte-for-byte unchanged.

- **2026-10-03, final retirement review:** clearing the extension index alone leaves unit/scale/inbox/outbox owners alive. Retirement now resets all records and guards apply/receive/update/snapshot paths, delayed hook registration and captured protocol callbacks. A snapshot failure that returns after synchronous teardown must consult current live records before requeueing. Actual installed DMF `dmf_mod_manager.lua:45` creates a fresh `DMFMod` per load; the owner fixture's distinct generations match that contract.
- **2026-10-03, missing-manager recovery and state validation:** defer event registration until a manager exists and retry on gameplay entry, releasing any replaced owner. A host-authenticated state with `k={false}` previously raised; skip malformed entries and cap work to the existing five-card bound. These guards keep the existing protocol.
- **2026-10-03, remediation evidence:** all seven original mutations now fail behavioral assertions, closing both survivors; ten additional mutations detect the approved fixes and synchronous-send regressions. Five supported-max repetitions per VM/mode remain at 16 jobs / 8,000 entries; tracing-off collected heaps return near baseline after reset. Normal-JIT heaps include compiler state and native/process costs remain unmeasured.

- **2026-10-03, F06 remediation:** Realms direct sends expose recipient failures, so fan out at the existing adapter and reuse current-size retry rather than adding per-peer schedulers. Successful peers may receive idempotent duplicates. Coalesce ids before admission and detach the outbox before sending so synchronous callbacks cannot lose new sizes. Refresh Realms peer replay after enable to remove missed disconnects and stale capability skips.

- **2026-10-03, finite imports:** chance/cooldown/spread/repeat/distances/timer and optional threat share finite-value rejection before rounding. Preserve absent/empty legacy threat as zero, but reject malformed supplied threat. Test both complete preset and single-card formats with valid checksums and isolated settings writes.

- **2026-10-03, aggregate budget:** derive the pending count from at most 64 owned jobs to avoid fragile mutable counters. Refuse an entire initial wave before expansion if it cannot fit in 8,000 entries; repeat-only jobs still consume a job slot. Full repeat ticks skip before constructing a batch; partial ticks clip to available room. Normal pressure must not flood timed-wave warnings.

- **2026-10-03, control lifecycle:** job cancellation preserves mission-owned units; maintenance/pruning continues while paused/stopped. DMF disables hooks before the disable callback, so disabled updates perform liveness cleanup only and do not rewrite tuning. Re-enable explicitly restarts the host or discards client state before a fresh handshake. The pending-job unload assertion also detects the former unload-reset mutation.

- **2026-10-03, F01 remediation:** cleanup must use the manager that registered the object, because `Managers.event` may already have changed or disappeared. Store that owner and test 100 generations with strong object keys, not a name-only map. Captured callbacks still need the retired-generation guard.

- **2026-10-03, final audit review:** `/rw_status` rounds heap to whole MiB; converting the displayed MB value to KiB cannot reveal sub-MiB retention. Record source/precision and keep precise live collected floors pending without telemetry. SessionControl false returns are availability/encoding failures, not demonstrated packet-loss acknowledgements.
- **2026-10-03, weak values do not release strong object keys:** actual EventManager holds each old mod key after unload. 100-generation fixture and unregister-only control demonstrate F01. Retiring callbacks suppresses behavior but does not remove their owner.
- **2026-10-03, verify DMF contracts rather than old comments:** current loader restores original hooked functions at reload; the runtime comments saying hooks cannot be removed are historical assumptions. DMF does keep delivering update events to disabled mods, so an enabled gate/disable lifecycle is necessary (F02).
- **2026-10-03, cancellation and teardown have different owners:** stop leaves enemies alive but uses full mission reset, discarding bypass/tuning state (F03). Pause freezes the director while Execute keeps repeating/feeding (F05). Test the real collaborator across the lifecycle boundary.
- **2026-10-03, local bounds do not sum to a global budget:** 32 legal repeating timers yield 992,000 pending entries although each job holds at most 1,000. Teardown releases them; classify aggregate pressure separately from a lifetime leak (F04).
- **2026-10-03, success is dependency-specific:** actual Realms broadcast returns true while logging a rejected peer. A stub returning false for the whole send cannot establish recipient recovery (F06).
- **2026-10-03, both runtimes matter for validation:** LuaJIT parses `nan` in a correctly checksummed preset and retains it through rounding/clamping; Lua 5.5 refuses it. Explicit finite-value validation is needed before applying imported fields (F07).
- **2026-10-03, passing counts do not measure test effectiveness:** five intended mutation detections and two survivors identify actual coverage strengths/gaps. An exception in harness setup is never counted as a detection. BetterInventory's selected lifecycle test uses source-string assertions, so its scenarios are useful without treating them as a measured soak.

- **2026-10-01, a screen change that moves a shared button can put it on a button of the screen it returns to.** Back was at 125, 800 on every screen; the new Cauldron has a stepper there, and the picker's Back (which returns to it) would have clicked it in the same frame (1.6.1 again, with a stepper this time). Rule kept: Back sits in the same place on every screen of a card, and the editor test places Back against every widget of the destination. The preview tool and the test of overlaps between clickable widgets found this class of mistake before the game could.
- **2026-10-01, a list that keeps its scroll offset across screens needs the offset reset or aimed.** The picker scrolled to 33; adding an enemy returned to the card with the same offset, which hid the card's groups once the card page had five rows instead of ten. The list now scrolls to the group that was added.
- **2026-10-01, text width is an estimate, and it must be careful.** A chip's width comes from its label length times 0.6 of the font size (`Workshop.GLYPH`); with 0.56 the tag of a short name touched the name in the preview. A chip that is too wide only leaves a gap, one that is too narrow overlaps: when in doubt estimate high. The real fonts decide, check in the game.
- **2026-10-01, the offline harness hides a failed check when it crashes later.** Only the final report listed results, so an error in the middle of a long test showed no earlier failure. `check` now also writes each failure to stderr as it happens.

- **2026-10-01, `io_dofile` runs a file again every time, so a module-level value is NOT shared.** The view, the blueprints and the definitions each `mod:io_dofile` the components file and get three separate copies. State that several of them must see (the accent colour of the buttons) has to live on an object they all share: the mod object (`mod.rw_accent`), changed in place. The offline harness does the same (`dofile` per call), so a test of it must read `mod.rw_accent`, not a second copy of the module.
- **2026-10-01, the UI renderer can snap to whole pixels, and the stock default is off.** `ui_renderer.lua:17` `SNAP_PIXEL_POSITIONS = false`; `draw_rect`, the bitmap and text draws honour `render_settings.snap_pixel_positions` only when the UI scale is 1 or more (`:224,285,343,407,859`). A view can set it on its own `_render_settings` table (created in `BaseView.init`, `base_view.lua:31`; the draw only rewrites `start_layer`, `scale`, `inverse_scale`), as the stock overcharge HUD does around its draw (`hud_element_overcharge.lua:43-58`). `draw_triangle`, `draw_circle` and `draw_rect_rotated` never snap and never smooth, which is why the feather copies stay. Consequence: one 1920 x 1080 layout is right for every resolution; only crispness needed work.
- **2026-10-01, a hotspot content table has `is_hover`, `is_held`, `on_pressed`, `on_released`** (`ui_passes.lua:1088-1186`); `is_held` is true while the button is down over the widget, which gives a pressed look without a callback.

- **2026-10-01, the melee attack-speed stat only shortens the end of an attack, and cuts chains.** `BtMeleeAttackAction._start_attack_anim` (`S\extension_systems\behavior\nodes\actions\bt_melee_attack_action.lua:259-271` for sweeps, `336-348` for other attacks) replaces the attack's end time with `max(duration / melee_attack_speed, timing + 0.2667)`. It does NOT speed the animation and does NOT move any damage timing. For a sweep attack with several hits (`attack_sweep_damage_timings` is a list of `{start, stop}` pairs) `timing` is the stop of the FIRST hit (`attack_sweep_start_or_table[2]`), not the last (the non-sweep branch uses the last, `attack_timing_or_table[#...]`). So at a high speed the action ended right after the first hit: Plague Ogryn combo (`chaos_plague_ogryn_actions.lua:379-394`: duration 3.56 s, first hit stops at 1.21 s, last at 2.84 s) at 250 percent ends at 1.48 s, before its second hit (1.81 s); the Chaos Spawn combo (`chaos_spawn_actions.lua:785-806`) is cut the same way. The user saw exactly this ("stops his chain attacks after the first attack"). The game never meets it because its own stat values are small (Havoc stimm 1.3-1.4, `havoc_mutator_local_settings.lua:378,389,456`). Fixed on branch `feature/attack-timing` for our units (`Tuning.fix_attack_end`, 2026-10-01); not merged until the user confirms it works in game. The fix only ever lengthens an attack to the end of its last hit plus 0.27 s.
- **2026-10-01, no per-unit animation speed in the game scripts.** The only animation controls a minion has are events (`anim_event`) and breed-listed variables (`animation_variables`, in practice `anim_move_speed` and `moving_attack_fwd_speed`, which steer locomotion blends); `MinionAnimationExtension` (`S\extension_systems\animation\minion_animation_extension.lua`) offers nothing else, and no script calls a unit-level speed function (`Unit.animation_set_speed`, `set_animation_speed` and similar do not occur anywhere in `S\`). The animation state machines are binary data, so a variable that scales attacks may exist but cannot be read offline. Hence `/rw_anim` (a probe, built 2026-10-01) lists what the engine and each unit offer.
- **2026-10-01, the buff system recomputes a minion's stats every frame** while any buff touches them (a mission-wide Havoc modifier, Enraged, a player's debuff); each recompute drops stat values we wrote (`buff_extension_base.lua:318-354`, `minion_buff_extension.lua:97-101`). A 4-times-a-second re-check missed the moment an attack started, so melee/fire rate/burst "did nothing". Fixed by a post-hook on `BuffExtensionBase._update_stat_buffs_and_keywords` (CHANGELOG, "after the first in-game test"). The user's own guess (the Havoc global modifier takes priority) was right.
- **2026-09-29, 1.6.1, click-through.** A button on the destination screen must never share a spot with the button that leads there when the widget is later in draw order: the same click reaches both in one frame.
- **2026-09-29, 1.5.7, `FixedFrame` is a module, not a global.** Tests that stub a module as a global hide a missing `require`; stubs now go through `package.preload`.
- **2026-09-29, 1.5.5, twin captains start with the void shield down** (`start_depleted`); the spawner must pass `optional_init_toughness`.
- **2026-09-29, 1.5.4, the Psykhanium has no main path**; `/rw_test` there needs the ring fallback.
- **2026-09-29, 1.5.3, DMF keybinds fire while typing** (its input check is a stub that always returns true): the mod hooks `check_keybinds` while a text box is open.
- **DMF localization**: every string passes through `string.format`; a bare percent sign breaks it. Write "percent" or double it.
- **Darktide UI passes have no anti-aliasing** (rect, circle, triangle, rotated_rect): shapes get a faint wider copy (a "feather") underneath. A second left click inside the double-click window calls ONLY the `double_click_callback`.
- **Git on Windows**: PowerShell 5.1 mangles multi-line `-m` text and `Set-Content -Encoding UTF8` adds a BOM, so commit messages are written to a BOM-free file and passed with `-F`; git writing progress to stderr makes PowerShell print `NativeCommandError` even when the push worked (read the `main -> main` line). The first push needs the user to sign in through the Git Credential Manager browser window; later pushes work.

- **2026-10-02, the burster's blast ignores the model's size.** The model's own danger-zone effect scales with the unit, but the explosion is made from fixed templates with a constant charge level (`bt_chaos_poxwalker_explode_action.lua:14,44`; `scalable_radius` only matters with a charge level other than 1; `explosion_radius_modifier` only counts for attack type "explosion", `explosion.lua:484-500`). The size mod now swaps the templates of the action for scaled copies during that one call. The user noticed it by looking, no test could have.
- **2026-10-02, the answer of `/rw_anim`** (the user ran it on a cultist berzerker, a plague ogryn and a chaos spawn): only `anim_move_speed` and `moving_attack_fwd_speed` exist; 50 `Unit` functions mention animation, speed, time, scale or rate; the speed ones are for simple animations and crossfades. A probe built in a few minutes closed a question that source reading could not.
- **2026-10-02, the DMF log shows when a hook is really in place**: "`(hook_safe): [BtMeleeAttackAction._start_attack_anim] needs to be delayed`" at load and "`Hooking '_start_attack_anim' from [BtMeleeAttackAction]`" when the mission starts: string-class hooks work for classes that load later (settles the open question in section 1).

- **2026-10-02, a hook on a parent class does not reach its subclasses**: the game's `class()` copies the parent's methods into the subclass at creation, so our hook on `BuffExtensionBase._update_stat_buffs_and_keywords` never ran for minions (`MinionBuffExtension` has its own copy). It hid for two rounds because (a) melee worked, probably because a unit with no buff is not recomputed, so the written value stayed, and (b) the offline test called the hook by hand, so it proved the hook's logic, not that the game calls it. The user's `/rw_tune` showed it in one run: stat written 0.25, stat read 1.3.
- **2026-10-02, a stat we write must be listed in `_modified_stats`**: the game resets only listed stats before each recompute. Unlisted, a buff that arrives later is added on top of our value (factor applied twice or lost). Listed, the recompute always starts from the base value and the factor is applied once.
- **2026-10-02, the log's numbers named the culprit**: speed 1.3 and 2.25x shots are exactly `havoc_ranged_attack_speed_05` (+0.3, x2.25). The user's own hint (a shooter that stims itself raises its volley) points at the same mechanism, a buff on the minion changing these stats. Not used as a feature (no new buffs), but our factor now stacks on top of any such buff.

- **2026-10-03, custom health was never 1:1 under Havoc.** `MinionSpawnManager.spawn_minion` does `optional_health_modifier = (param or 1) + additional` where `additional` is the Havoc extension's `get_minion_health_modifier` (or the survival or circumstance modifier), and QIangIQsUltraHavoc hooks that function to return `(1 + base) * (1 + hp) * boss - 1`. The spawn parameter is therefore ADDED to, not the final multiplier. The fix writes the unit's `_health` and the game object's `health` field right after the spawn (the same two writes `HealthExtension.init` makes); the boss's `_is_weakened` is read again with the game's rule because `BossExtension.extensions_ready` made it from the wrong health. The earlier "Weakened is the game ignoring the number" reading (`b5a41c5`) was a symptom of the same cause; the user asked for the word back.
- **2026-10-03, the game's real worst case for the pooled-cards message is about 34 KB**: 100 cards of twelve groups with modifiers and custom mods measured 34265 bytes, so 90000 leaves room; the trimming in `Director.send_waves` is a safety net.
- **2026-10-03, `Director.skip` only sets the countdown to zero**: the pick happens on the next `update`; tests (and anyone scripting it) must tick once after it.
- **2026-10-03, a unit's game object exists when `spawn_minion` returns on the host**, so `HealthExtension._game_session` / `_game_object_id` can be used at once; the husks on other machines read `health` from the game object on every call.

## 3. Attempts and dead ends

- **2026-10-03, snapshot retirement mutation:** the first new regression lacked the fixture's `gid` and still used a client-only spawner, so it never sent a snapshot. Restore the host id lookup, assert populated ownership before retirement and exactly one snapshot send alongside empty final ownership. The corrected unmutated check must pass before crediting any intended mutant failure. No setup/vacuous result receives credit.

- **2026-10-03, randomized spread assertion:** one queue-cap mutant also produced 499 visibly moved points out of 500, a valid near-origin sample under uniform radial sampling. Require at least 490 visibly moved points while retaining every navmesh/radius check and the distribution assertion. This collateral sampling failure received no mutation-detection credit; only intended queue assertions count.
- **2026-10-03, final read checks:** guessed documentation/DMF paths were absent; located the real names with `rg --files`. Disabling Git newline normalization made a review diff display unchanged CRLF lines; reviewed with normal repository settings. Neither attempt modified references. The new missing-manager fixture was split into initialization/unload and subsequent gameplay-entry cases before final verification. The staged whitespace check caught an extra EOF blank line in the generated validation companion; trim the generator output before staging.

- **2026-10-03, F06 warning assertion:** the old warning-count check counted the whole harness history, including the new independent rejection fixture. Scope the count to its own failure experiment; retain the assertion of one warning despite repeated updates.

- **2026-10-03, F07 threat fallback:** the first threat check still used `tonumber(...) or 0`; Lua 5.5 converted unrecognized non-finite text to the zero fallback. Reject invalid supplied text explicitly, reserving the fallback for absent/empty legacy fields.

- **2026-10-03, F01 regression control:** the first normal-JIT weak-owner loop retained a compiler-associated reference despite cleared event keys. Disable/flush tracing only during the ownership diagnostic, as in the audit control; keep normal execution checks separate. Both runtimes are still exercised.

- **2026-10-03, audit scratch probes:** missing command stub, invalid tune id, wrong simulation helper, below-minimum fixed timer and replacing a captured RW table invalidated early probes; corrected only in `.git/audit/`. A sparse-array probe initially used an empty snapshot and was corrected before conclusions. Setup errors were excluded from finding/mutation evidence.
- **2026-10-03, empty-standard allegation disproved:** forcing private `_parts = {}` restored defaults, but the real Remove callback refuses the last standard enemy group. Keep this as a rejected hypothesis, not a confirmed UI bug.
- **2026-10-03, measurement controls:** initial preset heap growth included first-time settings and JIT traces. Warm repetitions and tracing-off controls showed a stable floor; they do not prove native/game memory stability. Proxy-font overflow markers remain live-check candidates. Windows Python has no tzdata here; Windows TimeZoneInfo verified the São Paulo date without a new dependency.

- **2026-10-03, a taller Deck tile** (270 to 292) for the cooldown row: rejected, the Deck's two rows already end at the bottom panel and the stage card (the same tile at 1.4) would hit its stats line. The row was made by moving the lower part of the tile up 18 units and giving up one composition line; a dynamic whisper height (one line for short whispers) would win the line back but makes every tile lay out differently.
- **2026-10-03, a 6 px / 8 px glow behind the last-card window's card** was not needed: the card sits on a panel darker than any suit, with an outline of its own in the suit's frame colour; only Heresy keeps its glow.
- **2026-10-01, re-asserting stats from a 0.25 s timer** (first version of the custom mods): did not work for melee/fire rate/burst because of the per-frame recompute above. Replaced by the hook; the timer stays as a fallback only.
- **2026-10-01, one global animation speed** was considered and rejected: the engine's world time scale is global (every unit and the players), not per unit.
- **2026-10-01, scaling the damage timings to fake a faster animation** was considered and rejected: without a way to speed the animation itself the hit would land before the wind-up on screen.
- **2026-10-01, keeping the number of the old setting under the new name** was considered and rejected: a "Time between attacks" of 250 that makes enemies faster reads as a bug. The number was inverted (`100 / value`) and the old names are read through a `legacy` alias list that converts once, so saved cards behave as before.
- **2026-10-02, stepping the animation time by hand** (`Unit.animation_set_time` each frame, host only) as an "Animation attack speed": rejected, the other players would see the normal-speed animation under a faster hit.
- **2026-10-02, a direct (stat-free) application of fire rate and burst inside a hook after `start_shooting`**: rejected, and no longer needed (the stat route works once the subclass is hooked). Original reasoning: If the stat the game reads is the one we write, it adds nothing; if it is not, we do not know what else is wrong. The log lines and `/rw_tune` come first.
- **2026-10-01, a virtual clock for the whole attack** (hooking `BtMeleeAttackAction.run` and feeding it `t0 + (t - t0) * speed`) would make timings, movement and damage consistent at any speed, but without an animation speed control the picture still plays at normal speed; kept as the plan for an "Animation attack speed" IF `/rw_anim` finds a control.

## 4. Insights (how to work on this mod)

- Read the game's own consumer of a value before exposing it as a setting: three of the nine custom mods needed a second round because the value was written but read at a different moment or under different rules than assumed.
- A setting named for what the stat DOES (time between attacks) is understood faster than one named for the stat (attack speed), and a name whose number goes up when the effect goes down is a bug in the UI even if the code is right.
- A test that calls a hook by hand proves the hook's logic, not that the game calls it. For every hook on a base class, ask which subclasses copy the method (`class()` copies) and hook the one that matters; the log lines added in the second round ("stat written", "started shooting") are what exposed this in a single run.
- A mutation check is worth the minute: after writing tests for a guard, remove the guard and make sure the new tests fail (done for the guarded network send: two failures).
- A test that exercises a hook with nil, missing and damaged arguments found a real bug in the probe (indexing a nil `Unit` outside its `pcall`): write the hostile-input cases first.
- When a feature cannot be proven offline, ship a probe (a debug command that prints facts) in the same change, so the first in-game run answers the open question.

- 2026-10-03: the supplied copy has 25 commits after remote 1460711 and eight dirty files. Its origin is a different repo; preserve the ancestry in the requested Grandfathers-Tarot repo. Sorting and dragging have no added regression tests. check_lua.py and logic_test.py point at an installed mod, and the other harnesses assume the repo directory is named RealmsWaves; these can validate the wrong tree or fail on a fresh clone. Fix test paths before trusting results.

- 2026-10-03: Lua 5.5-only harness syntax (floor division), utf8.len and table.unpack prevented LuaJIT checks although the mod compiled. Warming the identical loop alone was still intermittently noisy due to new LuaJIT side traces; heap checks disable tracing during measurement. Supplied feature/attack-timing has fixes absent from feature/workshop-redesign; recover that branch too before evaluating custom stats.

- 2026-10-03: two unpublished branches held complementary code. The workshop branch still hooked only BuffExtensionBase, while attack-timing had the MinionBuffExtension hook and _modified_stats fix. Merge both histories instead of duplicating the fixes. Conflict resolution retains the workshop boss naming and its improved multi-batch assertions.

- 2026-10-03: `x and tile_at(x,y) or last_target` uses last_target even when a valid cursor is outside all cards; use the current hit test directly and cancel on missing cursor. Slot-based drags must end before scrolling/reloading. UIPasses releases during drawing, after view.update, and can acquire held input merely by hovering; arm releases from real press callbacks and retain the armed press for the release frame. Double clicks require a suppressed release, not just an absent pressed callback. Mutation checking exposed a weak scrolling test that initially dropped back on its source; moving over another slot makes it detect the stale-page swap.

- 2026-10-03: front-inserting each repeat unit shifts the entire pending array repeatedly; reuse the expanded batch and append the older stack once. The old <=1000 condition allowed a batch to overflow the cap. Reverse traversal of duplicate size updates applied oldest last; index pending entries by id and replace their value. unit_exists can become true before the handle is available: do not discard that update. Returned network false is a failure even when pcall succeeds; keep a bounded live retry queue. Realms relay routes preserve the original sender, so host-only RPCs need explicit connection host checks. A fresh engine stat can coincidentally equal our last tuned write; actual reset notification is needed instead of numeric comparison alone.

- 2026-10-03: README review found duplicated release history and stale branch/test-count claims. Keep player guidance in the root README and the docs README as an index; verify defaults, compatibility and merge/release/test status against current sources. BetterInventory's old table wrongly excluded its existing Melk grid. Original Realms audit metadata (1.0.0-rc2) differs from Eduardo's installed 1.0.0, so retain the audit as a historical snapshot instead of asserting current compatibility. Documentation patch attempts failed before writes when using delete/add for one path and an assumed heading; use an update with actual file context.

- 2026-10-03: the offline harnesses have limits that look like bugs. A Lua chunk can hold 200 locals ("too many local variables"): the logic harness is near it, so new test state goes into one table. An `error("text")` caught by `pcall` carries `file:line:` in front of the text: match the two halves separately. A pass needs a `style_id` for its `change_function` to receive a style. `_apply_screen()` without `keep_offset` resets the Deck's scroll.
- 2026-10-03, process: never chain `git stash` with other commands. A compound command that stashed the working tree, then ran an empty `python -` heredoc, hung in the REPL and was moved to the background; killing the REPL let the chain's `git stash pop` run later, and my own `git stash pop` in between hit the OLD workshop stash and aborted (no harm, but only by luck). Stash only in a command of its own, check `git stash list`, and keep a patch backup (`git diff --binary > file`) first. The old `feature/workshop-redesign` WIP stash is kept (stash@{0}): its committed work and 213 of 230 uncommitted lines are in `main`, the other 17 are an earlier draft of the Deck drag code that `main` rewrote.
- 2026-10-03: the next audit request is a reusable brief, not permission to execute or fix code now. Make future audits prove reachable failures and test effectiveness, distinguish allocation churn from retained Lua/native/process memory, test bounded supported workloads separately from oversized inputs, and keep accelerated/offline experiments separate from live multiplayer and eight-hour soak claims. BetterInventory patterns require source/assumption checks before reuse.

- 2026-10-03: 1,746 existing assertions did not imply complete dynamic coverage: the first Lua 5.5 line-hook probe reached only 22.22% of `spawn/positions.lua` source lines and 57.14% of the entry module. Most hidden-point selection was only traced in prior reviews. Add tests around reachable constraints and failures, then measure both VMs; LuaJIT emits different line events for declarations. Initial instrumentation made four HUD and one editor allocation assertions fail because `debug.getinfo` allocates tables. Suspending the hook during heap probes preserves the original assertions, and restoring the prior JIT state keeps coverage interpreted. Replace the sole editor sibling-source dependency with a checked callback fixture; retain the game-source checkout solely as a read-only reference. A documentation patch that matched only the prefix of a long CLAUDE line failed before any write; use exact text substitutions for that paragraph.

- 2026-10-03: reuse BetterInventory's line events and module floors without its large case manifest/branch matrix. Exact paths, stale/new module checks, missing/error evidence and raw comparisons keep the gate meaningful. Pin dependencies/actions and ignore generated artifacts. An action-tag lookup timed out; retry resolved the upload-artifact revision. A large documentation-writing shell command was rejected before execution; structured patches completed the same edits. Windows CLI quoting broke a string-containing jq invitation filter; PowerShell JSON filtering confirmed no pending invitation. Rechecking access on request shows `EduardoKenji` still has the Write role with no admin/maintain access. A failed workflow is only a mandatory merge gate after required checks are configured by an authorized owner; document both job names.

- 2026-10-03: overriding `core.autocrlf=false` for a whitespace check misclassified the repository's existing CRLF text as trailing whitespace. The normal repository-configured `git diff --cached --check` passes; preserve repository line-ending policy. actionlint 1.7.12 passes the new workflow, and 46 local links/Python syntax checks pass. Standalone suites use a temporary index export with no sibling game source; coverage artifacts are written outside that export so cleanup does not discard the evidence.

- 2026-10-03: the user reports that an admin-role grant could not be completed for this personal repository; API checks still show Write access. That role successfully pushed the workflow branch and opened PR #5, and both push/PR Actions runs started without a permission change. CI needs no redesign or organization transfer: the owner can configure required checks and pull-request enforcement, while the collaborator maintains workflow/tests. Automatic PR runs work before merge; manual workflow_dispatch requires the workflow on the default branch. Required-check setup remains owner work, separate from publishing and test execution.

- 2026-10-03: first hosted Ubuntu/Python 3.13 PR verification passes both VMs with 1,837 assertions each. Downloaded artifacts reproduce the Windows standalone source-line scores exactly (81.56% Lua 5.5 / 78.30% LuaJIT), so the initial floors need no operating-system adjustment. Successful runtime jobs also upload usable logs/JSON with the read-only workflow token; collaborator admin permission is unnecessary for this CI execution.

- 2026-10-03: PR #5 was merged by EduardoKenji and its branch deleted while publication notes were being prepared. Pushing those notes consequently recreated the original branch instead of updating the merged PR. Rechecked PR state and origin, synchronized local main and moved the notes onto a separate documentation branch from `03785e3`. The first main workflow also passes both VMs. Recheck PR/branch state around final metadata updates when another collaborator is active; publication and merge can happen concurrently.

- 2026-10-03: continuation baseline adds a fourth failure omitted from the hand-off: LuaJIT source-line coverage of editor definitions is 77.98% against 79. These proxies count declarations and differ across VMs; distinguish changed denominators from lost behavior checks. The installed mod is an older non-Git copy, while the requested branch is remote; use a dedicated worktree. CLI string quoting stripped quotes in a Python `-c` command; use script files or PowerShell JSON parsing. Scratch substitution scripts failed before writing when an expected comment differed; match inspected text. Small-limit trimming initially fitted two cards at 300 bytes; reduce the regression fixture to 50 bytes to exercise a truly unshareable first card.

- 2026-10-03: game `BossExtension.extensions_ready` sets `_is_weakened` only for below-normal health; normal means nil, not an explicit false. The old fixture hid a guard error. Native replicated-field writes must succeed before committing the local health copy. `pcall(function, evaluated_args)` does not protect argument evaluation: wrap facing and spawn together after beginning the bypass. Mutation scratch initially omitted `RealmsWaves.mod`; adding the descriptor permits syntax checks. Child output used Windows encoding; force `PYTHONUTF8=1` before interpreting diagnostics. These scratch failures are not behavior detections.

- 2026-10-03: raw text size is not encoded RPC size; legal names can contain quotes/backslashes. Bound the escaped string and reserve transport-envelope headroom. A failed overlarge first card must not leave old peer waves active; an empty valid preset clears them. Clamp effective hover separately from pointer identity to avoid repeated work at limits. Widget bounds tests previously tolerated a real composition/modifier overlap. A HUD error test initially began hidden and could not detect stale visible content; start with a visible good card before injecting failure. Partial staged patches need LF bytes: Windows text output introduced CRLF, causing apply/whitespace errors; normalize the scratch patch, restage the selected hunks and amend the unpublished spawn commit. No working changes were discarded.

- 2026-10-03: the last-card box reserved one modifier line although legal lists can contain 96 bytes. Reuse Spread.wrap_lines with an optional limit, preserving its existing three-line name default. Uppercase text needs a wider estimate than mixed-case names: the first 0.56 estimate still overflowed the Windows-font preview, while 0.70 gives six lines for twelve Enraged labels. The native font is not available to this preview; game checks must verify names, whispers and modifiers at different scales. Two scratch patch attempts rejected stale anchors atomically; read the actual line and retry only matching hunks.

- 2026-10-03: the hand-off listed three Lua 5.5 gate problems, but a fresh LuaJIT run also exposed editor definitions at 77.98 against 79. Add both new HUD files and record every measured module, with explicit Face/definitions source-proxy exceptions instead of pretending declaration coverage is behavior coverage. Stronger assertions and 18 valid mutation detections support the repairs; native performance, renderer and transport remain separate. Both full runners now have the same 2,104 assertions. Authentication confirms write/push access but neither admin nor maintain: publication is available; owner-side administration remains open.
