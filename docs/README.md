# RealmsWaves: documentation index

Start here. These docs exist so nobody has to repeat the audit of TwitchVersus, RealmsEvent, Realms and the game source.

## Goal (one paragraph)
A standalone Darktide mod, compatible with the **Realms Server** mod (LAN / listen server), that spawns random enemy waves during a mission near players but out of their line of sight. Wave units ignore the director's spawn limits and do not count toward them. Waves are chosen either randomly or by an in-game player vote (configurable). Event chances are configurable percentages that total 100. Host and clients see the upcoming wave(s), vote state and countdown on their HUD, synced. No Twitch or any third-party service.

## Doc map
| File | What it holds |
|---|---|
| [01-findings-twitchversus.md](01-findings-twitchversus.md) | Audit of TwitchVersus (and a note on VersusMode) |
| [02-findings-realmsevent.md](02-findings-realmsevent.md) | Audit of RealmsEvent |
| [03-findings-realms-and-game-source.md](03-findings-realms-and-game-source.md) | Realms architecture and mod-network API; game spawn chain, limits, position/LOS APIs |
| [04-design-and-rationale.md](04-design-and-rationale.md) | Requirements, decisions and why, design per requirement, protocol |
| [05-implementation-plan.md](05-implementation-plan.md) | Ordered checklist with status, reuse map, options list |
| [06-verification-and-open-issues.md](06-verification-and-open-issues.md) | Test matrix, risks, unverified assumptions, results log |
| [07-learnings-and-gaps.md](07-learnings-and-gaps.md) | The journal: open gaps with next steps, discoveries, attempts and dead ends, insights |
| [CHANGELOG.md](CHANGELOG.md) | What changed, per commit. Every .md stays under 100 KB (`python tools/check_docs.py`); at 100 KB it is split into granular files |

