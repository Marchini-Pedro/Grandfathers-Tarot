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
