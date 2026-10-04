# PR #9: card effects and compact UI

Development branch: `feature/card-effects-and-ui`, based on the confirmed PR #8
merge `fe957632ebf666306324b604fd62d028b32a3a22` (2026-10-03).
Implementation and offline verification are separate from native acceptance.
No installed mod copy or reference mod was modified.

## Card controls

- Prayer uses teal `#4F9CA3`, Miracle gold `#D8B45A`, Grace white `#E8EEF4`.
  They share the existing special-frame system with HERESY and have their own
  halo/sigil shapes, button colours, page backgrounds and strength colours.
- Selecting a beneficial face replaces the enemy panel with Beneficial Effects.
  Enemy callbacks, catalog reads, exports and the host executor prevent enemies
  from these faces. Switching face does not erase an existing enemy recipe;
  it stays dormant until a hostile face is chosen again.
- All six strength diamonds are directly clickable. Old automatic settings
  remain readable for compatibility; Auto/By hand switches are hidden.
  DESPAIR is level 6: near-black `#16131F` on hostile cards, edged in pale
  `#C7B8E0`. Ordinary cards retain five displayed HUD pips; the sixth appears
  at level 6. Beneficial pips use their face accent with the exceptional edge.
- Consecrate 12 cards replaces the standard slots with four cards of each new
  face. Prayer grants Blue Stimm, Miracle cleanses/heals, Grace restores combat
  abilities. It preserves weights/enabled settings and custom slots, saves the
  previous deck to Presets Undo, and requires typing CONSECRATE in the editor.
- Share Card replaces Share Wave. A small vector share glyph appears on each
  Deck/stage card; **Show Share Card sigils** defaults on and hides both glyph and
  hotspot when off. Sharing uses the existing sealed single-card import/export.
- Enemy shelf cells share one 156-unit width; long names use a smaller font
  within that cell. Shelf and repeat-stepper borders have foreground 2-unit
  edges. These are vector widgets, not individual enemy texture assets. Native
  rendering must confirm that this resolves the reported missing right edges.

## Gameplay effects

Native gameplay changes require a Realms mission host. Amounts are bounded,
saved per card, and shared through the existing preset format. Live eligible
players follow a stable party-key order; a count selects the first eligible
players, not a named-player preference list.

| Effect | Configuration and behavior |
| --- | --- |
| Party healing | 0–100 percent of maximum health, through native `add_heal(..., "buff")` |
| Health and corruption | Same percentage via `buff_corruption_healing`, then normal healing; native healing restrictions and corruption caps apply |
| Green / Yellow Stimm | Give an item to 1–4 eligible players with an empty small pocketable slot |
| Med Crates | Give crates to 1–4 eligible players with an empty large pocketable slot |
| Med Station | Add 1–4 charges to the nearest rechargeable station by party distance, clamped to its native maximum; needs a battery |
| Combat ability | Restore 0–100 percent of combat ability resource; each player applies the host grant to their locally owned native extension |
| Specialist guidance | Reveal living specialists through walls for 1–300 seconds, on every participating modded peer; ordinary enemy-colour outlines remain depth-tested |
| Blue Stimm | Apply the native speed-boost buff to 1–4 eligible players for 1–300 seconds; no pocketable slot consumed |
| Blackout | Hostile card option, 1–300 seconds; disables native level light controllers, captures original enabled states, restores on expiry/stop/disable/reset |

Timed effects continue during scheduler pause, matching native buff duration.
Blackout overlaps extend the deadline and include newly streamed controllers.
Already disabled lights remain disabled afterward. Guidance overlaps extend
the deadline and preserve native tags and other mods' additions on cleanup.
Ownership is bounded to 600 specialist outlines and 256 temporary buffs.
Dead/despawned units are pruned; native expiry is checked before buff removal.
Missing controllers, stations, player extensions or item definitions warn once
and skip the unavailable operation. Items never replace an occupied slot.

Blackout does not control sky, emissive surfaces or lights without a native
controller. Guidance and remote ability restoration require the same mod
revision on peers. Initial snapshots establish an instantaneous-grant baseline:
joining later does not replay old heals/items/ability resets. Active guidance
is synchronized by remaining duration; native light/buff systems own replication.
Instant ability grants retain 64 entries, completion audio eight; losses beyond
those windows are not replayed. Old peers ignore unknown effect state and
reject extended card text cleanly. Use matching revisions for these features.
Effect snapshots carry a revision and host timestamp; duplicate or older
snapshots cannot renew a reveal or restore it after a stop.

