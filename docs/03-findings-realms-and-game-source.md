# 03. Findings: Realms Server mod and Darktide spawn source

Audited 2026-09-28. Realms 1.0.0-rc2; source clone commit `0f0cb45` (game 1.12.5).
`R` = `mods\Realms\scripts\mods\Realms`. `S` = `Darktide-Source-Code\scripts`. Realms docs (authoritative for mod authors): `mods\Realms\docs\README.md`. The native DLL `bin\darktide-realms.dll` (FFI via `R\runtime\cdef.lua`, `native.lua`) was NOT analysed.

# Part A: Realms

## Host vs client
- No dedicated server: listen server; host is also a normal local player. Vanilla `HOST_TYPES.player` (`S\settings\network\matchmaking_constants.lua:5`; enum: player, mission_server, hub_server, party, singleplay, singleplay_backend_session).
- Host: `R\session\host_session_boot.lua:33-110` creates Realms `ConnectionHost` (`R\connection\connection_host.lua`), native UDP session `Native.start_local_session` (:70), hands it to `Managers.connection` as `_connection_host`. `host_type()` returns `HOST_TYPES.player` (:641); `host_is_dedicated_server()` false (:637).
- Client: `R\session\client_session_boot.lua:105-137`, vanilla `ConnectionClient` with `HOST_TYPES.player` and Realms ticket, tagged `_realms_protocol`. LAN discovery via `LanClient.create_lobby_browser`, `Network.join_lan_lobby`.
- **Recommended detection** (Realms README l.5-34): session `Managers.multiplayer_session:host_type() == HOST_TYPES.player`; role `Managers.connection:is_host()` (`_connection_host ~= nil`) / `is_client()` (`S\managers\multiplayer\connection_manager.lua:244-249`); authoritative logic also needs `Managers.state.game_session` and `game_session:is_server()`.
- Stricter check: `connection._realms_protocol == SessionTicket.PROTOCOL_VERSION` (`R\core\session.lua:216-234`).
- Local single-player with Realms `enable_server`: `MultiplayerSession.boot_singleplayer_session` is hooked and replaced by Realms host boot (`R\Realms.lua:128`, `R\core\session.lua:452`). `enable_hub_server` / `enable_shooting_range_server` can leave hub/Psykhanium as plain `ConnectionSingleplayer` (`host_type` singleplay; `is_host()`/`is_server()` true, Realms API unavailable).
- `shared_state.is_server = params.is_host` (`S\game_states\game\state_gameplay.lua:16`); not dedicated (`:35`). `GameSessionManager:is_server()` returns `_is_server`, set only by `set_session_host` (`S\managers\multiplayer\game_session_manager.lua:166-206`); nil then false on clients.

## Networking
- No new engine RPCs. Realms tunnels JSON through vanilla `rpc_check_mechanism` / `rpc_check_mechanism_reply` (`R\core\session_control.lua:19-20`, framing :187-200, reassembly :304-344, `is_available` :566), with a hello/ready handshake first. Protocols: mod-network, gameplay-control, preparation, chat, latency, profile updates.
- Gameplay traffic is vanilla `GameSession` with network units; **units the host spawns replicate to clients normally**.
- Between missions Realms runs pseudo-state `RealmsPreparationState` (`R\game_states\realms_preparation_state.lua`); no `Managers.state.*` gameplay managers then. Connections persist across missions (`ReusedHostSessionBoot`, `Session.queue_mission_transition` `R\core\session.lua:657`); `Managers.state.*` rebuilt per mission. Late unit RPCs guarded by `R\core\unit_rpc_lifetime.lua`.

