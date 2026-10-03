# Selected-enemy appearance: experiments and recommendation

Date: **2026-10-03**, America/Sao_Paulo. Companion evidence, versions, exact source citations and access limits: [findings.md](findings.md). Preserve the reusable [research prompt](research-prompt.md).

**All plans and snippets below are unexecuted.** This research did not change runtime code, installed mods, dependencies, shared documentation, branches or game state. The coordinating session should prepare a separate reversible experiment after reviewing these gates. Static source inspection and offline stubs cannot establish visible success.

## Recommendation

**Full-body surface recolouring remains unproven**, especially for black, mixed armour/clothing, shields, weapons, LODs and detached parts. The smallest credible investigation is an exact known `stimmed_color` write on one fresh enemy beside an identical untreated control, followed by explicit body-slot writes. This tests whether the limitation is application/traversal/timing before investing in material or shader work.

For the preferred surface-colour outcome, prioritize **actual enemy material metadata and compatible per-unit overrides**. The stock helper accepts a local override table; there is no need to register a new buff, breed or item name just to describe a visual parameter. If it yields only partial support, map supported body/equipment materials explicitly. If no compatible stock surface parameter exists, move to private compiled material resources or character shader patches, with control isolation and installed-build compatibility proven first.

| Rank | Action | Reason and decision gate |
| --- | --- | --- |
| 1: immediate diagnostic | E1: known material setter versus explicit slots | Minimal code, no new assets or gameplay buffs. A decisive coverage comparison; success is not assumed. |
| 2: preferred stock route | E2: inspect actual material override data, then vary a verified surface parameter | Best chance of preserving textures/lighting and supporting dark colour with ordinary Lua. Requires known key/type/default and every required material's support. |
| 3: preferred advanced route | E3/E6: compatible material replacement or private compiled donor/character patch | Concrete assignment and asset-loading paths exist. New albedo logic, skinning/wounds, version compatibility and restoration remain gates. |
| Fallback A | E4: selected-unit outline using isolated local settings | Strong existing selection mechanism with no stat change. An outline identifies an enemy; it does not recolour its surface. |
| Fallback B | E5: visual-only ailment/body glow or compatible emission | Public body-shader work is stronger than speculation; still glow, with masks/ailment conflicts and black limitations. |
| Last alternatives | E7: authored variant or rigged overlay shell | Useful for a predefined unusual appearance; extra resource/fit/rebuild costs and weaker texture preservation. |

Do not make the first prototype a shared buff-template patch, shared MasterItems replacement, full mutator activation, global ReShade tint, forced layer loop or per-frame all-enemy material scan. Each adds scope or breaks a stated requirement before the basic rendering question has been answered.

## Common setup and acceptance criteria

Use an approved **offline Realms mission or supported training setup** with loaded minion packages; regular hub spawning is not automatically safe. `BreedLoader` loads all breeds for missions but only player/companion breeds for hubs (`S/loading/loaders/breed_loader.lua:23-46`). The coordinating agent chooses the existing spawn/test facility; this report does not install or run one.

Keep three labelled enemies when useful:

- **A, treated:** fresh enemy receiving only the proposed visual operations.
- **B, control:** same breed, matching seeded/item loadout and material assets, no appearance operations or modifiers.
- **C, positive visual baseline:** an independently confirmed stock effect/material example. If using a stock stim buff, its gameplay effects are expected on C only; C is not the stat control for A.

Confirm C in the actual installed game before calling it a known working baseline. Source-backed examples are expected baselines, not newly verified results. If visual randomness prevents exact A/B matching, record item names and material variants and respawn until matching or explicitly qualify the result.

Record patch/build, project revision/hash, enabled mods and their versions, host/client role, unit ID and breed, seed/item names, body/slot/attachment identities, parameter/type/value, operation order, ready time and competing effects. For material experiments, record cache version and authored resource/default mappings. Log Lua calls separately from visible pixel observations.

Capture front/back and side views with head, torso, upper/lower arms, thighs/shins/feet, armour, clothing, weapon, shield and small attachments individually scored. Use identical camera/lighting/exposure; include untreated B in frames where possible. Capture near, medium and far distance, then return near. Do not count a torso cloud or luminous eyes as coloured legs.

Preferred success requires all of the following:

