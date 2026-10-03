# 04. Design and rationale

Written 2026-09-28. Findings backing each claim are in docs 01-03.

## Enemy colour experiments (2026-10-03)

The [appearance implementation](enemy-appearance.md) adds per-group ARGB sliders
and a method dropdown on `feature/enemy-appearance`, isolated from concurrent
CI work. Recipes serialize `<method:AARRGGBB>` after custom stats and before
repeat notation. Appearance participates in group identity and copies; the
editor follows the edited group when identical groups merge on save.

Usable experiments are natural stimm, visual-only applied stimm, explicit
loadout stimm and local outlines. Natural stimm uses existing breed actions and
vanilla buffs; it is the intentional gameplay-affecting option. RGB methods
interpret A as tint strength. Surface overrides/private patches display their
unverified prerequisites and perform no native operation; no guessed property,
shared template edit or asset dependency is introduced.

The optional Realms appearance capability preserves HUD protocol 2 / 2.0.0,
validates host/token/IDs/breeds/byte channels and renews bounded local ownership.
Late joins get living snapshots; native colour support and restoration of
untracked direct material writes remain live-test limits. See the linked design
for cleanup, lease limits, test controls and advanced-method gates.

## Requirements (user's words, verbatim)
User has two installed mods, "Twitch Versus (Beta) (Realms Compatible)" and "RealmsEvent" (both installed via Vortex). Merge them into a complete new version/mod:
- Compatible with the Realms Server mod ("Adds LAN multiplayer support to Darktide. A local single-player game can also run as a LAN listen server.").
- No Twitch dependency or anything third-party related, so everything must be done in-game among players with the mod itself.
- A random event throughout the mission that will spawn enemies near players but not in their line of sight.
- Those units should IGNORE the spawn limit and shouldn't count towards the max limit of the director/map.
- A configurable voting system with two modes: randomly chosen or players vote in-game. The idea is to randomly spawn one standard or custom event where a set of enemies spawn.
- A configurable % chance of events occurring, totalling 100%.
- It should render information about the next possible waves on the screen of both host and clients, synced.
- (Added later) Document all findings, insights, rationale and plan in .md files so no full audit/discovery has to be repeated. -> these docs.