## Mod-to-mod messaging (the only channel in this install)
DMF's own network functions are empty stubs (`mods\base\mod_manager.lua:384-410`). Use the Realms API (README l.36-122, exports `R\Realms.lua:23-47`, impl `R\core\mod_network.lua`: register :527, send :555-628, routing :367-419, dispatch :150, manifest :173-239):
- `realms.network_register(mod, rpc_name, cb)`: cb receives `(sender_peer_id, ...)`.
- `realms.network_send(mod, rpc_name, recipient, ...)`: recipients `"local"`, `"host"`, `"all"`, `"others"`, or peer id. Host routes client-to-client.
- `realms.network_is_available()`, `network_on_peer_joined(mod, cb)`, `network_on_peer_left(mod, cb)`, `queue_mission_transition(mod, ctx)` (host only).
- Usage rules: `get_mod("Realms")` in `on_all_mods_loaded`; register there (allowed without a session); **always dot-call**.
- Limits: args JSON-serialisable, max 32 args, max 96 KiB encoded (`R\protocol\mod_network_protocol.lua:9-13`); top-level nil preserved.
- Semantics: only "capable" peers (same mod enabled AND same RPC registered) get broadcasts; direct sends to incapable peers fail `target_rpc_unsupported`. `true` return = accepted for dispatch, not delivered; use reply RPCs for acks. Peer ids are lower-case 16-hex strings. Client `"all"`/`"others"` route via host, no echo to sender. **Host `"all"` DOES dispatch locally first** (loopback; RealmsEvent drops it by host check). One joined and one left callback per mod (re-register replaces; joined replays existing peers on registration). State in `mod:persistent_table("mod_network")` survives hot reload. API stays available through preparation/loading/gameplay/end view, so callbacks can fire with `Managers.state.game_session == nil`.

## Pitfalls for other mods
1. **Managers missing on clients:** `Managers.state.minion_spawn`, `.pacing`, `.horde`, `.bot_nav_transition`, `.voice_over_spawn` are created only when `is_server` (`S\game_states\game\gameplay_sub_states\gameplay_init_step_states\gameplay_init_step_managers.lua:107-113`). Nil-check everything.
2. Host is also the local player; but GhostHost mod removes the host's unit (hooks `should_spawn_dead`, `can_spawn_player`). Guard `Managers.player:local_player(1).player_unit`.
3. Bots: `R\core\bot_backfill.lua` `MAX_BOTS = 7` (:7); hooks `PlayerManager.next_available_local_player_id`, `BotSpawning.spawn_bot_character`, `PlayerUnitSpawnManager` internals. `max_players` 2-12 (`R\Realms_data.lua:68-72`).
4. Host forced single-threaded physics via `GameModeManager.init` (`R\workarounds\local_host_physics.lua:8-14`).
5. `PrivateOutlines` (`R\workarounds\private_outlines.lua`) wraps `OutlineSystem.add_outline/remove_outline`: outlines from other players' server-side buffs hidden on host unless spectating that player.
6. Non-hub mission level seed from loading manager's mission seed (`R\core\mission_seed.lua:8-26`).
7. Hub modes `hub`, `hub_singleplay`, `prologue_hub`, `shooting_range` are special (`R\core\session.lua:22-27`); `mission_preparation` setting skips preparation for them.
8. Realms internals (`mod._session`, `_gameplay_control`, `_session_control`) are not stable: use the documented API only.
9. UNVERIFIED: `Managers.connection.combined_hash` mismatch if mods alter network lookups.

# Part B: Minion spawning and limits (game source)

