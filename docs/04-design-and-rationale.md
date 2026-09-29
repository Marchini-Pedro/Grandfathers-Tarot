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

## As-built notes
- Vote mode: candidates are drawn at cycle start and shown during the countdown; votes are accepted the whole time; the last `vote_duration` seconds switch the header to "VOTE NOW". Winner = most votes (ties random); no votes -> weighted pick among the candidates, or skip (setting).
- Custom recipes: DMF has no text-input widget, so `/rw_custom <slot> <recipe>` stores `custom_N_recipe` and the chance is the numeric option `custom_N_pct` (0 = disabled).
- Cooldowns: an event that fired recently is only drawn again if there are not enough off-cooldown events to fill the ballot.
- Timers pause while there are no living players.

## Options (`RealmsWaves_data.lua`)
Mode (random/vote); interval min/max; vote duration; candidates per ballot; no-vote fallback; max per wave; max alive; distance ranges; vote keybinds 1..3; per-event enable and percent; 20 custom recipe slots; HUD size/position; debug logging.

## Reuse map
See `05-implementation-plan.md`.