1. Desired surface colour on every required body/equipment component, or a clear accepted scope limitation.
2. B and unrelated enemies remain visually unchanged, including those sharing the same resource.
3. Textures and lighting remain acceptable; saturated RGB, dark brown/blue and **black** are tested independently.
4. A's buffs, keywords, stat buffs, health/max health, toughness where relevant, movement, hit mass and attack/damage behaviour match B before/after. The prototype adds no buff, keyword, AI event or stat mutation.
5. Removal restores the actual prior appearance, including active vanilla effects. Death/despawn/mission/reload/disable leave no leaked objects or stale selection.
6. Intended peers see the same selected appearance; absent/older clients retain normal gameplay and safe vanilla visuals.

For gameplay checks, control difficulty, target health, weapons and attack conditions. Compare deterministic damage samples where available and inspect the buff/stat state as stronger evidence than visual impression alone. Do not claim unchanged gameplay solely because the prototype avoids an obvious buff call; material/mesh replacements must also leave collision, hit zones, navigation, interaction and AI unchanged.

## E1: distinguish particles, traversal and material coverage

**Entry point:** after the selected minion's visual loadout has completed `MinionVisualLoadoutExtension.extensions_ready` (`S/extension_systems/visual_loadout/minion_visual_loadout_extension.lua:137-163`). Existing spawn-return is useful for ownership, but the experiment must also observe actual slot readiness/replacement.

**Prerequisites:** A/B matched fresh enemies; known neutral `stimmed_color` baseline; no stims, Enraged, bolstering, corruption, ailment or another colour-writing mod on A/B. Confirm whole unit and equipment are present. Source baseline: purple material-vector application (`mutator_buff_templates.lua:441-445`) and minion setter (`minion_buff_extension.lua:486-511`).

Minimal actual API call, **not executed**:

```lua
-- Run only on a chosen live, ready, fresh rendering unit.
-- No buff is added. Source-supported variable; coverage is the question.
Unit.set_vector3_for_materials(target, "stimmed_color", Vector3(0, 1, 1), true)
```

Perform independent stages, resetting A between them on the known neutral baseline:

1. Root write with child traversal **false**, then capture coverage.
2. Root write with traversal **true**, then capture coverage.
3. Explicit write to each live body/slot/attachment unit, labelled by slot. Start with lowerbody alone before applying broadly so its contribution is distinguishable.
4. Compare against C's exact stock effect. Identify whether particles, eye glow, skin/clothing response or all of them account for the reported upper-body look.
5. Repeat once after an actual observed slot rebuild or later attachment creation; do not replace equipment simply to make a preferred result appear.

Illustrative traversal, **unexecuted diagnostic pseudocode using source-supported accessors**:

```lua
local vle = ScriptUnit.has_extension(target, "visual_loadout_system")
local seen = {}
local function write_existing_unit(u)
    if u and Unit.alive(u) and not seen[u] then
        seen[u] = true
        Unit.set_vector3_for_materials(u, "stimmed_color", Vector3(0, 1, 1), true)
    end
end
write_existing_unit(target)
if vle then
    for slot_name in pairs(vle:inventory_slots()) do
        local item_unit, attachments = vle:slot_unit(slot_name)
        -- Log slot_name + identities before writing; capture each slot separately.
        write_existing_unit(item_unit)
        for _, attachment_unit in ipairs(attachments or {}) do
            write_existing_unit(attachment_unit)
        end
    end
end
```

This repeats some descendant writes intentionally to compare explicit slot addressing with the parent path. It is not a proposed production update loop. Root recursion may already reach every item; neither a second write nor `pcall` success is evidence of added coverage.

**Expected observations and failure criteria:**

| Observation | Interpretation / next step |
| --- | --- |
| No body response; C only shows clouds/eyes | Report may concern particles, or A's materials do not support the known vector. Re-identify exact effect; no full-body success. |
| False reaches torso, true reaches all required parts | Child traversal matters in this case. Stock material-vector path already uses true; compare the friend's actual application. |
| True misses lowerbody/equipment, explicit slot write works | Hierarchy/readiness/application issue is plausible. Establish why that slot was not reached before integrating. |
| True and explicit writes have identical partial coverage | Repeating traversal is not solving it. Prioritize shader/material support or mask evidence in E2/E6. |
| Colour disappears after a buff/slot/LOD event | Competing writer or replacement is implicated; log order/identities and test E8 ownership. |
| B changes | Isolation failure. Stop; do not advertise per-enemy support. |

