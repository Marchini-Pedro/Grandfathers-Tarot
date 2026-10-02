# The Workshop redesign (button family, the Cauldron and the Mirror)

Spec and build log for the redesign of the card editor that followed the Deck (2.0.0). Origin: the user's request of 2026-10-01 ("integrate the rest of the mod into the same palette", "all buttons need to be remade", "the preview of the card in the enemies edit page on the right side, with an easy way to change the faces/enemies and the changes shown in real time"), a design page with every decision (https://claude.ai/artifact/JZKnq3YvrtZHk66zRgBBsv, private; the source HTML is not in the repo) and the user's answers to it. Branch: `feature/workshop-redesign`.

## 1. Decisions

From the design page (accepted: "I really enjoyed it"):

| Topic | Decision |
|---|---|
| Buttons | One family, eight roles, drawn only from rect / triangle / rotated rect / circle / text (the passes the Deck tiles use). Roles: **standard**, **primary** (one per screen), **danger** (two-step "Sure?"), **quiet** (no frame, underline), **chip** (36 high, no brackets), **stepper** (one plate: minus, value, plus; the signs are rects), **toggle / check** (the diamond), **tab / segment**, **icon** (triangle glyph). |
| Hover / press | Hover: fill = 14 percent of the accent mixed into the plate, frame in the accent, two corner brackets (top left, bottom right) 4 units outside the frame. Press: brackets pulled in to 1 unit, fill darker, label 2 units lower. Disabled: dim plate, dim frame, muted label. |
| Accent | Inside a card's screens (Cauldron, Mirror, picker, mods, custom) the accent is the card's suit accent; everywhere else it is bile (#b7c23a). One module-level colour (`Components.accent`) that the buttons read every frame. |
| Card on the right | On the Cauldron and the Mirror the live card is on the right at **1.4 times** its Deck size on a lit plate (`rw_tile_preview`, a tile built with a scale factor), same place on both screens. |
| Quick face | Under the card on the Cauldron: the twelve suits (icon tiles), the threat diamonds (clickable, Auto / By hand), the chance stepper. Whisper, cooldown and the cooldown look are on the Mirror. |
| Shelf | Common enemies as chips under the list, grouped by kind. One click adds one (or +1 to the group that already exists). "Search all enemies" opens the old picker. |
| Face is a tab | "Card face" becomes a tab beside "Enemies" in the header. |
| Colours | Chrome is the Nurgle palette; enemy colours stay the saturated ones of `catalog/colors.lua` (they are data and match the dots of the card). |
| Diamonds | Checks, toggles and threat share the card's diamond (filled and dimmed when off, never an outline: two rotated squares make an uneven one). |

From the user's answers (2026-10-01):

1. **Titles.** The Cauldron (the card's own screen: the enemies, the picker, Mods, Custom) is titled **"The Grandfather's Cauldron"** (the user's suggestion). The Mirror (card face) is titled **"The Grandfather's Mirror"** (a card's face is what the mirror shows). The Deck, the Spreads and the options keep "The Grandfather's Tarot".
2. **Every resolution.** There are no per-resolution versions: the editor is ONE 1920 x 1080 layout and the engine scales it (see 3.). No bitmap assets are used, so nothing looks low resolution.
3. **Shelf contents.** The Packmaster (`chaos_ogryn_houndmaster`, called Houndmaster by the user; its display name stays "Packmaster", the old names still parse) is on the shelf with the bosses. Both vanguards (`cultist_vanguard`, `renegade_vanguard`) are on the shelf in the **Fodder** group (they already count as normal enemies, not elites, for the threat and the multipliers).
4. **Dreg or Scab.** Units that exist in both factions show which one a click adds: one switch on the shelf, **Adds: Dreg | Scab**, and a small tag on every chip (D in the Dreg colour, S in the Scab colour; fixed for a unit that exists in one faction only, none for Chaos units). Rows of the card name the faction in the same colours ("3 Gunner  Scab"), and so does the picker.

## 2. Screens (1920 x 1080 units)

Common: the title at (80, 38), the subtitle at (80, 95), tabs `Enemies | Face` and `?` top right (x 1478 to 1752 and 1766), the left pane x 105..1240 (1135 wide), the right pane x 1290..1815 (525 wide), content from y 134 down to 1014, "[ESC] Back" in the input legend.

**Cauldron (screen `detail`).**
- Left: a header row (Enemy, Weight, Added each repeat, Same), five enemy rows of 52 (6 apart) from y 160, a summary line ("The Magician: 9 enemies in total", "1 - 4 of 4", scroll triangles), the shelf (y 496, 270 high), "How it spawns" (six steppers in three columns: Spread radius, Repeat every, Repeat for, Min distance, Max distance, Fixed timer), and the action bar (Back, Rename, Edit as text, Share wave; right: Reset to default, Delete with Sure?).
- An enemy row: a 5 wide edge and the name in the enemy's colour (the weight is the number in front of it), the weight stepper, the repeat stepper, the Same diamond, then the chips Mods (lit with a count when set), Custom (lit when set) and Remove (danger).
- Right: the stage plate (525 x 440) with the 1.4 times card, the toolbar (In the draw toggle, Preview cooldown), and the quick face (suit tiles 6 x 2, threat, chance).

**Mirror (screen `face`).**
- Left: Suit (twelve plates, 4 columns, each with its icon, its name and its line of whisper; the suggested one marked; the long description under the grid), Threat (five big diamonds, Auto | By hand, "Threat N by the numbers" as a sum), Whisper (the card's line and Change; the card follows while the box is open), Cooldown (stepper in 30 s steps, then three look plates: Rot and renewal, The murmur returns, The vial fills, and Automatic for this suit), and Back / Reset face.
- Right: the same stage plate and toolbar.

Not in the first build (deferred, see the checklist): the "In the hand" mini card, animated look plates (they are static swatches), whisper typed inline instead of in a box.

## 3. Resolution and sharpness (what the engine does, from the source)

- The root scenegraph node is `scale = "fit"` with size 1920 x 1080: the engine multiplies every position, size and font size by `RESOLUTION_LOOKUP.scale` (1.0 at 1080p, 1.333 at 1440p, 2.0 at 4k). Text is rendered from font outlines at the scaled size, rects and the other shapes are geometry: both stay sharp at any resolution. One layout is enough.
- `UIRenderer` can snap the position of rects, bitmaps and text to whole device pixels (`render_settings.snap_pixel_positions`, effective only when the scale is 1 or more; the stock default is off, `ui_renderer.lua:17,224`). Without it a 1-unit line at 1.333 scale lands on a fractional pixel and its two edges can differ in thickness. The view switches it on in `on_enter` (`self._render_settings.snap_pixel_positions = true`; the stock overcharge HUD does the same, `hud_element_overcharge.lua:43-58`). Below 1080p the engine keeps it off by its own rule.
- Triangles, circles and rotated squares are not anti-aliased by the engine (`draw_triangle`, `draw_circle`, `draw_rect_rotated` have no snap and no smoothing). They keep the **feather** (a faint 0.55-unit larger copy under each shape, `Spread.FEATHER`) that the Deck tiles already use; the new diamonds, triangles and the suit icons of the quick face use it too. At 4k the stair-steps are half as visible, at 1080p they are the worst case, so 1080p is where to look.
- Lines are 1 unit (a frame), 2 units (brackets, the underline of a quiet button) or 3 units (the tab bar): all whole units, so snapping lands them on whole pixels at 1080p and 4k and on a consistent pixel width at 1440p.

## 4. Build order (each a commit on the branch) and status

- [x] 0. This document and the plan in `05`.
- [x] 1. Button family in `ui/wave_editor_components.lua` (standard, primary, danger, quiet, chip, stepper, diamond check, tabs, icon), the popup buttons and frame, pixel snapping, the accent colour, and the two titles. Done offline; the accent lives on `mod.rw_accent` (see `07`).
- [x] 2. The shelf data: `Groups.faction`, `Groups.SHELF` (30 chips, Packmaster, vanguards as fodder, Dreg / Scab pairs), the faction word in rows and the picker. Done offline.
- [ ] 3. The tile at any scale (`blueprints.tile(node, k)`, `_paint_tile` with the scale) and the stage plate.
- [ ] 4. The Cauldron (rows, shelf, spawn block, action bar, stage, quick face, tabs).
- [ ] 5. The Mirror (suit plates, threat, whisper, cooldown, looks).
- [ ] 6. Preview tool for any screen, tests, docs.

## 5. Tests

Offline only (`tools/editor_test.py` drives the real view with stubbed engine classes; a Python preview draws the widgets into a PNG at 1920 x 1080 so layouts can be looked at). The in-game checks are in `06` (rows from 97). Every new widget gets: bounds inside 1920 x 1080 and inside its pane, hotspots that do not overlap, every visibility and change function runs under the engine's rules, and a scale check (the tile at k = 1 equals the old tile).
