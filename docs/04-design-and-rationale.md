# 04. Design and rationale

Written 2026-09-28. Findings backing each claim are in docs 01-03.

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

## Protocol (Realms mod-network; JSON-safe args; prefix `rw_`) (as built)
| RPC | Direction | Args |
|---|---|---|
| `rw_hello` | client -> "host" | proto (1), version ("1.0.0") |
| `rw_welcome` | host -> peer id | proto, version, ok (1/0) |
| `rw_state` | host -> "others" (or one peer id) | ONE json string: `{p=phase, m=mode, r=remaining_s, b=ballot_id, c=chosen_name, e=empty, k=[{k=key,n=name,p=pct,v=votes}]}` |
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
- **Limits that still apply:** `max_per_wave` caps each batch (initial and every tick), `max_alive` gates spawning (units wait in the queue), and a tick is skipped while more than 200 units are queued. Repeats keep coming even after the next wave has been drawn (they belong to the wave that started them).
- **Editor:** the detail screen row got a second stepper ("Added each repeat", header column 6); the bottom panel got "Spread radius", "Repeat every", "Repeat for" steppers. Repeat timing is only meaningful when some group repeats (the "Repeat every" line says "off: no repeats" otherwise).

## As-built notes
- Vote mode: candidates are drawn at cycle start and shown during the countdown; votes are accepted the whole time; the last `vote_duration` seconds switch the header to "VOTE NOW". Winner = most votes (ties random); no votes -> weighted pick among the candidates, or skip (setting).
- Custom recipes: DMF has no text-input widget, so `/rw_custom <slot> <recipe>` stores `custom_N_recipe` and the chance is the numeric option `custom_N_pct` (0 = disabled).
- Cooldowns: an event that fired recently is only drawn again if there are not enough off-cooldown events to fill the ballot.
- Timers pause while there are no living players.

## Options (`RealmsWaves_data.lua`)
Mode (random/vote); interval min/max; vote duration; candidates per ballot; no-vote fallback; max per wave; max alive; distance ranges; vote keybinds 1..3; per-event enable and percent; 20 custom recipe slots; HUD size/position; debug logging.

## Reuse map
See `05-implementation-plan.md`.