**Cleanup:** only on fresh zero-baseline A, write `Vector3(0,0,0)` to the root and all still-live touched units, including any separately tracked detached equipment. Verify baseline screenshots. In a mixed-effect test, restore the recorded owner/default policy instead of blindly zeroing. Remove disposable test units using the test facility's own server-authoritative destruction, not an invented raw world deletion; end the mission if restoration cannot be established.

**Evidence needed:** coverage grid and screenshots for each stage; slot/hierarchy IDs and timing; parameter writes; A/B buff/stat snapshots. Black must be logged as a separate negative/unknown result if zero simply disables tint.

## E2: discover and test a genuine surface-colour parameter

**Entry point:** read the live selected minion's `slot_items()` / `slot_item(slot)` and `slot_material_override_items(slot)` after readiness (`minion_visual_loadout_extension.lua:701-713,872-880`). Read only selected records and referenced material overrides from `MasterItems.get_cached()`; record `get_cached_version()` and relevant metadata (`S/backend/master_items.lua:446-461`).

**Prerequisites:** no guessed colour variable; known property name, vector/scalar dimension and original/default values from actual metadata or shader. A positive baseline should be the existing compatible skin/clothing override on the same family, rather than unrelated weapon emission. Compare `chaos_skin_color_01/02/03` and the selected upper/lowerbody authored variants where available. Log only relevant rendering data, not unrelated backend/account information.

**Read-only inventory first:** capture item identifiers, `material_override_items`, `vector*_material_overrides`, scalar/texture/material replacements, `material_override_apply_to_parent`, attachment references and cache revision. Determine which operation reaches root/body versus item units. An item named colour can still use a fixed resource rather than an RGB uniform.

**Conditional, unexecuted snippet:** `DISCOVERED_KEY` is a placeholder requiring evidence, not an API parameter claimed by this report.

```lua
local V = require("scripts/extension_systems/visual_loadout/utilities/visual_loadout_customization")
local MasterItems = require("scripts/backend/master_items")
local override = {
    vector3_material_overrides = {
        { property_name = DISCOVERED_KEY, value = {r, g, b} }
    }
}
V.apply_material_override_item(
    known_compatible_body_unit, known_compatible_body_unit, false,
    override, false, MasterItems.get_cached()
)
```

The helper accepts tables (`visual_loadout_customization.lua:25-46,235-240`) and applies validated schema operations (`:541-609`). Choose the actual property's dimension; vector4 schema ordering differs, so do not reuse this vector3 example blindly. First test one compatible material/body unit; then extend to all required materials and equipment with a documented support map.

**Expected result:** hue changes the underlying surface and follows normal light/shadow, with existing texture detail visible. Dark/black reduces base reflectance if the parameter is a genuine surface multiplier/blend; it need not eliminate specular reflections. **Failure:** emission-only change, fixed-palette limitation, masked areas, B changing, wrong vector type, unsupported materials or no visible response. Record limited success by material; do not infer universal support.

**Cleanup:** reapply captured authored values/overrides for each unit and verify vanilla effects still work. No generic engine parameter getter was established; if original values cannot be determined, do not mutate persistent units. Use matched disposable A/B units for the gated proof and end their lifecycle cleanly. Capturing only an override-item list may omit base-material defaults, so document that gap.

## E3: replace a compatible material or texture on one enemy

**Entry point:** one known body/attachment unit and exact material slot, after package/asset readiness. Source APIs: `Unit.set_material(u, material_slot, resource)` and `Unit.set_texture_for_material(u, material_slot, texture_slot, resource)` (`visual_loadout_customization.lua:585-609`).

**Prerequisites:** known working donor resource on the installed build, appropriate skinning/wound/LOD/permutation support, original slot-to-resource and texture mappings, retained load handles. A neutral donor is the positive baseline. Prefer private compiled copies if changing material properties could be shared. Do not assign a material from one arbitrary handle to every enemy.

**Unexecuted pseudocode:**

```lua
-- Resource/slot names must come from inspected authored data.
-- ASSET_READY and original_slot_mapping are experimental prerequisites.
if ASSET_READY and original_slot_mapping then
    Unit.set_material(selected_body_unit, KNOWN_SLOT, PRIVATE_COMPATIBLE_RESOURCE)
end
-- Restore the exact original resource before releasing ownership/load tickets.
```