## Spawn call chain (server only)
`MinionSpawnManager` (`S\managers\minion\minion_spawn_manager.lua`) updated only on the server (`S\game_states\game\gameplay_sub_states\gameplay_state_run.lua:135-140`, with terror_event, pacing, horde).
- `spawn_minion(breed_name, position, rotation, side_id, optional_param_table)` (:95): applies `replacement_breed`, sets side/breed/random_seed/aggro state, applies havoc/survival/circumstance health modifier, `Managers.state.unit_spawner:spawn_network_unit` (:152; def `S\foundation\managers\unit_spawner\unit_spawner_manager.lua:603`), `_num_spawned_minions += 1` (:160), sets blackboard/inventory/buffs. **No limit or budget checks.**
- Param keys (`S\extension_systems\unit_templates\minion_unit_template.lua`): `optional_aggro_state`, `optional_target_unit` (:131-138), `optional_group_id` (:153-162), `optional_health_modifier` (:174), `optional_group_target` (:295); in `spawn_minion` itself: `optional_spawner_unit`, `optional_mission_objective_id`, `optional_owner_player_unit`, `optional_init_toughness`, `optional_void_shield_start_depleted`, `spawn_source`.
- Usage: `local p = ms:request_param_table(); p.optional_aggro_state = "aggroed"; p.optional_target_unit = u; ms:spawn_minion(breed, pos, rot, 2, p)`. Side 2 = villains, 1 = heroes (`S\managers\pacing\pacing_manager.lua:40`).
- `request_param_table()` (:89) shared scratch table cleared per call. `queue_minion_to_spawn(breed,pos,rot,side_id)` (:223) returns entry to fill; `_update_spawn_queue` (:238) spawns one per frame; **ring buffer `MINION_QUEUE_RING_BUFFER_SIZE = 256` (:9), no overflow guard**.
- `total_allocated_num_enemies()` (:256) = spawned + queued. `num_spawned_minions()` (:369), `spawned_minions()` (:373). `despawn_minion(unit)` (:354) calls `pacing:remove_aggroed_minion`, refuses owned units. `delete_units()` (:48), `despawn_all_minions()` (:344). `unregister_unit(unit)` (:316) called from `_server_finalize_death` (`S\managers\minion\minion_death_manager.lua:211`): counts include dying units.
- Other wrappers: `ScriptedScenarioSystem:spawn_breed_ramping(...)` (`S\extension_systems\scripted_scenario\scripted_scenario_system.lua:666`); `FlowCallbacks.expedition_spawn_random_enemy` (`S\script_flow_nodes\flow_callbacks.lua:2207`); mutators and BT summon call `spawn_minion` directly. Installed `mods\creature_spawner` does likewise with an `is_server()` gate (`creature_spawner.lua:96, 882-893, 970`).

## Where limits live
No Breed-level `max_spawned` / `count_towards_limit` / `ignore_spawn_limit` flag exists (grep of `S\settings\breed`, `S\managers`, `S\extension_systems` found none).
- **`PacingManager:spawn_type_enabled(spawn_type)`** (`pacing_manager.lua:444`) returns `false, reason`: `pacing_is_disabled` (except terror_events), `Hard_allocated_limit_reached` when `total_allocated_num_enemies() > HARD_ALLOCATED_LIMIT` (`local HARD_ALLOCATED_LIMIT = 145` :442, an upvalue; change only by hooking the function), `disabled_by_challenge_rating`, `paused`, `not_allowed`, `disabled_by_heat_stage`. Types: hordes, trickle_hordes, specials, roamers, monsters, terror_events. `spawn_type_allowed` (:483).
- Challenge-rating thresholds (`S\managers\pacing\templates\default_pacing_template.lua:188-194`, scaled by challenge step 1-2): specials 40, hordes 30, trickle_hordes 20, roamers 90, terror_events 100 (none for monsters).
- Allowed types per pacing state (`default_pacing_template.lua:40-89`): `sustain_tension_peak`, `tension_peak_fade` disable hordes/roamers/specials/terror/trickle.
- Specials (`S\managers\pacing\specials_pacing\specials_pacing.lua`): `max_alive_specials` 3-10 (`templates\default_specials_pacing_template.lua:33-400`) times `_max_alive_specials_multiplier` + havoc bonus (`_setup` :206-236); `_spawn_special` (:561) spawns at :665; `max_of_same` (:135).
- Horde pacing (`S\managers\pacing\horde_pacing\horde_pacing.lua`): `_update_horde_allowance` (:76-97) blocks when `num_spawned_minions() >= template.max_active_minions` (:80; values 70,70,85,90,95,110 in `templates\default_horde_pacing_template.lua:244,302,541,817,1176,1655`); `_setup_next_horde` (:517) far_vector when `>= max_active_minions_for_ambush` (50); trickle gate :741; terror-event trickle `total_minions_spawned_stop_threshold` (`S\managers\terror_event\terror_event_manager.lua:434-441`); `spawn_by_points` requires `num_aggroed_minions < 100` (`terror_event_nodes.lua:313-315`); auto events use `total_allocated_num_enemies` (`auto_event.lua:509`).
- Monster pacing (`monster_pacing.lua`): `_spawn_monster` (:878) records units in own lists (:906, 970, 974); `num_aggroed_monsters()` (:832).
- `HordeManager` (`S\managers\horde\horde_manager.lua`): `horde(horde_type, horde_template_name, side_id, target_side_id, composition, ...)` (:25) returns `success, horde_position, target_unit, group_id, spawned_direction`; `can_spawn` (:41) dry-run; `num_active_hordes` (:51), `num_alive` (:83). **No limit checks; gating is all in `HordePacing` before the call** (`_spawn_horde` :501). Types `S\settings\horde\horde_settings.lua:5`. Templates: `ambush_horde_template.lua:46` (`execute(physics_world, nav_world, side, target_side, composition, towards_combat_vector, optional_main_path_offset, optional_num_tries, optional_disallowed_positions, optional_spawn_max_health_modifier, optional_prefered_direction, optional_target_unit, optional_skip_spawners)`), `far_vector_horde_template.lua:226`, far_distance, flood, trickle. Composition `{breeds = {{name=..., amount={min,max}}}}`.

