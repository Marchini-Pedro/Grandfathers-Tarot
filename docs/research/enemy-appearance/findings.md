# Selected-enemy appearance: findings

Research date: **2026-10-03**, America/Sao_Paulo. Research only; no game experiment, runtime change, mod installation, dependency change, branch operation or publication was performed. Only this report and [experiments-and-recommendation.md](experiments-and-recommendation.md) are deliverables. The existing [research prompt](research-prompt.md) is preserved.

## Conclusion and evidence standard

**Arbitrary full-body surface recolouring remains unproven.** Ordinary mod Lua can write a known colour variable to one enemy and its children without adding a gameplay buff. It can also apply material/texture overrides and manage selected-unit outlines. Neither the setter's existence nor its recursive flag proves that every enemy shader, armour piece, leg mesh, shield or weapon consumes that variable.

The smallest useful first step is a controlled `stimmed_color` coverage test. The most promising route to actual surface colour is to identify compatible enemy material parameters or material resources, then apply them to selected body/equipment units. If the stock materials cannot do it, public shader-patching and custom-asset tools provide a credible advanced investigation route. Polychromatic supplies concrete enemy **body-glow** shader work, rather than proof of arbitrary surface colour. A conventional per-enemy outline is the strongest inexpensive identification fallback.

Confidence is high in the inspected Lua call paths and moderate in feasibility of those narrowly defined mechanisms. Confidence in whole-body coverage, black surface colour, material-instance isolation and live compatibility is low until the experiments run. No method in this report is labelled in-game verified by this investigation.

Evidence labels used below:

- **Reported:** the user's friend or an implementation author describes a result; this investigation did not reproduce it.
- **Source-supported:** the inspected source contains the stated mechanism. This does not establish rendering success.
- **In-game verified:** requires captured live results; none were produced here.
- **Hypothesis:** a plausible explanation or adaptation with a specific test still needed.
- **Unknown:** the necessary shader, asset, runtime state or access was unavailable.

Surface recolouring changes the visible material's base colour; additive tint/emission adds light or colour; an overlay draws another translucent surface; a silhouette fill paints projected geometry; an outline draws edges/highlight layers; particles are separate visual objects. These have different black, lighting, texture and coverage behaviour.

## Inspected revisions and scope