No invented readiness API is implied by `ASSET_READY`; use the chosen loader's verified contract. `Application.can_get_resource` alone is not package readiness. Apply named material assignments separately to each necessary unit; the source `set_material` call has no recursive argument.

**Expected result:** A alone changes; black/coloured donor renders consistently across supported body pieces and distances. **Failure:** B changes, checker/missing resource, broken normals/skinning/wounds, invisible LOD, crash, or gameplay mesh/hit-zone change. Replacing a texture can require a particular channel, UV layout or mask and may not preserve detail; log the exact change.

**Cleanup:** restore original material/texture mappings to all surviving touched units; wait until native objects no longer reference the custom resource before releasing its ownership according to the loader. Resource release may not free all native memory; restart/end mission when required by the provider. If original resource names are unavailable, do not promise a reversible live swap.

## E4: targeted outline, with a separate fill investigation

**Entry point:** a live rendering minion with `outline_system` extension. Source-supported public calls are `OutlineSystem:add_outline(unit,name)` and `remove_outline(unit,name)` (`S/extension_systems/outline/outline_system.lua:190-274`). Normal adds/removes are local in the inspected implementation; peer visibility requires local application on each peer.

**Prerequisites:** A/B controls, isolated settings map and nested colour table, unique local ownership name, no insertion into `NetworkLookup`, recorded old settings identity. Positive baseline: a normal game minion tag outline observed in game. Lower numerical priority wins; choose/test priority rather than overpowering existing tags by default.

**Unexecuted illustration:**

```lua
local outlines = Managers.state.extension:system("outline_system")
local ext = ScriptUnit.has_extension(target, "outline_system")
-- Require a ready MinionOutlineExtension and a live rendering target.
local old_settings = ext.settings
local own_settings = {}
for key, value in pairs(old_settings) do own_settings[key] = value end
own_settings.rw_research = {
    priority = 2,
    material_layers = {"minion_outline", "minion_outline_reversed_depth"},
    color = {r, g, b},
    visibility_check = function(u) return HEALTH_ALIVE[u] end
}
ext.settings = own_settings
outlines:add_outline(target, "rw_research") -- exactly once per owner

-- Cleanup while ext/target/system are still valid:
outlines:remove_outline(target, "rw_research") -- balance only our add
if ext.settings == own_settings then ext.settings = old_settings end
```

This explicit map copy avoids assuming that cloning arbitrary metatable-bearing tables is safe after game updates. Shared stock entries are read-only; the owned setting/colour are new tables. Production must guard absent/dead/retired systems and concurrent settings owners; this illustration is not a complete lifecycle implementation.

**Expected result:** only A gets a coloured outline across visible body and `use_outline` equipment. Verify shields/weapons/attachments. **Failure:** B changes, force-enabled layers linger, tags/abilities disappear, unexpected through-wall behaviour, culling changes persist, or spectator switching shows another player's contextual highlight.

**Cleanup:** balance exactly the owned stack; restore settings only while still owned. Do not call `remove_all_outlines`. Prefer system ownership over raw layer forcing; if raw layer forcing is used for diagnosis, capture and explicitly restore every forced layer/culling state.

**Optional separate fill gate:** inspect/test the player `default_mesh_always` / `player_outline_general_depth` path on a disposable minion only after confirming compatible material layers/resources. Source establishes player mesh modes, not enemy fill. Record visible/obscured behaviour separately; label any success **silhouette fill**, including lost texture/lighting detail, not surface recolour.

## E5: statless ailment visuals or emissive fallback

**Entry point:** the existing visual-only `Ailment` helper and selected compatible materials (`S/utilities/ailment.lua:9-33`), or a verified existing emissive part. Source positive baselines are stock warpfire visuals and the explicitly supported equipment glow path; confirm them live first.

**Prerequisites:** capture/restore effect textures, permutations and timing; know the helper's current signature and ailment settings. Do not add `warp_fire`, burning or stim buffs merely for colour. Avoid guessed particle material names. A must have no damage ticks, altered health or new keywords.

**Unexecuted pseudocode:**

```text
resolve the selected unit's supported ailment visual definition
record textures/permutations/timing and active vanilla visual owner
invoke only the existing visual path with a bounded duration
capture body/equipment coverage; compare against untouched B
restore original visual state without removing actual gameplay ailments
```

