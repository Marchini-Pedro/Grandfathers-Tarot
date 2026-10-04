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
`core/effects.lua` (revive, ammo, audio chain, volume), `RealmsWaves.lua`
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

Out-of-date test expectations (not changed this round): the faction tint of shelf chips, the 156 unit chip cell, the
`Consecrate` callback (`cb_bless_deck`, now `cb_deck_search`), the old Last Card geometry (176 x 250, card at y 24, window
frame colours) and the old `Effects.summary` text. They need updating before the branch is merged.

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
file), and adds voice lines from the game's dialogues (`dialogues/generated`): every enemy line (2,312) and one line per player voice
and topic of combat talk (5,458; conversations, quirks, lore and responses left out). 9,434 entries in all. A voice line (`loc_...`)
plays as the game plays the local player's own lines: `trigger_resource_external_event` on the 2D player voice route
(`play_sfx_es_player_vo_2d`, `es_player_vo_2d`, format 4) on the player's auto source. Old peers do not know the voice lines: a card
with one is silent for them.

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