Reference prefixes: **G/** = this repository; **S/** = `Content/Darktide-Source-Code/scripts/`; **M/** = `Content/mods/`. File:line citations identify physical source lines, not dynamically generated assets. Game references are pinned to the source revision below; G/ runtime citations describe a dirty working snapshot, not the committed tree.

| Reference | Inspected snapshot | Limit |
| --- | --- | --- |
| Grandfather's Tarot / RealmsWaves | HEAD `4cc68670ee03d1ee02ff11bd19eb8cfca96563af`, commit dated 2026-10-03; runtime reports 2.0.0, protocol 2 | Another session has uncommitted runtime and documentation edits. Relevant runtime hashes were checked twice and matched; see snapshot ledger below. |
| Game source | Clean `419fe18d414a618ce0474bd015bab470afb446d6`, 1.13.0, 2026-09-29 | [Pinned source tree](https://github.com/Aussiemon/Darktide-Source-Code/tree/419fe18d414a618ce0474bd015bab470afb446d6). Decompiled scripts do not include authored shader/material/unit/texture/package files. |
| Installed Microsoft Store package | `Content/appxmanifest.xml:3`: `1.13.6794.0` | Package identity corroborates a 1.13 installation; it does not prove byte-for-byte agreement with the script reference or compatibility with any shader payload. |
| Installed Realms | `M/Realms/info.json:10`: 1.0.0 | Historical project audit says 1.0.0-rc2; use the installed implementation for the appearance handoff. |
| Installed VersusMode | `M/VersusMode/info.json:2`: 3.3.0 | Descriptor still says 3.0.58. Only the relevant outline section was revisited. |
| Installed HavocConditionManager | `M/HavocConditionManager/info.json:4-5`: 4.5.0, IRONCROWY | Its asset documentation describes optional SimpleAssets, which is absent here. |
| Other installed examples | Red Weapons at Home 1.2.6; danger_zone localisation 1.1.1; transonic_stance_colors localisation claims 1.2.1 | Display/comment versions are weaker provenance than an upstream commit. PurpleStimms and TraumaOutlines have no established version in the inspected evidence; file hashes identify them. |

Read before new research: `CLAUDE.md`, project README, docs index, and docs 03-07. The user's research-only scope overrides the standing rule to edit shared docs immediately; proposed updates are handed off in the companion report. No applicable AGENTS.md was found on the project ancestry or inside its tree. The existing audit leads were rechecked only where relevant to appearance.

Historical `docs/03-findings-realms-and-game-source.md:143-150` correctly identifies `stimmed_color`, zero resets and network lookup risks. Its description of an added tint/glow and black limitation remains an inference without the shader. Do not extend it into a claim that all stims write this variable or all enemy body parts support it. The current colour catalog is explicitly UI/name colour (`G/scripts/mods/RealmsWaves/catalog/colors.lua:1-10,172-178`).

## Stim-effect trace and the upper-body report

**Reported:** the friend's stim effect appears mainly on the upper body. No screenshot, exact buff/effect identity, breed, armour variant, game revision or application snippet was supplied. The listed Discord channels are also user-provided leads; the screenshot itself is absent from this session.

### Distinct activation paths

The ordinary activation chain is server-side `MutatorStimmedMinions` listening to `minion_aggroed` and setting `stim.can_use_stim` (`S/managers/mutator/mutators/mutator_stimmed_minions.lua:14-16,35-51`), then `BtUseStimAction` choosing an existing buff and adding it (`S/extension_systems/behavior/nodes/actions/bt_use_stim_action.lua:69-76`). Minion buffs use existing network IDs (`minion_buff_extension.lua:206-223`), and late joins synchronize active buffs (`:30-70`). The following rendering paths must be distinguished:

1. **Material-vector buff path.** Purple stim's `mutator_stimmed_minion_purple` has a `minion_effects.material_vector` named `stimmed_color`, together with node particles (`S/settings/buff/mutator_buff_templates.lua:328-446`, particularly 441-445). `MinionBuffExtension._start_fx` starts the material-vector effect (`S/extension_systems/buff/minion_buff_extension.lua:436-439`). `_start_material_vector_effect` selects by priority and calls `Unit.set_vector3_for_materials(unit, name, Vector3(...), true)` (`:486-510`). On stop, it clears the current vector and may restore another active effect (`:514-563`). Stacked bolstering has the same material-vector mechanism (`S/settings/buff/havoc_buff_templates.lua:114-141,299-309`). [Pinned purple template](https://github.com/Aussiemon/Darktide-Source-Code/blob/419fe18d414a618ce0474bd015bab470afb446d6/scripts/settings/buff/mutator_buff_templates.lua#L328), [pinned buff extension](https://github.com/Aussiemon/Darktide-Source-Code/blob/419fe18d414a618ce0474bd015bab470afb446d6/scripts/extension_systems/buff/minion_buff_extension.lua#L486).

2. **Direct start/stop writes.** Havoc corrupted enemies write the variable at `S/settings/buff/havoc_buff_templates.lua:393` and clear it at 418; Toughened Skin writes at 522 and clears at 537; Enraged writes at 1250 and clears at 1305. The appearance calls occur before the server-only gameplay work, so each peer executing the buff can apply its own native visual write. Adding those buffs also adds their gameplay behaviour; copying just the verified setter avoids that coupling. [Pinned Havoc templates](https://github.com/Aussiemon/Darktide-Source-Code/blob/419fe18d414a618ce0474bd015bab470afb446d6/scripts/settings/buff/havoc_buff_templates.lua#L376).

3. **Particle-only ordinary stim variants.** The ordinary red/blue/green/yellow Havoc buff definitions starting around `havoc_buff_templates.lua:1422` contain spine and eye particle effects, but do not contain the purple material-vector field. A colourable spine cloud or glowing eyes can look like a torso colour effect without recolouring the underlying clothing or legs. Standalone effect templates have separate cleanup semantics; a method called `start_local_template_effect` is not sufficient evidence of non-networked execution.

4. **Standalone named visual effects.** `S/settings/fx/effect_templates/blue_stimmed.lua:61-63`, green `:65`, purple `:61`, red `:58` and yellow `:70` write `stimmed_color`. Blue/green/purple/red stop functions stop particles but do not reset the colour; yellow resets it at `:97`. They are registered by `S/settings/fx/effect_templates.lua:75-79`. `FxSystem.start_local_template_effect` (`S/extension_systems/fx/fx_system.lua:183-187`) delegates to `EffectTemplatesHandler.add_template_effect`; the inspected handler still looks up the template and sends an RPC (`S/extension_systems/fx/utilities/effect_templates_handler.lua:81-85`, stop at 142). Reusing a newly named template is therefore not automatically local or network-safe. The first diagnostic should call the known setter directly.

The setter already passes **`true`** for child traversal. Missing recursion is therefore not established as the cause. The engine's exact traversal and each material's variable support still need validation; separate descendants that appear later or are not in the traversed hierarchy remain possible.

### Geometry and attachment path

Minion visuals are not a single guaranteed material. `MinionVisualLoadoutExtension` exposes `inventory_slots()` (`S/extension_systems/visual_loadout/minion_visual_loadout_extension.lua:243`) and `slot_unit(slot_name)` (`:722`, includes attachment units). Body slots, weapons, shields and optional attachments must be enumerated separately. Visual readiness is established by `extensions_ready` (`:137`); override operations recreate slot units (`:1028-1071`). [Pinned loadout extension](https://github.com/Aussiemon/Darktide-Source-Code/blob/419fe18d414a618ce0474bd015bab470afb446d6/scripts/extension_systems/visual_loadout/minion_visual_loadout_extension.lua#L722).

Concrete authored loadouts illustrate separate upper/lowerbody, face, weapons and gear: `S/settings/minion_visual_loadout/templates/renegade/renegade_melee_visual_loadout_templates.lua:11-44,58-101`; bulwark torso/lowerbody/arms, shield, weapon, head and gear: `S/settings/minion_visual_loadout/templates/chaos/chaos_ogryn_bulwark_visual_loadout_template.lua:11-37,53-82,96`. `VisualLoadoutCustomization.spawn_item` creates attachments and applies overrides (`:87-97`); `World.link_unit` attaches them and registers them with parent LOD (`:356-365`). The extension's wield/unwield/drop paths unlink equipment (`:346-397,448-487`), so detached equipment can escape later parent-recursive cleanup. Destroy/unequip remove items and attachments (`:171-203,638-667`).

| Visible part | Evidence and present conclusion |
| --- | --- |
| Head, torso, arms, legs | Minion body/slot units can be addressed. Actual `stimmed_color` shader support and mask coverage are unknown for each material; upperbody/lowerbody separation is a lead, not a diagnosis. |
| Armour and clothing | May use different shader families or authored colour masks. A setting that works on cloth, exposed skin or one armour piece does not prove universal compatibility. |
| Weapons and shields | Separate inventory units; shader compatibility and child linkage need inspection. The bulwark breed names `slot_shield` (`S/settings/breed/breeds/chaos/chaos_ogryn_bulwark_breed.lua:54`). |
| Small attachments | `slot_unit` returns an attachment list; deduplicate nested traversal. Visibility and material support can differ from the main slot. |
| Gibbable parts/ragdolls | New or detached units may not inherit later writes; runtime continuity and cleanup remain untested. |
| Lower LODs | The scripts do not prove that each LOD uses the same parameter/mask/material instance. Near success must be retested at distance. |

### Competing effects and resets

The buff extension keeps active material-vector effects and a current priority/value (`minion_buff_extension.lua:17-24,486-590`). A direct custom write does not register itself with that arbitration. Later buff start/stop or stack changes can overwrite it; direct Havoc start/stop setters are another writer. Zero is the game's neutral/reset value for the demonstrated path, **not** an established black albedo value. Blindly writing zero can erase an appearance that was active before the mod's intervention.

The installed PurpleStimms author reports duplicate-effect/refcount cleanup trouble (`M/SoloPlayPurpleStimms/scripts/mods/SoloPlayPurpleStimms/SoloPlayPurpleStimms.lua:653-659,722-730`). This is compatibility evidence, not a reproduced defect in this investigation. Avoid calling private buff-vector functions with invented templates merely to obtain priority management.

### Why partial coverage remains unresolved

| Hypothesis | Evidence | Smallest discriminating observation |
| --- | --- | --- |
| The apparent colour is a spine/eye particle cloud | Several ordinary stim paths are particle-only; exact reported effect unknown | Compare the direct known material write against the native effect, with particles independently identified. |
| Only some shaders consume `stimmed_color` | Setters are present; enemy shader definitions are absent | Compare named materials and actual pixels on matched upper/lowerbody units. |
| An authored shader/texture mask limits the effect | Plausible; no inspected mask or shader proves it | Identify the affected material's shader and mask; unchanged partial coverage after explicit slot writes supports this direction. |
| Equipment/legs are outside the relevant traversal or created later | Separate units and slot reconstruction exist | Log hierarchy and slot-unit identities; compare recursive parent write with explicit existing-slot writes after readiness. |
| Another writer or LOD/material rebuild cancels colour | Buff resets and slot replacements are source-supported | Time-stamped before/after writes, buff changes, slot identities and LOD-distance screenshots. |

There are zero authored `.material`, `.shader`, `.unit`, `.texture` or `.package` files in the source checkout search. Compiled assets exist in the installed `Content/bundle` directory, but their character shaders/masks were not decoded here. Missing authored data or inaccessible pages do not establish impossibility. Repeating a setter cannot overcome a shader mask that ignores the intended pixels.

## Concrete candidate mechanisms

### Existing material variables and override helpers

`S/extension_systems/visual_loadout/utilities/visual_loadout_customization.lua:25-48` accepts either an item-definition name or an override table. `_apply_material_override_item` (`:535-609`) writes scalar/vector2/vector3/vector4 variables, textures, or calls `Unit.set_material(unit, material_slot, material_resource)`. Whole-unit variable writes use child traversal. Texture/material-slot writes require exact authored slot/resource identifiers. A table can describe a local experiment without registering a new vanilla lookup name. [Pinned helper](https://github.com/Aussiemon/Darktide-Source-Code/blob/419fe18d414a618ce0474bd015bab470afb446d6/scripts/extension_systems/visual_loadout/utilities/visual_loadout_customization.lua#L25).

`MasterItems.get_cached()` obtains runtime backend item definitions (`S/backend/master_items.lua:446-449`); those definitions are not contained in this Lua checkout. Existing `material_override_items`, property values, texture slots and authored material resource lists are the best next source of legitimate candidates. A plausible string such as `base_color`, `albedo` or `color_tint` is not evidence of enemy support. The consumed `breed.side_color_material_variables` field is another lead, with no matching breed definitions established here.

No inspected game call demonstrates a material getter, parameter getter, safe material-instance clone or release contract for minions. Do not invent these APIs. A write addressed to a unit suggests targeting, but an untreated enemy using the same asset must establish actual isolation. Restore authored values/resource paths captured from supported metadata, or use disposable test units; do not promise generic capture-and-restore from an unverified getter.

### Installed implementations

| Installed reference | Concrete implementation | What it proves / does not prove |
| --- | --- | --- |
| PurpleStimms `cosmetics.lua:47-89` | Local RGB conversion, shared replacement value for existing purple buff vector and particle material variables | Later purple effects can read configurable local RGB; all those effects share one local template value. It is not independent per-enemy colour, no-buff appearance or full-body proof. |
| transonic_stance_colors main Lua `:39-62,576-675,715-755` | Selected weapon-unit vector/scalar writes, known `blade_energy`/`blade_wiggle` slots, weak caches and event-driven static colours | Weapon emission is a useful pattern. Its speculative variable list and successful `pcall` are not verified enemy shader capabilities. |
| VersusMode main Lua `:727-734,10108-10235,10483-10616` | Per-unit `outline_color`, explicit equipment/attachment traversal, layer enable and reassertion after outline updates | Real selection and outline colouring mechanisms. Forced layers bypass normal bookkeeping and can survive ordinary remove; no surface-colour proof. |
| TraumaOutlines main Lua `:30-47,87-147` | Adds/removes existing outline identities on selected enemies, cleans tracked records | A no-stat targeted-outline fallback. Static wave membership should not copy its radius scan every frame. |
| Realms `workarounds/private_outlines.lua:22-44,73-126,189-242,280-356` | Perspective-scoped player buff outline ownership/refcounts | Relevant host/spectator compatibility; it does not automatically privatize arbitrary RealmsWaves outlines. |
| danger_zone main Lua `:13-15,48-54,65-129` | Loads a training package; spawns a separate projected ground decal; colours `projector` with `particle_color`/`color_multiplier`; destroys decal units | A coloured ground indicator, not body tint. Wrapping an articulated enemy with it is unproven and risks clipping/spill. |
| HCM `docs/diy/ASSETS.en.md:60-62,88-110` | Optional SimpleAssets loading of compiled material/particles/unit/animation; explicit native-object ownership | Credible custom-resource route. No automatic dependency rewriting, asset transfer, FBX conversion or general native unload; live rendering remains untested. |
| Red Weapons at Home main Lua `:71-73,182-199` | Rarity colours and UI display names | UI-only dead end for model recolour. |

Full installed file prefixes are `M/<mod>/scripts/mods/<mod>/` except the HCM document and Realms metadata. `outline_colours` was not installed at the researched path; its absence is not a public-upstream capability judgement. [Realms upstream](https://github.com/deluxghost/darktide-mods/tree/main/Realms), [Realms Nexus](https://www.nexusmods.com/warhammer40kdarktide/mods/1223).

### Outline and silhouette distinction

`S/extension_systems/outline/outline_system.lua:89-131` writes named layer `outline_color` to the parent and inventory slots with `slot.use_outline`, including attachments. `add_outline`/`remove_outline` manage stacks (`:191-281`); existing effects can compete by priority. Minion settings name `minion_outline` and reversed-depth layers (`S/settings/outline/outline_settings.lua:16-43`). Player settings also expose `default_mesh_always`/`default_mesh_obscured` and `player_outline_general_depth` (`:281-309`). Those player names are a **filled-silhouette investigation lead**, not demonstrated enemy fill support. [Pinned outline system](https://github.com/Aussiemon/Darktide-Source-Code/blob/419fe18d414a618ce0474bd015bab470afb446d6/scripts/extension_systems/outline/outline_system.lua#L89), [pinned settings](https://github.com/Aussiemon/Darktide-Source-Code/blob/419fe18d414a618ce0474bd015bab470afb446d6/scripts/settings/outline/outline_settings.lua#L281).

Prefer normal local ownership with balanced additions/removals. Forcing material layers also changes culling (`outline_system.lua:79-86`) and needs explicit restoration. Removing all outlines risks other mods and can invoke network removal; it is not appropriate cleanup for one appearance owner.

### Authored variants, overlays and unconventional routes

**Source-supported visual variant:** `mutator_minion_visual_override.lua:17-53` collects override item/gib packages; `:60-85` selects a template and calls the public loadout override. Rotten Armour settings cover particular Scab Mauler/Rager and Crusher slots (`S/settings/mutator/mutator_minion_visual_overrides_settings.lua:6-80`). Those are predefined models, not arbitrary RGB. Public `override_slot` applies locally and sends the existing override-name ID (`minion_visual_loadout_extension.lua:986-995`); clients reconstruct their own template (`:998-1025`). It does not transmit an arbitrary host-created item table. The private replacement recreates items without a generic saved-original inverse (`:1028-1071`). Hot-join sync checks slot state `"overriden"` (`:912-935`), while the public call supplies no explicit new state; do not assume this supplies a complete custom appearance late-join solution. [Pinned mutator](https://github.com/Aussiemon/Darktide-Source-Code/blob/419fe18d414a618ce0474bd015bab470afb446d6/scripts/managers/mutator/mutators/mutator_minion_visual_override.lua#L17).

**Source-supported ailment visual plumbing:** `S/utilities/ailment.lua:9-33` assigns `effect_mask`, `effect_gradient`, `HAVE_BURN` permutation and `offset_time_duration`. Burning/freezing/warpfire settings provide fixed masks/ramps (`S/settings/ailments/ailment_settings.lua:36-48,190-201,218-229`). Invoking only the visual helper may avoid gameplay buffs, but shader coverage, duration, arbitrary colour and complete restoration of textures/permutations remain unknown. It also competes with genuine ailments.

**Surface-emitted particles:** `S/extension_systems/buff/buff_extension_base.lua:1092-1097` calls `World.set_particles_surface_effect`. Here `material_emission` means emission of particles from surfaces, not setting the body's emissive RGB. Particle colour setters at `:1132` address particle materials. Another effect can write the ailment timing neutral vector at `:1166-1167`. This is not evidence for an opaque paint layer. The installed PurpleStimms comment `cosmetics.lua:14-21` reports a native crash after guessing a particle's material name; a Lua `pcall` does not validate arbitrary native particle names.

**Wounds:** `S/extension_systems/wounds/utilities/wound_materials.lua:8,35-46` supports three local wounds; colour at `:191-204` is a two-component palette input, not arbitrary RGB. `:209-254` applies optimized parameters across slots/attachments. Fixed palette pairs are in `S/settings/damage/wounds_templates.lua:10-48`. A giant wound as a body overlay is unproven, limited and competes with damage rendering.

**Decals:** `S/managers/decal/decal_manager.lua:74-87` has `add_projection_decal(...)` but returns no individual Lua handle. `remove_linked_decals(parent_unit)` at `:94-95` removes all linked decals, including other owners' damage decals. Projection has a credible local-mark use; whole animated-body coverage and clean individual removal are not established.

**Visual shell:** the captain void-shield effect names `slot_fx_void_shield`, `color_a` and `shield_power` (`S/settings/fx/effect_templates/renegade_captain_void_shield.lua:3-6,41-44,210-231`). This is a resource-specific translucent effect with toughness/light dependencies. A separately authored, rigged shell has an attachment basis in `spawn_item`/`World.link_unit`, but fit, animation, equipment, LOD, ragdoll and clean lifetime ownership require assets and tests. It is an overlay/replacement appearance, not preservation of existing surface colour.

**Stencil or custom post-process:** existing outline layers are concrete secondary passes. No general per-enemy arbitrary-colour stencil buffer or custom post-process registration path was established in ordinary Lua. A screen-wide filter would also fail selection isolation unless a verified unit mask exists.

## Public implementation evidence

Public repositories, native/asset tools, Nexus evidence and Discord coverage are detailed below. Their claims are kept distinct from local script findings and live verification.

### Polychromatic: character shader body glow

Inspected [commit e8cf7cb57de41c6b1d685f4128d744fcbb8094a3](https://github.com/Wobin/Polychromatic/commit/e8cf7cb57de41c6b1d685f4128d744fcbb8094a3), 2026-09-29; [Nexus 1.0.6](https://www.nexusmods.com/warhammer40kdarktide/mods/1346). Cached search showed 1.0.3; the direct page showed 1.0.6. The technical document's introduction dates 1.0.6 September 27, while commit/page dates are September 29.

**Source-supported:** [runtime:903](https://github.com/Wobin/Polychromatic/blob/e8cf7cb57de41c6b1d685f4128d744fcbb8094a3/scripts/mods/Polychromatic/Polychromatic.lua#L903) lists eight hashed character-material redirects and `.burnhsv` payloads. At 2327-2372 it uses burn/warpfire `offset_time_duration` with an encoded HSV carrier, positive minimum brightness and daemonhost exclusion. At [2672-2710](https://github.com/Wobin/Polychromatic/blob/e8cf7cb57de41c6b1d685f4128d744fcbb8094a3/scripts/mods/Polychromatic/Polychromatic.lua#L2672) it hooks existing warp-fire effects and writes the unit vector recursively. This is the strongest discovered concrete precedent for a patched character shader reading per-enemy colour. It is not an independent statless surface-RGB API.

**Author-reported:** [technical account:239](https://github.com/Wobin/Polychromatic/blob/e8cf7cb57de41c6b1d685f4128d744fcbb8094a3/docs/how-each-effect-is-coloured.md#L239) separates body glow from particles and reports broad breed coverage excluding daemonhost, gib-cap and small-body-decal limitations, and unsuccessful experiments. It documents native redirects, package residency and shutdown problems; [format note:370](https://github.com/Wobin/Polychromatic/blob/e8cf7cb57de41c6b1d685f4128d744fcbb8094a3/docs/how-each-effect-is-coloured.md#L370) records material format 61 to 62 on September 29. None was reproduced here. Body-glow coverage does not establish weapons/shields, black albedo or compatibility with an independent appearance owner.

### For the Drip and Chromatic Auspex

For the Drip [commit aac01cdf5df01c242b1ac7144ce89c761196978d](https://github.com/Adspartan/For_the_Drip/commit/aac01cdf5df01c242b1ac7144ce89c761196978d), [release v0.12.9](https://github.com/Adspartan/For_the_Drip/releases/tag/v0.12.9), 2025-12-02, contains recursive scalar/vector/texture overrides ([main Lua:37,181](https://github.com/Adspartan/For_the_Drip/blob/aac01cdf5df01c242b1ac7144ce89c761196978d/scripts/mods/for_the_drip/for_the_drip.lua#L37)). Its [README](https://github.com/Adspartan/For_the_Drip/blob/aac01cdf5df01c242b1ac7144ce89c761196978d/README.md) explicitly says only compatible parts/materials respond; leather can determine its own black colour. [gear_customization.lua:302](https://github.com/Adspartan/For_the_Drip/blob/aac01cdf5df01c242b1ac7144ce89c761196978d/scripts/mods/for_the_drip/gear_customization.lua#L302) clones Lua customization data and writes shared slot-named overrides. Lua table copies do not prove GPU instance isolation. The unresolved public [issue #10](https://github.com/Adspartan/For_the_Drip/issues/10) is a reported current-compatibility caution. This is a mechanism reference, not a ready enemy-recolour dependency.

Chromatic Auspex [commit 77bcdc25086c3fc48aba4c31a728b7832e431e9f](https://github.com/Wobin/Chromatic-Auspex/commit/77bcdc25086c3fc48aba4c31a728b7832e431e9f), 2026-08-23, explicitly enumerates body/slots/attachments ([recolour.lua:33](https://github.com/Wobin/Chromatic-Auspex/blob/77bcdc25086c3fc48aba4c31a728b7832e431e9f/scripts/mods/Chromatic%20Auspex/modules/recolour.lua#L33)), writes `emissive_color_intensity`/`emissive_color` and adjusts lights ([124](https://github.com/Wobin/Chromatic-Auspex/blob/77bcdc25086c3fc48aba4c31a728b7832e431e9f/scripts/mods/Chromatic%20Auspex/modules/recolour.lua#L124)). These are verified equipment-emission names; they are not validated universal enemy surface parameters.

### Newly available custom-resource tools

**Custom Assets:** [Nexus 1200](https://www.nexusmods.com/warhammer40kdarktide/mods/1200), first upload 2026-09-30, version 1.0.2 updated October 3, AI Assisted tag. Inspected [patcher revision 90a0aabdbefcd08a10127e2da226ee75d93b886e](https://github.com/fviuff/darktide-mods/commit/90a0aabdbefcd08a10127e2da226ee75d93b886e), 2026-10-03. The [API README](https://github.com/fviuff/darktide-mods/blob/90a0aabdbefcd08a10127e2da226ee75d93b886e/Custom-Assets-patcher/README.md) describes compiled asset manifests, asynchronous acquire/status/release tickets and resource/package resolution. [Native patcher:1712](https://github.com/fviuff/darktide-mods/blob/90a0aabdbefcd08a10127e2da226ee75d93b886e/Custom-Assets-patcher/mods/CustomAssets/tools/native/custom_assets_patcher.cpp#L1712) accepts cooked material/unit/texture/animation/bones/state-machine/particle resources. It is not a runtime Lua shader compiler. Not installed or executed here.

**Darktide Asset Compiler beta:** inspected [revision 8860ddaa869bac353cf6a31e166bf4989f63bcc5](https://github.com/fviuff/Darktide-Asset-Compiler/commit/8860ddaa869bac353cf6a31e166bf4989f63bcc5), 2026-10-03. Its [README](https://github.com/fviuff/Darktide-Asset-Compiler/blob/8860ddaa869bac353cf6a31e166bf4989f63bcc5/README.md) describes PBR assets, copying existing game shader families, skeleton/node attachment and beta rendering/collision limits. The shared `MasterItems.base_unit` example changes every use and fails selected-unit isolation. The Linux instructions are explicitly LLM-derived and untested; that caveat is not proof that its Windows implementation fails.

[material_builder.cpp:698](https://github.com/fviuff/Darktide-Asset-Compiler/blob/8860ddaa869bac353cf6a31e166bf4989f63bcc5/src/compiler/material_builder.cpp#L698) provides stronger implementation evidence: donor cloning, validation of known variable names/dimensions, and private shader-family copies. It does not establish authoring arbitrary new character-shader logic. [material_v61.cpp:53](https://github.com/fviuff/Darktide-Asset-Compiler/blob/8860ddaa869bac353cf6a31e166bf4989f63bcc5/src/stingray/material/material_v61.cpp#L53) accepts version 61/62 edits and parses 60/61/62, while its inherited builder assigns 61 at 194. Verify each output against the installed 1.13 build. [Shader metadata](https://github.com/fviuff/Darktide-Asset-Compiler/blob/8860ddaa869bac353cf6a31e166bf4989f63bcc5/tools/blender/darktide_assets/game_shaders.json) names `color` for unlit and `tint_color` for glass/crystal; these are family-specific, not character-albedo evidence.

**SimpleAssets:** inspected public [revision a4564b7dda7c6fdbd92eb633c1931b1a51a749ae](https://github.com/deluxghost/darktide-mods/commit/a4564b7dda7c6fdbd92eb633c1931b1a51a749ae), 2026-09-29. [Engine-resource API](https://github.com/deluxghost/darktide-mods/blob/a4564b7dda7c6fdbd92eb633c1931b1a51a749ae/SimpleAssets/docs/api/engine-resources.md) loads compatible compiled material/particle/unit/animation resources and returns resource names. Loading is separate from discovering or constructing a suitable body shader. Installed HCM documentation corroborates the consumer/lifetime constraints above. SimpleAssets is absent here.

These tools make a private material or authored shell worth investigating. They do not prove arbitrary RGB, black, skinning/wound support, control isolation or clean native release. Their very recent versions also postdate older community claims that asset tooling did not exist. AI-assisted provenance is neither success evidence nor a reason to reject source-backed mechanisms.

### Additional web coverage and limitations

[Minion Glow](https://www.nexusmods.com/warhammer40kdarktide/mods/870), v1 dated 2026-05-30, describes spawned RGB lights and warns reload can leave lights after death. Its [May 31 author comment](https://www.nexusmods.com/warhammer40kdarktide/mods/870?tab=posts) reports little observable cost on one machine without measured benchmark data. Light illuminates nearby surfaces, cannot paint black, and may affect unselected enemies/environment. [For the Drip Extra](https://www.nexusmods.com/warhammer40kdarktide/mods/306) adds enemy-derived cosmetic attachments with fit/slot warnings; this is asset reuse, not enemy recolouring. [Improved Havoc Tags](https://www.nexusmods.com/warhammer40kdarktide/mods/500) changes UI labels. [Official No Man's Land notes](https://www.playdarktide.com/news/patch-1-10-0-no-mans-land) corroborate gameplay changes in Rotten Armour, so the full mutator is not a visual-only solution.

Historical [Stingray Unit API](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/lua_ref/obj_stingray_Unit.html#set_material) and [material assignment guide](https://help.autodesk.com/cloudhelp/ENU/Stingray-Help/stingray_help/lighting_rendering/shading_and_materials/assign_material.html) distinguish unit-slot assignment from resource-wide changes. They explain concepts, but Darktide's binding/source must establish actual signatures and instance behaviour. An [Autodesk 2017 correction](https://forums.autodesk.com/t5/stingray-forum-read-only/how-to-change-material-color-using-lua/td-p/7533628) demonstrates why vector dimensions matter in that engine; it does not validate a Darktide enemy parameter.

Searches covered GitHub code/issues, Nexus descriptions/version information/comments, modding guides, Reddit, Fatshark discussions and engine references. Some GitHub/Nexus web opens failed; public GitHub raw/API reads succeeded. A direct Nexus request was Cloudflare-blocked, while the web tool could read useful pages and Minion Glow comments; Nexus comment search requires login. No complete sweep of authenticated comments or Discord messages is claimed. No download/install was performed. These access limitations cannot rule out a technique.

## Discord research coverage

### Access routes and outcomes

| Route attempted on 2026-10-03 | Actual outcome |
| --- | --- |
| Public web searches for exact symbols, channel names, shader/material/tint/full-body terms and archives | Found public implementation links and secondary Discord references. No authenticated message search or useful public message archive was established. Search non-results are coverage limits. |
| Available/deferred tool inspection and Plugin Management search for `Discord` | No Discord read/search tool was exposed; directory search returned an unrelated Vercel plugin. This is not a claim that no Discord integration exists anywhere. No integration was installed. |
| Supported Browser skill, target `https://discord.com/channels/@me`, documented connection troubleshooting and browser discovery | Runtime returned `No browser is available`; discovery returned an empty list. No signed-in UI session or native server search was accessible. |
| Public invitation and For the Drip Discord permalink through web tool | Tool reported URLs inaccessible. Public references establish leads, not message content or current membership/channel visibility. |
| Supported API feasibility | Official docs checked before considering requests. No supplied bot/OAuth credentials or authorized integration was found; presence-only checks for `DISCORD_BOT_TOKEN`, `DISCORD_OAUTH_TOKEN`, `DISCORD_CLIENT_ID` were false. No protected message API was requested. No personal tokens, browser session stores or self-bot routes were inspected. |
| Approved OAuth2/local RPC | No existing approved integration was exposed. A Discord desktop installation would not itself establish an authorized message-reader API. |
| User-provided material | Only the research text is attached. No screenshot, excerpts, attachments, export or directly readable message content was supplied. |

The public guild-ID lead is **1048312349867646996**, supported by the mod author's [HUD Studio comments dated 2026-09-08](https://www.nexusmods.com/warhammer40kdarktide/mods/1263?tab=posts), which link the server and channel and give an invitation. This does not establish IDs for the channels in the brief. Current names/access for `#making-mods`, `#reverse-engineering-bundles`, `#dmf`, `#creation-showcase`, `#mod-requests`, `#mod-bugs`, `#using-mods` and the Realms Server thread could not be confirmed. Public sources use both creation-showcase and creation-showcases; preserve that uncertainty.

### Supported API prerequisites, verified from current official references

An existing authorized bot must be installed with channel access; `VIEW_CHANNEL` and `READ_MESSAGE_HISTORY` matter. Message content availability is also governed by `MESSAGE_CONTENT`. [Permissions](https://docs.discord.com/developers/topics/permissions), [authentication](https://docs.discord.com/developers/reference#authentication).

The [Message Resource](https://docs.discord.com/developers/resources/message#search-guild-messages) now documents `GET /guilds/{guild.id}/messages/search`, `GET /channels/{channel.id}/messages`, and `GET /channels/{channel.id}/messages/{message.id}`. Search requires history permission and is restricted by message-content intent; history requires channel visibility and returns nothing without history permission. Single-message reads require both. Search is bounded to 25 results, history to 100. Search may return 202 while indexing; retry as instructed, not as an empty result. Search results no longer include surrounding context, so fetch relevant replies/history separately. No anonymous history access is implied.

The `guilds` OAuth2 scope supplies basic guild information. `messages.read` is a local-RPC scope, not blanket REST history authorization; approved RPC integration is a separate prerequisite. [OAuth2 scopes](https://docs.discord.com/developers/topics/oauth2). For future authorized reads, use small targeted pages and obey bucket headers and 429 retry instructions. [Rate limits](https://docs.discord.com/developers/topics/rate-limits). Normal-user-token automation is outside the permitted bot/OAuth route. [Self-bot guidance](https://support.discord.com/hc/en-us/articles/115002192352-Automated-User-Accounts-Self-Bots).

### Search coverage and secondary leads

Public discovery used the brief's five exact symbols (`stimmed_color`, `Unit.set_vector3_for_materials`, `override_slot`, `minion_visual_loadout_extension`, `mutator_minion_visual_override`) and variations of recolor/recolour, material, shader, full body, emissive, armour, attachments, Havoc, stim and AI-assisted tools. Public hits spanned 2023-2026; no completeness or date-range sweep is claimed. **Direct Discord coverage: zero messages, zero channels, no searchable date range.** None of the proposed `in:` queries was executed inside Discord.

| Lead and date | Content status and corroboration | Next input |
| --- | --- | --- |
| For the Drip support [message lead](https://discord.com/channels/1048312349867646996/1048318548180738118/1163114688540848169) linked by its public repository | Message inaccessible; no channel name, discussion date or claim extracted from the message. Public implementation is independently readable. | Support-thread excerpts about current enemy/cosmetic material overrides and latest corrections. |
| [For the Drip issue #10](https://github.com/Adspartan/For_the_Drip/issues/10), opened 2026-04-04 by Backup158 | Direct public bug report says colours/masks preview/save but do not persist after Beyond the Hive; mentions buried Discord reports. Open with no visible resolution when inspected. Does not prove every fork/current build is broken. | Latest Discord resolution, actual fixed revision and reproducible body-material sample. |
| [Extracted Models discussion](https://www.reddit.com/r/DarkTide/comments/1lvjnpi/), 2025-07-09 | Secondary participant points to reverse-engineering-bundles and reports no model-extraction tool at that time. Historical lead, not evidence about current compiler capability. | Latest bundle/shader extraction pins, attachments and exact version. |
| [Extended Weapon Customization discussion](https://www.reddit.com/r/DarkTide/comments/1p8efd3/extended_weapon_customization/), 2025-11-27 | Secondary channel link `.../1168063453416669284`; replies disagree about authorship/rewrite status. No enemy recolour result established. | Relevant attachment/material discussion plus latest correction, not unrelated support chatter. |

Smallest useful future input: one or two message permalinks **plus copied surrounding technical replies and the latest correction**, or an already-authorized export containing a known successful material/shader example. A link alone may still require membership.

For a future authorized native search, verify current names first, then separately run `in:making-mods stimmed_color`, `in:making-mods Unit.set_vector3_for_materials`, `in:reverse-engineering-bundles shader`, `in:dmf material`, `in:creation-showcase recolor`, `in:making-mods tint has:file`, and `in:making-mods material has:link`. Repeat for override/loadout symbols, masks, LOD, failed attempts and the named compiler/Polychromatic tools. Search all available history first, then narrow to recent 1.13 material-format changes; review pins, thread replies and newest corrections. These are **planned queries**, not completed coverage. [Native search documentation](https://support.discord.com/hc/en-us/articles/115000468588-How-to-Use-Search-on-Discord).

## Candidate comparison

All coverage entries concern **unverified enemy rendering**, unless explicitly described as source addressing or author-reported glow. Costs are estimates.

| Method | Lua/API and resources | Colour / black | Body and equipment | Isolation, texture/lighting, cost |
| --- | --- | --- | --- | --- |
| Known `stimmed_color` write | Ordinary Lua setter; existing enemy materials | Arbitrary input RGB; zero is neutral, black surface unproved | Recursive address path; shader/mask/equipment compatibility unknown | Selected unit possible; test shared assets. Existing textures remain assigned; exact blend unknown. Low event-driven cost. |
| Discovered surface parameter | Override-table helper or exact known vector/scalar setter; inspect MasterItems/shader first | Arbitrary RGB only if actual shader supports it; best stock black candidate | Per compatible material/part, all parts not established | Must prove instance isolation and restoration. Can preserve texture/lighting if shader supports tint. Low to moderate mapping/maintenance cost. |
| Existing material/texture replacement | `Unit.set_material`, texture setters; loaded compatible resources and original mappings | Predefined resource, or parameterized donor; black depends on donor | Must enumerate named body/equipment material slots | Targeted assignment plausible; shared-variable isolation unknown. Can alter textures/lighting/wounds. Moderate cost and compatibility work. |
| Private compiled donor material / shader patch | Native loader/patcher and private compatible compiled family; ordinary Lua assigns/writes after loading | Existing validated variables; arbitrary new albedo branch still hypothesis | Parent-family/LOD/equipment mappings required | Private resource or neutral-gated per-unit path needed. Best advanced surface route; high maintenance and native/GPU uncertainty. |
| Rotten/pre-existing loadout variant | Existing item packages and loadout helper; public override RPC reconstructs predefined template | Fixed authored appearance | Some upper/lowerbody/armour slots; breed-specific, not universal | Select a unit without activating full mutator. Rebuild/restoration/hotjoin complexity; textures changed. Moderate to high. |
| Stock outline | Local isolated outline settings, existing minion layers | RGB outline; black may be invisible, not black surface | Source traverses eligible slots/attachments, including representative shields | Per unit; textures remain below highlight. Marking/priority/culling conflicts. Low Lua setup, extra rendering passes. |
| Filled silhouette | Existing player mesh/depth layers as lead | Possible layer RGB; no enemy support proven | Projected mesh, equipment coverage unknown | Not surface recolour or preserved lighting. Layer and depth compatibility gate. Moderate uncertainty. |
| Ailment / Polychromatic body glow | Existing Ailment variables/masks; Poly adds native shader redirects | Added glow, quantized HSV; not black albedo | Author reports many breeds; gibs/decal limits; weapons/shields unproved | Per-unit carrier exists but competes with burns. Not independent statless feature as shipped. Moderate to high. |
| Emission parameters | Verified only on compatible equipment/emissive shader families | RGB glow; zero removes glow | No universal enemy-material support | Selected unit/attachments possible; does not darken base textures. Low if compatible. |
| Surface particles / point lights | Existing particle APIs or spawned lights/resources | Particle/light palettes; not black paint | Aura/surface particles can surround geometry; not recoloured skin | Lights can affect unselected surroundings. Per-enemy native objects and overdraw; medium to high horde cost. |
| Wounds / decals | Wound palette parameters or projection APIs/resources | Fixed palette/local mark; arbitrary RGB unproved | Local regions/projection, not whole articulated body | Damage-system interference and difficult decal ownership. Low rank. |
| Attached shell / replacement mesh | Authored rigged unit, node link, native resource readiness | Depends on authored material, RGB/black conceivable | Fit/animation/armour/equipment/LOD/ragdoll all need work | Selected attachment possible; changes or overlays textures/silhouette. High asset and overdraw/maintenance cost. |
| Custom stencil/post-process | Only outline secondary passes established | No general per-enemy API demonstrated | Screen-space selection mask missing | Global filters fail unchanged controls; native/shader work prerequisite. High uncertainty. |

## Dead ends, limits and unanswered questions

- Adding stim/enrage/Rotten Armour buffs or enabling the whole mutator to obtain visuals fails the no-gameplay-change requirement; full mutators can also select ambient enemies.
- UI/name colours, rarity colours and Havoc tag labels do not establish model recolouring.
- Changing a shared template colour, shared MasterItems item or stock material resource can change every matching unit. Selection must be carried separately and tested with identical controls.
- `pcall` success is not a shader-capability or visible-result test; arbitrary native material/particle names can still be unsafe.
- `true` recursion already exists. Explicit slot traversal is a diagnostic, not a guaranteed mask fix.
- The variable's zero reset does not establish a black surface option. Negative/HDR values are not a supported dark-colour workaround without shader evidence.
- The private loadout rebuild has no general inverse; public override-name RPCs do not carry custom item contents. Do not assume stock latejoin handles arbitrary overrides.
- A method named local does not prove no replication. New keys added to sorted lookups can renumber buff/breed/effect/override/outline IDs (`S/network_lookup/network_lookup.lua:85-106,161,172,197,277`). Pure local descriptor/settings data must not enter those RPCs.
- Shader assets/material metadata, exact friend effect, actual per-material masks, material-instance ownership, full restoration/defaults and all-LOD coverage are the largest missing evidence.
- Effects after death, detachment/dismemberment, unit-ID reuse and any pooling were not validated. No generic minion pooling contract was established; clear state on destruction and test reuse instead of assuming it exists or cannot occur.
- Native/asset outputs need exact installed-build checks; the source version, old cosmetic releases and new compiled materials are different evidence snapshots.

The next step and complete validation/ownership requirements are in [experiments-and-recommendation.md](experiments-and-recommendation.md). No in-game success, benchmark or offline-stub rendering proof is claimed.

## Snapshot ledger and verification

SHA-256 identifies inspected local bytes where Git cannot identify installed or dirty files. The source checkout stayed clean at the pinned revision. Relevant G/ runtime and installed appearance files were rechecked by the read-only investigators without hash changes. The coordinating session advanced project HEAD from `4cc68670ee03d1ee02ff11bd19eb8cfca96563af` through `5eacc3ebb2cb5dfba03fa73e312f9abe0ff703c0` to closing revision **`661d28c030a41557bcf8a52a96231d208c85ce50`** (2026-10-03). The four runtime files independently rechecked at closing still match their ledger hashes. These research citations therefore identify inspected working bytes, with no branch/commit activity performed by this task.

Shared docs were actively changing in the other session. `docs/07-learnings-and-gaps.md` moved from `5ec523d1765817778abcf09036281b00f3a26d9f8c00630dd89a4bedbedf5a3c`, through `9dfba3edea7b094d23e9b7a7ccfd760bd9208bca156c7a0d99da89f0d7b1b48b`, to `52b9923b8abd3e47eff93333f2f94faf399d0b1174886b0f9e3a9d19d01aec57`. Docs index, 05 and 06 also changed before closing. Historical-doc citations refer to the initial inspected snapshots; technical findings were verified against the stable source/implementation bytes instead of attributing all docs to one revision. Doc 03, doc 04, CLAUDE.md and root README hashes matched their inspected snapshots at closing. This task did not edit any shared document.

| Local file (prefixes above) | Inspected SHA-256 |
| --- | --- |
| G/ `scripts/mods/RealmsWaves/RealmsWaves.lua` | `f6a7f3f6655e0379a00f4742348a91e6024a8dd17e68a738a43f8863200be8e0` |
| G/ `scripts/mods/RealmsWaves/spawn/execute.lua` | `d6f57efcd1ace7c28f15387c26d43e4f2753280aa2fb4d6e7d9af56d70597fd5` |
| G/ `scripts/mods/RealmsWaves/spawn/tuning.lua` | `d8bde72962e18791c33860f9cb32340ed50c931bc0d3d72be2fe239c7d38fb7d` |
| G/ `scripts/mods/RealmsWaves/core/protocol.lua` | `5fd9d5ec05dcc6d616e6b032517ab093812a792c8613c5a19c0f6e12cae1892b` |
| G/ `scripts/mods/RealmsWaves/catalog/groups.lua` | `8730081e5e6f4daf81d33ccb0f514b2df6f0222a700a190b6f06b485e84b1379` |
| G/ `scripts/mods/RealmsWaves/catalog/colors.lua` | `4a33dc6176dacc1767a64c978af5a5f79081468428715a773a3b063d0ffcc24f` |
| S/ `extension_systems/visual_loadout/minion_visual_loadout_extension.lua` | `7f3e33464c55561ad91a0d0441d8a015716b54be5c7d48c16e8ea08bf9c99d41` |
| S/ `extension_systems/visual_loadout/utilities/visual_loadout_customization.lua` | `17d88a1ac8ea54ffed2d8c3ce1f3082b5603f4edc0d4fec3a03083fb8617dd2b` |
| S/ `extension_systems/buff/minion_buff_extension.lua` | `2aa74308e72e652e0edb8dfda31cfdcc217212307f44a5bf39f06d3e9fa9c33c` |
| S/ `settings/buff/havoc_buff_templates.lua` | `4ffa7786a203db0ffabad2e4ce8bdfd63d3c1b60612b27b3fed17f1ad369bd2a` |
| S/ `extension_systems/outline/outline_system.lua` | `73bd06a82a1b5046e5be9745d9eb84c374b01df05e8f1a86ed5431b3f2891506` |
| M/ `SoloPlayPurpleStimms/scripts/mods/SoloPlayPurpleStimms/cosmetics.lua` | `50e1ae4c0c8562763b486002608183664559ccc529308c6e1bc8e4ae70d0e89c` |
| M/ VersusMode main Lua | `258245a48dc7c09d53adc99d3e9fb31b20c5f60f914c8449200937920197dd96` |
| M/ transonic_stance_colors main Lua | `57f048b05e0a22dd6a459b87c819c8096206418f155fe59abbf52de7321c7b67` |
| M/ Realms `workarounds/private_outlines.lua` | `25c97eee2e7c1cf9834be0f8cb5bf2876c40a9d3f4cdb2df64b2b8fb6f62437f` |
| M/ danger_zone main Lua | `e4e696c2edf702a9379cb351f3affc545c18e8e9a8805e255c2b2ec313761e87` |
| M/ TraumaOutlines main Lua | `54775dfc8a712e1be2d3c48f9d8b8157de8bf107ed78a570ae992e71705aee42` |
| M/ HCM `docs/diy/ASSETS.en.md` | `f9daba160c7fb00b540d7a933f22a8f8762b08578c8583833dd4b6147fb1ed80` |
| G/ existing `docs/research/enemy-appearance/research-prompt.md` | `e4cdfbabc58d9261e37d577323ff4bb330a2979dc4615b40946d3b3d5d2b188c` |

Verification on 2026-10-03: `python tools/check_docs.py` passed (25 Markdown files, zero over the 100 KB limit). Both report links and explicit local source citation paths were checked; fenced examples are balanced. The existing research prompt retains the ledger hash. Only the two reports were written by this investigation. Offline Lua tests were not used as a proxy for visible shader results; no runtime code changed in this task.
