# 02. Findings: RealmsEvent

Audited 2026-09-28, RealmsEvent 2.0.0. Paths relative to `mods\RealmsEvent\scripts\mods\RealmsEvent\` unless stated. Requires Realms.

## Summary
- Framework for host-driven random events: weighted scheduler, six Realms RPCs, version/event-list handshake, banner, pool editor view, 26 events.
- Only 5 events spawn enemies; all use one helper. **No voting, no budget/pacing handling, no bypass code.** Events chosen host-side only.
- Good to reuse: protocol, handshake, host/loopback guards, weighted roulette. Weak: spawn-position selection.

## Files
Root: `RealmsEvent.mod` (load_after Realms), `info.json`, `README*.md`, `docs/{Readme,ModDescription,SDK}*.md` (SDK = `define_event` API).

| File | Bytes | Purpose |
|---|---|---|
| `RealmsEvent.lua` | 10,259 | Entry, init order, view registration, public API |
| `RealmsEvent_data.lua` | 1,416 | Options (roll_interval, sleep_duration, keybind) |
| `RealmsEvent_localization.lua` | 8,968 | Strings (also banner title, errors) |
| `v2/core/runtime.lua` | 16,500 | Match lifecycle, wiring, per-frame update |
| `v2/core/scheduler.lua` | 13,058 | Weighted roll engine, cooldowns, global sleep |
| `v2/core/event_registry.lua` | 14,711 | `define_event`, validation |
| `v2/core/event_pool.lua` | 14,389 | Per-event enabled/weight/duration/cooldown, persistence |
| `v2/core/active_events.lua` | 17,078 | Instance lifecycle (`ctx`), execution rules |
| `v2/core/protocol.lua` | 22,236 | Six Realms RPCs |
| `v2/core/consistency.lua` | 30,667 | Version and event-list handshake state machine |
| `v2/core/presentation/banner.lua` | 5,943 | Area-notification banner |
| `v2/util/shared.lua` | 16,305 | Side/unit helpers, host check, spawn-point picker, spawner |
| `v2/view/*` | ~76 KB | Pool editor UI (`realms_event_view*.lua`, `view_components.lua`) |
| `v2/events/*.lua` | 26 loaded | Each self-registers via `mod:define_event` (`_index.lua` loader) |

Spawn events: `boss_ambush`, `bomber_frenzy`, `hound_frenzy`, `grenade_legion`, `sniper_elite`. Modifier/player events (not needed): `giant_enemies`, `tiny_enemies`, `swift_enemies`, `double_barrels`, heal/cleanse/ammo/toughness/buff events. `frenzied_enemies.lua` is commented out at `_index.lua:44`.

## Init and DMF
- `RealmsEvent.lua`: `mod.on_all_mods_loaded` (L39) loads registry, pool, protocol, scheduler, active_events, consistency, runtime; then `v2/events/_index` (L84); `mod:add_global_localize_strings` (L109); `Managers.event:register(mod, "event_mission_objective_start", "_on_mission_objective_start")` (L113); `mod:register_view` (L118). `on_game_state_changed` L162, `update` L180 (accepts `dt` and `self, dt`). `mod.define_event` L200. Command `revents` L216.
- **No `mod:hook` calls.** Only runtime swaps of game tables: `EffectTemplates["renegade_sniper_laser"]` (`sniper_elite.lua:150`), `GameModeManager.infinite_ammo_reserve` (`infinite_reserve.lua:119`), buff templates.
- `mod_load_order.txt` lists RealmsEvent before Realms; harmless because Realms lookups happen in `on_all_mods_loaded`.
- Options: `roll_interval` 0.1-2.0 default 0.2; `sleep_duration` 5-600 default 20; keybind. Event pool persisted as ONE flat string setting `event_pool_state`, records `key|e|w|d|c;...` (`event_pool.lua:102-186`) because nested tables crash DMF's sjson save. **Copy this trick for per-event percents.**

## Spawning
All five spawners call `Shared.spawn_minion_at_players(breed, min_distance)` (`util/shared.lua:303`).

| Event | Breed | Cadence | min dist | Default duration / cooldown |
|---|---|---|---|---|
| `boss_ambush` | random of `chaos_plague_ogryn`, `chaos_beast_of_nurgle`, `chaos_spawn` (L87) | 1, retried per frame | 22 | 1 s / 60 s |
| `bomber_frenzy` | `chaos_poxwalker_bomber` | 1/s | 16 | 30 s / 60 s |
| `hound_frenzy` | `chaos_hound` | 1/s | 18 | 30 s / 120 s |
| `grenade_legion` | 50/50 `cultist_grenadier`/`renegade_grenadier` | 1/s | 18 | 30 s / 60 s |
| `sniper_elite` | `renegade_sniper` | 1 per 5 s | 20 | 60 s / 120 s |

`sniper_elite` runs `execution = "all"` (also suppresses sniper laser); guarded by `is_state_host`. Others `execution = "server"`.

APIs (`shared.lua:303-344`): `minion_spawn:request_param_table()`, `param.optional_aggro_state = "aggroed"`, `param.optional_target_unit = <random player unit>`, `spawn_minion(breed, position, Unit.world_rotation(target,1), villains_side.side_id, param)`. Villains side by `side_system:get_side_from_name("villains")`.

Position picker `find_fallback_spawn_position` (`shared.lua:192`):
1. Random player unit (`random_player_unit()`), `nav_mesh:nav_world()`, `main_path:nav_spawn_points()`.
2. Group count `pcall(GwNavSpawnPoints.get_count)`; `start_group = math.random(1, num_groups)`; scan at most 8 sequential groups (`FALLBACK_MAX_GROUPS` L190).
3. Per group `SpawnPointQueries.occluded_positions_in_group(nav_world, nav_spawn_points, group, {player_position})`; returns the point farthest (flat XZ) from the player that is >= `min_distance`; else global farthest.
4. nil if no data / main path not ready (throttled `diag("spawn", ...)`).
Comment in code: vanilla `get_random_occluded_position` was removed because its C query errors in this mod environment.

## Scheduling
- `Runtime.update` (`runtime.lua:278`): ticks active events on both peers; drives scheduler on host only once `_pacing_started` (first `event_mission_objective_start`) and `main_path:is_main_path_ready()` (L303).
- `Scheduler.update` (`scheduler.lua:89`) accumulates dt, one `_roll_round` per `roll_interval`. `_roll_round` (L149): global sleep gate; eligible = enabled, weight>0, not on cooldown, not active, `registry.is_shared(key)`; weighted roulette `math.random() * total_weight`; `condition_passes` (L123) post-roll check (number = probability); `_fire` (L230). Cooldown recorded at finish `_elapsed + pool cooldown` (`on_event_finished` L256). One instance per event key (`active_events.lua:207`).

## Limits
None handled (see doc 03 for what pacing counts). Only event-level throttles: cadence, duration, cooldown, global sleep, one instance per key. No enemy-count guard.

## Voting
None. Host-only weighted random (default weight 50, range 0-100). `/revents` or keybind opens the pool editor, which writes local settings that only matter on the host.

## Network / Realms integration
- Host check `Shared.is_state_host()` (`shared.lua:111`) = `Managers.state.game_session:is_server() == true`. Not restricted to `HOST_TYPES.player`, so it also acts as host in SoloPlay (sends fail safely, only logged).
- Transport is the Realms mod-network API, always **dot-called**: `realms.network_register/send/is_available`, `network_on_peer_joined/left` (exports at `mods\Realms\...\Realms.lua:23-41`).
- Six RPCs (`v2/core/protocol.lua`, `PROTOCOL_VERSION = 2` L63, `Protocol.init` L307, `send()` L141 checks availability, receive validation L170-271, JSON via game global `cjson`):
  `re2_hello` (client->host: proto, mod_version, event_keys_csv), `re2_welcome` (host->client: proto, mod_version, shared_keys_csv), `re2_trigger` (host->all: key, duration, params_json), `re2_finish` (defined, never called), `re2_state` (host->all: topic, payload_json; stub), `re2_text` (host->all: title, name for banner).
- Trigger flow: `Runtime._on_event_fired` (`runtime.lua:109`): `active_events.start(...,"host")`, `protocol.send_trigger`, `banner.show`, `protocol.send_text`. Clients: `_on_trigger_remote` (L176) guarded by not-host and not-disabled.
- **Loopback:** Realms `"all"` also dispatches locally to the sender; host drops it with `if Shared.is_state_host() then return end` (L177, L193, L203, L215). Copy this pattern.
- Execution model (`active_events._runs_locally` L63): `server` = only host runs callbacks (state changes are engine-synced); `all` = both peers run (purely local effects like `Unit.set_local_scale`).
- **Handshake** (`v2/core/consistency.lua`): client sends `re2_hello` on entering `GameplayStateRun` (`client_hello` L536) and again on `peer_joined` (`bind_network_events` L596). Host `on_hello` (L398): mismatch of proto/mod version calls `disable()` (L237) and replies empty welcome; else computes event-key intersection (`_recompute_shared` L338). Client `on_welcome` (L462). `on_peer_left` recomputes; `on_game_state_exit` (L663) resets. RealmsWaves keeps only the version part.
- HUD: `banner.lua` reuses the vanilla area popup by triggering `Managers.event:trigger("event_player_set_new_location", player, full_key, short_key)` (L57); consumed by `hud_element_area_notification_popup.lua:38`. Remote banners inject unique loc keys per message (`show_remote` L92); fallback `mod:notify`. **No countdown or state HUD exists.**

## Interaction with other Realms mods
- Nothing outside RealmsEvent references it or its RPCs (only the load-order line).
- `Realms Connect`: discovery/rendezvous only; irrelevant.
- `DTRealmsGhostHost`: own `is_realms_host()` (`GhostHost.lua:101`, `host_type() == HOST_TYPES.player` and `connection:is_host()`); hooks `GameModeManager.should_spawn_dead` and `can_spawn_player` so the host has no player unit. Consequence: `side.valid_player_units` excludes the host; if the ghost host is the only human, RealmsEvent's `random_player_unit()` returns nil and nothing spawns.

## Weaknesses to fix in RealmsWaves
1. Spawn location is not "near a player": random group anywhere on the main path, no proximity filter; occlusion computed against ONE random player (`shared.lua:196,223`); aggro target chosen separately (`:325`).
2. Setting mismatch: `sleep_duration` 5-600 default 20 in `_data.lua:26-28` but `Pool.SLEEP_MAX` 300 and `SLEEP_DEFAULT` 30 (`event_pool.lua:54-56`) clamp; loc text says 0-300, 0 = none.
3. Dead code: `Protocol.send_finish`, `Runtime._on_state_remote` (stub), `frenzied_enemies.lua`.
4. Handshake compares registered keys, not pool state.
5. `ctx:broadcast`/`re2_state` never used by any event.

Not read in detail: internals of buff/template events and the pool editor view widgets.