## Decisions and why
| Decision | Why | Rejected |
|---|---|---|
| **New standalone mod `RealmsWaves`** in `mods\RealmsWaves` | Originals are Vortex-managed (updates overwrite edits); merge crosses two codebases; user just disables the originals | Editing RealmsEvent in place |
| Base layout on RealmsEvent, spawn code from TwitchVersus | RealmsEvent has the clean Realms protocol/handshake/scheduler; TwitchVersus has the good position search, recipe parser, wave data, spawn queue | Starting from TwitchVersus (no network layer) |
| Vote mode = ballot of N (default 3) candidates drawn by weight; Random mode = pre-rolled next wave shown with countdown | Gives both modes a meaningful synced HUD ("next possible waves") and matches TwitchVersus's `draw_ballot` idea | Always showing the whole chance table |
| Percent per event, normalised to 100 over enabled events; same weights drive rolls and ballots | Satisfies "totalling 100%" without forcing the user to hand-balance; store raw weights, display `weight/sum*100` | Additional per-interval trigger chance (offered, not chosen) |
| Voting by rebindable keybinds (vote_1..vote_3) | Works mid-combat, for host and clients, no menu | Chat commands |
| Direct `spawn_minion` + tracked-unit set + hooks that hide tracked units from the director counters | Pacing has no per-breed exemption flags (doc 03); direct spawning already bypasses gating; hooks make units "not count" | Disabling pacing (would break normal game), raising `HARD_ALLOCATED_LIMIT` (an upvalue) |
| Spawn-only events (RealmsEvent's 5 + TwitchVersus waves + custom recipes) | User's request is "a set of enemies spawn"; buff/ammo events are out of scope | Porting all 26 RealmsEvent events |

## Design per requirement

### 1. Realms compatibility
- `get_mod("Realms")` in `on_all_mods_loaded`; register RPCs there; dot-call the API (doc 03 Part A).
- Authority = `Managers.state.game_session:is_server()` and non-nil `Managers.state.minion_spawn`. No spawning in `hub`/`prologue_hub`. Every server-only manager is nil-guarded (absent on clients).
- Only the host drives the director; clients render HUD and cast votes.
- Ghost host: pick positions from living human units, never assume the host has a unit; if there are no living humans, skip the wave and retry.

### 2. No third-party
No HTTP, OAuth or `Managers.backend:url_request`. Triggers = timer + in-game vote only.

### 3. Near players, out of sight
- Host timer: min/max interval after `event_mission_objective_start` and `main_path:is_main_path_ready()`.
- Position finder: choose a random living human, anchor near them via `MainPathQueries.position_from_distance(travel +/- offset)`, snap with `NavQueries.position_on_mesh_with_outside_position`, then `SpawnPointQueries.get_occluded_positions` given ALL human positions; enforce min/max distance to the nearest human (defaults 20-60 m; monsters 30-70 m). Stage fallbacks like TwitchVersus (widened, relaxed); if nothing occluded is found, retry later. Never fall back to in-view (differs from TwitchVersus's `unoccluded` last resort).
- pcall around engine queries; use `get_occluded_positions` / `occluded_positions_in_group`, not `get_random_occluded_position`.

### 4. Ignore the limit, do not count
- Spawn directly: `spawn_minion(breed, pos, rot, villains_side_id, param)` with `optional_aggro_state = "aggroed"` and a target.
- Track mod-owned units in a set (add on spawn; remove on death/unregister).
- `spawn/budget_bypass.lua` hooks: `PacingManager.add_aggroed_minion` (skip tracked units, so challenge rating never rises); `MinionSpawnManager.num_spawned_minions` and `total_allocated_num_enemies` (subtract tracked count, clamp at 0). This keeps hordes/specials/monsters running as if the wave did not exist.
- User-tunable safety valves: max units per wave and max mod-owned alive units (default about 120). Beyond the valve, queue rather than drop. Never queue >~200 (256 ring buffer, no overflow guard). Drip-feed 2 units per 0.15 s.
- Rationale for valves: engine unit/network object limits are real even when the director's are ignored.

### 5. Voting (two modes)
- `random`: host rolls by weight, broadcasts the pending wave with countdown, then spawns.
- `vote`: host draws N distinct candidates by weight, broadcasts ballot, opens a vote window (configurable seconds). `rw_vote(ballot_id, option)` from clients; host votes locally. One vote per peer id, changeable until close. Live counts broadcast. Ties random. Zero votes -> weighted-random pick (or skip wave; setting).
- Event sources: standard events (RealmsEvent 5 spawn events, TwitchVersus wave tiers, some single-breed groups) and up to 20 custom recipe slots (`"5 trappers, 5 mutants, 10 hounds"`, parser from TwitchVersus `Groups.parse`).

### 6. Percent chances
Per-event percent setting (stored as raw weight). Normalised across enabled events to total 100 for display and rolls. Per-event cooldown prevents immediate repeats. Persist as a flat string setting like RealmsEvent's `event_pool_state` (nested tables crash DMF sjson save).

### 7. Synced HUD
- `hud_element_waves` registered for alive/dead states. Shows phase (Next wave / Voting / Incoming), candidate names with percent and live votes, countdown, winner highlight.
- Host sends compact `rw_state` on every change and about once per second for the countdown (remaining seconds, not absolute time: peers' clocks differ). Clients render from the last received state and interpolate locally between updates. Late joiners get the state on `peer_joined` and after `welcome`.
- Host drops its own broadcast loopback (as RealmsEvent) and renders from the same state table it sends.

### 8. The tarot draw (2.0.0, default mode)
- **Cycle**: `waiting` (interval countdown) -> at `remaining <= hand_window` the host deals a hand (`phase = hand`) -> at 0 the winner spawns, the next interval starts at once and the hand stays 16 s in the state with `drawn = true`. `hand_window = min(tarot_seconds, interval)`.
- **Deal**: eligible = enabled, has enemies, weight > 0, not on a fixed timer, not cooling down. X cards (`tarot_cards`, 1-5) are drawn by weight without replacement; fewer eligible cards than X means a smaller hand. The winner index is `math.random(1, #hand)` (uniform) and is chosen at the deal and sent with it, so every client's roulette lands on the same card. One card: no roulette.
- **Cooldown**: `last_fired[key]` is stamped with `cd_clock` (seconds of played time: it advances only when the director is not paused and a player is alive) and a card is eligible again only when `cd_clock - last_fired >= cooldown`. Nothing eligible: `empty` state (`e = 1` nothing in the draw, `e = 2` all cooling down), retry after 10 s.
- **Clients** never run the draw: they render the last hand, keep the cooldown map (`cd`: seconds left per cooling card) and count it down locally.
- Everything a card shows comes from `Cards.describe` on the host (name, suit, threat, enemy kinds, whisper, rarity, modifiers), so a client without a card's wave (a friend's custom card) still draws it. A card never carries its chance.

### 10. The Deck (2.0.0, the editor's home screen; the card's own screens, the Cauldron and the Mirror, are in `08-workshop-redesign.md`)
- **Screen id** stays `"list"` (Back, the presets and every other flow still return to it), but what it shows is the Deck. `_source()` returns `self._deck`: the standard cards (also when emptied) and the custom cards with enemies, then a blank sentinel while a custom slot is free. Pages are whole rows: `Deck.max_offset`, `Deck.clamp_offset`; the scroll buttons and the wheel move seven cards.
- **A tile** (228 x 270, `blueprints.tile`) is shapes and text like the HUD (rect, circle, triangle, rotated rect, text, the stock `frame_glow_01` glow), painted by `View._paint_tile` from `Cards.describe(wave, groups, rgb_of, self._deck_range)`; hover (the face takes the suit's lighter colour) is a `change_function` on the background, everything else is written on refresh. Hotspots that never overlap: the face (toggles `on_<key>`, to y 235), ten pips (y 235-249, side by side from edge to edge: `blueprints.pip_hit`; `cb_tile_pip` writes `pct_<key>`), the left of the state line (toggle) and the Edit pill (46 x 16, `_open_detail`; its click area is exactly its lit box). `right_pressed_callback` on every hotspot opens the card; `double_click_callback` repeats a pip or the pill (the hotspot pass (`ui_passes.lua` hotspot) calls ONLY the double click callback for a second click inside the threshold, so without it a fast second click is lost; the toggles are left without it on purpose). A card out of the draw: `widget.alpha_multiplier` 0.55 and its colours pulled 70 percent toward grey.
- **Under the name**: the number of lines the name takes (`View._name_lines`: the game's `Text.text_height` with the pass style when the view has a `_ui_renderer`, else `Spread.wrap_lines` with a careful glyph width) decides `Deck.layout`: divider, composition start and how many composition lines fit (5 / 4 / 2) before the modifier line at y 164. The modifier line is `Cards.modifier_line(parts, groups, paint)` with colour tags from `colors.modifier_rgb` (whole numbers: the tag is written with `%d`).
- **Chance levels** (`Cards.level`, `is_rare_level`, `weight_for_level`): relative to the lightest and heaviest weight of the cards in the draw (`View._draw_range`, the director's `pool_range`); see the CHANGELOG entry "Deck polish". The literal min-max reading was chosen because the user asked for "ten rectangles = the highest chance, one = the lowest"; a proportional reading (`w / w_max`) would keep a card of weight 5 among 5..10 at five pips and the lightest card would rarely be one pip. It is one function to change.
- **The strip** (`blueprints.strip`): `Deck.strip_segments` makes one segment per card in the draw; the draw rule is the director's (enabled, enemies, weight, no fixed timer). Cooling cards stay in the draw (they are only temporarily out).
- **Cooldowns** on a tile come from `director.cooldown_remaining(key, cooldown)` (the host's own clock, a client's synced map), the state line says "Back in" and the clock.
- **Palette**: `Components.colors` is the Plague Tarot palette for every editor screen.

### 11. The card face (the Mirror, 2.0.0, rebuilt in 2.1.0)
- Screen id `"face"`, entered from `"detail"` with the Face tab (Back or the Enemies tab returns there). Since 2.1.0 it is no table: four sections (suit plates, threat diamonds, a whisper field, the cooldown with three look plates) and the same stage as the Cauldron on the right; see `08-workshop-redesign.md` for the layout and the reasons. The whisper box shows what is typed live on the card; Reset face (`Events.reset_face`) puts the face back.
- `Cards.suggest_suit` and `Cards.threat_auto` (catalog/cards.lua) feed the suggestion mark and the "by the numbers" line; nothing is computed twice.
- The card on the stage is a tile widget (`rw_stage_card`, scale 1.4) painted by the Deck's `_paint_tile`; its hotspots are disabled. "In the hand" is the Spread HUD's card at 1.5 times, laid out with the HUD's own numbers (`ui/spread.lua`).
- A standard card cannot be given "no whisper": an empty setting means the card's built-in line (or the suit's line when it has none), as in the data model.

### 12. Custom mods of a group (2.0.0, the brief's optional step 6, extended)
- **Data**: `part.tune = { health = 150, size = 130, ... }` (percent, only values that differ from 100), written in the recipe after the modifiers: `3 crushers[enraged]{health=150 size=130}@2` (`Groups.TUNE`, `parse_tune`, `tune_recipe`, `tune_text`; part keys include it, so different tunings never merge). Because it is part of the recipe it travels with everything that carries recipes: the card's own setting, shared cards (RWW1), presets, "everyone's waves".
- **Editor**: the row blueprint got a third button (Mods 1372, Custom 1482, action 1592; 104-108 wide each, after the count stepper that ends at 1362), screen `"tune"` (`ui/wave_editor_tune.lua`) with the ordinary rows: stepper (the value's step), number box (its range), Reset (action button), the row name coloured while changed. Back returns to the card's screen.
- **Spawning** (`spawn/tuning.lua`, host): health as the spawn parameter, the rest right after `apply_modifiers` (so attack speeds and hit mass are relative to what Enraged and the like already did). Stats are kept on top by a post-hook on the buff system's per-frame recompute (`BuffExtensionBase._update_stat_buffs_and_keywords`) plus a 0.25 s check as a fallback (a written stat that the buff system rewrote gets the factor again, once). Sizes go out in batches of up to 100 every 0.3 s (`rw_scale`, a JSON list of `[id, percent]`), and to a peer that says hello later; clients keep a size up to 20 s until its unit exists there. Every step is in `pcall` and logged once; a missing extension only skips that value.
- **Why not buffs**: a buff template carries numbers, and a new template would be a new `NetworkLookup` entry (docs/03, "Enemy variants without new breeds"); every value used here is already read by the game's own code (docs/03, "Custom mods per group").
- **Time between attacks and why it is a time (2.0.0, `feature/attack-timing`)**: the stat the game reads is a speed that only shortens the end of an attack, so the setting is named for what it does (a TIME between attacks, 100 = normal, 50 = half the wait) and the stored number is inverted (`100 / value`) before it is written; a setting whose name says "time" and whose number gets bigger when the wait gets shorter is a UI bug even when the code is right. Old recipes keep their behaviour through a `legacy` alias list in `Groups.TUNE` that converts the number once, on reading. A hook after `BtMeleeAttackAction._start_attack_anim` lengthens the attack of a unit with this setting to the end of its LAST hit, because the game's own end measures the first hit of a chain (docs/03). An "Animation attack speed" setting (a faster swing) is NOT built: the game has no per-unit animation speed in its scripts; `/rw_anim` asks the running game what exists (docs/07).
- Rejected: scaling by stacking Rampaging (only 2 percent a stack, five stacks, plus its damage resistance); sending stats to clients (they are host-side AI values, clients never read them).

### 9. The Spread HUD (2.0.0)
- **Files**: `ui/spread.lua` (pure arithmetic: sizes, layout, roulette, timeline, eye and icon shapes, rot geometry; tested offline), `ui/hud_element_waves_definitions.lua` (the widgets), `ui/hud_element_waves.lua` (the element: legacy text panel + the Spread).
- **One node.** Everything is drawn inside the scenegraph node `panel` (700 x 262): custom_hud lists every non-root node, so a second node would be a second thing to drag. The node is on a **top-left basis** (`horizontal_alignment = "left"`, position x 610, y 36, which is the middle of 1920 units), because that is the basis custom_hud pins nodes on and draws its edit box on; a centre-aligned node made its box sit away from the HUD (first in-game test: "should be editable by custom HUD"). Widgets: `legacy` (the old text lines), `header` (label, time, status, fuse), `card_1..5`, `fx` (rot), `banner`. Layers are z offsets (header 10, cards 20-40, fx 70+, banner 100), because widget order is not defined (they come from a `pairs` loop).
- **A pure function of the view.** The stage comes from `view.remaining` (hand, roulette) or `view.drawn_age` (reveal, rot), never from the HUD's own clock, so host, clients and late joiners agree. Stages: waiting, hand, roulette, reveal, rot (`Spread.timeline`). The highlight of the roulette is `Spread.roulette_index(count, winner, p)`: three laps, ease-out `1 - (1 - p)^2.2`, one card per step, lands on the winner.
- **Drawing without icons.** Pass types in use: `rect`, `circle`, `triangle` (corners relative to the pass offset, `triangle_corners`), `rotated_rect` (45 degrees: no rotation direction to get wrong), `text`. Suit marks are shape slots (4 triangles + 4 circles) filled by `Spread.icon` from the reference's 24-unit grid; a slot colour is the suit's accent or the card's own background (to cut a hole: the moon's bite, the drop's inside, the eye's inside). The eye is two drawings that cross-fade as it opens: shut = the smile of a lid (the reference's curve sampled at 7 points and drawn as a 6-segment ribbon of triangles) with three lashes; open = a lens (a diamond whose height is the opening) with an inside and a pupil. The first in-game test showed that a "sliver with lashes" looked like an insect. Glow of a highlighted card = the stock `frame_glow_01` texture (used by the spectator HUD) tinted with the suit colour. Every diamond, dot and every shape of a suit mark has a faint (30 percent), slightly larger (0.55 units, `Spread.FEATHER`) copy under it, one half layer lower than its shape: the UI draws triangles, circles and rotated rectangles without anti-aliasing and the copy softens the jagged edge. Empty threat diamonds are the same diamonds dimmed, not an outline. Dots shrink and are cut down (`Spread.dots_fit`) so they never come closer than 12 units to the diamonds. `tools/hud_preview.py` rasterises the same geometry into a PNG to look at the shapes without the game.
- **No allocation per frame.** `Spread.*` write into tables owned by the element; the element writes into widget style tables; strings (time text) are built only when the displayed second changes. Whole-card fades and the dimming of the rot use the widget's own `alpha_multiplier` and `color_intensity_multiplier` (one number each), and the raise uses `widget.offset`.
- **Rot** (`Spread.rot_fx`): blotches (a stack of four circles, the outermost the faintest: a soft edge without a gradient; a blotch grows until it touches the card's nearest edge, the first in-game test showed that clipped squares look nothing like the reference), flies on circles around the centre, drips below the card, a brown wash, the whole card darkening and fading (no sag: the text does not move with the card layer). Strength `k` and duration come from the card's cooldown (synced as `c`) and the player's own timeline options.
- **Look options** (per player, read every frame, applied at once): size and opacity act in the `draw` override (renderer scale x size about the node corner, widget alpha x opacity, undone afterwards); timer below and hide-the-symbol change the layout (`Spread.layout(layout, hand, options)`: `cards_y`, `time_y`, `name_w`); the font option changes the text styles flagged `display` (card names, countdown, banner name) and the glyph width used to estimate name wrapping (`GLYPH_BY_FONT`). The chosen card's desaturation is `Spread.grey` applied to every colour of the card, driven by `timeline.desat` (grey exactly when the fade-out starts).
- **Not in the reference** (cannot be done with this UI): radial gradients, italics, Cinzel, scaling the text with the card.

## Protocol (Realms mod-network; JSON-safe args; prefix `rw_`) (as built)
| RPC | Direction | Args |
|---|---|---|
| `rw_hello` | client -> "host" | proto (2 since 2.0.0), version ("2.0.0") |
| `rw_welcome` | host -> peer id | proto, version, ok (1/0) |
| `rw_state` | host -> "others" (or one peer id) | ONE json string: `{p=phase, m=mode, r=remaining_s, b=ballot_id, c=chosen_name, e=empty (0/1; 2 = all cooling down in tarot), z=paused, k=[{k=key,n=name,p=pct,v=votes}]}`; tarot adds `h` (hand, up to 5 of `{k,n,s,t,b,q,m,r}`), `w` (winner index), `sq` (hand number), `dn` (resolved 0/1), `da` (seconds since the pick, only when resolved), `y` (hand seconds), `cd` (map card key -> seconds of cooldown left); each card of `h` also has `c` (its cooldown in seconds, for the rot) |
| `rw_vote` | client -> "host" | ballot_id, option |
(The planned `rw_wave` banner RPC was dropped: the HUD panel's "incoming" phase covers it.)
Version mismatch disables the mod on that client (`rw_welcome ok=0`). Peers without the mod are not "capable" and are skipped by Realms. Host sends state on every change, once per second for the countdown, to a peer on `peer_joined`, and in reply to `rw_hello`. Clients interpolate `remaining` locally from the time of receipt (peers' clocks differ).

## Wave editor and per-wave settings (1.1.0)
User requirements added after the first test: fix the percent display, allow a 5 s minimum interval, give custom waves a real interface, a keybind-opened menu "like RealmsEvent's" listing every wave with its composition and letting the user change name and composition, and make the vote panel movable through the Custom HUD mod.

- **Data model** (`catalog/events.lua`): every wave is `key` (built-in key or `custom_1..20`) with settings `wave_def_<key>` = `"name<TAB>recipe"` (override; `""` = built-in), `on_<key>` (enabled; default on for built-in, off for custom), `pct_<key>` (chance weight, relative; default from the built-in table, 10 for custom), `cd_<key>` (cooldown seconds). Flat plain values only, because nested tables crash DMF's sjson save (RealmsEvent learned this). Chances are normalised over the waves that are enabled, non-empty and weight > 0, so shares always total 100.
- **Recipe text** is the storage format for compositions (`Groups.parse` / `Groups.to_recipe` round-trip). `a|b` = one of several breeds per unit; this is how "Boss Ambush" is represented.
- **Editor** (`ui/wave_editor_*.lua`, view `realms_waves_editor`, class `RealmsWavesView`): one row blueprint (checkbox, name, composition, stepper, share, action button) serves three screens: **list** (all waves), **detail** (one wave: enemies with count steppers and Remove; buttons Rename / Edit as text / Add enemy / Enabled / Reset; steppers for chance and cooldown), **picker** (all known breeds). A popup with the vanilla text-input widget handles numbers and text (rename, recipe). Every change is written to settings immediately; nothing to save. Built-in waves cannot lose their last enemy (Reset to default restores them); custom slots can be emptied (Clear this slot).
- **Why not DMF options:** DMF's options page cannot show a composition or edit names; the editor mirrors RealmsEvent's pool editor (same vanilla templates), and DMF's own `text_input` widget type exists in this DMF but a dedicated view fits the "list all events with composition" requirement better.
- **Host-only effect:** only the host's settings drive the draw; the editor shows this in its description text.
- **Custom HUD:** the `custom_hud` mod builds an edit box for every non-root scenegraph node of every registered HUD element and re-pins saved positions. So the panel is one real-sized node (`panel`, 640 x 210 px at 40,330 by default) with all text inside it; nothing else is needed for it to appear in that mod's editor. In its edit mode (`custom_hud.is_customizing`) the panel shows a sample so there is something to drag.

## Modifiers (1.2.0)
User requirement: add non-mission-loaded modifiers to enemies, e.g. a Havoc with only Garden, and a wave of "3 crushers with the enraged modifier".
- **Model:** each enemy group (a part) can carry `mods = { ids }` (`part.mods`, ids from `Groups.MODIFIERS`, kept in catalog order). Stored in the recipe text as `3 crusher[garden+enraged]` (the recipe is the storage format, so no new setting). Groups with different modifiers never merge.
- **Application:** per unit, right after `spawn_minion` returns (`Execute.apply_modifiers`): for each modifier's buff templates, `buff_extension:is_valid_target(name)` then `add_internally_controlled_buff(name, gameplay_time)`, then `_update_stat_buffs_and_keywords`. Same calls as `MutatorBase._add_buffs_on_unit`. Server side only; minion buffs are RPC-synced so clients see the effects.
- **Why per-unit buffs and not loading mutators:** loading a mutator (`MutatorManager.load_mutator_from_name`) would affect every enemy in the mission and persist; per-unit buffs affect only the wave units the user chose.
- **Safety:** every buff call is in a pcall; problems are logged once with `mod:warning` (always visible in the console log). Havoc-only modifiers (Toughened Skin) are skipped outside Havoc missions because the vanilla buff would error there.
- **Editor:** detail screen row -> **Mods** button -> modifier screen (checkbox rows). Row blueprint got a `show_mods` flag; the screen list is `Groups.MODIFIERS`.
- **Not verified in game:** the buffs' visuals (garden head effect, enraged eye/colour effects), the enrage shout, and that clients see them.

## Spread and repeating waves (1.3.0)
User requirements: enemies must not all spawn on the same spot (a radius slider in the editor); a "continuous wave" choice, e.g. 5 crushers instantly, then X crushers every Y seconds for Z seconds.
- **Spread:** per-wave setting `sp_<key>` (metres). After a hidden candidate point is picked, `Positions.spread(point, radius)` tries up to 5 random points in the disc (uniform: radius * sqrt(random)), keeps the first that is on the nav mesh (`NavQueries.position_on_mesh(world, pos, 2, 2)`) and reachable in a straight line (`NavQueries.ray_can_go`, so not through walls), else uses the original point. The offset points are NOT re-checked for line of sight (a small radius keeps them near the hidden point; a big radius can put a unit in view).
- **Repeats:** the recipe gets `@N` per group ("units added on every tick"), and the wave gets two settings, `re_<key>` (every, seconds) and `rf_<key>` (for, seconds). Design choice: per-group `@N` (instead of a separate second composition) so mixed waves work ("5 crushers@2, 10 poxwalkers") with one text format and one editor. `Execute.start_wave` builds the initial queue from `count`; a job with repeats gets `job.rep = {every, total, clock, next, done}`; `run_repeats` queues the `rep` units for every tick that is due (a frame can catch up several); the job ends when its queue is empty and its repeats are done. Ticks at Y, 2Y, ... <= Z. Feeding takes the oldest job with units waiting, so a repeating job idling between ticks does not block later waves.
- **Same amount (1.5.0):** a part may carry `rep_same = true` instead of a number; `Groups.repeat_amount(part)` returns `part.count` for those and `part.rep` otherwise, and `Execute.expand` uses it for the `rep` batches, so the type multiplier and rounding apply exactly as for the initial spawn. Recipe `@=` / `@same`. In the editor the tick box is a second checkbox on the detail row (`hotspot_same`, style ids prefixed `same_`).
- **Limits that still apply:** `max_per_wave` caps each batch (initial and every tick), `max_alive` gates spawning (units wait in the queue), and a tick is skipped while more than 200 units are queued. Repeats keep coming even after the next wave has been drawn (they belong to the wave that started them).
- **Editor:** the detail screen row got a second stepper ("Added each repeat", header column 6); the bottom panel got "Spread radius", "Repeat every", "Repeat for" steppers. Repeat timing is only meaningful when some group repeats (the "Repeat every" line says "off: no repeats" otherwise).

## Type multipliers, enemy search, higher limits (1.4.0)
User requirements: three global sliders (0-500 percent) that scale every wave's enemy numbers, one for normal and elite enemies, one for bosses only (twins included), one for specials; a search when adding enemies; max alive 250 -> 1000 and max per wave 200 -> 500; rename the "count" word to "weight".
- **Multipliers** are read at spawn time (`Execute.expand`, `mod:get("mult_normal|mult_boss|mult_special")`), so changing a slider affects the next wave immediately and never rewrites the saved waves. They scale `count` and `rep` alike. Rounding is always DOWN (`Execute.scaled_amount`: `floor(count * percent / 100 + 1e-9)`, product first so 20 x 115 / 100 is exactly 23; 1.4.3, user request; it was half up in 1.4.0-1.4.2), so 1 unit stays 1 until 200 percent and 13 units at 150 percent is 19; there is no carry-over between groups. `max_per_wave` is applied AFTER scaling, so it still limits a wave.
- **Why kinds are a data table in `groups.lua`:** it mirrors the tags of the 41 spawnable breeds (audited 2026-09-29 from the breed files, see CHANGELOG 1.4.0) so the mod does not need to `require` the breed settings at load; a test asserts 10 specials / 9 bosses / 12 elites.
- **Search:** `Groups.search(query)` (all words must appear in `normalize(id + aliases + kind words)`); the view keeps `self._filter`; the search popup calls `on_change` every frame the text changes and `on_cancel` to undo. The popup accepts a `y` so it can sit under the list.
- **Limits:** only the option ranges and the repeat-queue guard changed; nothing else in the pipeline had a 200/250 assumption (`Bypass`, `Execute` use the settings). The game's own hard limit of 145 is not affected because wave units are hidden from the counters (see doc 03).

## As-built notes
- Vote mode: candidates are drawn at cycle start and shown during the countdown; votes are accepted the whole time; the last `vote_duration` seconds switch the header to "VOTE NOW". Winner = most votes (ties random); no votes -> weighted pick among the candidates, or skip (setting).
- Custom recipes: DMF has no text-input widget, so `/rw_custom <slot> <recipe>` stores `custom_N_recipe` and the chance is the numeric option `custom_N_pct` (0 = disabled).
- Cooldowns: an event that fired recently is only drawn again if there are not enough off-cooldown events to fill the ballot.
- Timers pause while there are no living players.

## Options (`RealmsWaves_data.lua`)
Mode (random/vote); interval min/max; vote duration; candidates per ballot; no-vote fallback; max per wave; max alive; distance ranges; vote keybinds 1..3; per-event enable and percent; 20 custom recipe slots; HUD size/position; debug logging.

## Reuse map
See `05-implementation-plan.md`.

### Deck order (2026-10-03 recovery)
`deck_order` stores visual card keys as a comma-separated string, normalized against the current catalog on load. Missing/deleted keys never erase a card; absent/new keys append. `deck_sort` and `deck_sort_desc` mark the last ascending/descending sort (threat, rarity/chance, enemies, face); manual swaps clear the mark. This order has no effect on the director pool or probability. Dragging starts after a real face/state press held 0.3 seconds, swaps within the visible page on release over another card, and cancels everywhere else. A popup, page/screen change, reload or editor exit cancels before reusing widgets. The quick click acts on release; a double-click arms a hold but suppresses its second toggle.

### Runtime recovery hardening (2026-10-03)
Repeat queues hold at most 1000 pending units per job, truncate a repeat batch to the available room, and skip missed ticks once full. Batch prepending preserves the older pending units first using linear work and the existing batch table. Size replication coalesces one pending update per id (newest arrival wins, at most 600 ids); it waits for the unit handle and retries transient scale failures up to 20 seconds. Whole-call outbound failures retry every 0.3 seconds with current live sizes only; the subsequent audit found that Realms partial peer failures are not reported through that return value (F06). Host-only RPCs require the actual session host sender; protocol 2 stays compatible. A real buff reset is recorded so equal numerical values cannot hide a fresh recompute.

### Adversarial audit ownership review (2026-10-03)

The [dated report](audits/2026-10-03/report.md) records seven baseline defects,
before remediation: event subscriptions survive unload; disabled
updates still spawn; stop clears living-unit ownership; pause leaves Execute
running; local queue caps lack an aggregate budget; partial broadcast rejection
loses size recovery; LuaJIT preset numeric parsing admits NaN. The user approved
implementation after reviewing the audit. Fixes use existing ownership and
validation boundaries, preserving protocol 2, public options and serialization.
The approved [remediation log](audits/2026-10-03/remediation.md) tracks current
changes. Entry unload now releases both subscriptions from their stored original
event manager; retired callbacks are inert even if already captured.
Gameplay entry registers a manager that appeared after initialization or replaces
the original owner safely. Retirement releases tuning records/queues and protocol
peer/handler references, blocks captured entry points, and prevents delayed
hook-require callbacks from installing hooks. A failed late-join send checks
current live records before retrying, including synchronous teardown during send.
Scheduling cancellation now drops jobs/cache without discarding living unit
records. Pause freezes feed/repeat/timeout clocks while maintenance continues;
stop retains tracking/tuning and prunes dead units even without jobs. Disable
cancels jobs and performs liveness cleanup only while DMF hooks are suspended.
Re-enable requires host `/rw_start`; clients clear stale state and handshake.
Pending work now has fixed internal limits of 64 jobs and 8,000 aggregate
entries. Admission estimates the clipped initial batch before allocation and
rejects it atomically if it cannot fit. Repeats skip full-budget overdue ticks
or clip to remaining capacity, retaining the per-job 1,000 bound. Status exposes
limits; timed-wave failures log at most once per five seconds. Supported
recipes/multipliers bound individual temporary batches; this is not a new option
or a guarantee about native frame time.
Both preset and single-card import validate finiteness of every numeric field
before rounding/clamping. Supplied invalid threat is rejected; absent/empty
legacy threat stays zero. Huge finite numbers still clamp, and validation
completes before settings writes. Serialization is unchanged.
Size replication now tracks at most 16 known Realms peers, fan-outs through
direct sends, and aggregates recipient failures into the existing coalesced
current-size retry. Successful recipients can receive idempotent duplicates;
unsupported RPCs are skipped until a compatible hello or peer refresh. Re-enable
replays Realms peers to discard missed disconnects. Failed late-join snapshots
coalesce into the same outbox, and synchronous sends cannot clear newly queued
sizes. No new protocol fields or per-peer scheduler is introduced.
Client state skips malformed candidate entries and reads at most five candidates,
matching the existing hand/ballot bounds. No message schema changes are required.
Full mission teardown works in the Lua fixtures; actual engine resources and
eight-hour acceptance remain pending.