## Completion audio

The card's Completion sound picker starts with Silence and content-ranked
native events. Search filters the broader catalog of 2,685 source-listed events.
Ranking includes enemy breeds, healing/stimms, Med Crates, Medicae, combat
abilities, Veteran-style guidance and lighting/power interruption.
Selection previews the sound. **Play card completion sounds** defaults on.
SimpleAudio is optional: enabled `SimpleAudio.play(event)` is used if available,
otherwise the existing UI Wwise world plays the resource event. Calls are
protected; an unavailable bank warns and does not abort the card.
Source-listed names do not prove every bank is loaded in every mission.

Audio waits for initial/repeated queues to finish, tracked enemies to die or
despawn, and that card's timed effects to expire. Failed/timed-out spawning and
cancelled cards are silent. At most 64 unfinished sounding cards are tracked;
silent cards consume no completion slot. An hour-old unresolved ticket expires
without sound. Host snapshots carry a bounded audio journal; duplicate snapshots
never replay it and late joins start silently. Failed optional playback never
changes spawn admission or stats. Selecting Silence keeps previous card behavior.

## Appearance experiments

The **Independent outline** switch coexists with natural/applied/equipment stimm
tint. Ordinary colour outlines use only `minion_outline` at priority 2; native
manual smart tags retain higher priority and their through-wall material layer.
**Keep edited tint over other buffs** defaults off. When enabled, safe hooks on native
material-effect start/stop reapply the configured vector without changing buffs.
When off, native buff changes can replace the colour.

Recipes support `<applied_stimm+outline!:AARRGGBB>`: `+outline` enables an
independent outline and `!` protects the tint. Old suffixes still parse. Peer
validation accepts bounded booleans in the two optional appearance fields.
Recipe parsing protects appearance suffixes before splitting enemy separators,
so outline flags survive saving/reopening mixed enemy lists. Removal packets
clear both flags together with the visual method.
Surface overrides and private shader patches are visibly unavailable and
disabled. No compatible authored material data/assets were found; descriptions
retain the actual prerequisites. See [the method guide](enemy-appearance.md).

## Native evidence and acceptance

New targeted reads use the existing game source revision `419fe18d414a618ce0474bd015bab470afb446d6`.
Relevant contracts: `scripts/extension_systems/health/player_unit_health_extension.lua:212`,
`scripts/utilities/pocketable.lua:77`, pickup charge handling at
`scripts/extension_systems/pickups/pickup_system.lua:1272` (retained-charge items
need a pickup; the selected syringe/crate definitions do not retain charges),
`scripts/extension_systems/health_station/health_station_extension.lua:205` and
`:236`, `scripts/extension_systems/ability/player_unit_ability_extension.lua:1120`
versus `player_husk_ability_extension.lua:402` (throws), native light-controller
RPC dispatch in `light_controller_system.lua:154`, and outline material layers
in `scripts/extension_systems/outline/outline_system.lua`.

Runnable evidence: `tools/effects_test.py` exercises pure schema, real catalog,
shared cards, native API stubs, multiplayer grant/audio handling, bounded
ownership, timed overlap, cancellation and actual editor callbacks.
Appearance/HUD/editor harnesses retain regression and allocation checks.
Real-widget PNG previews cover the shelf, beneficial panel/Mirror, DESPAIR,
sound picker, appearance dropdown and compact Last Card. Preview fonts are
Windows substitutes and no native materials or sound banks are rendered.

Final offline runners pass **2,321 assertions each**, 39 Lua compilation inputs
and all 38 module gates, with no existing floor reduced (Lua 5.5 82.37% / LuaJIT 2.1 79.13%).
See the [complete coverage table](10-ci-and-coverage.md).

Required game checks before merge:

1. All requested enemy cells and repeat borders at 1080p and other UI scales;
   full long names/flavor, Last Card transparency and unobtrusive share glyph.
2. All beneficial effects for host, remote human and bot; corruption prevention,
   occupied pockets/grimoires, empty/full/no-battery stations and disconnect/death.
3. Blue duration below/above native 15 seconds; overlapping buffs and stop/reload.
4. Blackout across several levels, streaming/hot join and initially disabled
   lights; specialist reveal across the map, expiry and ordinary tag precedence.
5. Edited colour plus outline, natural stimm and enrage with protection on/off;
   unavailable methods remain disabled and cleanup preserves other mods.
6. Ranked/search-selected audio with/without SimpleAudio and unavailable banks;
   repeating waves, failed spawning, dead enemies, delayed snapshots and late join.