## What direct spawns count toward
| Counter | Counted? | Detail |
|---|---|---|
| `num_spawned_minions` / `total_allocated_num_enemies` | **Yes** | Feeds 145 hard limit, horde `max_active_minions`, ambush limit, trickle stop, auto-event limit. Direct spawns starve pacing but are never blocked. |
| `PacingManager._num_aggroed_minions` / `_total_challenge_rating` | **Yes once aggroed** | `MinionPerceptionExtension:aggro()` calls `Managers.state.pacing:add_aggroed_minion(unit)` (`S\extension_systems\perception\minion_perception_extension.lua:320-351`, call :349) regardless of spawner; adds `breed.challenge_rating` (e.g. chaos_hound 6). Runs at spawn for `optional_aggro_state="aggroed"` (:133-146). Removed on death (`minion_death_manager.lua:135`), destroy (`minion_perception_extension.lua:604-606`), `despawn_minion`. Expedition heat also gets `add_on_aggro_heat`. |
| `MonsterPacing.num_aggroed_monsters` | No | Only monster-pacing spawns. |
| Specials slots `_num_spawned_specials` | No | Only pacing/inject spawns. |
| `HordeManager._total_alive_horde_minions` / `num_active_hordes` | No | Only via `HordeManager:horde`. |

## Bypass toolbox (used by RealmsWaves)
1. Direct `spawn_minion` on the server: nothing blocks it.
2. Keep challenge rating out: hook `PacingManager.add_aggroed_minion` and skip mod-owned units (`remove_aggroed_minion` is already guarded by `aggroed_minions[unit]`, `pacing_manager.lua:870-888`), or spawn aggroed then call `pacing:remove_aggroed_minion(unit)` (also drops from `side.aggroed_minion_units`), or pass `optional_aggro_state = "passive"` (default falls back to `breed.spawn_aggro_state`, "aggroed" for hounds etc.).
3. To hide from the counters: hook `MinionSpawnManager.num_spawned_minions` and `total_allocated_num_enemies` to subtract mod-owned count (all limit readers above call these).
4. Other levers (not needed): hook `PacingManager.spawn_type_enabled`; `add_pacing_modifiers` with `max_alive_specials_multiplier` / `override_allowed_spawn_types` (`pacing_manager.lua:339, 940-1180`); `set_enabled(false)` (:343), `pause_spawn_type` (:319), `freeze_specials_pacing` (:1257); edit templates via `mod:hook_require`.
5. `try_inject_special(breed_name, prefered_direction, target_unit, spawner_group, ignore_allowance, is_prevention, is_loner_prevention, auto_event_id)` (`pacing_manager.lua:1239`, `specials_pacing.lua:1547`) still needs a free slot; `ignore_allowance` only skips `spawn_type_allowed`.
6. `Managers.state.horde:horde(...)` directly bypasses HordePacing; `force_horde_pacing_spawn()` (:936) still blocked by `_update_horde_allowance`.
7. Dead flag: `template.ignore_disallowance` in trickle code (`horde_pacing.lua:742`) is effectively dead (`not reason == "..."` parses as `(not reason) == "..."`).
8. `mutator_ignore_roamer_limits` bypasses roamer limits (`roamer_pacing.lua:287`).

