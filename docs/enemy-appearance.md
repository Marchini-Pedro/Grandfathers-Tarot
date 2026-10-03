# Enemy colour experiments

Implemented on `feature/enemy-appearance`, in its own worktree based on `main` at
`6d5756d`. This preserves the separate CI/coverage checkout. Offline validation is
complete; native rendering and multiplayer acceptance are pending. Nothing has
been merged, pushed or installed by this feature session.

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
| Per-material surface override (prerequisite) | Selectable to inspect its requirement; saves the choice but applies no operation. Needs a verified colour property, authored neutral/default values and a coverage map for actual enemy materials |
| Private material / shader patch (prerequisite) | Selectable to inspect its requirement; saves the choice but applies no operation. Needs compatible compiled assets, a loader, per-unit isolation and verified restoration. This revision installs no asset dependency or native patch |
| Outline | Adds one local outline stack with a private settings map and RGB tint. Stock tags may take priority. It does not recolour the surface |

The prerequisite methods deliberately have no guessed shader variables or
dummy successful fallback. Their saved selection allows the experimental UI to
show the intended method and the missing prerequisite without misrepresenting
what happens in the game. Warnings go to the mod log.

## Recipe and runtime behaviour

The suffix follows modifiers/custom stats and precedes repeat notation:

```text
1 crusher, 1 crusher<applied_stimm:FF8000FF>, 1 crusher<slot_stimm:FFFF0000>@1
2 crusher{size=130}<natural_stimm:FF00FFFF>
```

The suffix is `<method:AARRGGBB>`. Methods use the IDs defined in
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
using their existing stubs. `LUA_RUNTIME=luajit21` selects LuaJIT; the default is
Lua 5.5. The existing compile, logic, editor, entry and HUD checks still apply.
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
unimplemented until the prerequisites above are actually verified. Merge into
`main` remains gated on the user's in-game confirmation under `CLAUDE.md`.
