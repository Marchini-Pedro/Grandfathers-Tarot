# Grandfather's Tarot (RealmsWaves)

A Darktide mod that adds configurable enemy waves to local and LAN missions
hosted through Realms Server. Build a deck of waves, draw a tarot hand, or use
random selection and player voting. No Twitch service is required.

> Development status (2026-10-03): the workshop recovery is merged into `main`
> in [PR #1](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/1).
> Offline checks pass; the recovered changes still need in-game and multiplayer
> verification. The runtime reports `2.0.0`; the last tagged release is `v1.13.0`.
> The open branch `feature/heresy-card-and-ui-pass` (exact custom health, the HERESY suit, 100 cards,
> a last-card window, cooldowns on the Deck tiles, `/rw_test_close`, card-coloured pages) has offline
> tests only: it is not merged and nothing of it has been played yet.

## Features

- **Three wave modes:** tarot draws with card cooldowns, weighted random waves,
  and player ballots, with a synchronized countdown and HUD.
- **The Deck:** up to 100 cards; create, enable, share and import waves; set a
  card's chance (the pips) and cooldown (the `-` / `+` on its tile) in place; save five
  **Deck presets**; sort cards by threat, rarity, enemy count or face; drag to swap
  cards on a page. **HERESY** is the one special suit (frame and glow of its own).
- **The Cauldron:** build enemy groups with a searchable catalog and Dreg/Scab
  shelf, modifiers, custom stats and a live card preview.
- **The Mirror:** customize the card's suit, threat, whisper and cooldown look,
  with a preview of its appearance in the hand.
- **Last card window:** a HUD window with the card whose wave went out last and how long
  ago, the same on every player's screen (option "Last card", movable with Custom HUD).
- **Wave controls:** weights, spawn distances, spread, repeating groups, fixed
  timers, enemy-type multipliers and optional pooling of players' waves.
- **Host controls:** pause, stop, resume or advance the cycle; configurable
  per-wave and live-enemy limits and a Lua heap guard.

## Requirements and installation

Install Darktide Mod Loader, Darktide Mod Framework, SoloPlay and
[Realms Server](https://www.nexusmods.com/warhammer40kdarktide/mods/1223)
with its required dependencies. Waves need a local or LAN host with server
authority; a client in an ordinary online mission cannot spawn them.

1. Download this repository and place its contents in
   `Content/mods/RealmsWaves/`. Rename the extracted repository folder if needed.
2. Confirm the descriptor is at `Content/mods/RealmsWaves/RealmsWaves.mod`.
3. Add `RealmsWaves` on its own line in `Content/mods/mod_load_order.txt`,
   after `Realms` and its dependencies. The internal mod name is **RealmsWaves**.
4. Restart Darktide. Disable TwitchVersus and RealmsEvent when testing this mod
   to avoid overlapping wave systems.

Install the same development revision on participating players' machines for
the shared HUD, voting and enemy-size replication.

Optional integrations: Custom HUD can reposition the wave panel; Spidey Sense
and Improved Havoc Tags supply enemy/modifier colours when installed.

## Getting started

1. Open **Mod Options > Realms Waves** to choose a mode, timing and spawn limits.
2. Press **F6** or use `/rw_editor` to open the Deck. Select a card to edit its
   enemies in the Cauldron or its appearance in the Mirror.
3. Start a Realms mission as host. Use `/rw_status` to inspect the cycle and
   `/rw_test hound_frenzy` to test a wave. Vote keys default to **F1–F3**;
   the keybindings are configurable in Mod Options.

| Command | Effect |
| --- | --- |
| `/rw_editor` | Open or close the wave editor |
| `/rw_status` | Show director state and spawn counters |
| `/rw_test <wave key or name>` | Spawn a test wave immediately, out of sight (host) |
| `/rw_test_close <wave key or name>` | Spawn the wave right in front of you, facing you (host) |
| `/rw_start` / `/rw_stop` | Start or stop the cycle; stopping leaves spawned enemies alive (host) |
| `/rw_pause [on\|off]` | Freeze/resume wave clocks and queued spawns; living units stay maintained (host) |
| `/rw_next` | Discard the current wave and draw a new one (host) |
| `/rw_skip` | Resolve the current wave immediately (host) |

## Current limits

- [Audit remediation](docs/audits/2026-10-03/remediation.md) fixes reload event
  cleanup and pause/stop/disable ownership offline. Stop cancels pending work
  while surviving units remain counted and tuned. Disable suspends tuning/hooks
  and cancels jobs; re-enable needs `/rw_start` on the host and resyncs clients.
  Pending work is capped at 64 jobs / 8,000 entries; full budgets skip new waves
  and repeat ticks. Imports reject non-finite numeric fields. Size updates retry
  rejected peers with current living-unit values. All fixes await game acceptance.

- The recovered workshop, drag interactions and multiplayer changes have
  offline coverage; actual game rendering, frame time and process RAM remain
  unmeasured. Start with moderate enemy counts and restart for clean testing.
- Custom **Time between attacks** changes attack timing. Animation playback
  speed has no confirmed per-unit API and is not an implemented control.
- Enemy size replication requires RealmsWaves on each peer. A custom health is
  exact (normal health times your percent, whatever Havoc adds); a boss below its
  normal health keeps the game's own **Weakened** name.

See the [recovery review](docs/09-recovery-review.md) and
[verification matrix](docs/06-verification-and-open-issues.md) for remaining
game checks and compatibility details.

## Development

From the repository root, with Python and `lupa` installed, run:

```powershell
python tools/check_lua.py
python tools/logic_test.py
python tools/editor_test.py
python tools/entry_test.py
python tools/hud_test.py
python tools/check_docs.py
```

The editor harness needs the sibling
`Content/Darktide-Source-Code/scripts/` reference checkout. UI preview tools
also need Pillow. Offline tests use engine stubs and do not replace game tests.

The [documentation index](docs/README.md) links design decisions, implementation
status and historical audits. [CLAUDE.md](CLAUDE.md) defines the contribution
workflow; the [changelog](docs/CHANGELOG.md) records detailed changes.
