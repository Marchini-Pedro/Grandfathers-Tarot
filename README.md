# Grandfather's Tarot (RealmsWaves)

A Darktide mod that adds enemy waves and beneficial tarot cards to local and LAN
missions hosted through Realms Server. Build a deck, draw a tarot hand, or use
random selection and player voting. No Twitch service is required.

> Development status (2026-10-04): `main` includes the card effects of
> [PR #9](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/9). The branch
> `feature/cauldron-redesign` adds Faith, a crimson Heresy, Nightmare (once per game), one
> cooldown look, the beneficial shelf and card sounds that play at the draw ([guide](docs/13-cauldron-redesign.md));
> offline checks pass, game acceptance is pending.
> Runtime version: `2.0.0`; last tagged release: `v1.13.0`.

## Features

- **Three wave modes:** tarot draws with card cooldowns, weighted random waves,
  and player ballots, with a synchronized countdown and HUD.
- **The Deck:** up to 100 cards; create, enable, share and import cards; set a
  card's chance (the pips) and cooldown (the `-` / `+` on its tile) in place; save five
  **Deck presets**; sort cards by threat, rarity, enemy count or face; drag to swap
  cards on a page. **HERESY** (crimson; its glow beats like a heart and it bleeds in the HUD), **NIGHTMARE** (black,
  a breathing darkness and a dying light, black ink, a black fog over the card and, when drawn, over the screen and a grey
  world for every player (option "Nightmare darkness": 30 the usual, 100 almost black); once per game), **Warp** (a pulsing glow and rising motes), **Prayer**, **Miracle**,
  **Grace** and **Faith** have their own frames and sigils.
- **The Cauldron:** build enemy groups with a searchable catalog and Dreg/Scab
  shelf, modifiers, custom stats and a live card preview. The On Fire modifier has its
  burn damage (0 to 300 percent, 35 by default) on the right of its row, and its enemies
  keep burning while they live. The editor key reopens the screen you left; the Deck
  keeps its scroll.
- **Enemy colour experiments:** per-group ARGB sliders and a method dropdown
  under **Custom > Enemy colour experiments**. Try natural/applied stimm,
  explicit loadout tint with an independent outline and protected-colour toggle.
  Surface/shader methods are visibly unavailable; their requirements remain documented.
- **Beneficial cards:** a shelf in four groups: **Healing** (party health,
  corruption cleanse, Green Stimm, Med Crates; Med Station is off for now),
  **Buffs** (combat abilities, reveal Specialists, Yellow/Blue/Red Stimm buffs),
  **Items** (Yellow/Blue/Red Stimm items) and **Game Effects** (raise one downed and one
  hogtied player and bring them back, instant rescue of the next downed players, refill ammunition, replenish grenades,
  Ammo Crates).
  Hostile cards can add a timed **Blackout**. The Deck has **Search cards**.
- **Card sounds:** game sounds and enemy and player voice lines, a movable search box,
  Preview on every row, up to two sounds in a row and a volume each (experimental).
  The sound plays for everyone the moment the card is drawn; the wave spawns when it ends.
- **The Mirror:** suit (12 hostile or 4 beneficial behind a switch), six manual
  strength pips (level 6 is Despair, or Apotheosis on a blessing, and shines),
  whisper and cooldown; every card rots and renews. A threat 5 or 6 card's whisper
  murmurs letter by letter when it is drawn.
- **Test commands:** `/rw_test` and `/rw_test_close` play the card's sound, then spawn; `/rw_drawtest <card>`
  stages a three-card draw that picks it after 3 s (HUD only); `/rw_fulltest <card>` does the same with its sound and wave.
- **Boss bars:** while a boss is up the Draw HUD slides below the boss health bars (or keeps the top and moves the
  bars below it) and turns see-through (options). A boss with more health than the network carries shows it in
  bars, with "xN" for the full bars still to go.
- **Last card window:** a compact full card face with its name, flavor, sigil and age,
  synchronized for every player. It has its own transparency slider and is movable
  with Custom HUD. Draw/Last Card omit enemy modifier labels.
  Stopping the cycle clears the window on host and clients.
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
the shared HUD, voting, enemy-size and enemy-colour replication.

Optional integrations: Custom HUD can reposition the wave panel; Spidey Sense
and Improved Havoc Tags supply enemy/modifier colours when installed; optional
No new dependency is required.

## Getting started

1. Open **Mod Options > Realms Waves** to choose a mode, timing and spawn limits.
2. Press **F6** or use `/rw_editor` to open the Deck. Select a card to edit its
   enemies/effects in the Cauldron or its appearance in the Mirror. Share through
   **Share Card** or the small per-card glyph (toggleable in Mod Options). Shared texts
   survive Discord and other Markdown chats; texts from older versions still import.
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

- Pooled decks send the first enabled cards that fit Realms' encoded message
  limit and warn once when cards are omitted; if no card fits, the shared pool
  is cleared. Local decks still hold up to 100 cards.
- Beneficial effects, Blackout, colour protection and completion audio still need
  [native acceptance](docs/12-card-effects-and-ui.md); so do the
  [Cauldron redesign](docs/13-cauldron-redesign.md) effects. A sound volume below 100
  is an experiment (the game has no per-sound volume), and a card with two sounds or
  a volume is silent for older peers. Use matching development
  revisions on peers for guidance and remote ability restoration. Blackout controls
  native light controllers; event names do not guarantee all sound banks are loaded.
- The recovered workshop, drag interactions and multiplayer changes have
  offline coverage; actual game rendering, frame time and process RAM remain
  unmeasured. Start with moderate enemy counts and restart for clean testing.
- Custom **Time between attacks** changes attack timing. Animation playback
  speed has no confirmed per-unit API and is not an implemented control.
- Enemy size replication requires RealmsWaves on each peer. A custom health is
  exact (normal health times your percent, whatever Havoc adds); a boss below its
  normal health keeps the game's own **Weakened** name.
- Enemy colour **A** means tint strength, not mesh transparency. Natural stimm
  keeps vanilla gameplay buffs on supported breeds. Black matches the stimm
  reset; [near-black readability](docs/enemy-appearance.md#black--near-black-stimm-feasibility-2026-10-03)
  is unverified. Surface recolouring and
  private shader patches are unavailable until compatible material data/assets
  are verified. Colour coverage and cleanup still need game acceptance; disable
  removes experimental colours and re-enable needs fresh coloured spawns.

See the [recovery review](docs/09-recovery-review.md) and
[verification matrix](docs/06-verification-and-open-issues.md) for remaining
game checks and compatibility details.

## Development

From the repository root, with Python 3.13 installed, run:

```powershell
python -m pip install -r tools/requirements-test.txt
python tools/run_tests.py --runtime lua55 --output-dir test-results/lua55 --timeout-seconds 280
python tools/run_tests.py --runtime luajit21 --output-dir test-results/luajit21 --timeout-seconds 280
```

The runner compiles Lua, runs every offline harness, checks documentation sizes
and enforces coverage floors. Logs and JSON reports go to `test-results/`.
GitHub Actions runs both runtimes on pushes and pull requests; see the
[coverage review and gate policy](docs/10-ci-and-coverage.md).
Tests run from a standalone checkout using engine fixtures. UI previews also
need Pillow. Offline tests do not replace game tests.

The [documentation index](docs/README.md) links design decisions, implementation
status and historical audits. [CLAUDE.md](CLAUDE.md) defines the contribution
workflow; the [changelog](docs/CHANGELOG.md) records detailed changes.