Polychromatic's [pinned runtime](https://github.com/Wobin/Polychromatic/blob/e8cf7cb57de41c6b1d685f4128d744fcbb8094a3/scripts/mods/Polychromatic/Polychromatic.lua#L2672) proves a per-unit encoded burn-colour carrier with native redirects. Its current hooks and positive brightness encoding should not be copied as an independent paint feature. An adaptation needs an independent channel or explicit coexistence rules with genuine burn updates.

**Expected result:** a defined glow/overlay if acceptable. **Failure:** new gameplay buffs/damage, mask-limited regions presented as full body, dark colour simply removing glow, lingering effect or overwritten real burns. **Cleanup:** exact prior texture/permutation/timing state and all owned particles/lights restored/destroyed. This is more complicated than the E1 zero-baseline reset; if reset cannot be proved, do not integrate it.

## E6: privately copied character materials or patched shaders

**Entry point:** a separate offline asset investigation after E2 identifies the relevant enemy shader families/masks and installed material format. Positive baseline: a compatible unmodified donor copy on A looks identical to B. No tool installation, compilation or asset patching occurred in this research.

**Prerequisites and gates:**

1. Verify the chosen tool/output against the installed 1.13 package, including material format 62 and shader permutations. The compiler's inherited material version is a concrete compatibility check, not automatic failure.
2. Identify parent materials for skin, cloth, armour, weapons, shields, gibs and LODs. A change to one character family cannot guarantee equipment coverage.
3. Create a **private** resource family with known dependencies/residency, or a precisely neutral-gated per-unit branch if intentionally patching shared shaders. Default unselected state must render identically to stock.
4. Establish a verified base-colour operation and independent selection/RGB carrier. Donor-variable editing/copying is supported by the compiler source; arbitrary new character-albedo shader logic is still a separate research hypothesis.
5. Preserve skinning, normal/roughness/metallic channels, wounds, opacity, dismemberment and collision/AI behaviour. Do not mutate shared MasterItems entries or replace physics/actors as a shortcut.
6. Prove A/B isolation, black and exact restoration before horde/multiplayer work.

**Unexecuted rendering design pseudocode, not a claimed existing shader API:**

```text
stock surface = original character shader's base-colour result
selected surface = documented blend/multiply(stock surface, requested RGB)
selection = independently verified per-unit input, default off
use stock surface when selection is off
retain original normals, lighting, roughness, wounds and non-colour behaviour
```