## Position / line-of-sight APIs
- `SpawnPointQueries` (`S\managers\main_path\utilities\spawn_point_queries.lua`): `get_random_occluded_position(nav_world, nav_spawn_points, from_position, side, offset_range, num_groups, optional_min_distance, optional_max_distance, optional_initial_offset, optional_only_search_forward, optional_disallowed_positions)` (:409; **errors in the Realms/mod environment per RealmsEvent, avoid**); `get_occluded_positions` (:340); `group_from_position` (:265); `occluded_positions_in_group` (:275). They hide from `side.valid_enemy_player_units_positions`; pass villains side `side_system:get_side(2)` and its enemies are the players. `nav_spawn_points` from `Managers.state.main_path:nav_spawn_points()` (`main_path_manager.lua:81`); `num_groups` from `GwNavSpawnPoints.get_count(...)`. Samples: `specials_pacing.lua:849-854`, `ambush_horde_template.lua:132`. Needs `main_path:is_main_path_ready()` (:200); unavailable in hub/shooting range.
- Main path: `main_path:ahead_unit(side_id)` (:208), `behind_unit` (:212), `travel_distance_from_position` (:244); `MainPathQueries.position_from_distance(distance)` (`S\utilities\main_path_queries.lua:46`), `closest_position` (:23).
- Nav (`S\utilities\nav_queries.lua`): `position_on_mesh` (:7), `position_on_mesh_guaranteed` (:31), `position_on_mesh_with_outside_position(nav_world, traverse_logic, position, above, below, lateral, distance_from_nav_mesh)` (:60), `ray_can_go` (:91). `nav_world` from `Managers.state.nav_mesh:nav_world()`; traverse logic `Managers.state.pacing:roamer_traverse_logic()` (`pacing_manager.lua:1275`).
- LOS raycast helper: `HordeUtilities.position_has_line_of_sight_to_any_enemy_player(physics_world, from_position, side, collision_filter)` (`S\managers\horde\utilities\horde_utilities.lua:24`), filter `"filter_minion_line_of_sight_check"` (`far_vector_horde_template.lua:43`). `HordeUtilities.try_find_spawn_position(nav_world, center_position, index, num_columns, max_attempts, traverse_logic)` (:6). Physics world: `World.get_data(Managers.world:world("level_world"), "physics_world")` (as creature_spawner does).
- Side data: `Managers.state.extension:system("side_system")` then `get_side(id)` / `get_side_from_name("villains")`; fields `valid_player_units`, `valid_enemy_player_units_positions`, `valid_human_units`; `add_aggroed_minion`/`remove_aggroed_minion` (`side_system.lua:275,302`).
- Expedition-only: `PacingManager:exp_random_position_away_from_players(side_id)` (:1461).

## Combination pitfalls
- Spawn only when `game_session:is_server()` and `minion_spawn` non-nil.
- **Hub missions:** `BreedLoader` (`S\loading\loaders\breed_loader.lua:26-43`) loads all Breeds for non-hub missions but only player/companion breeds in hubs; spawning regular minions in a hub is unsafe. UNVERIFIED whether shooting range counts as `is_hub`.
- `PacingManager._disabled` is true when no main path (`pacing_manager.lua:125`); direct spawns unaffected.
- For Realms-only behaviour use README predicates or `_realms_protocol`, not just `is_server()`.
