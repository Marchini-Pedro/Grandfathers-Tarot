# 01. Findings: TwitchVersus (and VersusMode note)

Audited 2026-09-28, TwitchVersus 1.0.0. Paths relative to `mods\TwitchVersus\scripts\mods\TwitchVersus\` unless stated. Line numbers are from this version.

## Summary
- Host-only Twitch Channel Points spawner. **No network layer, no in-game voting, no wave HUD.** Twitch is the only trigger and the only voting mechanism.
- Its spawn side (`spawn/`, `catalog/`, `core/`, `effects/`) has **zero Twitch references**, so it is reusable as-is.
- "Realms compatible" only means: works if your PC is the host (`game_session:is_server()` and `minion_spawn` exist). Inert on Realms clients and retail missions. `Realms` in `info.json` is a metadata dependency; no code calls `get_mod("Realms")`.

## Files (bytes)
| File | Bytes | Purpose |
|---|---|---|
| `TwitchVersus.lua` | 85,730 | Main: state, redemption handler, votes, auto-poll, profiles, presets, commands, HUD registration |
| `TwitchVersus_data.lua` | 21,582 | DMF options (built dynamically from catalogs) |
| `core/authority.lua` | 2,985 | Host/authority checks, enemy side, alive players |
| `core/budget.lua` | 4,324 | Enemy cap accounting |
| `core/presets.lua` | 8,206 | 3 settings presets |
| `catalog/breeds.lua` | 2,983 | Allow-list of spawnable breeds |
| `catalog/events.lua` | 31,033 | About 34 reward definitions |
| `catalog/groups.lua` | 19,748 | 20 user recipe slots and parser |
| `spawn/execute.lua` | 34,293 | Request queue and all spawn calls |
| `spawn/positions.lua` | 54,922 | Position search plus probe/report tooling |
| `effects/pickups.lua` | 28,033 | Crates, stimms, golden toughness, grenades, ability hold, dome break |
| `logic/vote.lua` | 29,774 | Twitch Helix polls |
| `transport/twitch_auth.lua` | 39,018 | OAuth device flow, 3 profiles |
| `transport/twitch_rewards.lua` | 49,625 | Channel Points reward sync and redemption polling |
| `transport/twitch_chat.lua` | 6,495 | Chat announcements |
| `transport/http_probe.lua` | 4,191 | `/tv_http` test |
| `ui/hud_element_banner*.lua` | 5,007 / 2,633 | One-line "vote started" banner |

## Entry point and DMF
- `TwitchVersus.mod:5-9` `new_mod(...)`, no `load_after`. In `mod_load_order.txt` it sits before Realms; harmless.
- `mod.tv_module` (`TwitchVersus.lua:151`) cached `io_dofile` wrapper. `mod.on_all_mods_loaded` (`:1714`) loads modules and configures Rewards/Vote/Chat.
- Hooks: `hook_safe` on `GameModeCoopCompleteObjective`, `GameModeSurvival`, `GameModeExpedition` `_change_state`, `GameModeManager._set_end_conditions_met` (`:1627-1637`, mission-failure tracking); `hook_safe("HordeManager","update")` (`:1646`) drives `Execute.gameplay_tick`. `mod.update` `:1688`. HUD: `mod:register_hud_element` `:1702`.
- Options: `TwitchVersus_data.lua:569`; groups connection/presets/events/custom/vote/banner/safety/presentation. Event widgets `ev_<id>_mode|_cost|_count|_seconds|_cooldown|_poll|_poll_chance` (`event_widgets()` `:358`). Custom slots `:676` (20 slots). `budget_cap` 20-140 default 90 (`:804`).

## Spawning
- Flow: `on_redemption` (`TwitchVersus.lua:1385`) checks entry/mode/live mission/cooldown/budget, then `run_entry` (`:738`) then `entry_requests` (`:694`) then `Execute.request(kind, args)` (`spawn/execute.lua:1329`).
- **Queue:** 32 requests, 2 per tick, 20 s TTL, dedupe by redemption id (`execute.lua:62-66`). Group jobs drip-feed 2 units per 0.15 s (`:39-40`) via `drain_job` (`:395`).
- **Threading constraint:** horde and despawn requests run inside `Execute.gameplay_tick` (`:1300`) driven by the `HordeManager` update hook, because `POSITION_LOOKUP` is only valid inside the game's update (`:68-100`).
- **Authority** (`core/authority.lua:36-42`): needs `Managers.state.minion_spawn ~= nil` and `game_session:is_server()`. `in_live_mission` (`TwitchVersus.lua:220`) excludes `hub`/`prologue_hub`.
- **Side:** `Authority.enemy_side()` (`authority.lua:60`), `side_system` `get_default_player_side_name()` then `relation_sides("enemy")[1]`, fallback side id 2 ("villains").
- **Target:** `main_path:ahead_unit(hero_side_id)` (`execute.lua:350`) as `optional_target_unit`, `optional_aggro_state = "aggroed"` (Daemonhost is passive, `:652`). `optional_health_modifier` 0.5 for weakened units.
- **Single spawn:** `spawn_at` (`:362`) calls `Managers.state.minion_spawn:spawn_minion(breed, pos, Quaternion.identity(), villain_side_id, param_table)` (`:369`). `resolve_breed` (`:314`) honours `minion_spawn:replacement_breed`, so mutators still swap breeds.
- **Specials:** `do_special` (`:563`) calls `Managers.state.pacing:try_inject_special(breed, direction, target_unit, spawner_group, ignore_allowance)` (`:606`), requires `pacing:max_num_specials() >= 1` (`:578`). Deferred: pacing places it later.
- **Hordes:** `do_horde` (`:737`) calls `Managers.state.horde:horde(type, type, villain_side, hero_side, composition, towards_combat_vector, main_path_offset)` (`:797`); reads private `pacing._horde_pacing._current_compositions` (`:730-735`), fallback `renegade_small`.
- **Pickups:** `pickup_system:spawn_pickup` (`effects/pickups.lua:413`); crate interaction disabled with `interactee_system:set_active(false)` (`:234`).

## Position search (`spawn/positions.lua`)
- `Positions.escalate` (`:1032`): tries optional sources (mutator locations `:764`, `:902`; `minion_spawner_system:spawners_in_range` `:1119`), then 3 stages (occluded, widened, relaxed; `:39-58`) via `SpawnPointQueries.get_occluded_positions(...)` (`:641`). Last resort `unoccluded` (`:667`) scored on distance to nearest human, min 10 m, max 90 m.
- Anchor from `main_path:ahead_unit`/`behind_unit` plus `MainPathQueries.position_from_distance(travel +/- 35)` (`:254-295`), snapped by `NavQueries.position_on_mesh_with_outside_position`.
- `forward_only` compares group indices via `SpawnPointQueries.group_from_position` (`:397`).
- Defaults: 20-60 m for groups, 30-70 m for monsters.
- **No own raycasts.** "Occluded" = engine `get_occluded_positions` given `human_positions`.
- Contains a lot of probe/report tooling (`/tv_*`); when reusing, extract only the search path.

## Limits and director bypass
- `Budget.can_afford(count, cap)` (`core/budget.lua:129`): `minion_spawn:total_allocated_num_enemies() + count <= cap`. Defaults: cap 90, `HARD=145`, `MAX_CAP=140` (`:5-9`).
- **Bypasses:** groups/waves (`group_mix`) pass `budget_cap = IGNORE_ALIVE_CAP` (145) via `Groups.part_args` (`groups.lua:13,705-712`); `on_redemption` skips the up-front budget check for them (`TwitchVersus.lua:1446`). Per-part limit 24 (`execute.lua:38`), recipes max 8 parts / 60 units. Specials use `ignore_allowance = true` (`execute.lua:590-594`). Hordes/minions/monsters call `horde_manager:horde` / `spawn_minion` directly, skipping pacing timers.
- **It does NOT suppress the director**: no pacing state modified, no hooks on pacing. Units still count toward `num_spawned_minions`/`total_allocated_num_enemies` and, once aggroed, toward pacing's challenge rating. (This is the gap RealmsWaves must close; see doc 03.)
- Dead/metadata-only: ring-buffer check (`optional_use_queue`, 256 minus 32) is never requested; `max_alive` in `catalog/events.lua` is validated but not enforced. `Budget.director_says` (`:162`) only feeds `/tv_budget`.
- Per-entry cooldowns `state.cooldown[key]` (`:1411`): 30-900 s built-in, 0-3600 s custom.

## Event data format (`catalog/events.lua:154` `DEFINITIONS`)
- Fields: `id`, `title` (<=45), `prompt`/`prompt_template` (<=200), `cost`, `kind` (hurt/help/vote), `cooldown_s`, `max_alive`, optional `count_min/max`, `seconds_min/max`, `effect`.
- `effect.request` in: `group`, `special`, `monster`, `horde`, `despawn_all`, `break_domes`, `restore_grenades`, `hold_abilities`, `golden_toughness`, `deployable`, `stimm`, `vote`, `group_mix` (`:37-51`).
- Wave entries: `wave()` (`:131`), 5 tiers up to 83 enemies, `group_mix` with `parts = {breed_name, count, label, health_modifier?}`.
- Custom groups: recipe strings such as `"5 trappers, 5 mutants, 10 hounds"`, parsed by `Groups.parse` (`groups.lua:332`, aliases `:59`) into `group_mix`, ids `user_group_N`. Max 8 parts, 60 total.

## Voting (Twitch only)
- Modes per reward: `off` / `instant` / `vote`. Vote: `start_vote` (`TwitchVersus.lua:1104`) calls `Vote.start(candidates, {duration_s, title, on_finished})` (`logic/vote.lua:1243`), Helix `/polls`, scope `channel:manage:polls`.
- `vote_open` reward (`catalog/events.lua:646`) draws 3 eligible rewards via `draw_ballot` (`TwitchVersus.lua:1286`); auto-poll `start_auto_poll` (`:1327`) every 60-900 s.
- Chance config: `ev_*_poll` and `ev_*_poll_chance` (1-100). `draw_ballot` is two-stage (per-candidate `math.random(100) <= chance`, then top-up by `take_weighted` `:1257`). `poll_candidate_of` (`:1197`).
- **In-game vote seam (reusable contract):** `Vote.start` / `update` / `cancel` / `active` / `status`; `on_finished(winner, result)`; winner option's `.candidate` is your `{title, key}` input; `result` has `total`, `cancelled`, `error`. RealmsWaves reimplements this contract with Realms RPCs instead of Helix.

## Network and HUD
- No DMF network, no RPC, no `get_mod("Realms")`. Clients just see ordinary replicated enemies. `authority_failure_reason` (`:232`) reports retail (`HOST_TYPES.mission_server`) and Realms-client (`HOST_TYPES.player`) sessions as inert.
- HUD: only `HudElementTwitchVersusBanner` (`ui/hud_element_banner.lua:72-162`), one line "A VOTE HAS STARTED IN TWITCH CHAT", never names choices. State in `mod:persistent_table("banner")`. Registered for alive/dead/communication_wheel/tactical_overlay.

## Twitch coupling and the clean cut line
- Everything Twitch goes over `Managers.backend:url_request` (HTTP polling), no EventSub/websocket. Modules: all of `transport/`, `logic/vote.lua`.
- Endpoints: `id.twitch.tv/oauth2/*`, `api.twitch.tv/helix/{channel_points/custom_rewards,redemptions,polls,chat/announcements,users}`. Scopes: `channel:manage:redemptions channel:manage:polls moderator:manage:announcements` (`twitch_auth.lua:20`). Tokens stored in plain DMF settings.
- Coupling in `TwitchVersus.lua`: module loads `:1721-1727`; `update_body` ticks `:1668-1686`; `update_gate` `:1493`; `update_sync` `:1575`; `settle_redemption`/`refund_redemption` `:620`,`:676`; vote/auto-poll `:1025-1383`; commands `tv_login|logout|profile|sync|clear_rewards|http`; options groups `group_connection`, `group_vote`.
- **Cut line:** `run_entry(key, entry, nil)` (`:738`). `/tv_test` already calls it that way (`:2662`); `/tv_fake` shows redemption-shaped input (`:3193`). Cooldown/budget checks happen before it in `on_redemption` (`:1411`,`:1447`) so a replacement trigger must repeat them.

## Bugs / dead code noticed
- `clear_queue` calls `Rewards.refund` unguarded (`TwitchVersus.lua:1466`); errors with nil `Rewards` if the queue is non-empty and Twitch modules are removed. Do not copy that path.
- `Authority.is_realms_session` (`authority.lua:117`) exists but is unused.

## VersusMode (separate mod, only relevant as a pattern)
- Humans "possess" enemy minions over Realms RPCs; 23,002-line `VersusMode.lua` (sampled by grep, not fully read). Not part of the merge.
- Useful pattern: `VersusMode_realms.lua` (13,119 B): Realms mod-network install (`:221-282`), 11 RPCs all `protocol = 1`, sender validation with `is_host()/is_client()/from_host(peer_id)`, payload whitelisting (`:386-426`), exact-version handshake (`receive_hello` `:125-148`, client re-sends `vm_hello` every 2 s until acked).
- HUD pattern: `VersusMode_team_hud.lua` (roster rows, 0.1 s refresh). It hooks `realms_preparation_view` (`VersusMode.lua:20012+`).
- Version inconsistency: `.mod` 3.0.58 vs `info.json`/code 3.3.0 (handshake uses code).
- `mods\VersusMode\.claude\settings.local.json` is a dev leftover (harmless, ignore).