The [compiler implementation](https://github.com/fviuff/Darktide-Asset-Compiler/blob/8860ddaa869bac353cf6a31e166bf4989f63bcc5/src/compiler/material_builder.cpp#L698) validates existing variable names/dimensions and privately copies donor families. The [Custom Assets loader contract](https://github.com/fviuff/darktide-mods/blob/90a0aabdbefcd08a10127e2da226ee75d93b886e/Custom-Assets-patcher/README.md) supplies acquisition/readiness/release tickets. These are concrete building blocks, not proof that the proposed shader branch already exists.

**Expected result:** actual surface recolour on mapped materials, with off/default state exactly stock and no glow-only substitution. **Failure:** unsupported donor variables, wrong resource version/permutation, global control changes, missing equipment, black merely disabling emission, wrong LOD/rig/wounds or inability to restore/release. Record the smallest failing material rather than widening the patch blindly.

**Cleanup:** restore unit assignments/carriers before destroying owned objects/releasing tickets; restore patched resources through the tool's documented mechanism and restart where native residency requires it. Never infer generic hot-reload safety from Lua reset. Record native/GPU memory before/after and process restart requirements. If release is process-lifetime only, say so explicitly.

## E7: authored variants or a visual shell

**Variant entry:** existing loaded Rotten Armour or another suitable authored item variant on supported breeds. `mutator_minion_visual_override` prepares packages; public `override_slot` replicates an existing name whose template is reconstructed locally (`S/extension_systems/visual_loadout/minion_visual_loadout_extension.lua:986-1025`). For a visual-only test, do not enable the whole mutator or add its gameplay buff.

**Variant prerequisites:** same packages and item mapping on every rendering peer, exact old slot/item/gib state, known inverse/restoration strategy, completed late-join test. Predefined variants provide limited colours and change original textures/models. They are a useful approximation only if the user accepts that appearance.

**Shell entry:** privately authored colourable/skinned unit linked using the game's supported item/node attachment path. Positive baseline is an uncoloured correctly fitted shell on A. No existing universal shell was identified; rig/fit/resource authoring is required.

**Unexecuted pseudocode:** load retained private resources; create selected unit's visual-only item/shell; link verified skeleton/node mapping; retain every native object; change only verified material fields; destroy shell/restore original visuals on removal. Do not assign a shared item `base_unit` or introduce hit actors/gameplay stats.

**Expected result:** defined variant or translucent/opaque overlay with stable animation. **Failure:** global item replacement, collision/hit-zone changes, z-fighting, wrong animation/scale, disappearing close/far views, unmatched shield/weapon geometry, ragdoll or dismemberment gaps. **Cleanup:** restore recorded item/gib state, destroy every owned shell/attachment and release resources after use. The private loadout rebuild has no generic inverse; disposal of a test enemy is not proof of reusable feature restoration.

## E8: ownership and compatibility stress after a visual candidate passes

Run only after a candidate has a visible A/B result. These checks are part of acceptance, not excuses for permanent per-frame colour writes.

| Trigger | Required observation |
| --- | --- |
| Vanilla stim/Enraged/bolstering/burn starts or stops | Candidate follows an explicit precedence policy; removing it reveals current vanilla appearance rather than stale captured state. |
| Slot replacement, equip/unwield/drop or new attachment | Newly created relevant units receive selected appearance after readiness; removed/dropped units follow the documented detach policy and are cleaned. |
| LOD switch, near/far return, ragdoll/dismemberment | Report exact continuity/coverage; no stale colour on recycled/detached units. |
| Target dies/despawns between selection and write | No invalid native call; pending selection and resource ownership are cancelled. |
| Late join before/after unit registration | Selected live snapshot arrives once compatible; bounded latest-value retry waits for actual visual readiness. |
| Mission changes or unit ID is reused | Mission/generation identity invalidates old selection; a new ordinary enemy never inherits it. |
| Pause/stop/disable/reload/unload | Deliberate policy for living units, restoration before records vanish, no retired callbacks or leaked native objects. |
| Mark/ability highlight, TraumaOutlines/Versus/private Realms outlines | Owned additions/removals preserve other systems; host/spectator visibility stays correct. |

## Compact validation matrix

For every row, include matched A/B and separate scores for **head, torso, arms, legs, armour, clothing, shield, weapon, attachments, detached/gib parts**. Use `pass`, `partial`, `fail`, `not applicable`, or `not tested`; do not collapse equipment omissions into a body pass.

| Representative enemy | Important cases | Required views/peers |
| --- | --- | --- |
| Poxwalker/newly infected | Exposed skin, limited clothing, dismemberment | Bright and dark light; front/back; near/medium/far; host and modded client |
| Scab melee/rifleman | Separate upper/lowerbody, head, weapon and decals | Same above; matched authored colour variant; equip/drop |
| Dreg melee/rager | Different flesh/cloth family from Scab | Same above; armour/cloth edges and back of legs |
| Mauler and Crusher | Heavy armour versus skin; supported Rotten variants | Same above; armour/body support scored independently |
| Bulwark | Shield, shield state/visibility, weapon, hands | Front behind shield and rear; shield/weapon separate units; modded client |
| Hound or another non-humanoid | Different mesh/rig/material family | All sides, moving pose, distance/LOD, death |
| Plague Ogryn / Chaos Spawn / Beast of Nurgle | Boss skin/material diversity and ragdoll | At least one large boss initially; all three before universal claim |
| Daemonhost | Distinct family; Polychromatic exclusion | Explicit support/failure row rather than assuming boss coverage |
| Captain / twin where relevant | Shield FX, multiple slots and boss effects | Shield active/broken, lighting, distance, host/client |

Run the following overlays on every passing representative or document why skipped:

| Axis | Minimum scenarios |
| --- | --- |
| Colour | Bright cyan/magenta, red/green/blue, dark blue/brown, black, removal/default |
| Lighting | Bright neutral, dark, coloured environmental light; bloom/exposure noted |
| Distance | Close, medium, LOD-transition/far and return close; record distances/settings |
| Motion/state | Idle and attacking/moving; wounded, detached equipment, dying/ragdoll/gibs |
| Peers | Host only; modded client; late join; client with no feature/mod; older/different feature version |
| Selection | One A among identical B; entire chosen group with ambient enemies unchanged; overlapping recipe variants |
| Lifecycle | Despawn during pending apply; stop/disable/re-enable; two reloads; mission exit/new mission; ID reuse |
| Gameplay | Equal A/B buff/stat/health snapshots and controlled combat/AI samples before, during and after |

Horde scale follows single-target acceptance: compare 0/1/10/50/100 selected units, then the user's actual permitted maximum if stable. Hold breed/loadouts and total enemy count constant between visual-off/on trials; repeat comparable runs. Measure frame time distribution, Lua CPU/heap, process/native/GPU memory where tools genuinely expose them, draw/particle/light/object counts, apply/rebuild time and cleanup growth. No costs have been measured here. Event-driven setters should scale with selected units × materials/attachments at transitions; duplicated materials, particles/shells/lights and extra passes may dominate rendering or native memory.

## Lifecycle and multiplayer requirements for integration

| Responsibility | Requirement |
| --- | --- |
| Host selection | Host chooses wave/group/individual appearance and associates it with existing unit IDs. Gameplay tuning remains a separate descriptor/path. |
| Local rendering | Each rendering peer applies its own material/layer/object operations. A raw Unit setter on the host does not replicate visuals. Single-player host also needs local application. |
| Capabilities | All peers intended to see custom appearance need compatible code; native assets/loaders must exist locally when used. Guests without the feature see safe vanilla appearance. Do not send unknown vanilla IDs to them. |
| Network transport | Use Realms mod messages with finite bounded RGB, validated kind/variant, existing unit ID, set/clear revision and mission/generation identity. Validate the actual host sender. |
| Late join and creation | Send only live current appearance snapshot to compatible peers; bounded retries wait for unit registration **and** visual readiness. Coalesce newest state and invalidate stale IDs/mission generations. |
| Missing assets | Acquire/load on every peer before apply, retain owner handles and dependencies; timeout/absence skips appearance and logs a bounded reason. No shader/resource bytes are assumed to transfer automatically. |
| Defaults/restoration | Record authored defaults/original resource mappings and a competing-effect policy. Restore while live units/system handles still exist, before clearing records or retiring hooks. |
| Death/despawn | Cancel pending work; remove owned outlines/particles/shells and native references. Decide whether corpses retain colour, then validate ragdolls/gibs separately. |
| Detached equipment | Track touched units independently of current root ancestry; deliberate keep/restore policy when dropped/unequipped. |
| Disable/reload | Raw native writes persist beyond Lua hook disable. Restore owned state and cancel callbacks first; retire generations so captured callbacks cannot reapply. Native providers may require restart. |
| Conflicts | Avoid shared template/table mutation; balanced outline stacks; compatible ordering with buff starts/stops, Ailment and cosmetic mods. Recompute current baseline where necessary rather than restoring an obsolete effect. |
| Performance | Event-driven dirty/apply on selected units, bounded ready/retry queues, deduplicated attachment lists; avoid per-frame all-unit walks or repeated resource acquisition. |

No new replicated breed/buff/effect/visual-override/outline key should be inserted into vanilla sorted lookups. A local appearance table and local outline setting can avoid those names entirely when no vanilla RPC transmits them. Do not infer that `FxSystem.start_local_template_effect` is safe for custom templates; the inspected handler still performs lookup/RPC work. Resource names used only by a local loaded asset are a different issue from names entering vanilla network lookups.

Use an explicit fallback when a material/provider cannot satisfy coverage. UI must accurately name the implemented result, for example **Tint**, **Body glow**, **Outline**, **Silhouette**, or **Variant**. Do not expose implementation internals as user options unless they help users choose the visual result. Do not claim a full-body or black option until its matrix is accepted.

## Integration points for the coordinating session

These citations describe the working snapshot identified in findings. The other session subsequently committed architecture fixes; recheck small boundaries against its final revision before editing. They are suggestions, not changes made by this investigation.

- **Distinct data:** use a validated `part.appearance` concept if the feature is approved. Keep it separate from `Groups.TUNE`'s numeric percentages (`G/scripts/mods/RealmsWaves/catalog/groups.lua:197-245`) and UI/name colours. Preserve recipe/preset/share round trips and include appearance in group identity (`groups.lua:680-693`) so differently coloured groups do not merge.
- **Queue/repeats:** part expansion currently passes `{breed, mods, tune}` (`G/scripts/mods/RealmsWaves/spawn/execute.lua:310-320`). Carry the appearance descriptor through the initial and repeating entries, preserving host choice rather than consulting later mutable global settings.
- **Ownership after spawn:** `spawn_one` calls `spawn_minion`, modifiers and tuning (`execute.lua:580-626`, particularly 607,618,623). Register appearance ownership here; defer visual operations to observed readiness and reapply only for relevant visual rebuilds/competing writers.
- **Living units versus scheduled jobs:** maintenance occurs before paused/no-job returns (`execute.lua:629-651`); cancellation versus mission reset is distinct (`:754-773`). Choose whether stop keeps colour on living units, and document it; disable must actually restore it.
- **Networking:** use the existing handshake/actual-host validation conceptual patterns (`G/scripts/mods/RealmsWaves/core/protocol.lua:104-114,223-244`) and direct recipient send/failure handling (`:315-357`). Add an explicit appearance capability/version instead of assuming protocol-2 scale support implies appearance support.
- **Retry/snapshot patterns:** `spawn/tuning.lua:685-813` bounds current-state retries, late-join snapshots and registration waits; reuse the established boundaries rather than copy a second unbounded scheduler. Appearance also needs visual-ready and resource-ready gates absent from a scale-only operation.
- **Teardown:** entry unload/game-state/disable paths (`G/scripts/mods/RealmsWaves/RealmsWaves.lua:195-290`) are coordinating-session work. Restore appearance before retirement discards handles. `Tuning.reset` (`spawn/tuning.lua:940`) clearing Lua records is not proof of native visual restoration.

A minimum accepted feature is one confirmed visual mechanism, one per-group descriptor, one selected-unit ownership path and capability-aware local peer application. Do not add a palette/editor/serialization feature for unproven shader capabilities before the smallest diagnostic passes. An individual-unit proof can precede wave/group editor work.

## Handoff: shared documentation updates, not performed here

| Existing document | Proposed later update |
| --- | --- |
| `docs/README.md` | Link these two reports, dates/revisions and confidence; distinguish source-backed hypotheses from game acceptance. |
| `docs/03-findings-realms-and-game-source.md` | Correct overly broad stim descriptions; retain zero-off inference, add particle/vector/standalone distinctions, explicit attachments, MasterItems/override metadata and local-FX lookup caveat. |
| `docs/04-design-and-rationale.md` | Approved appearance type, selection/precedence/restoration policy, statless rendering and peer/resource responsibilities. |
| `docs/05-implementation-plan.md` | Add only approved proof/feature work; leave full-body/black claims unchecked until live matrix passes. |
| `docs/06-verification-and-open-issues.md` | Import executed results and failed cases, screenshots/log references, representative enemies, peers, reload/disable and measured costs. |
| `docs/07-learnings-and-gaps.md` | Preserve failed masks/material attempts, actual default/resource discoveries, Discord evidence/access limits and native compatibility/release caveats. |
| `docs/CHANGELOG.md` | Coordinating-session documentation/implementation milestones only; no invented runtime feature entry for this research. |
| Project `README.md` | Update only when a user-facing appearance feature is implemented/accepted; name outline/glow honestly and document requirements/limits. |

For Discord follow-up, the smallest useful material is a working enemy shader/material example with surrounding replies and newest correction, especially from making-mods/reverse-engineering-bundles or the relevant public implementation's support thread. Current session direct Discord coverage is zero messages: no connector, authorized credential or browser connection was available. The precise attempted routes and planned searches are in [Discord research coverage](findings.md#discord-research-coverage). This limits community coverage, not the feasibility conclusion.

## Completion checks

On 2026-10-03, `python tools/check_docs.py` passed across 25 Markdown files with zero over the 100 KB limit. Local report links, explicit source-file paths and fenced-example pairing were checked. The existing research prompt's SHA-256 is unchanged. The coordinating session's closing HEAD is `661d28c030a41557bcf8a52a96231d208c85ce50`; inspected entry/execute/tuning/protocol byte hashes remained unchanged from the research snapshot. See the [snapshot ledger](findings.md#snapshot-ledger-and-verification) for revision and concurrent-document distinctions. No in-game experiment or runtime test result is claimed by this document.
