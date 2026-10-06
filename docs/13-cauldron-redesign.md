# Cauldron redesign: Faith, crimson Heresy, one cooldown, sounds (feature/cauldron-redesign)

Development branch: `feature/cauldron-redesign`, created on 2026-10-04 from `main` at
`bc4d9ff` (the merge of PR #9). It brings the mod in line with the user's second
workshop design page ("Grandfather's Cauldron Workshop", 2026-10-04) and the
user's follow-up requests. Nothing here is accepted in game yet; the branch stays
open until the user confirms it (CLAUDE.md rule 2).

## What the user asked for

From the design page and its two rounds of feedback (2026-10-04):

| Request | What was built |
| --- | --- |
| One cooldown: "all cards use rot and renewal" | `Cards.look` always returns `rot`. The Mirror's three look plates became one plate that shows rot and renewal, marked EVERY CARD, not clickable; Automatic for this suit is gone. Saved looks (`cl_`, presets, shared texts) still parse and are kept. |
| Threat 5 and 6 murmur when drawn and chosen | The HUD banner writes the whisper letter by letter in 1.6 s after the card is shown, only at threat 5 and 6 (`Cards.murmurs`). Lower threats show it whole at once. The cut never splits a two-byte letter (`Cards.utf8_cut`). |
| Auto / By hand replaced by a hostile / beneficial switch | `btn_kind_hostile` and `btn_kind_ben` beside FACE under the card and at the end of the Mirror's Suit header. The quick face shows the 12 hostile suits or the 4 beneficial ones; the Mirror's plates follow. The switch starts on the card's own kind and follows a suit that is picked. |
| Level 6 of a beneficial card is not "Despair" | `Cards.threat_name`: DESPAIR on hostile cards, APOTHEOSIS on beneficial ones. Its edge is `Cards.threat_edge`: pale lilac `#C7B8E0` or warm white `#FFF6DC`. Shown beside the quick-face diamonds and on the Mirror's threat line. |
| The sixth pip: strong and shiny, dark for enemies, light for blessings | `Cards.six_shine(t, suit)` pulses 0.35 to 1. Despair's halo breathes between a deep violet and its pale edge and the diamond darkens; Apotheosis glitters faster between the accent and warm white and the diamond brightens. The HUD Spread, the Deck tiles and the stage card all animate it. The Last Card window keeps the static edge. |
| Heresy crimson, bloody, dark and frightening | New palette: card `#0D0204`, frame `#8A0F1C`, crimson accent `#D42A3A` (was gilded `#E5B94C`), lit `#FF3344`, blood `#5A0610`. Its glow and frame beat like a heart (`Cards.heartbeat`, a double beat about 70 per minute) in the HUD and on the Deck and stage cards. In the HUD three drops of blood run down from the card's lower edge. |
| A fourth beneficial card, Faith, themed for 40k and unlike any other | Faith, the Order of the Sacred Rose: wine-rose card `#220F1C`, frame `#C25A8C`, accent `#F08CB8` (no other suit is pink), whisper "Believe, and endure.", a rose in a ring. It is the 16th suit (`Cards.SUIT_ORDER`, `HOSTILE_COUNT = 12`). Consecrate now makes three cards of each of the four faces. |
| Beneficial screen like the enemies screen | Effect rows (the group's colour on the edge, compact amount stepper, players stepper for Blue Stimm, Remove) and a shelf of chips in four groups. A chip adds its effect at its default; a second click takes it off. |
| Groups renamed | Healing, **Buffs** (was Guidance), **Items** (was Prayer), **Game Effects** (new; the design page called it Wonders). |
| Keep Wonders and its effects | Two new host effects in Game Effects: **Raise the fallen** (1 to 4 knocked-down players) and **Refill ammunition** (0 to 100 percent of every weapon's reserve). |
| Disable Recharge Med Station for now | `disabled = true` in `catalog/effects.lua`: the chip is greyed and says off, `Effects.allowed` drops it, so a saved value never runs. It is still parsed and shared. |
| Compact the steppers | Row steppers 32 high (32 + 46 + 32 wide, 19 unit value, 6 unit signs) instead of 40 (40 + 56 + 40, 22); row chips 30 high instead of 36. |
| Borders match the suit | Already true in the mod: `Components.set_theme` scales the shared frame colour to the suit's frame. No change needed; the design page itself was what had fixed borders. |
| Deck export icon | Already in the mod (the Share Card sigil, `card_share_icons`). Missing only from the design page. |
| Sound menu: Search button, preview, volume, a second sound | See below. |

## Raise the fallen and Refill ammunition (native paths)

- **Raise the fallen** writes `assisted_state_input.force_assist = true` on the host for a
  knocked-down player (`PlayerUnitStatus.is_knocked_down`) who is not already being
  helped. This is what a Veteran's shout does
  (`scripts/extension_systems/ability/utilities/shout_ability.lua`, `revive_allies`)
  and the servo skull's syringe (`bt_inject_syringe.lua` `_revive_ally_if_needed`).
  Netted, pounced, consumed and dead players are not touched. It runs at most
  for the configured number of players, in the party's stable order.
- **Refill ammunition** calls `Ammo.add_to_all_slots(unit, percent / 100)` on the
  host for every living player (`scripts/utilities/ammo.lua:494`), the helper the
  Veteran coherency talents call on the server for other players. A full reserve
  stays full; a failure for one player is contained and warned once.
- Both are host-only like the other gameplay effects. Old peers reject a card text that carries
  `revive` or `ammo` (unknown effect id), as they already did for any unknown id.

## Completion sound: two sounds, volumes, preview, search

- The `snd_` setting keeps the old form for one sound at full volume (`event`), so an
  ordinary card stays readable by older peers. Otherwise it holds up to two
  `event@volume` entries separated by `;` (`Sounds.parse`, `Sounds.encode`,
  `Sounds.check`). Presets and Share Card carry the text unchanged and validate it
  with `Sounds.check`.
- The second sound starts when the first ends. The native player is asked with
  `WwiseWorld.is_playing`. SimpleAudio gives no id, so its second sound follows
  after 2.5 s. Nothing waits longer than 12 s. The chain is advanced by
  `Effects.tick_audio`, called from `mod.update` everywhere, so the editor's
  preview works in the hub too. At most eight chains are kept.
- **Volume is experimental.** The game exposes no per-sound volume; the stock options
  set global Wwise parameters (`options_sfx_slider`). A volume below 100 plays the
  event through its own manual source and sets that parameter on the source,
  scaled by the player's sfx volume. Whether Wwise honours it per source must be
  checked in game. Volume 0 never plays (that part is certain).
- The sound screen: every row but Silence has **Preview** (plays it, saves nothing);
  **Select** fills the open slot (1, or 2 once there is a first) and the screen
  stays; **Search** reopens the search box; **Remove 2**; and a volume slider per
  sound (drag, or click the number for a box). Silence clears both. The button
  under the card says silent, 1 set or 2 in a row.
- Old peers: a card with a volume or a second sound is silent for them (their
  `Sounds.valid` refuses the text). Use matching revisions.

## Removed

The cooldown looks other than rot and renewal (the deck's murmur and vial animations,
the Mirror's whisper and vial plates and their callbacks), Automatic for this suit
(`btn_look_auto`) and the hidden Auto | By hand buttons (`btn_thr_auto`,
`btn_thr_hand`, `cb_threat_auto`, `cb_threat_hand`). A threat of 0 saved by an
older version still means "worked out from the enemies". The tile keeps its
vial and bubble passes (never shown) so old widget layouts stay valid.

## Files

`catalog/cards.lua` (palettes, Faith, threat names, edges, shine, heartbeat, one look,
murmur, utf8 cut), `catalog/effects.lua` (categories, new effects, disabled flag),
`catalog/sounds.lua` (two sounds), `catalog/events.lua`, `catalog/presets.lua`,
`core/effects.lua` (revive, ammo, audio chain, volume), `GrandfathersTarot.lua`
(`tick_audio`), `ui/hud_element_waves*.lua` (heartbeat, blood, shine, murmur),
`ui/hud_element_last_card.lua`, `ui/spread.lua` (the Faith mark),
`ui/wave_editor_deck.lua` (`_tick_living_tile`), `ui/wave_editor_effects.lua`
(rewritten: effect rows, effect shelf, sound controls), `ui/wave_editor_workshop.lua`,
`ui/wave_editor_face.lua`, `ui/wave_editor_view.lua`, `ui/workshop.lua`,
`ui/workshop_blueprints.lua`, `ui/wave_editor_components.lua` (stepper font and
sign size), `ui/wave_editor_definitions.lua`, localization.

## Second round: matching the design page (2026-10-04)

After a first look in game the user found the shelves, the beneficial card and the Last Card still in the older style. Fixed in one
more commit on this branch. The Lua test suites were deliberately not run or updated for this round (the user's choice); the
editor and HUD harnesses still drew the screens for a visual check, and their only failures are the old expectations listed below.

| Request | What was built |
| --- | --- |
| Shelves like the design page (columns, thin outlines) | `Workshop.shelf_layout` and `fx_shelf_layout` share one column layout: four columns side by side (Fodder, Elites, Specials, Bosses at widths 0.9 / 1.05 / 1.25 / 1.3; Healing, Buffs, Items, Game Effects equal), the title on top, chips as wide as their label (`Workshop.chip_width`), wrapping inside the column. Chips have a one unit outline (the second two-unit frame is gone) and no faction tint (the Dreg / Scab switch says which faction a click adds). Effect chips carry a diamond at the right, lit while the card holds the effect. |
| Card text of a beneficial card: colours and amounts | `Effects.summary(values, lines, chars, markup, text_rgb)` writes `95% Party health`: the amount (`Effects.lead`: `95%`, `15s`, `4`) in the bone colour, the name in its group's colour, `+N more` when it does not fit. Its dots are the colours of its effects' groups (`Effects.dots`, used by `Cards.describe`). |
| The amount in the effect rows | A row reads `100%  Party health` (the amount in the bone colour), as on the design page. The stage line under the card counts effects, not enemies. |
| Replace Consecrate 12 cards with a Search button | The Deck's `rw_deck_search` (same place) opens a box; the Deck shows only the cards whose name, suit, enemy or effect holds the text, as it is typed. Escape restores the previous search, empty shows every card; the blank card is hidden while searching. Consecrate is gone. |
| The Last Card window was broken | Rebuilt as the design page's card "in the hand": 240 wide, the suit's accent as a bar at the left, the name (one or two lines, the Spread's font option) with the suit mark at its right, the threat diamonds and enemy dots on one row, the whisper inside the card (Heresy's crimson). No ring or disc around the mark. Its whisper text is raised above the card face (it was drawn under it). Beneficial cards show no dots in the HUD (a synced card carries only enemy kinds). |
| Quick face 2 x 6, not 2 x 8 | `Workshop.SUIT_COLS = 6`, tiles 80 wide with a 9 unit gap: six fill the 525 unit pane. |

The test expectations these rounds left behind were brought up to date on 2026-10-04 (see [the results log](06-results-log.md)).

## Third round: steppers, cooldown, outline line of sight, sound (2026-10-04)

Lua suites again not run or updated (the user's choice); every changed file was checked to load.

| Report | Cause and fix |
| --- | --- |
| Stepper borders too thick | `Components.stepper_passes` drew a two unit edge over its one unit frame; the edges are one unit now (every stepper). |
| The Mirror's cooldown "2:00" broke over two lines | `blueprints.workshop_stepper` used the 46 unit compact value cell with the default 22 unit font. It now has a 64 unit cell at the compact font (19) and sign size: "30:00" and "auto" fit. |
| The enemy colour outline showed through walls | The outline material layers draw through geometry. Its `visibility_check` (asked every frame by the outline system) is now `in_sight` in `spawn/appearance.lua`: true when a player has tagged the enemy (`smart_tag_system:is_unit_tagged`), else a ray from the local camera to the enemy's spine, then its head (`filter_minion_line_of_sight_check`, static level geometry) must be clear. Each enemy is cast at most every 0.15 s, the answer kept in a weak table. A failed cast hides the outline and is warned once. |
| Longest card cooldown 30 minutes | The option `tarot_longest` defaults to 30 (it allowed 2 to 30 already) in the settings, `Events`, the Face and the HUD, and `Cards.rot_strength` falls back to 1800 s. A one-time step on load raises a saved value below 30 to 30 (`tarot_longest_30_done`); after that the option is the player's again. |
| No card sound was heard, neither the preview nor the completion | Nothing failed (no warning in the console log): almost every event of the list is a 3D game sound, and an event triggered without a source plays at the world's origin, out of hearing. Sounds now play on an auto source on the local player's unit in the level's sound world (`WwiseWorld.make_auto_source`, as `player_unit_fx_extension.lua` does); without a player unit (menus) they fall back to the UI world with no source. SimpleAudio is no longer used for this (it triggers the same native event without a source). The experimental volume now sets the sfx parameter on that auto source. |

## Fourth round: the sound list (2026-10-04)

At the user's request the list of completion sounds (`catalog/sounds.lua`) drops the weapon events (814), the non-vocal attack and
impact sounds of enemies and players (147; any `_vce` vocalisation is kept) and the 60 `vo/play_sfx_es_*` routes (silent without a
file), and adds voice lines from the game's dialogues (`dialogues/generated`): every enemy line (2,312), the twin bosses' mission and darkness lines (122 more, 2026-10-05) and one line per player voice
and topic of combat talk (5,458; conversations, quirks, lore and responses left out). 9,558 entries in all (the two syringe events
`play_syringe_stab_self`, the stimm use sound, and `play_syringe_heal_husk_charge_cancel` were missing and were added the same day). A voice line (`loc_...`)
plays as the game plays the local player's own lines: `trigger_resource_external_event` on the 2D player voice route
(`play_sfx_es_player_vo_2d`, `es_player_vo_2d`, format 4) on the player's auto source. Old peers do not know the voice lines: a card
with one is silent for them.

## Fifth round: the sound at the draw, new effects, Nightmare (2026-10-04)

| Request | What was built |
| --- | --- |
| The search box hides the sound names; let me move it or see through it | The popup panel is dragged by its title strip (the 56 units above the input), stays on the screen and is remembered for its `place_key` while the editor is open. A popup that filters a list (`allow_rows`) is see-through (alpha 170 of 255). The sound search opens at y 760, over the volume sliders, with a hint that it can be moved. |
| The card's sound plays when the card is drawn, like an alert; the wave spawns when it ends | `Effects.alert` (core/effects.lua) plays the sound on the host at once, writes it in the audio journal (the other players hear it with the next state, which `launch` sends at once) and returns a job that is done when the last sound of the card has ended (never before 0.3 s: a sound may not report itself as playing on its first frame). `launch` (core/director.lua) holds the wave until then, at most 20 s, not while paused or stopped; it is used for the tarot draw, the vote and random modes and fixed-timer waves. `/gt_test` still spawns at once. The completion sound (played when the wave's enemies were all dead) and its tickets are gone. A host who muted card sounds does not hold the wave; the others still hear it. |
| Raise the fallen: one downed and ONE hogtied | One knocked-down player (assisted_state_input.force_assist) and one hogtied player, freed as the rescue interaction does it on the host (assisted_state_input.success, hogtied_state_input.hogtie = false). The amount is fixed (`fixed`, max 1): the row reads "1 downed + 1 hogtied" and has no stepper; the card line reads "1+1 Raise the fallen". |
| Items: Yellow, Blue and Red Stimm items; remove the Blue Stimm buff from Items | `yellow_stimm` (renamed Yellow Stimm item), `blue_stimm_item` (syringe_speed_boost_pocketable), `red_stimm_item` (syringe_power_boost_pocketable) into an empty small pocketable slot. |
| Buffs: Yellow, Blue and Red Stimm buffs | `yellow_stimm_buff` (syringe_ability_boost_buff), `blue_stimm` (syringe_speed_boost_buff, the old id so saved cards keep it, moved from Items), `red_stimm_buff` (syringe_power_boost_buff); seconds and players, the native 15 s changed by `add_duration`. |
| Game Effects: replenish X grenades; Ammo Crates to X players | `grenades` (1 to 6): `restore_ability_charge("grenade_ability", n)` on the host for every living player with a grenade ability, as the grenade pickup does it. `ammo_crate` (1 to 4 players): ammo_cache_pocketable into an empty large pocketable slot. |
| Delete Dusk; a new suit like Heresy but all black, nightmarish, super dangerous, after Heresy | **Nightmare**: card #030304, frame #2B2735, ash accent #9B93AD, a pale light #F2EEFA, gloom #120E1A, black ink. In the HUD its glow is a darkness that breathes (`Cards.dread`, one breath every 3.3 s), its two-unit frame is a dying light that flickers back now and then (a flash of 0.6 to 1 in about one beat in seventeen at 9 per second), and black ink drips from its lower edge. The Deck tile and the stage card share the glow and the frame. Its mark is a horned eye with a slit pupil and a black tear. Dusk's saved cards become Murmur (`dusk` is an alias everywhere a suit is read). |
| Nightmare only once per game | `once = true`: when one card of the suit goes out (draw, vote, random, fixed timer), every card of the suit leaves the draw for the rest of the mission (`Director.spent_once`); a new mission brings it back. |
| Order Warp, Heresy, Nightmare | `Cards.SUIT_ORDER`: ... Brute, Warp, Heresy, Nightmare, then the four blessings (the quick face's second row ends Warp, Heresy, Nightmare). |
| A Warp effect | `motes`: Warp's glow is on at rest and pulses unevenly (`Cards.warp_pulse`) with crackles toward a pale violet `lit`, and three motes of the warp rise from the card's top edge in the HUD; the Deck tile and the stage card pulse too. |

Old peers: a card with a Nightmare face shows as Plague for them; cards with the new effect ids are rejected by them (unknown
effect), as before for any unknown id. The glow of Nightmare is a dark colour: whether the game's glow material shows a dark glow
(it may blend additively) must be checked in game; the flicker of the frame and the ink do not depend on it.

## Sixth round: test commands, the rehook warning, Nightmare's fog and dread, the boss bars (2026-10-04)

| Request | What was built |
| --- | --- |
| "[WARNING] (hook_safe): Attempting to rehook active hook [start_shooting]" when a game starts | DMF runs a `hook_require` callback every time the game loads the file again; `spawn/tuning.lua` hooked `MinionAttack.start_shooting` again on the same table. A weak set now keeps the tables already hooked; `spawn/appearance.lua` had the same pattern (the minion buff class) and has the same guard. |
| /gt_test and /gt_test_close play the sound first | Both go through `launch()`: the card's sound plays, the wave spawns when it ends (at most 20 s). A test never spends a once-per-game suit and is released even while the waves are paused or stopped. |
| /gt_drawtest card_name | `Director.stage_draw`: three cards (the named one and two others of the draw) are dealt as a real hand and the named one is picked 3 s later: the Spread, the roulette, the banner, the murmur, the Last Card and the Nightmare's dread all play. No sound, no enemies, no cooldown. The cycle goes on where it was (its countdown, or the vote/random state). Refused when not host, not running, paused, or while a staged draw shows. |
| /gt_fulltest card_name | The same staged draw, then the card's sound and its wave, as in play (a test: no cooldown, no once-per-game). |
| The Draw HUD below the boss bars while bosses are up | `HudElementGrandfathersTarotPanel._update_boss_push`: while the game's `HudElementBossHealth` has an active boss and the panel overlaps the bars' band at the top centre (748 wide, down to y 172), the panel is drawn lower, sliding at 500 units a second, and back up when the boss is dead. The node (custom_hud's place) never moves; a panel moved elsewhere is left alone. Option `hud_avoid_boss_bars`. |
| The Spillway's whole-screen effect, black and grey and see-through, with a Nightmare card's sound; a toggle | The Spillway's effect is a mood (`spillway_nurgle_transition`: a shading environment and a screen particle in Nurgle green, `scripts/settings/camera/mood/mood_settings.lua`); its colours are baked and cannot be changed. `ui/hud_element_dread.lua` is the mod's own full-screen overlay instead: a black veil that breathes and flickers with the dying light (at most about 40 percent dark, so the screen stays readable), a feathered vignette (16 thin frames) and four banks of ash-grey fog drifting across, three layers each. It rises when a Nightmare card is drawn (every player: the draw is synced), holds about 5.5 s and fades by 8 s; a late joiner is not shown an old one. Option `nightmare_dread`. |
| Nightmare's card: a black fog that periodically darkens all its content, very special | `Cards.fog`: a veil over the whole card (mostly clear, a slow surge every 7.4 s) and three banks of fog drifting down it, black, above everything on the card, in the Draw HUD, on the Deck tile and the stage card, and in the Last Card window (which now ticks every frame for it). |

## Seventh round: the Restart crash, the despawn error, the idle Packmaster (2026-10-04)

| Report | Cause and fix |
| --- | --- |
| Crash on Restart: `camera_manager.lua:536: bad argument #1 to 'camera'` | The console log's stack: mission cleanup destroyed a Packmaster in its summon action; the game's `BtSummonMinionsAction.leave` summons when the summon has not happened yet, even when the unit is being destroyed, so hounds were spawned while the level was torn down and the new unit's proximity extension asked for a camera that was gone. `Tuning.summon_leave` (a hook on `leave`) marks the summon done when `destroy` is true: a unit being destroyed never summons (the mod's or the game's). |
| `[Keybindings] mod.despawn_units: bt_summon_minions_action.lua:222: flood_fill_from_position` (creature_spawner's despawn key while a mutant held you) | The same path: the despawn destroyed the Packmaster during its summon. Fixed by the same hook. |
| The Pursuer's Packmaster (`1 packmaster{health=10 size=95 speed=135}`) did not move, no aggro | The Packmaster is the hound mutator's unit: it summons its hounds PASSIVE and sets them up as its patrol (`should_patrol`), and its tree puts the summon before combat; the log shows it inside its summon action when it was despawned. For a summoner of a wave (Bypass-tracked: Packmaster, radio operator): no patrol setup, its summoned minions come in aggroed with a target, and once a second it is made to fight again if it lost its aggro or its target (`MinionPerceptionExtension.aggro`, `force_new_target_attempt`). |
| /gt_fulltest put its wave on top of the current one | By design: a staged draw does not cancel the cycle, and the enemies already on the map stay (as after any draw); the countdown goes on afterwards. |

## Eighth round: rescues, damage dealt, boss-bar options, questions answered (2026-10-04)

| Request | What was built or found |
| --- | --- |
| Nightmare card darkness slider | Option `nightmare_fog_strength` (0 to 100 percent): scales the card fog in the Draw HUD, the Deck and the Last Card (`Spread.fog`'s strength). |
| The Draw HUD see-through while bosses are up | Option `hud_boss_opacity` (10 to 100, default 50): the Draw HUD fades to it while a boss bar is shown and back after (2 a second). |
| A toggle to invert: Draw HUD on top, boss bars below | Option `hud_boss_bars_below`: while a boss is up and the Draw HUD is in the bars' band, the boss health element's `background` node is moved below the Draw HUD (`set_scenegraph_position`) and put back to where it was (custom_hud's place included) when the boss is gone. |
| Raise the fallen: the hogtied rescue did nothing; rescue one hogtied player and teleport them to the nearest living player; remove the downed revive | Why it failed: the hogtied state's `Assist` only completes an assist it started (an interaction or `force_assist`); the first version wrote `success` alone. Now `force_assist` frees ONE hogtied player, and they are brought to the nearest standing player: the host teleports its own player and bots (`PlayerMovement.teleport`), a remote human's own game does it from a "teleport" grant in the effects journal. The downed revive is removed. |
| Instant rescue | New Game Effect (1 to 4): the next N players who go down are helped up at once (forced assist, checked every quarter second on the host); stop and reset disarm it. |
| Sniper damage | New custom mod **Damage dealt** (10 to 500 percent, the tenth row): the unit's `damage` stat, which `damage_calculation.lua` adds for every attacker, melee and shots alike. `1 sniper{damage=200}` doubles a sniper's shot. |
| A black outline / black stimm colour (picture: A 255, RGB 0) | Not possible with these methods. The stimm tint (`stimmed_color`) is light ADDED to the surface and all-zero is the game's own "no tint" value; the outline is drawn the same additive way, so black adds nothing and shows nothing. A real black needs a darkening material, i.e. new shader assets, which a Lua mod cannot ship (see docs/research/enemy-appearance). |
| Sniper aim laser colour | Not done. The laser is a particle effect (`renegade_sniper_laser`: `content/fx/particles/enemies/sniper_laser_sight` and an outdoors beam); the game only sets its length (`hit_distance`). A colour would need a colour variable inside the particle asset, whose name is not in the Lua source: it could only be found by trying names in game (a probe command), not promised. |

Old peers: a card with `damage=` in a recipe, or the effects `instant_rescue`, is rejected by them as unknown.

## Ninth round: clients, darkness, the hogtied teleport, boss health, imports, On Fire (2026-10-04)

| Request | What was built or found |
| --- | --- |
| The combat ability refill and the Specialists' outline worked only for the host | The outline: a client never ran the effects update, and the update is what draws a reveal's outlines on each machine; clients now run it (`GrandfathersTarot.lua` `mod.update`, `Effects.update(dt, false)`). The refill: on the host a remote player's ability extension is a husk (its restore throws), so the client restores its own ability from the host's grant in the effects journal. The grant is now applied to the client's own player, found through the player manager (`local_player_safe(1)`; the party list a client builds may miss it), and each grant applied writes `GrandfathersTarot card effects: combat ability restored by N percent` to the console log. No defect was found in the grant path itself: if a client still gets nothing, that log line (present or missing) shows which side fails. |
| Darkness slider: 100 = almost completely dark, 30 = today's look | Option **Nightmare darkness** (`nightmare_fog_strength`, default 30). `Spread.darkness(base, percent)`: none at 0, the old look at 30, alpha 245 (almost black) at 100, straight lines between. It drives the card fog (HUD, Deck, Last Card) and the dread over the screen (veil, vignette, fog). A saved 100 (the old full strength) becomes 30 once (`nightmare_dark_v2_done`). |
| While the darkness lasts, every player sees the "one wound left" look | When a Nightmare card is drawn, each machine adds the game's `last_wound` mood to its own player (the grey, colourless world); a hook on `PlayerUnitMoodExtension._remove_mood` keeps it on while `dread_active` is set, because the game re-checks the mood every frame. Only the look: nobody's health changes. It ends with the dread. |
| A way to darken an enemy (shadow or similar) | Found, not built: the Daemonhost's ambient fog is a particle effect (`content/fx/particles/enemies/daemonhost/daemonhost_ambient_fog`, `chaos_daemonhost_settings` `fog_effect`) that could be created on another enemy and linked to it (`World.create_particles` and a link), as an experimental "shadow fog" modifier. Untested: whether the resource is loaded outside a Daemonhost mission, how it looks on a small enemy, its cost with many enemies. The user decides whether to try it. |
| The hogtied rescue works but the player is not teleported | The teleport was done in the same frame as the rescue, while the player was still hogtied (the forced assist takes time), and it did not stick. The host now keeps the rescued player in a list for up to 15 s and teleports them to the nearest standing player once they are neither hogtied nor knocked down (a remote human through the teleport grant, as before). |
| The Wrath card's boss health shows 0 or another number for clients | Clients read a unit's maximum health from the networked game object, whose health field is capped by the network (`NetworkConstants.health_large.max`); a custom health above that overflows on clients. A custom health is now capped at that maximum (`Tuning.network_health_max`), with one warning in the log when it is. |
| The import of `RWW1\|custom_27~Fire and Steel~...` fails | The text was damaged by the chat app: `~~1~~` between field separators is Markdown strikethrough, so the empty fields and a `~` were eaten. Exports now write an empty field as `.` and escape `*`, `_`, `\` and backticks, and the card key is escaped too; older texts still import. The damaged text cannot be recovered: it has to be exported again with this version. |
| On Fire: too subtle, only the host burns; then "clients burn now, but it hurts too much, let me set it beside the modifier" | The On Fire row of the Mods screen has a stepper on the right (0 to 300 percent, a click on the number opens a box), stored with the group's custom values (`{burn=50}`; 100 is not stored). The game's burn templates are wrapped once: the burning enemy marks the players it sets on fire with its group's share, and their burn runs the game's own damage with the power level scaled (0 = no damage). The host decides damage, so clients burn by the same share. |

Old peers: a text exported now (`.` fields, escapes) and a recipe with `burn=` are not read by them.

## Tenth round: boss health in bars, On Fire that lasts, the editor's memory (2026-10-05)

| Request | What was built |
| --- | --- |
| Remove the health limit; instead show x2, x3 beside the boss bar (a 130k limit: 490k shows x3, 450k x3 with its last bar not full) | The cap of the ninth round is gone. A unit with more health than the network's health field carries keeps its real health on the host (every hit, heal and death works on it); the network gets health and damage divided by the smallest whole `k` that fits (after each `add_damage`, `add_heal` and `set_health_instant` of `HealthExtension`), so the share of health left that clients read is exact. The spawn parameter itself stays within the limit (the game object is created with it) and the exact health is set right after. The real maximum goes to clients in the director's state (`hl`: game object id and maximum, 16 units at most). Every boss bar (host and clients) shows the health in bars of the network's limit: full bars first, the last one holds what is left over, and "xN" beside the name counts the full bars still behind the one shown. A new bar starts a fresh bar animation; a client's "Weakened" name, made from the divided maximum, is put right. |
| The On Fire look lasts only 1 s after the spawn; make it last while the monster lives | The look is the game's "burning" ailment effect: the buff starts it once and the material shows it for 2 s. Every machine now keeps its end 3 s ahead of the clock (the same material value, the start unchanged) while the enemy lives and has the buff, so it fades 3 s after death or after the buff ends. This also applies to the game's own On Fire enemies (Havoc), whose look is the same. |
| Default On Fire damage 35% | A wave's On Fire enemies burn players at 35 percent unless their group sets the damage (the Mods screen stepper starts at 35). 35 is not stored or written; 100 (the game's own damage) is now `{burn=100}`. The game's own Havoc On Fire enemies keep the game's damage. |
| The Deck remembers its scroll | Noted when scrolling, when a card is opened and every frame on the Deck; Back to the Deck and the next open come back to it. |
| The editor key reopens the window that was left | The screen that was open when the editor closed comes back: a card's screen, Face, its sound list, a group's Mods, Custom mods or Appearance, Settings, Presets, a preset being viewed. What is gone falls back: a deleted card to the Deck, a missing group to the card's screen, a missing preset to the presets. Kept for the game session (`mod.rw.editor_memory`). |

Old peers: they read a divided unit's bar as one bar of the right share (no "xN"); a `burn=100` recipe is read by them as the game's damage too.

## Before the merge: the name (2026-10-05)

- The mod is **The Grandfather's Tarot**: DMF id, mod folder (`mods\GrandfathersTarot`, also in `mod_load_order.txt`),
  `scripts/mods/GrandfathersTarot`, `GrandfathersTarot.mod/.lua/_data/_localization`. Internal identifiers follow the files
  (`GrandfathersTarotView`, `HudElementGrandfathersTarot*`); setting keys, network RPC names and the editor's view name stay.
- **Saved decks and options are kept**: DMF stores settings under the mod's name, so the first load copies every setting saved
  under `RealmsWaves` (decks, cards, presets, options; the old entries are left as a backup) and marks it done
  (`gt_settings_migrated`). Custom keybinds take effect from the next game start.
- Commands are `/gt_...` (`/gt_editor`, `/gt_test`, `/gt_status`...).
- The mod menu is in the Nurgle palette: the title in rot green and pus yellow, every section header in a Plague colour.
- The editor's card screen is called **The Grandfather's Workshop** (was Cauldron).
- Peers must run the same version (the RPC names did not change, the mod id did).

## Polishing: living cards, Dream, the Workshop (2026-10-05)

| Request | What was built |
| --- | --- |
| Rename the Purple Stimm buff to Twins | The modifier is called **Twins** everywhere it is shown; its id (`purple_stimm`) and the old names stay valid in recipes, `twins` is a new one. |
| Holding the - and + of a cooldown keeps stepping | The click takes its step as before; held for 0.4 s the button repeats it every 0.07 s until it is let go or the pointer leaves it. On the Deck's tiles, the cooldown beside the chance, the Face tab's cooldown and the card on the stage; not while a popup is open. |
| Picture 1: "1 random of Beast of Nurgle / Chaos Spawn / ..." ran over three lines, over the header and the modifier line | A row's name is one line: its font shrinks from 26 down to 17 to fit, then it is cut with "..." (the colours of a random group are kept). |
| A subtle sign that an enemy has a colour experiment | A small diamond between the row's edge and its name, in the experiment's colour (the skin effects have their own: burning orange, warp blue, bruise purple; a colour too dark for the row is shown pale lilac). |
| Right click an enemy to change it and keep its modifiers | A right click on a row's name opens the enemy picker for that group (the top line says so). The enemy picked, or a random group made there, replaces the group's enemy; its count, repeats, modifiers, custom mods and colour experiment stay. Back changes nothing. |
| Picture 2: the outlines of Poxwalker, Melee, Rager and Beast of Nurgle | At screen sizes other than 1080p the chip's fill, rounded to whole pixels, could cover the one unit frame on some chips. The four edges are now drawn again on top of the fill. |
| A new beneficial suit, **Dream**, the opposite of Nightmare, colourful and positive, with an impactful heavenly effect | The fifth beneficial suit (after Faith): the brightest card of the deck (twilight lavender), a sky-blue accent, a pastel frame and glow that turn through a rainbow, clouds in every colour and rainbow stars on its face, a cloud with a star as its mark. When one is drawn **Dream's sky** opens over the whole screen for 7.5 s (every player, the draw is synced): a bloom of light from the middle, rays falling from above, clouds rolling in along the foot and the head of the screen, a rainbow edge, rising stars; see-through, light, never dark. Option "Dream's sky on screen". |
| A fire effect on Rage and a plague effect on Plague, in the Deck and in the HUD / last card; a thematic effect for Plague, Murmur, Blight, Swarm, Fateful, Volley, Snare, Brute, Prayer, Miracle, Grace and Faith | `ui/aura.lua`: every suit's own animation on its card's face, under its text. Rage: flames lick up from the foot (yellow, orange, deep red) with embers. Plague: bile bubbles rise and pop, flies buzz. Murmur: pale lights drift and blink like whispers. Blight: drops of pus fall with trails, a yellow gas at the foot. Swarm: a whirling cloud of tiny things. Fateful: stars twinkle, dust of the last page sifts down. Volley: tracers streak across. Snare: a chain creeps round the edge, tightening. Brute: every 2.2 s a blow: a shock along the floor, chunks of brick fly, the glow flares. Prayer: incense rises with sparks of light. Miracle: golden stars flash open, motes of light. Grace: white feathers drift down, rocking. Faith: rose petals tumble. Dream: clouds and rainbow stars. On the Deck's tiles and the card on the stage, the Spread's cards and the last card window; fainter while a card rests, none on a card out of the draw. Heresy and Nightmare keep their own blood and fog. Option "Living card effects". |
| The warp HUD effect on the Deck | A Warp card on the Deck (and in the last card window) has the warp's motes rising through it, flaring when it crackles; the Spread keeps its own motes over the card's top. |

Old peers: a Dream card synced to a peer without it is shown as Plague there (an unknown suit); its effects are the same.

## Polishing 2: the effects seen, a clean help, the last card on the Face tab (2026-10-05)

| Request | What was built |
| --- | --- |
| Plague, Murmur, Swarm, Snare, Prayer and Faith show no effect (and Dream only "two squares") | Those effects are made of circles. The game draws a circle on the whole layer under its z (`Gui.triangle` takes a whole layer), so the aura's circles at z 1.5 on the Deck's tile (z + 4.5 on the HUD) were drawn on the face's own layer and the face covered them; the rects of the other suits were not. Every aura shape is now on a whole layer above the face (2 on the tile, z + 5 on the HUD and the last card); Dream's sky's clouds and their hearts too. Tests check every aura pass's layer. |
| Volley more like bullets | Five bullets at a time: a brass slug (longer than high) with a white-hot nose, a fading tracer behind it, and a spark where it strikes the far edge. |
| Dream more intense | Big soft clouds in every colour along the foot and the head (eight, a quarter of the card wide and more), a bright heart in four of them, motes of light rising, two rainbow stars flashing open. |
| Brute and Rage more intense | Twenty shapes a card (was twelve). Rage: fourteen flames reaching higher, a breathing bed of fire along the foot, embers to the top, and its glow flickers. Brute: a blow every 1.8 s, twelve chunks flying higher, four puffs of dust, a shock along the floor, two cracks opening, a harder flare. |
| A cleaner "?" description, with formatting (picture 1: a wall of text) | The tooltip is a card of its own: opaque, in the page's colours, with a shadow, the accent's strip and frame, a "?" badge and a title, a divider, the body and a footer ("Click the ? to keep this open"). Its height follows the text. The help strings are written in a small markup (`ui/help_text.lua`: `# ` a title, `## ` a heading, `- ` a bullet, `*lit*` words) turned into the game's `{#color}` / `{#size}` markup; every screen's help was rewritten as short sections and bullets. |
| On the Face tab, the last card window beside the hand card; rename the caption | The caption is **When it is drawn**. Beside the hand card stands the last card window as the HUD draws it, at its HUD size (240 wide, the two fill the 525 of the right side), its card's top level with the hand card's, "just drawn" where the HUD says how long ago; its aura and Nightmare's fog live as on the HUD. The HUD's painter moved to `ui/last_card_paint.lua`, used by both. |

## Polishing 3: effects that follow the threat, new looks, options (2026-10-05)

| Request | What was built |
| --- | --- |
| Every card's effect grows and shrinks with its difficulty | `Aura.update(..., level)` takes the card's threat (1 to 6): the number of shapes of every suit (`Aura.amount(lv, lo, hi)`), their size (0.85 to 1.05) and their light (0.62 to 1 of it) grow with it; the glows of Rage, Brute and Dream too, Brute's blows come faster. 28 circles / rects and 12 triangles a card (was 20 / 0). |
| More Swarm, Volley and Fateful at high threat | Swarm: 8 to 26 things, faster and wider, a second cloud whirling the other way at 5 and 6. Volley: 2 to 7 bullets, faster. Fateful: 2 to 6 stars, 3 to 10 motes of dust, a falling star at 5 and 6. |
| Rage: flames / blaze, fewer circles unless 5 or 6 | A blaze of triangle tongues of flame in three layers (deep red, orange, a yellow heart; 6 at threat 1, 12 at 6), swaying and flickering over the bed of fire; balls of fire: none at 1 and 2, three faint ones at 3 and 4, nine at 5, fourteen at 6. |
| Blight: remove the two big circles | The two gas clouds are gone: a pool of pus lies along the foot (deeper with the threat, its surface trembling) and every drop bursts into two droplets where it lands. |
| More Murmur at high threat; at 5 and 6 every letter murmurs | 5 to 20 lights, larger and brighter. A Murmur card of threat 5 or 6 writes all its texts letter by letter (the name, the enemies, the modifiers, the whisper, in that order), holds them, wipes them from the end and writes them again (`ui/murmur_text.lua`; the game's colour tags are kept whole). On the Deck and the cards of the editor, the Spread's name and the last card's name and whisper. |
| Lightning / strong weather on Heresy 5 and 6 | A storm: rain lashing down (14 streaks at 5, 22 at 6), lightning from the top in six slivers with a branch, the whole card flashing; every 3.3 s at 5, every 2.1 s with a second flicker at 6. |
| Prayer looked like water | Candles along the foot (2 to 5: wax, a trembling flame, its glow), incense smoke rising from them, soft rays of light from above, a halo at 5 and 6; no teal any more. |
| A slider for Dream's sky | "Dream's sky strength", 0 to 150 percent (0 = none), replaces the on / off option. |
| Snare is called Entrapment | The suit's name (its id stays `snare`, old cards and recipes keep working). |
| A toggle for all the card effects in the Deck | "Card effects in the Deck": every living effect of the editor's cards (the Deck, the card being edited, the Face tab's previews: auras, Heresy's heartbeat, Nightmare's fog, the sixth diamond's shine, the murmur of the letters). Off, the cards stand still. "Living card effects" is now "Card effects on the HUD" (the hand and the last card window). |
| Hover descriptions for every option | Every option and group of the mod's menu has a description (DMF shows `<setting_id>_description` on hover): 57 new ones. |

## Polishing 4: Rage's anger, quieter Heresy and Prayer, a slower murmur (2026-10-05)

| Request | What was built |
| --- | --- |
| Remove the rain from Heresy, keep the lightning | Heresy of threat 5 and 6 keeps only its lightning (six slivers and a branch) and the card's flash. |
| Remove Prayer's candles and its circles, keep the beams | Prayer is only soft beams of light falling from above and swaying slowly: 2 at threat 1, 6 at threat 6. |
| Remove Rage's animation; the whole card turns more red, more angry, the higher the difficulty | No flames, balls of fire or embers any more. A red veil over the whole face (faint at threat 1, deep at 6), redder edges in three bands that widen with the threat, and a throb like a pulse (`Aura.anger`: from 0.8 a second at 1 to 1.9 at 6); the glow throbs with it, redder and stronger as the threat grows. |
| The murmur must repeat and be slower, slower with the threat | 11 letters a second at threat 5, 7 at 6 (was 26); held 2.5 s, wiped from the end three times as fast as it was written, a breath of 0.8 s, and again, forever. |

Triangles: 8 a card now (only Heresy's lightning uses them).

## The author's deck as the default, the Packmaster's dogs (2026-10-06)

| Request | What was built |
| --- | --- |
| Make my deck and all my options / window locations the mod's default | `catalog/user_defaults.lua` holds every card setting of the author's deck (621, read from their user_settings.config on 2026-10-06) and the Deck's order and sort. A fresh install (never migrated, no card saved, nothing copied from RealmsWaves) is seeded with it once (`RW.seed_defaults`, flag `defaults_seeded`); nobody's own deck is touched. `Events.reset` (a card's Reset, Restore defaults, an empty preset, a preset's card) writes these values over the built-in ones, and Restore defaults also takes the default deck's order and sort. The options' defaults in GrandfathersTarot_data.lua are the author's (28 changed: timing 600 s fixed, 3 cards, 30 s to pick, spawn limits and distances, the Spread's timings and font, the editor key Num -, ...). The last card window's default place is the author's: x 1680, y 550. |
| A Packmaster: decide whether he spawns dogs, a toggle at the right of his line | A **Dogs** chip at the right end of a Packmaster's row (the Mods, Custom and Remove chips are a little narrower to make room; on other rows it is hidden): lit, he calls his hounds the game's way; dark, he comes alone. Stored in the recipe as `(no dogs)` ("1 packmaster[enraged](no dogs)"), so it travels with shared cards and presets. On the host a unit of such a group is marked at spawn and `SummonedMinionsExtension.can_summon_minions` answers no for it (spawn/tuning.lua). |

The Lua tests were not run for this round (the user's request); the suites still expect the built-in reset values and the old chip widths.

## 75 s between waves, the Captains' shield, the Daemonhost's kills (2026-10-06)

| Request | What was built |
| --- | --- |
| The default time between waves: 75 s | `interval_min` and `interval_max` default to 75 (the mod menu, the editor's settings and every fallback in the code). A player who already set a time keeps it. |
| Captains and Twins: spawn with their shield or not, like the Packmaster | The Dogs chip became the row's own toggle (`hotspot_extra`, 76 wide; Custom 92 and Remove 80 to make room). On a Captain's (Dreg or Scab) or a Twin's row it reads **Shield**: dark, `(no shield)` in the recipe. On the host a Twin of such a group is spawned without `optional_init_toughness`, and every one gets `MinionToughnessExtension.destroy_shield()`: the shield is down, `_update_toughness` stops while it is not active (no regeneration), and the game object's `toughness_damage` tells the clients. |
| Daemonhosts: how many players they kill before they leave (1, 2, 3 or all) | On a Daemonhost's row the toggle steps **1 kill > 2 kills > 3 kills > All** (`(leaves 2)`, `(leaves 3)`, `(leaves all)`; 1 is the game's own and writes no marker). The game's Daemonhost leaves (`death_leave`, condition `daemonhost_wants_to_leave`) once its blackboard's `statistics.player_deaths` reaches `num_player_kills_for_despawn` (1 on every difficulty), but the deaths are counted only for a Daemonhost that went through its passive stage (`BtChaosDaemonhostPassiveAction.leave` registers it with `PacingManager.set_minion_listening_for_player_deaths`). A wave's Daemonhost comes aggroed, never passive, so it never counted: it never left. Now `Tuning.watch_daemonhost` registers every Daemonhost a wave spawns, and for 2, 3 or all the hook of that PacingManager function gives it a counter of its own (`Tuning.death_counter`) that writes the death to the game only once the number is reached ("all": every player in the game, bots included). Any player's death counts, as in the game. |

The Lua tests were not run for this round; the suites still expect the built-in reset values and the old chip widths.

## Reveal Elites, the Boss bar, the Blackout crash (2026-10-06)

| Request | What was built |
| --- | --- |
| Remove the Combat ability effect, add Reveal Elites (like Reveal Specialists, for Elites) | `cooldown` is gone from catalog/effects.lua (`Effects.RETIRED`: a saved card that still has it loads and saves without it; the author's default cards lost it too) and its host and client code with it (the "teleport" grant of Raise the fallen stays). `reveal_elites` (Buffs, seconds, 15 by default): every machine outlines the Elites (breed tag `elite`, never a Specialist) in amber while its time runs, the Specialists keep the teal outline; each kind ends on its own time. The time goes to clients in the effects snapshot (`reveal_elites`). |
| A friend crashed while a Blackout was on | The client's log: `light_controller_system.lua:155: attempt to index local 'extension' (a nil value)` in `rpc_light_controller_set_enabled`: the host switched the lights with `set_enabled(false, false)`, which sends that RPC for each light (four times a second for lights the level turned back on), and a light the host has was a unit without a light controller extension on that client; the game's handler does not check. The lights are now switched deterministically (`set_enabled(x, true)`, no RPC, as level flow does) and every machine darkens its own: the remaining time is in the effects snapshot (`blackout`), a client runs Effects.update, and it restores its lights when the host's time is over. |
| An individual unit as a boss, with its total health and name in the boss bar; a toggle for any unit, a custom modifier | A **Boss bar** row (a checkbox) on the Custom screen: `{boss=1}` in the recipe, "Boss bar" in the row's custom line. The game's boss bar shows a unit at the event `boss_encounter_start` (unit, boss extension) and asks the extension only `display_name`, `is_empowered` and `boss_is_depleted_interrupter`; a stand-in gives the breed's own name. The host marks the units at spawn (`Tuning.mark_boss`); their game object ids go with the host's state (`bb`, 16 at most); every machine starts and ends its own bars (`Tuning.update_bosses`, `boss_encounter_end` at death) and gives them to a boss bar made anew (a hook on its `init`). A Monster or a Captain (the game's own boss extension) is left to the game. A unit whose custom health is under the normal reads "Weakened ..." as the game names a weakened boss. |
| A name of my own for the boss bar, per card / unit | A **Boss name** row under Boss bar on the Custom screen (Edit: a text box; empty = the enemy's own name), per group: `part.boss_name`, "(name The Warden)" in the recipe, so it travels with shared cards and presets. Letters, digits, spaces and ' - . ! ? only, 30 at most (`Groups.clean_boss_name`); the parser keeps the name aside before it splits the recipe, so "Lord and Master" stays one name. The host sends { id, name } in the state's boss list; the stand-in carries the name and `Tuning.layer_boss_targets` writes it over the bar's text on every machine (no "Weakened" prefix for a named one). |

## Version 2.2.0: clients without a card cycle, the boss bar's colour, its numbers, a client crash (2026-10-06)

| Report or request | What was found and built |
| --- | --- |
| A client saw no reveal outlines and no custom boss bars (both fine for the host); fine after /gt_start | The package was complete (all 48 files the same as the repository). The host's state, which carries the effects (the reveal times, the Blackout), the health layers and the boss bars, went out only while the card cycle ran; waves started by hand had none. The director now sends a small state once a second while no cycle runs (`o = 1`: `fx`, `hl`, `bb`, `side_snapshot`); a client reads those and nothing else of it. |
| A client crashed when the Tower with a custom boss bar died | "Cannot access property current_health_percent on destroyed object of type HuskHealthExtension" (hud_element_boss_health.lua:258): the game ends a real boss's bar when its BossExtension is destroyed, in the same frame as the health extension; the stand-in's bar was ended by the quarter-second check only. `Tuning.drop_dead_bosses` runs every frame right before the bar's update and ends a stand-in's bar whose unit is dead or whose health cannot be read. |
| The boss bar's health numbers were not synced; "x1 x2 x3 again?"; is the cap per unit | Per unit: one unit's health field cannot carry more than `NetworkConstants.health_large.max`. A unit is divided for the network from 98 percent of it (`Tuning.fit_network`), but a client put the real numbers back only above the limit: a unit just under it (the Tower's 65000) read halved. Now a client uses the real maximum for any divided unit (the "xN" layers still only above the limit), and the bar's health object answers `current_health` and `max_health` with the real numbers too (NumericUI's boss number reads `current_health`). |
| The boss bar's colour | A **Boss bar colour** row on the Custom screen: - and + step through the game's red, Orange, Gold, Green, Bile, Teal, Blue, Purple, Pink and White; a click on its name takes a colour code (ff7a1a); Reset. Per group, "(colour ff7a1a)" in the recipe, sent with the boss list ({ id, name, colour }); `Tuning.colour_boss_bars` colours the widget group each target is drawn in and gives the others the game's red back. |
| The mod's version in the mod options | `catalog/version.lua` ("2.2.0") is the one place: the handshake (`Protocol.VERSION`, so a host and a client of different versions refuse each other with a warning, as the state changed), "v2.2.0" after the mod's name and "Version 2.2.0." at the start of its description. |
| The name and colour of a unit that is already a boss did nothing | A unit with the game's own BossExtension (a Monster, a Captain, a Twin) was left to the game entirely. Now a group's Boss name or Boss bar colour puts such a unit on the boss list too (Boss bar ticked or not; `Tuning.name_boss`), and every machine writes them on the unit's own boss extension (`_rw_custom_name`, `_rw_colour`, `Tuning.update_bosses`); the game still starts and ends its bar, and the per-frame bar code reads them as it does a stand-in's. |
| The boss bar colour never showed: always white for custom enemies, red for real bosses (the Recolor Boss Health Bars mod?) | It was that mod: a hook_safe on HudElementBossHealth.update sets the bar's colour (and its max part and name) every frame after the update, its own colour for a real boss and nil (a white bar) for any other unit; the colour was set before the update. The colours are now set right before the bars are drawn (a hook on `_draw_widgets`, `Tuning.boss_bar_draw`), after every update hook. A stand-in without a colour takes Recolor's "others" colour (the game's red without it); with Recolor on, the bar's max part, its name and NumericUI's number take the colour too, as that mod does; without it, a group goes back to the game's colour when its target has none. |
| Instant rescue armed, healed back above one wound: no golden health | The player panels draw their health segments again only when a health value changed (`_draw_health_segments`, set by `_apply_health_fraction`), and the gold is applied in that draw; when the gold came or went on its own (above one wound again, a charge armed or spent) the bar kept its old colour. The panel hook (it runs every frame) now asks for that draw whenever its gold decision changes (`panel._rw_golden`). |
| The Plague Ogryn of Anger (Enraged, the stimm look) cancels the last hit of his three-hit combo | The game's own rule (bt_melee_attack_action.lua): with `melee_attack_speed` above 1 an attack ends at max(duration / speed, end of its FIRST hit + 0.27 s), while the hits keep their normal times; at x1.3 the ogryn's 3.56 s combo ended at 2.73 s, before its third hit (2.70 to 2.84 s). `Tuning.fix_attack_end` already lengthened such an attack to its LAST hit, but only for a unit with a custom time between attacks; it now does so for every unit of a wave (offline: 2.73 s becomes 3.11 s). |
| A boss randomly cancels its combo on attack 1, 2 or 3; a toggle | **Random combo end**, a checkbox custom mod (`{combo=1}`, Custom screen): each attack of several hits (a chained sweep or several hit moments) ends after a random one of its hits, the last one included: 0.27 s after it, never once the next has begun (offline, 300 combos: after the first 97, the second 93, all three 110). Host only, like every behaviour. |

## In-game checks before merge

1. Heresy at 1080p, 1440p and 4K: the heartbeat is visible but not distracting,
   the drops read as blood and stay attached to the card in the hand, the
   roulette and the rot; the crimson buttons and title are readable.
2. Threat 6 on hostile and beneficial cards in the HUD, the Deck and the stage:
   the shine is visible and has no stepped edge worse than the other diamonds.
3. A threat 5 or 6 card drawn: the banner whisper appears letter by letter, and a
   late joiner during the reveal sees it complete correctly.
4. Faith: tile, quick face, Mirror plate, HUD sigil; an older peer shows it as
   Plague (unknown suit) without errors.
5. The hostile / beneficial switch on both screens; picking a beneficial suit
   swaps the screen to effects and back without losing the enemy recipe.
6. Beneficial rows and shelf: add, step, type a number, remove; the disabled
   Med Station chip; a card saved with Med Station runs nothing for it.
7. Raise the fallen with one and two knocked-down players (host, remote human,
   bot), a netted player, a player already being revived and a dead player.
8. Refill ammunition with empty, half and full reserves, weapons without ammo,
   a disconnect in the same frame.
9. Sound: Preview on rows, two sounds in a row (native and SimpleAudio), volume
   below 100 (does it get quieter at all?), volume 0, Remove 2, Silence; the
   compact row steppers and chips at every UI scale.
10. Second round: both shelves in columns at every UI scale (no chip label spills over its outline); the effect chips' diamonds;
    the Deck's Search (typing filters, Escape restores, empty shows all); the Last Card for a long name, Heresy, Faith and a rare
    card, and when moved with custom_hud; the quick face's two rows of six.
11. Third round: a card sound and its Preview are heard in the hub and in a mission (a 3D event like a syringe, a UI event, two in a
    row); the coloured outline hides behind walls and shows when the enemy is in view or tagged; the cooldown stepper on the Face
    screen at 30:00; the thinner stepper edges at every UI scale.
12. Fifth round: the card sound plays at the draw for every player and the wave spawns when it ends (one and two sounds, a voice
    line, a muted host, a pause during the sound); the search box drags and is see-through; Raise the fallen with a downed and a
    hogtied player; the three stimm buffs and items, grenades (a class without grenades, full pouches), Ammo Crates; Nightmare in
    the HUD (is the dark glow visible? the flicker, the ink), once per game (a second Nightmare never comes that mission, comes
    back the next); the Warp glow and motes.
13. Sixth round: no rehook warning at a game start or a mission restart; /gt_test and /gt_test_close wait for the sound;
    /gt_drawtest and /gt_fulltest (for a Nightmare card too: the dread on every screen); the Draw HUD sliding below a Beast of
    Nurgle's and two bosses' bars and back, at another HUD size and when moved with custom_hud; the dread at 1080p and 4K (is the
    game still readable? the vignette's steps?) and its option; the Nightmare card's fog in the HUD, the Deck and the Last Card.
14. Seventh round: Restart (Page Down) and the despawn key while a Packmaster summons; a wave's Packmaster fights and its hounds
    attack; the game's own hound-mutator Packmaster still patrols.
15. Eighth round: Raise the fallen with a hogtied host, bot and remote human (each brought to the nearest standing player), none
    hogtied; Instant rescue with one and two players going down; Damage dealt on a sniper; the fog slider; the Draw HUD's opacity
    and the bars below it with one and two bosses, and with the boss bars moved by custom_hud.
16. Ninth round: a client gets the combat ability refill (its console log says "combat ability restored") and sees the Specialists'
    outlines; Nightmare darkness at 0, 30 and 100 and the grey world for every player, ending with the dread; Raise the fallen
    teleports a hogtied host, bot and remote human once they stand; a Wrath boss's health on a client; a card exported, pasted in
    Discord and imported; On Fire damage at 0, 50 and 300 on host and clients.
17. Tenth round: a Wrath boss above the network's limit (e.g. Chaos Spawn at 500 percent) on host and client: the bar's share, "xN"
    counting down, each new bar full, the last bar partial, no "Weakened" on the client, the kill; two such bosses at once. On Fire
    enemies keep burning while alive and stop after death; their default damage (35) and 100. The Deck's scroll after Back and
    after reopening; the editor key reopening each screen, and a card deleted in between.
18. Polishing: every suit's effect on the Deck, the stage card, the Spread and the last card at 1080p and 1440p (readable text,
    nothing outside a card, the frame rate with a full Deck page); Rage's flames, Plague's bubbles, the Warp motes on the Deck;
    a Dream card drawn (the sky, its rainbow frame; host and client); holding a cooldown's - and +; the long random group's row;
    the colour-experiment diamond; a right click swap keeping Enraged and the custom mods; the Twins name; the chips' outlines.
19. Polishing 2: Plague, Murmur, Swarm, Snare, Prayer, Faith and Dream's clouds now seen on the Deck, the Spread and the last card;
    Volley's bullets; Rage's fire bed and flicker; Brute's blow; the "?" panel on every screen (fits the text, readable markup,
    pinned footer); the Face tab's last card beside the hand card (no overlap, its aura living).
20. Polishing 3: a card of threat 1 against one of 6 for every suit (fewer, fainter shapes against a busy card); Rage's blaze
    of triangles; Blight's pool and splashes; the Murmur card of threat 5 or 6 writing its letters (Deck, Spread, last card);
    Heresy's storm at 5 and 6; Prayer's candles; the Dream sky slider at 0, 50 and 150; Entrapment's name; the option "Card
    effects in the Deck" off; the hover text of every option in the mod menu.
21. Polishing 4: Rage cards of threat 1, 3 and 6 side by side (the red deepening, the throb quickening, the text still readable);
    Heresy 5 and 6 with lightning and no rain; Prayer's beams alone; a Murmur card of threat 5 and one of 6 writing slowly and
    starting again (on the Deck, the Spread and the last card).
22. The defaults: a card's Reset and Restore defaults give the author's cards back; the mod menu's options reset to the author's
    values; the last card window at 1680, 550 on a fresh profile. The Dogs chip on a Packmaster's row: dark, the Packmaster of
    that card never calls his hounds (host); lit, he does; the chip absent on other rows; Mods, Custom and Remove still readable.
23. A fresh profile waits 75 s between waves. A Captain's (both factions) and a Twin's row: Shield dark, the enemy has no void
    shield and it never comes back, for the host and a client alike; lit, as before (the Twins' shield raised). A Daemonhost's
    row: 1 kill, it leaves after the first player death (before this it never left); 2 kills and 3 kills; All, it stays until
    every player has died once (a rescued player's second death counts too).
24. Reveal Elites: amber outlines on the Elites for its time, host and client; Reveal Specialists still teal; a card saved with
    the old combat abilities effect still loads. A Blackout with a client: no crash, the client's lights go dark and come back.
    The Boss bar custom mod on a normal enemy (The Tower's): its name and health in the boss bar for the host and a client, gone
    when it dies; after a respawn the bar comes back. A Boss name on that group: the bar reads it, host and client.
25. Without /gt_start (waves started by hand): a client sees the reveal outlines, the Blackout and the custom boss bars. Killing
    a custom boss with a client: no crash. A boss bar colour on host and client; a unit of about 65000 health shows the same
    number on both (NumericUI). The mod options show v2.2.0; a client with the old files is refused with a version warning.
    A Boss name and colour on a Monster's or a Captain's group: its own bar shows them, host and client. With Recolor Boss
    Health Bars on: the chosen colours win; a custom boss without one is Recolor's "others" colour, never white.
    Instant rescue armed: down to one wound the gold goes, healed above it (medpack, med station, stimm) it comes back; drawing
    the card with full health turns the bars gold at once.
    Anger's Plague Ogryn (Enraged) finishes all three hits of his combo; with Random combo end he stops after one, two or three.
