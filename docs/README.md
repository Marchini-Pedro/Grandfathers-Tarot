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

## Current status
See the checkboxes in `05-implementation-plan.md`. Update this line when a phase completes.
**Status (2026-10-01): 1.13.0 is the last released state (git tag `v1.13.0`, backup zip in `Content\backups\`); the 2.0.0 "Grandfather's Tarot" rebuild is in progress (checklist in `05-implementation-plan.md`: steps 0-3 done: UI feasibility, card data model, tarot draw director, the Spread HUD; Deck screen, the remaining options and the optional multipliers still open). Everything is verified offline only (compile check + stubbed logic/editor/entry tests); the in-game matrix in `06-verification-and-open-issues.md` has not been run.**

Quick start for testing: disable TwitchVersus and RealmsEvent, keep Realms and RealmsWaves enabled (RealmsWaves is already the last line of `mods\mod_load_order.txt`), start a mission as host, use `/rw_status`, `/rw_test hound_frenzy`, `/rw_skip`, `/rw_roll`, `/rw_custom`. Vote keys default to F1-F3 (mod options).

**Iteration 1.1.0 (2026-09-28):** wave editor (F6 or `/rw_editor`), per-wave name/composition/chance/cooldown/enabled, 5 s minimum interval, HUD percent formatting, `custom_hud`-movable panel. Offline tests: 52 + 45 checks pass. See `CHANGELOG.md`. Still needs in-game verification.

**1.1.1-1.2.0 (2026-09-29):** stimmed-minions fix, editor crash fix (`_create_widgets` shadowing BaseView), and **modifiers** (force Garden/Enraged/etc. onto enemy groups: `3 crushers[enraged+garden]`, editor "Mods" screen). Offline tests: 62 logic + 60 editor. In-game verification pending (matrix rows 17-22 in doc 06).

**1.2.1-1.3.0 (2026-09-29):** editor hover/click fix (hotspot `visibility_function` content), **spread radius** per wave, **repeating waves** (`5 crushers@2`, repeat every/for). Offline tests: 111 logic + 89 editor. In-game verification pending (matrix rows 23-26 in doc 06).

**1.3.1-1.4.0 (2026-09-29):** both Twins + Packmaster rename, spread up to 100 m, **type multipliers** (normal+elite / boss / special, 0-500 percent), **enemy search** in the picker, "Count" renamed "Weight", limits 500 per wave / 1000 alive. Offline tests: 147 logic + 106 editor. In-game verification pending (matrix rows 27-31 in doc 06).

**1.4.1-1.4.2 (2026-09-29):** `/rw_test` by wave name; out-of-memory crash analysis and hardening (Lua memory guard option, throttled failed position searches, reload hygiene). Offline tests: 178 logic + 106 editor. Cause of the crash NOT proven (see doc 06); restart instead of hot-reloading, keep max alive/per wave moderate.

**1.5.0-1.5.1 (2026-09-29):** "Same" tick box for repeats, modifier renames (Purple, Red, Blight, Orange, Pus-Hardened Skin), new **Purple Stimm** modifier (self-created split spawner), multi-word names in brackets. Offline tests: 225 logic + 115 editor. In-game verification pending (matrix rows 36-38 in doc 06).

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
