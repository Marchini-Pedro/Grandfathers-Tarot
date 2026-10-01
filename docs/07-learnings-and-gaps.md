# Learnings, dead ends and open gaps

The journal the user asked for (2026-10-01): every attempt and error, discovery, actionable gap and insight, so a later session does not repeat a dead end. Newest entries first inside each section. The CHANGELOG says WHAT changed per commit; the results log in `06` says what was tested; this file says what we LEARNED and what is still missing. Keep it under 100 KB (`python tools/check_docs.py`); at 100 KB split by section into `docs/learnings/` and keep this file as the index.

Entry format: `date, short title: what happened / what was found. Evidence (file:line or test). Consequence.`

## 1. Open gaps (actionable)
Things we know are missing or unverified, each with the next concrete step.

| Gap | Next step | Since |
|---|---|---|
| Nothing of 2.0.0 (Spread HUD options, Deck look, card builder, custom mods) has been checked in a real two-player game | the user plays; matrix rows 91-96 in `06` | 2026-10-01 |
| Per-unit **animation speed** of attacks: no API found in the game scripts | a probe command is planned on branch `feature/attack-timing`; run it in game with an enemy near and send the console log; then implement against what exists | 2026-10-01 |
| Size of a custom-mod enemy on a client without RealmsWaves is the normal size | by design (see doc 03, "Custom mods per group"); only a mod on every machine can fix it | 2026-10-01 |
| `CHANGELOG.md` is 86 KB (limit 100) | split into `docs/changelog/` per major version when it passes 100 KB (`check_docs.py` warns from 80) | 2026-10-01 |

## 2. Discoveries (things the source or the game taught us)

- **2026-10-01, the melee attack-speed stat only shortens the end of an attack, and cuts chains.** `BtMeleeAttackAction._start_attack_anim` (`S\extension_systems\behavior\nodes\actions\bt_melee_attack_action.lua:259-271` for sweeps, `336-348` for other attacks) replaces the attack's end time with `max(duration / melee_attack_speed, timing + 0.2667)`. It does NOT speed the animation and does NOT move any damage timing. For a sweep attack with several hits (`attack_sweep_damage_timings` is a list of `{start, stop}` pairs) `timing` is the stop of the FIRST hit (`attack_sweep_start_or_table[2]`), not the last (the non-sweep branch uses the last, `attack_timing_or_table[#...]`). So at a high speed the action ended right after the first hit: Plague Ogryn combo (`chaos_plague_ogryn_actions.lua:379-394`: duration 3.56 s, first hit stops at 1.21 s, last at 2.84 s) at 250 percent ends at 1.48 s, before its second hit (1.81 s); the Chaos Spawn combo (`chaos_spawn_actions.lua:785-806`) is cut the same way. The user saw exactly this ("stops his chain attacks after the first attack"). The game never meets it because its own stat values are small (Havoc stimm 1.3-1.4, `havoc_mutator_local_settings.lua:378,389,456`). Fix in progress on branch `feature/attack-timing` (not merged until the user confirms it works).
- **2026-10-01, no per-unit animation speed in the game scripts.** The only animation controls a minion has are events (`anim_event`) and breed-listed variables (`animation_variables`, in practice `anim_move_speed` and `moving_attack_fwd_speed`, which steer locomotion blends); `MinionAnimationExtension` (`S\extension_systems\animation\minion_animation_extension.lua`) offers nothing else, and no script calls a unit-level speed function (`Unit.animation_set_speed`, `set_animation_speed` and similar do not occur anywhere in `S\`). The animation state machines are binary data, so a variable that scales attacks may exist but cannot be read offline. Hence a probe command is planned to list what the engine offers.
- **2026-10-01, the buff system recomputes a minion's stats every frame** while any buff touches them (a mission-wide Havoc modifier, Enraged, a player's debuff); each recompute drops stat values we wrote (`buff_extension_base.lua:318-354`, `minion_buff_extension.lua:97-101`). A 4-times-a-second re-check missed the moment an attack started, so melee/fire rate/burst "did nothing". Fixed by a post-hook on `BuffExtensionBase._update_stat_buffs_and_keywords` (CHANGELOG, "after the first in-game test"). The user's own guess (the Havoc global modifier takes priority) was right.
- **2026-09-29, 1.6.1, click-through.** A button on the destination screen must never share a spot with the button that leads there when the widget is later in draw order: the same click reaches both in one frame.
- **2026-09-29, 1.5.7, `FixedFrame` is a module, not a global.** Tests that stub a module as a global hide a missing `require`; stubs now go through `package.preload`.
- **2026-09-29, 1.5.5, twin captains start with the void shield down** (`start_depleted`); the spawner must pass `optional_init_toughness`.
- **2026-09-29, 1.5.4, the Psykhanium has no main path**; `/rw_test` there needs the ring fallback.
- **2026-09-29, 1.5.3, DMF keybinds fire while typing** (its input check is a stub that always returns true): the mod hooks `check_keybinds` while a text box is open.
- **DMF localization**: every string passes through `string.format`; a bare percent sign breaks it. Write "percent" or double it.
- **Darktide UI passes have no anti-aliasing** (rect, circle, triangle, rotated_rect): shapes get a faint wider copy (a "feather") underneath. A second left click inside the double-click window calls ONLY the `double_click_callback`.
- **Git on Windows**: PowerShell 5.1 mangles multi-line `-m` text and `Set-Content -Encoding UTF8` adds a BOM, so commit messages are written to a BOM-free file and passed with `-F`; git writing progress to stderr makes PowerShell print `NativeCommandError` even when the push worked (read the `main -> main` line). The first push needs the user to sign in through the Git Credential Manager browser window; later pushes work.

## 3. Attempts and dead ends

- **2026-10-01, re-asserting stats from a 0.25 s timer** (first version of the custom mods): did not work for melee/fire rate/burst because of the per-frame recompute above. Replaced by the hook; the timer stays as a fallback only.
- **2026-10-01, one global animation speed** was considered and rejected: the engine's world time scale is global (every unit and the players), not per unit.
- **2026-10-01, scaling the damage timings to fake a faster animation** was considered and rejected: without a way to speed the animation itself the hit would land before the wind-up on screen.

## 4. Insights (how to work on this mod)

- Read the game's own consumer of a value before exposing it as a setting: three of the nine custom mods needed a second round because the value was written but read at a different moment or under different rules than assumed.
- A setting named for what the stat DOES (time between attacks) is understood faster than one named for the stat (attack speed), and a name whose number goes up when the effect goes down is a bug in the UI even if the code is right.
- When a feature cannot be proven offline, ship a probe (a debug command that prints facts) in the same change, so the first in-game run answers the open question.