## Current status
See the checkboxes in `05-implementation-plan.md`. Update this line when a phase completes.
**Status (2026-10-01): 1.13.0 is the last released state (git tag `v1.13.0`, backup zip in `Content\backups\`); the 2.0.0 "Grandfather's Tarot" rebuild is in progress (checklist in `05-implementation-plan.md`: steps 0-3 done: UI feasibility, card data model, tarot draw director, the Spread HUD; step 4 done: the Deck (4a), the cooldown looks (4b), the card builder (4c) and the polish after the user's first look at the Deck (4d: relative pips, clickable pips, right click, anti-aliasing, twelve faces); step 5 (options) done; step 6 done as "custom mods" per enemy group (health, size, run speed, time between attacks, fire rate, burst, hit mass, explosion and damage over time taken; the rename to time between attacks, the chained-attack fix and the `/rw_anim` probe are on branch `feature/attack-timing`, merged into `main` only after the user confirms them in game), its in-game test is still open). Everything is verified offline only (compile check + stubbed logic/editor/entry tests); the in-game matrix in `06-verification-and-open-issues.md` has not been run.**

Quick start for testing: disable TwitchVersus and RealmsEvent, keep Realms and RealmsWaves enabled (RealmsWaves is already the last line of `mods\mod_load_order.txt`), start a mission as host, use `/rw_status`, `/rw_test hound_frenzy`, `/rw_skip`, `/rw_roll`, `/rw_custom`. Vote keys default to F1-F3 (mod options).

**Iteration 1.1.0 (2026-09-28):** wave editor (F6 or `/rw_editor`), per-wave name/composition/chance/cooldown/enabled, 5 s minimum interval, HUD percent formatting, `custom_hud`-movable panel. Offline tests: 52 + 45 checks pass. See `CHANGELOG.md`. Still needs in-game verification.

**1.1.1-1.2.0 (2026-09-29):** stimmed-minions fix, editor crash fix (`_create_widgets` shadowing BaseView), and **modifiers** (force Garden/Enraged/etc. onto enemy groups: `3 crushers[enraged+garden]`, editor "Mods" screen). Offline tests: 62 logic + 60 editor. In-game verification pending (matrix rows 17-22 in doc 06).

**1.2.1-1.3.0 (2026-09-29):** editor hover/click fix (hotspot `visibility_function` content), **spread radius** per wave, **repeating waves** (`5 crushers@2`, repeat every/for). Offline tests: 111 logic + 89 editor. In-game verification pending (matrix rows 23-26 in doc 06).

**1.3.1-1.4.0 (2026-09-29):** both Twins + Packmaster rename, spread up to 100 m, **type multipliers** (normal+elite / boss / special, 0-500 percent), **enemy search** in the picker, "Count" renamed "Weight", limits 500 per wave / 1000 alive. Offline tests: 147 logic + 106 editor. In-game verification pending (matrix rows 27-31 in doc 06).

**1.4.1-1.4.2 (2026-09-29):** `/rw_test` by wave name; out-of-memory crash analysis and hardening (Lua memory guard option, throttled failed position searches, reload hygiene). Offline tests: 178 logic + 106 editor. Cause of the crash NOT proven (see doc 06); restart instead of hot-reloading, keep max alive/per wave moderate.

**1.5.0-1.5.1 (2026-09-29):** "Same" tick box for repeats, modifier renames (Purple, Red, Blight, Orange, Pus-Hardened Skin), new **Purple Stimm** modifier (self-created split spawner), multi-word names in brackets. Offline tests: 225 logic + 115 editor. In-game verification pending (matrix rows 36-38 in doc 06).

**1.5.2-1.5.8 (2026-09-29):** bigger popup buttons, pick enemies while the search box is open (1.5.2); typing in the editor no longer triggers keybinds, `check_keybinds` hook (1.5.3); `/rw_test` in the Psykhanium, typing opens the search, "stay or go back" toggle (1.5.4); twin captains spawn with their void shield (1.5.5); new **Rotten Armor** modifier (1.5.6); `FixedFrame` require fix, stubs no longer define modules as globals (1.5.7); shorter Rotten Armor text (1.5.8). Offline tests: 151 editor, 9 entry.

**1.6.0-1.6.2 (2026-09-29):** **wave presets** with five slots, import/export text, undo (1.6.0); Back no longer clicks through to Presets (1.6.1); options menu without wrapped lines and two per-frame allocations removed from the HUD path (1.6.2). Offline tests: 183 editor.

**1.7.0 (2026-09-29):** coloured enemy names (Spidey Sense colours when present), a "Timing and voting" screen, `interval_random`, `hud_show_percent`, wave list rows with Delete / Create / Reset. Editor tests 219. Matrix rows 51-54.

**1.8.0 (2026-09-29):** per-wave minimum and maximum spawn distance (0 = the options' values), three stepper rows in the editor panel. Editor tests 230. Matrix row 55.

**1.9.0 (2026-09-29):** share a single wave as one line of text and import a friend's wave into the first free custom slot. Editor tests 243. Matrix row 56.

**1.10.0 (2026-09-29):** host option "Use everyone's waves": clients send their enabled waves to the host over the new RPC `rw_waves`; the host merges them into the draw. Matrix row 57 (two machines needed).

**1.11.0 (2026-09-29):** **fixed timer per wave** (a wave that ignores chance and cooldown and spawns every N seconds). Editor tests 258. Matrix row 58.

**1.12.0 (2026-09-29):** editor layout (corner "More options" and "?" help), time between waves as steppers, delete any wave and Restore defaults, blank presets load the defaults, commands `/rw_stop` `/rw_start` `/rw_pause` `/rw_next`, anti-snowballing, enemy colours without Spidey Sense, Improved Havoc Tags colours for modifiers. Editor tests 289, entry 13. Matrix rows 59-64.

**1.13.0 (2026-09-29, last release before 2.0.0, git tag `v1.13.0`):** random-group button in the picker, colours that survive the cut, Ranged Twin / Melee Twin names, blue gunners, editable cooldown column. Editor tests 310. Also a compatibility check against game 1.13.0: no code change needed. Matrix row 65.

**2.0.0 "The Grandfather's Tarot" (2026-10-01, in progress; each step is a commit, see `CHANGELOG.md` and `05`):** step 1 card data model, step 2 tarot draw director, step 3 the Spread HUD (two fix rounds after the first in-game look), step 4 the Deck (4a), cooldown looks (4b), card face builder (4c), polish after the first look (4d), step 5 the options, step 6 (done as) **custom mods per enemy group** (health, size, run speed, melee attack speed - renamed time between attacks on branch `feature/attack-timing` -, gunner fire rate, shots per burst, hit mass, explosion and damage-over-time taken) plus its first fix round after the in-game test. Current offline tests: logic 0 failures, editor 497, entry 14, hud 179.

## Where the originals are now
`mods\TwitchVersus` and `mods\RealmsEvent` were purged by the user (empty marker folders). Their files remain in Vortex staging: `C:\Users\ayko4\AppData\Roaming\Vortex\warhammer40kdarktide\mods\<folder>\mods\<mod>\...` (folder names include version/date, e.g. `RealmsEvent 1338 1.1.0 2026-09-23T15-11Z l24cL2qMY`, `DT Twitch Versus realms(crash fix) 1273 5 2026-09-16T16-47Z ndQ1mdFjx(1)`). Read-only reference; do not copy them back into `mods\`.

## How to resume
1. Read this file, then `04` and `05`. Read `01`-`03` only for the area you are touching.
2. Do NOT re-audit TwitchVersus / RealmsEvent / Realms / game source unless a doc is marked stale (see versions below). If you find something new or wrong, fix the relevant doc in place and note it in `06`'s results log.
3. Original mods (`mods\TwitchVersus`, `mods\RealmsEvent`) are Vortex-managed: never edit them, only copy code from them.

## Versions audited (staleness check)
Audit date: **2026-09-28**. Compare these against the current install before trusting line numbers.

| Component | Version / id | Source |
|---|---|---|
| TwitchVersus | 1.0.0 (author Rikara) | `mods\TwitchVersus\info.json` |
| RealmsEvent | 2.0.0 | `mods\RealmsEvent\info.json` |
| VersusMode | 3.3.0 in info.json and `VersusMode.lua:451` (`.mod` says 3.0.58) | `mods\VersusMode\` |
| Realms Server | 1.0.0-rc2 (deluxghost; needs SoloPlay) | `mods\Realms\info.json` |
| DTRealmsGhostHost | 0.1.1 (Rikara) | `mods\DTRealmsGhostHost\info.json` |
| Darktide source clone | audited at commit `0f0cb45991e9305ef4a7b925370792d7d6035f95`, "Added Version 1.12.5 08-18-26"; clone now at `419fe18d4` (1.13.0, 2026-09-29), hooks/calls re-checked, see CHANGELOG | `Content\Darktide-Source-Code` (`git log -1`) |

Path conventions in these docs: mod paths are relative to `Content\mods\`; game source paths are relative to `Content\Darktide-Source-Code\scripts\` and written `S\...`.
