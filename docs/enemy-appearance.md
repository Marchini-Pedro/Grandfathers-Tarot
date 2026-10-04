# Enemy colour experiments

Implemented on `feature/enemy-appearance`, in its own worktree, originally based
on `main` at `6d5756d` and synchronized with `06c2b3a` after PRs #5 and #6.
This preserves the separate CI/coverage checkout. Offline validation is complete;
native rendering and multiplayer acceptance are pending. GitHub records
[PR #7](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/7) as merged by
`EduardoKenji` at `c7cf1da` on 2026-10-03, after both final hosted runtime checks
passed. Local main is synchronized with that merge. Installed mods were not
changed during this work session; the merge does not establish game acceptance.

The preceding [research findings](research/enemy-appearance/findings.md) and
[experiment plan](research/enemy-appearance/experiments-and-recommendation.md)
remain records of the earlier read-only investigation. This document describes
the implementation that followed it.

## Using the controls

Open `/rw_editor`, select a card, click **Custom** beside an enemy group, then
**Enemy colour experiments**. Choose a method in the dropdown. Drag the four
0–255 ARGB sliders, or click their numbers for exact entry. The hex swatch shows
the input colour, not a rendered enemy preview. Changes belong to that group;
other groups of the same breed can remain untreated or use different methods.
Colours persist through reopening, repeats, recipe sharing and preset storage.

**A means tint strength for the usable RGB APIs.** It multiplies RGB by A/255;
it does not make enemy meshes transparent. Natural stim particles and buffs
retain the game's behaviour even at A=0. Black resets the stimm parameter; it
does not produce a black enemy surface. LODs, masks and unsupported materials
can limit visible coverage.

| Method | What this revision does |
| --- | --- |
| Default appearance | Does not apply an appearance operation; preserves the sliders for later experiments |
| Natural stimm | Checks the breed's existing `use_stim` action and blackboard component, arms its permission on the server, and colours after the vanilla `stimmed` keyword appears. Vanilla animation, selected stim buff, particles and gameplay changes remain. Unsupported breeds keep their appearance and produce one log warning |
| Applied stimm colour | Writes the known `stimmed_color` RGB vector recursively after spawn, without adding a buff or effect template |
| Explicit body / equipment stimm | Uses the same known vector on the root, each visual loadout slot and its attachments. This compares coverage with recursive root writes; it is not a surface material override |
| Per-material surface override (unavailable) | Disabled in the editor; applies no operation. Needs a verified colour property, authored neutral/default values and a coverage map for actual enemy materials |
| Private material / shader patch (unavailable) | Disabled in the editor; applies no operation. Needs compatible compiled assets, a loader, per-unit isolation and verified restoration. This revision installs no asset dependency or native patch |
| Outline | Adds one local outline stack with a private settings map and RGB tint. Stock tags may take priority. It does not recolour the surface |

Unsupported methods expose their requirements and remain disabled. Saved older
selections are readable but cannot claim an operation succeeded. No guessed
shader variable, material fallback or compiled asset was introduced.

PR #9 adds **Independent outline** and **Keep edited tint over other buffs** switches.
An ordinary outline uses only the depth-tested material layer at priority 2;
native manual tags retain their through-wall layers and higher priority.
Protection defaults off. When enabled, native buff material-effect start/stop
hooks reapply the edited vector; buffs and gameplay stats stay native.
See [card effects and UI](12-card-effects-and-ui.md) for verification and limits.

## Black / near-black stimm feasibility (2026-10-03)

The current controls can express a near-black input, but **a visible black stimm
has not been established**. Native `MinionBuffExtension._stop_material_vector_effect`
clears the effect with `Vector3(0, 0, 0)` (`minion_buff_extension.lua:529`, source
revision `419fe18d`). Pure black therefore writes the same value as removal.
The exact shader blend is absent from the inspected Lua source. If it adds glow,
reducing RGB weakens that glow rather than painting the underlying surface black;
low RGB alone is not evidence of a dark surface or a readable stimm pattern.

Use **Applied stimm colour**, A=255 and equal nonzero RGB channels for the
smallest live test. Compare untreated and zero-reset controls with greys 8, 16,
24, 32 and 48 on matched enemies. For example, RGB 16 (`#101010`) uses
`<applied_stimm!:FF101010>` and writes approximately `(0.062745, 0.062745, 0.062745)`.
These are diagnostic candidates, not a verified darkest/readable preset. A=0
returns to the zero vector; A is strength, not mesh transparency. Natural stimm
retains vanilla particles/buffs, which this one parameter does not recolour.

If a candidate passes, offer **Charcoal stimm (experimental)** as a preset of
the existing method and channels, keeping other methods and the outline/protect
flags available. It needs no new buff, renderer, dependency or packet format.
Different groups retain independent choices. On one enemy, competing writes to
`stimmed_color` cannot display two independent tint colours at once; use the
existing protection policy, whose hook coverage does not include every direct
write made by another mod or native template.

The independent outline is an independent operation, **not an independent
colour**: it currently shares the tint's RGB and A. Enabling it with charcoal
does not supply a contrasting bright edge. A separate outline colour would be
a further implementation change and must preserve native tag precedence; an
outline must not be presented as proof of a black stimm.

Choose the darkest candidate that still preserves the stimm pattern, body
silhouette and texture detail in bright and dark areas, at several distances
and LODs. Check armour, skin, legs, weapons/shields, other colour buffs, unrelated
enemies and cleanup on each participating peer. Reject candidates that merely
remove the effect or obscure its shape. If all fail, actual black requires a
verified surface/mask material path or compatible private assets; the existing
unavailable methods remain unavailable. Negative/HDR vectors and guessed
properties are not established alternatives.

Offline probes on Lua 5.5 and LuaJIT 2.1 preserve seven grey values (0, 1, 8,
16, 24, 32, 48) across applied, explicit-slot and natural recipes, including
outline/protect flags, and confirm the strength calculation. These probes
establish input support only; no native screenshot or shader result was obtained.

## Recipe and runtime behaviour

The suffix follows modifiers/custom stats and precedes repeat notation:

```text
1 crusher, 1 crusher<applied_stimm:FF8000FF>, 1 crusher<slot_stimm:FFFF0000>@1
2 crusher{size=130}<natural_stimm:FF00FFFF>
```

The suffix is `<method:AARRGGBB>`. Add `+outline` and/or `!` before the colon
to combine an outline with the method and protect tint, e.g.
`<applied_stimm+outline!:FF8000FF>`. Methods use the IDs defined in
`catalog/appearance.lua`. Malformed IDs/hex fail parsing. The group key includes
appearance, so coloured and untreated groups do not merge. Editor copies are
independent. Existing recipes without this suffix retain their behaviour.

`spawn/execute.lua` carries appearance through initial and repeat queues, then
applies it after modifiers and custom stats. `spawn/appearance.lua` owns at most
600 selected units per peer and checks them every 0.25 seconds. Stable material
writes are not issued every frame: loadout changes or tracked buff-vector
changes trigger them. New loadout units retry recursion or receive explicit
writes; detached explicit targets restore the current known neutral/buff value.

Stop/pause retain living colour ownership. Disable clears colours and unsent
work; re-enable starts with fresh colour ownership. Death prunes records and
restores surviving detached/slot units. Gameplay exit/reset and unload discard
pending work, restore local settings/vectors and retire captured owners.
Unconsumed natural stim permission is returned to its prior state; an already
consumed vanilla stim buff keeps its own lifecycle.

Material cleanup restores the current buff extension's `stimmed_color` value
when available, otherwise the game's zero reset. **There is no verified getter
for arbitrary prior writes made directly by another mod or a vanilla template.**
Those writes cannot be faithfully reconstructed; combine appearance with such
effects only as an explicit experiment. This revision also cannot prove private
engine material instances, LOD coverage or unchanged unrelated pixels offline.
Native failures are logged; one restoration failure does not stop cleanup of
the other tracked targets. A failing native restoration still needs live diagnosis.

## Replication and compatibility

The existing HUD protocol/version remains 2 / 2.0.0. Optional capability `1` in
`rw_hello` enables the new mod RPC `rw_appearance`; only capable peers receive
colour entries. No vanilla `NetworkLookup` is extended. Welcome carries a
per-load/per-reset appearance token. Entries with an old token, a non-host
sender, an invalid ID/breed/method or non-integer/out-of-range channels are
rejected. A packet is limited to 32 KiB and 200 entries. The receiver verifies
the arrived unit's breed before applying anything.

Host entry, reload and re-enable request the normal handshake again through
the appearance endpoint. Older/absent clients safely ignore the unsupported
endpoint and retain normal visuals; natural stim's vanilla gameplay can still
replicate to them. Matching development revisions are recommended, especially
when pooling/sharing recipes containing the new suffix with an older host.

Living records are renewed every five seconds; a capable late joiner receives
a snapshot after hello. Failed sends retry with a fresh snapshot at that cadence.
Client colours have a 15-second lease, so a disconnected/disabled host cannot
leave them applied indefinitely. Missing unit IDs wait at most 20 seconds in a
600-entry coalesced queue. Disable/unload attempt an immediate `none` snapshot.
A synchronous reset during sending stops the remaining snapshot batches.

## Validation and live acceptance

`python tools/appearance_test.py` covers schema/recipes, runtime lifecycle and
host-only packet validation, and drives the real editor and entry/executor
using their existing stubs. `RW_LUA_RUNTIME=luajit21` selects LuaJIT; the default
is Lua 5.5. The CI runner discovers this test and gathers coverage from all three
of its VMs. The full suite uses the shared CI helper and existing checks:

```powershell
python tools/run_tests.py --runtime lua55 --output-dir test-results/lua55
python tools/run_tests.py --runtime luajit21 --output-dir test-results/luajit21
```

The three new modules have explicit source-line floors of 84 (schema), 79
(runtime) and 90 (editor), selected from both runtimes' measured scores. Existing
module floors and the 78 overall floor are preserved. The score includes syntax
lines and measures line events rather than branch/native coverage.

For real-text layout inspection:

```powershell
$env:UI_DUMP_DIR = '<existing output folder>'
$env:UI_REAL_TEXT = '1'
python tools/appearance_test.py
python tools/ui_preview.py "$env:UI_DUMP_DIR/appearance.json" appearance.png --scale 1
python tools/ui_preview.py "$env:UI_DUMP_DIR/appearance_dropdown.json" dropdown.png --scale 1
```

Live acceptance must compare untreated and treated groups of the same breed:

- Verify initial/repeat colour, sliders, exact numbers, saving and importing.
- Compare recursive/explicit coverage on body, armour, clothing, weapons,
  shields and attachments at near/medium/far LODs; include black and A=0.
- For natural stimm, verify a supported Crusher/Reaper/Bulwark actually uses
  its action and normal buff; unsupported enemies must remain untreated.
- For visual-only methods, compare stats and gameplay with the untreated group.
- Test tags, modifier/buff transitions, loadout rebuilds and competing direct
  colour setters. Confirm cleanup and document any lost prior direct colour.
- Test late joins, a client/host leaving, disable/re-enable, reload, mission
  changes, older/absent clients and incompatible asset mods. Check the log and
  frame time/RAM at realistic enemy counts.

Full-body surface recolouring and private material/shader patching remain
unimplemented until the prerequisites above are actually verified. The live
checklist remains open after the GitHub merge; no in-game confirmation is recorded.
