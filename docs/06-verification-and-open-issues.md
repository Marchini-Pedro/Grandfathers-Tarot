# 06. Verification, risks, open issues

## 2026-10-03 - Record PR #7 merge and refresh main

The [final hosted PR run](https://github.com/Marchini-Pedro/Grandfathers-Tarot/actions/runs/37155424490)
at `4782cfb` and its push run pass both runtimes. GitHub then records PR #7
merged by `EduardoKenji` at `c7cf1da`, 21:35:06 UTC. Fetch and fast-forward
local main in its dedicated worktree; preserve the other agent's checkout.
Update current merge status in the README, index, method guide, plan and CI log.
The runtime/tests/workflow match the verified PR head; this follow-up changes
documentation only, checked with the size checker and `git diff --check`.
Native rendering, multiplayer, performance and installation remain unverified.

## 2026-10-03 - Publish enemy appearance PR #7

Push `feature/enemy-appearance` at `0103281` and open
[PR #7](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/7) against main
at `06c2b3a`, as requested by the user. GitHub reports the PR conflict-free.
Its [first hosted PR run](https://github.com/Marchini-Pedro/Grandfathers-Tarot/actions/runs/37155162068)
passes both runtimes: 1,916 assertions each, all module gates and source-line
scores of 81.80% on Lua 5.5 / 78.54% on LuaJIT 2.1. Downloaded test/coverage
reports match local results with no coverage failures. This publication record
updates documentation only. Publication does not establish native acceptance;
the feature remains unmerged and no installed mod files were changed.

## 2026-10-03 - Synchronize appearance with merged PRs #5 and #6

Fetch origin, pull main to `06c2b3a` in a separate worktree and merge main into
`feature/enemy-appearance`. Preserve both changelog histories and the concurrent
agent's checkout. This synchronization changes documentation only.
Both aggregate runners pass again: **1,916 assertions per runtime**, Lua
compilation, documentation sizes and every coverage gate; source-line scores
**Lua 5.5 81.80%, LuaJIT 2.1 78.54%**. Reports are in ignored
`test-results/pr7-lua55/` and `test-results/pr7-luajit21/`. Native rendering,
multiplayer and performance acceptance remain pending; the feature is unmerged.

## 2026-10-03 — Enemy colour experiments (offline; feature branch)

Implemented per-group ARGB/method selection, persisted recipes/repeats, natural
stim behaviour, visual-only stimm/explicit-slot tint and local outlines in the
isolated `feature/enemy-appearance` worktree. Surface/private patch choices
display prerequisites and perform no operation. Alpha is tint strength; native
full-body/black surface coverage is not claimed. See [the live checklist and
restoration limits](enemy-appearance.md).

Before CI integration, the baseline passed: 33 compiled files, logic 828, editor
694, entry 45 and HUD 179 assertions; documentation sizes passed. The initial
focused appearance harness added 71 assertions (52 schema/runtime/protocol, 13 editor, six real
entry/executor lifecycle) and reuses the editor/entry regressions. It passes on
Lua 5.5 and LuaJIT 2.1. Real-English slider/dropdown previews were rendered from
the real widgets and visually inspected; the zero-fill render failure was fixed.

No game installation/session, shader/assets, native material coverage, live
host/client, frame-time/RAM or user acceptance checks have run. The original
CI checkout and installed mods remain untouched. No feature merge into `main`.

### 2026-10-03 — Final integrated CI verification

Integrate CI work at `fd56262` into this feature branch only. Resolve README and
changelog conflicts while retaining both histories. Extend the protocol failure
fixture for DMF schema loading/seven RPCs; instrument all three appearance test
VMs and report every focused assertion. Add eight readiness/unsupported-stim/
cleanup cases, bringing focused checks to 79 (60 schema/runtime/protocol,
13 editor, six entry/executor).

Both aggregate runners pass: **1,916 printed assertions**, compilation,
documentation and every module/overall coverage gate. Source-line execution
scores: **Lua 5.5 81.80; LuaJIT 2.1 78.54 percent**. New-module floors are
schema 84, runtime 79, editor 90; all existing floors and overall 78 remain.
The source-line proxy includes structural lines and is not branch/native
coverage. Reports are reproducible under `test-results/` with `tools/run_tests.py`.
No installation, publish, main merge or in-game acceptance is implied.

## Test matrix
| # | Test | Expect | Status |
|---|---|---|---|
| 1 | Load with only RealmsWaves enabled (originals off); check `%APPDATA%\Fatshark\Darktide\console_logs` | No errors; mod listed | not run |
| 2 | Solo (SoloPlay / Realms local host): `/rw_test <event>` in a mission | Units appear out of sight, aggro, near players | not run |
| 3 | `/rw_status` before/after wave | Adjusted `total_allocated_num_enemies` and aggroed challenge rating exclude tracked units; hordes and specials still trigger normally | not run |
| 4 | Two-instance Realms LAN (host + client) | Same HUD countdown/ballot on both; client vote counted; same result | not run |
| 5 | Client without the mod joins | Host unaffected; client just sees enemies | not run |
| 6 | Percents not summing to 100; `/rw_roll 1000` | Normalised; frequencies within tolerance | not run |
| 7 | Hub / prologue | No spawning, no errors | not run |
| 8 | Leave mission; hot reload (`ctrl+shift+r`) | State cleared; state survives reload sanely | not run |
| 9 | Ghost host present (DTRealmsGhostHost) | Waves still spawn near guests | not run |
| 10 | Open the wave editor (F6 / `/rw_editor`) in a mission and in the hub | View opens, no errors in console log; list shows 32 waves with compositions | not run |
| 11 | Editor: edit a built-in wave (count stepper, remove, add from picker, rename, edit as text, reset) | Values persist across closing/reopening the editor and restarting the game; next draw uses them | not run |
| 12 | Editor: build a custom wave in a slot, enable it, `/rw_test custom_1` | Spawns the composition; appears on ballots | not run |
| 13 | Editor popup: type text/numbers, Enter, Esc, mouse click on OK/Cancel | Input accepted/rejected as designed; hotspots locked while open | not run |
| 14 | `custom_hud` edit mode: find and drag `HudElementRealmsWavesPanel|panel`; sample panel visible | Panel moves, position persists, sample text shows while editing | not run |
| 15 | Interval min 5 s, vote mode | Whole countdown is the voting phase; wave fires after 5 s | not run |
| 16 | HUD percentages | Show `52.1%` style values, no long decimals | not run |
| 17 | Editor opens without crashing (1.1.2 fix), all screens reachable (list, detail, picker, mods, popups) | No errors in the console log | not run |
| 18 | Custom wave `3 crushers[enraged+garden]`, `/rw_test custom_1`, normal mission | Crushers spawn with garden head effect and enraged colour/speed; console has no modifier warnings | not run |
| 19 | Same in a Havoc mission that has only Garden | Enraged crushers still enrage; Garden ones heal neighbours | not run |
| 20 | `[toughened]` in a normal mission | Skipped, one console warning "needs a Havoc mission"; in Havoc it applies | not run |
| 21 | Havoc order with stimmed minions | Wave units are sometimes stimmed (1.1.1 fix) | not run |
| 22 | Client view of modifier effects | Client sees the buff visuals on modified units | not run |
| 23 | Editor rows: hover highlight, click checkbox / `-` / `+` / value / Edit / Mods / Remove | Everything highlights on hover and responds (1.2.1 fix) | not run |
| 24 | Spread radius 0 vs 3 vs 10 with `/rw_test hound_frenzy` | Radius 0 stacks on one spot; 3 and 10 spread the pack; units not in players' view | not run |
| 25 | `5 crushers@2`, repeat every 10 for 35, `/rw_test custom_1` | 5 at once, +2 at 10/20/30 s, none after; also try with a second wave running, and `max_alive` low | not run |
| 27 | Twins: `/rw_editor`, custom slot, add "Twin Captain One" and "Twin Captain Two", `/rw_test custom_1` | Both spawn hidden near the squad and fight; check whether an unpaired twin behaves (disappears/retreats/shield) | not run |
| 28 | Spread radius 50-100 m | Units scatter widely; note how often they appear in view or fall back to the spawn point | not run |
| 29 | Options menu: three multiplier sliders show 0-500 with "percent"; try 0 / 200 / 500 with `/rw_test` on a mixed wave | Types scale/vanish as configured; wave with everything at 0 gives the console message | not run |
| 30 | Picker search: open Add enemy, click Search enemies, type `twin`, `boss`, `beastmaster`; Enter and Esc | List filters live, popup does not hide the list, Esc undoes, Enter keeps | not run |
| 31 | Big waves: max per wave 500, max alive 1000, a 500-unit wave via multipliers | Spawns without errors; note frame rate/network behaviour and whether the game copes | not run |
| 32 | Rename a custom wave to "Mutants Everywhere" in the editor, then `/rw_test mutants_everywhere` and `/rw_test Mutants Everywhere`; also `/rw_test` alone | Wave spawns; the no-argument form lists waves as `Name (key)` | not run |
| 33 | `/rw_status` before and after a large wave (e.g. 200+ units), note the "lua heap" MB | Heap grows by roughly tens of MB per hundred units and falls again after they die; guard never trips at default 800 | not run |
| 34 | Set the memory guard low (e.g. 300 MB) and run `/rw_test` | Wave refused with a "memory guard" message; a running wave pauses; console shows ONE "spawning paused" warning; resumes when raised | not run |
| 35 | Hot-reload the mods (Ctrl+Shift+R) twice, then run a wave | Waves still work; `/rw_status` counters sane; heap floor growth per reload noted (FpsDoctor) | not run |
| 36 | Detail screen: tick "Same" on `3 crushers`, wave repeat every 10 s for 25 s, `/rw_test` | 3 at once, +3 at 10 s and 20 s; box and "=" show; unticking stops repeats; `1 mutant@10` gives 1, then +10 per tick | not run |
| 37 | Mods screen shows the new names (Purple, Red, Blight, Orange, Pus-Hardened Skin, Purple Stimm) with the new descriptions; old recipes with `[garden]`, `[toll]`, `[bolstering]` still work | Names/descriptions as specified; old wave definitions keep their modifiers | not run |
| 38 | `2 crushers[purple stimm]`, `/rw_test`, kill them | Each bursts into two weaker enemies (executor) with a purple explosion; they split again; no console errors; watch the Lua memory (`/rw_status`) and unit count | not run |
| 39 | Any popup (rename, number, search): look at the OK and Cancel buttons | Inner rectangle is the normal size for the frame, "OK"/"Cancel" fit inside, buttons do not overlap the hint text; if still small, widen the nodes (see CHANGELOG 1.5.2) | not run |
| 40 | Add enemy > Search, type `pox`, click "Poxwalker" without closing the box | Enemy is added, box closes, back on the wave's detail screen; other buttons ignore clicks while the box is open | not run |
| 41 | Open any text box in the editor (rename, edit as text, search) and type words containing `i`, `f`, `o`, digits, and the F1-F6 keys | Letters land in the box; no inventory/other menu opens; no vote or editor keybind fires; after Enter/Esc/closing the editor, keybinds work normally (e.g. F6, hub hotkeys) | not run |
| 42 | Psykhanium (solo): `/rw_test twins` | Chat says `queued - no spawn points on this level ... ring`; both twins appear 10-30 m around you within a couple of seconds. If not, chat says why after ~4 s (e.g. "no walkable ground" or a spawn failure): report that text | not run |
| 43 | Add enemy screen: type `pox` without clicking anything | Search box opens, `pox` is in it, list filtered; no inventory/menu opens for letters like `i`; the first letter is not lost or doubled | not run |
| 44 | Add enemy screen: click the toggle next to Search (label "After adding: stay here"), then click two different enemies | Screen stays on the picker, counts go up, note "Added X (now N in this wave)" shows; toggle back and click one: returns to the wave. Setting survives closing the editor | not run |
| 45 | Add enemy screen with a search box open and the toggle on: click an enemy | Box stays open with the filter, enemy added; Enter/Esc then closes the box only | not run |
| 46 | `/rw_test twins` (in a mission): look at both twins | Both have their void shield up (shield effect, boss bar shows shield); breaking it works. If still missing, the shield may also depend on the twins' behavior/encounter state (see CHANGELOG 1.5.5) | not run |
| 47 | On a normal (non-Rotten) mission: `3 crushers[rotten], 2 scab mauler[rotten], 2 hounds[rotten]`, `/rw_test` | Crushers and maulers spawn (no rotten model, that is expected); shooting a fresh one does very little damage and it gets softer as its health drops; toxic puddle when it dies; hounds are skipped with one log line; NO console resource errors. If the console shows missing particle/liquid resources or a crash, remove the modifier and report | not run |
| 48 | Wave list > Presets > open slot 1 > Save current waves here; change a wave's chance; open slot 2, Save; go back to slot 1 and Load | Both slots show their changed waves; loading slot 1 restores its chances; Undo last load brings the other back. Buttons in two rows, none overlapping, hint text on the presets screen readable | not run |
| 49 | Slot > Export (copy), then paste into any chat/notepad; on a second game (or slot) Import (paste) | Text starts with `RW1|`, one line; Ctrl+V pastes all of it; Import box is prefilled when the clipboard holds it and OK imports; a damaged paste (delete some characters) is refused with a message | not run |
| 50 | Export a setup with all 20 custom slots filled (long text, several KB) | The box holds and scrolls it, copy/paste works, import succeeds | not run |
| 51 | With Spidey Sense installed: change the Crusher colour in its options, reopen the wave editor, open a wave with crushers and the enemy picker | Crusher name uses that colour; others use the palette; with Spidey Sense off/absent or "Use Spidey Sense colours" off the palette applies. In the wave list the composition text is coloured per enemy and NO raw `{#color(...)}` text is visible | not run |
| 52 | Wave list: look at the row buttons; click Delete on a custom wave, wait 5 s, click again, click twice | Delete -> "Sure?" -> back to Delete after ~4 s; two quick clicks empty the slot. Standard waves show Reset only after you changed them. Hint text says to click a row to edit it | not run |
| 53 | Timing and voting screen: toggle random off, set the minimum to 20, start a mission | Waves come every exactly ~20 s; with random on and 15/40 they vary between 15 and 40 s; 10 rows readable and not overlapping | not run |
| 54 | Vote mode, turn off "Show chances in the vote" | The vote panel shows names and vote counts without the percent | not run |
| 55 | Edit a wave: set Min distance 60 and Max distance 100, `/rw_test` it a few times in a big area | Units appear 60-100 m from the nearest player (hidden spots only; if none exist the wave waits as usual). "auto" waves still use the options. The three stepper rows fit above the bottom of the screen, nothing overlaps the input legend | not run |
| 56 | Edit a custom wave, Share wave, paste the text to a friend (or into an empty custom slot of yours via Import wave) | The text is one line starting `RWW1|`; Import wave (wave list) puts the wave into the first free custom slot with name, enemies, modifiers, chances, distances intact; pasting a wave over the Share text replaces the open wave | not run |
| 57 | Two instances (host + client): client enables a custom wave "Friend Special" the host does not have; host turns "Use everyone's waves" on (settings screen), starts a mission, client opens and closes the wave editor once, `/rw_status` on the host | Host status shows "everyone's waves: on, N from 1 players"; the wave can appear as the next wave / on the ballot on BOTH screens and spawns on the host; with the option off it never appears | not run |
| 58 | Edit a custom wave (e.g. `4 hounds`), set Fixed timer to 20 s, enable it, start a mission and wait; also keep the normal waves on a long interval | The wave spawns 20 s after the first cycle starts and then every 20 s regardless of the countdown/vote of the other waves; it never appears as a "next wave"; the list shows "every 20 s"; the detail screen shows the chance/cooldown rows as ignored; all steppers and the Share button are visible and not overlapping | not run |
| 59 | Wave list: look at the top right and the bottom; hover the "?" | "More options" and "?" in the corner, tooltip with the help text on hover, no long gray text at the bottom, two steppers for the minimum/maximum time between waves, Presets / Import wave / Restore defaults in the button row; no overlap | not run |
| 60 | Delete a default wave (two clicks), then Restore defaults (two clicks) | The wave disappears, the list says "1 default waves are deleted"; Restore defaults brings it back and clears your other changes; Presets > Undo last load restores them | not run |
| 61 | Presets: open an empty slot, Load this setup | Default waves load (no "nothing to load"), Undo last load brings the previous setup back | not run |
| 62 | `/rw_pause`, wait, `/rw_pause`; on a client watch the panel | Countdown and fixed timers freeze (HUD "(PAUSED)" on both), resume afterwards. `/rw_next` drops the wave and starts a new timer without spawning. `/rw_stop` removes the panel and stops everything until `/rw_start` | not run |
| 63 | Options: Anti-snowballing on, delay 30 s; let a player die while a wave timer runs | Chat line "a player died, the wave timers are delayed by 30 seconds"; countdown and fixed timers move back 30 s | not run |
| 64 | Spidey Sense off (or absent) and ImprovedHavocTags absent: open a wave with `3 crushers[purple+enraged]`, the picker and the Mods screen | Enemy names coloured per the palette (crusher bright grey, hound bright yellow, bosses red, ...), modifier names in the Havoc Tags colours (purple, red...). With the real mods installed their colours are used | not run |
| 65 | Enemy picker: Random group on, click three enemies, Create group; wave list: change a Cooldown with - / + and by clicking the number | One row "1 random of A / B / C" with each enemy in its own colour; the cooldown column is readable next to the composition and the chance weight; the Mods column keeps its colours when cut; twins show as Melee Twin / Ranged Twin; gunners blue | not run |
| 26 | Recipe text with `@`: `3 crushers[enraged]@2` in "Edit as text" | Accepted, shown as "(+2 per repeat)" in the list | not run |
| 66 | Default options, start a mission, wait for the interval | Mode is "Tarot draw": about 10 s before the wave a hand is dealt (HUD still the old panel until step 3), the wave spawns at 0, a card never appears twice in one hand | not run |
| 67 | Tarot mode with a long cooldown on every card (e.g. 600 s) and `/rw_skip` several times | The picked card is never in a later hand during its cooldown; once all are cooling the state says so and the director retries every 10 s | not run |
| 68 | Two instances (host + client), tarot mode: watch the hand | Both screens get the same hand and the winner the host chose; the wave that spawns is the winner; a 1.x client is refused by the handshake | not run |
| 83 | A card's screen > Card face: click a suit, step the threat, change the whisper, the look and the cooldown | The preview tile in the bottom right follows every change; "Threat N by the numbers" is right for the enemies; the suggested suit is marked; nothing overlaps the buttons or the text; Back returns to the card's screen and the Deck shows the new face | not run |
| 85 | The Deck: hover the ten pips of a card, click one; then look at the other cards | The pips up to the one under the pointer light up, the caption over the strip says "<name>: chance N of 10"; a click sets the chance, the card shows N pips (the likeliest card always ten, the least likely one); the other cards' pips move when the range changes; works on a card out of the draw; no sound tick when sliding over the pips | not run |
| 86 | Right click a tile (face, pips, state line, Edit); click Edit; click a pip twice fast | A right click opens the card's own screen; only the 46 x 16 pill lights up on hover (not a big rectangle); a fast second click on a pip is not lost; the toggle ignores a second click inside the double-click time | not run |
| 87 | Look at the suit marks, dots and threat diamonds on tiles and in the HUD, at 1080p and at a higher resolution | Smoother edges than before (the faint larger copy); the empty diamonds are dim, filled, complete (no gaps anywhere). If the edges still look stair-stepped, or the copy looks like a halo, say which (`Spread.FEATHER`, `FEATHER_ALPHA`); if a filled diamond still has holes, say so (next step: build it from two triangles) | not run |
| 88 | A card with `[garden+enraged]` modifiers on a tile; Mod options > colour enemies off; with Improved Havoc Tags installed | Each modifier name in its Improved Havoc Tags colour (its own setting when installed), plain rust with the colours off, drained on a card out of the draw | not run |
| 89 | Tiles with a one line, a two line and a three line name and five or six enemy groups | The divider follows the name, the composition has 5 / 4 / 2 lines and "+N more" after, nothing runs into the divider, the modifier line or the whisper, the gap under a short name is small but not tight | not run |
| 90 | Card face: scroll to the new suits, pick each; make a card with a Daemonhost | Volley, Snare, Brute, Fester, Dusk, Warp in their colours with their marks on the tile, the HUD and the preview; a Daemonhost card is purple (Warp) without choosing; the four settings stay on the first page | not run |
| 91 | A card's screen: Custom on a crusher row; set Health 300, then spawn it (`/rw_test <key>` in a mission) | The crusher's health bar takes about three times as long to empty; the row and the tile say so ("Health 300%", "Custom"); no console error | not run |
| 92 | Same with Size 200 (host alone, then with a client that has the mod and one that has not) | Twice as big for the host and the client with the mod, normal for the other; shoot its head and body: say whether the hits land where the bigger model is (the hit areas may stay small); does it get stuck in doors? | not run |
| 93 | Run speed 200 on poxwalkers, 50 on hounds | Poxwalkers run twice as fast (and the client sees the same), hounds crawl; the animation keeps up or slides (say which) | not run |
| 94 | Time between attacks 50 on maulers; Gunner fire rate 200 and Shots per burst 300 on gunners | Maulers wait about half as long between swings (the swings themselves are not faster); gunners fire twice as fast and three times as long a burst; also after you hit them with a bleed or a brittleness weapon (the stats are put back on top after every recompute). First test (before the stat hook): health, size, run speed, hit mass worked, the three attack stats did not | the melee stat took effect after the hook (the user saw the chain cut at 250); fire rate and burst not reported yet, re-test them |
| 97 | Time between attacks 40 (x2.5) on a Plague Ogryn; watch its combo | All three hits of the combo come, then it attacks again sooner than normal. Before the fix it stopped after the first hit | not run |
| 98 | The same on a Chaos Spawn (its multi-attack) | The combo is whole | not run |
| 99 | Time between attacks 200 on maulers | They wait about twice as long between swings | not run |
| 100 | A card saved before this version with `{melee=200}` (or typed with "Edit as text") | It shows "Time between attacks 50%" in the Custom screen and behaves as before | not run |
| 102 | A burster with Size 200 (card Custom screen), kill it near you | The danger zone and the blast are both twice as wide (12 m instead of 6); size 50 makes both half. Report if the blast and the zone still differ | not run |
| 103 | Riflemen and gunners with Gunner fire rate 25 and Shots per burst 500, in a mission with a Havoc modifier or any buff on the minions (and one without); let them shoot, then `/rw_tune` | Fire rate 25 shoots four times slower, burst 500 five times the shots (times the Havoc bonus, if any). Console log: "started shooting: speed x0.325 (Havoc) or x0.25 (none), N shots". Before the 2026-10-02 fix the log read x1.3 and 2.25x. Report if the speed or the shots still read the plain game values | not run |
| 101 | `/rw_anim` as host in a mission with a wave unit alive | Chat and console log list the engine's Unit functions about animation / speed / time / scale / rate and each breed's animation variables. Send the console log: it decides whether Animation attack speed can be built | not run |
| 95 | Hit mass 300 on poxwalkers; a cleaving weapon | A swing cuts through about a third as many of them | not run |
| 97 | Open the editor and hover every kind of button: Spreads, More options, Import card, Restore defaults, the - and + of a number, an enemy row's Mods / Custom / Remove | Hover lights the frame and draws two corner brackets just outside it; pressing pulls them in and drops the label a little; Import card is a solid bile button, Restore defaults has a rust frame; the number is one plate with a lit cell under the pointer; no button overlaps another (More options and ? are two buttons) | not run |
| 98 | Open a card of each suit and hover its buttons | The highlights, brackets, stepper values and the OK button take that suit's accent (swarm grey-green, rage rust, warp purple); on the Deck and in Spreads they are bile again | not run |
| 99 | Click Delete on a card, Restore defaults on the Deck | The button turns solid rust and says Sure? for about four seconds, then goes back; a second click inside that time does it | not run |
| 100 | Open a text box (Rename) and the help tooltip | The panel has a thin accent frame with two corner brackets, OK is a solid button on the right with Cancel left of it, no ornamental frame; the title is in the accent | not run |
| 101 | Run the game at 1080p, 1440p and 4k and look at the same screen | One layout in all three, same proportions; lines (button frames, the table rows) are as thin and even at 1440p as at 1080p; text is sharp; the diamonds and triangles have soft edges (the faint copy). Say which resolution shows a problem and where | not run |
| 102 | The titles: Deck, a card's screen, the enemy picker, Mods, Custom, the card face | Tarot, Cauldron (x4), Mirror | not run |
| 103 | A card with Scab and Dreg enemies: a gunner, a Dreg gunner, a flamer, a Tox Flamer, a rager; and the enemy picker with "gunner" typed | The rows say "Gunner  Scab", "Dreg Gunner", "Flamer  Scab", "Tox Flamer  Dreg", "Rager  Dreg"; the picker lines the same; the words are brass (Scab) and soft green (Dreg) | not run |
| 104 | Open a card (the Cauldron): look at the whole screen | The enemy rows on the left, the shelf under them, How it spawns and the action bar under that, the card on the right at 1.4 times its Deck size on a plate in its suit's colours, the quick face under it. Nothing overlaps, no text runs into the next widget, nothing is cut off; at 1080p, 1440p and 4k the same | not run |
| 105 | Click chips on the shelf (a Hound twice, a Gunner, a Mauler), switch to Dreg and click the Gunner again, click the Packmaster and a Vanguard | One more of that enemy each time, the row and the card on the right change at once; a new group appears as the last row; the Gunner is a Scab gunner, then a Dreg gunner after the switch (the row says Gunner Scab / Dreg Gunner); the chip is lit when the card has that enemy | not run |
| 106 | Click different suits, threat diamonds, Auto / By hand, the chance - and + | The card, its plate and every button of the screen take the suit's colours; the diamonds set the threat and the card shows it; Auto works it out again; the chance changes the line under the card | not run |
| 107 | Preview cooldown on a Plague card, a Murmur card and Rain of Rot | The stage card plays its cooldown look through in about five seconds (rot and renewal, the murmur writing itself, the vial filling) and returns to normal | not run |
| 108 | Add a thirteenth group; add enemies until a card has 120; scroll a card with more than five groups (up, down, the wheel) | A message and nothing added; the rows scroll one at a time; the summary line says "N - M of K" | not run |
| 109 | Tabs Enemies | Face, Whisper and cooldown, Back from the picker, Mods, Custom and Face | The tabs switch between the two screens of the card; Back is always at the foot of the left side, never on another button; clicking it does not also click something | not run |
| 110 | Open a card's Face tab (the Mirror): look at the whole screen | Four sections (suit plates, threat diamonds, whisper field, cooldown with three look plates) on the left, the same card on its stage on the right with the toolbar and "In the hand" under it; nothing overlaps or is cut; same at 1080p, 1440p and 4k | not run |
| 111 | Click a suit plate, a threat diamond, Auto and By hand; click Change and type a whisper (and Esc); Use the suit's line | The card on the right, its plate, "In the hand" and the buttons follow every click and every letter; Esc puts the old line back | not run |
| 112 | Choose each look plate; Automatic for this suit; the cooldown - and + (30 s steps), its number box; Preview cooldown | The chosen look has an accent frame, AUTOMATIC marks the suit's own; the clock changes in 30 s steps up to the longest option; the preview plays the look on the card | not run |
| 113 | Reset face on a card whose suit, threat, whisper, look and cooldown you changed | They go back to their defaults, the enemies stay |
| 114 | Custom health under Havoc (an Ultra Havoc / Havoc mission): groups `1 plague ogryn{health=50}`, `{health=150}` and one with no custom health, spawned with `/rw_test_close` | The first has half of its normal health, the second one and a half (the bar number and the damage needed), whatever Havoc adds; the half one says "Weakened", the other does not; the group without custom health keeps Havoc's scaling | not run |
| 115 | `/rw_test_close <card>` in a mission and in the Psykhanium, turning around between casts; with a wall in front; with no argument; as a client | The units appear 3.5-8 m in front of you on the ground, facing you; closer with a wall; the no-argument call lists the cards; a client is told only the host can | not run |
| 116 | Open the Mods and Custom pages of a Plague, a Rage, a Warp and a Heresy card; change the suit on the Mirror | The page (ground, panels, rows, titles, headings) takes the card's colour and follows a suit change at once; the Deck, options and Deck presets stay in the original green | not run |
| 117 | A card with enemies of every kind in the Cauldron; look at the Deck's top button | The shelf chips are smaller and aligned (no D/S), six enemy rows show; the top button says "Deck presets" | not run |
| 118 | Give a card HERESY (the last suit plate); a card that was Fester in an older setup; draw it | Black-red card with a blood-red frame and gilded mark on the Deck, the stage, the hand preview and the Spread (frame at rest, glow); the banner says "Heresy is drawn"; the old Fester card is Heresy | not run |
| 119 | Fill many custom slots (`/rw_custom 88 ...`), scroll the Deck to the end; as a client with many cards with "use everyone's waves" on | 100 cards in all: strip, scrolling, sorting and dragging work, no "waves text too long" in the log, the host draws from the client's cards | not run |
| 120 | Play until a card goes out; join a second player; open Custom HUD; switch the option "Last card" off | A "LAST CARD" window right of the Spread shows the card and its age ("2:34 ago") until the next card; the client sees the same; a sample shows in Custom HUD; the option hides it | not run |
| 121 | The Deck tiles' cooldown row: click `-` / `+`, hover them, click the value, right click, a card out of the draw, a resting card, a fixed-timer card | 30 s a click within the limits, the value previews on hover, the number box takes seconds, a right click opens the card, timer cards say EVERY; nothing overlaps; compositions show one line less; three-line names keep composition clear of modifiers | not run |
| 96 | Share a card with custom mods (Share wave), import it on another machine; "Edit as text" with `{hp 150, run speed 120%}` | The custom mods arrive and show as `{health=150 speed=120}`; an unknown name ("toughness") is refused with the list | not run |
| 84 | Make a card of your own with the blank tile: name it, add enemies, give it a suit | The suggestion matches the enemies; the card appears in the Deck with its tile; share it as text and import it elsewhere: suit, threat, whisper and look arrive (step 1) | not run |
| 81 | Draw a card (`/rw_skip` in a mission), then open the editor | Its tile rests: "Back in" and a clock counting down, the colours grey -> brown -> ochre -> suit colour (rot look), the whisper writing itself and a faint card (Murmur cards), the liquid rising with bubbles (Rain of Rot). Cooldown 30-60 s makes it quick to watch | not run |
| 82 | Keep the editor open until the card is back; Mod options > Ping when a card is back off | A ring leaves the tile, the name flashes, "Ready", then "In the draw"; with the option off nothing but the text change | not run |
| 76 | Open the editor (F6): the home screen | The Grandfather's Tarot: a grid of card tiles (suit mark, name, composition with coloured enemies, whisper, diamonds, dots, ten pips, state line), the strip above, "N in the draw", Spreads / More options / ? at the top right. Nothing overlaps; text does not overflow its box | not run |
| 77 | Click a tile; click its left state line; click Edit | The card goes out of the draw (dimmed, drained of colour, "Out of the draw") and back; Edit opens the card's screen; Back returns to the Deck | not run |
| 78 | The blank tile; a custom card; Delete in a card's screen (twice) | The blank tile opens an empty custom card; a card with enemies gets its tile; Delete asks "Sure?" then removes it and returns to the Deck | not run |
| 79 | More than 14 cards (fill custom slots); scroll buttons beside the grid and the mouse wheel | A row of seven per step, the last page has the blank tile, nothing overlaps the bottom panel | not run |
| 80 | Hover a tile; a card that rests after being drawn (`/rw_skip` in a mission, then open the editor) | Its name shows over the strip and its segment rises; the resting card says "Back in" and a clock | not run |
| 69 | Tarot mode, start a mission, wait for a hand | "Next card in m:ss" at the top centre; a hand of cards with names, suit marks, threat diamonds and dots in the right colours; a shut eye on every card; a fuse that burns and turns rust for the last 5 s; nothing overlaps; no console errors. If a shape is missing or garbled, say which (the suit marks and diamonds are drawn from `circle`, `triangle` and `rotated_rect` passes, never seen in a HUD element before) | not run |
| 70 | Same, watch the pick (`/rw_skip` to hurry) | A highlight ticks across the cards, slows and lands on the card whose wave spawns; the winner rises, its eye opens, the others fade, the banner shows the name, whisper and modifiers; then it rots (browns, blotches, flies, drips) and is gone | not run |
| 71 | Cards drawn 1 and 5; a card with a long name | One card: no roulette, centred; five cards fit the screen; a three-line name makes all cards taller, nothing spills out | not run |
| 72 | A Murmur card, a rare card (one of the two lightest of the draw) | Murmur: half moon in the corner; rare: pus-yellow outline. The twelve suit marks look like what they should (eye, half moon, flame, drop, dots, star, crosshair, linked rings, plated square, boil, setting sun, eye in a triangle) | not run |
| 73 | Mod options > The Spread (your screen): change the sliders (roulette, winner shown, eye, rot) and the eye size | The next hand follows them; a longer cooldown card rots harder and longer; the eye size changes the mark | not run |
| 74 | `custom_hud` edit mode | A sample hand shows; the node can be dragged and keeps its place; there is only ONE draggable box for this mod | not run |
| 75 | Join a running mission as a client during the roulette / the rot | The client sees the same stage at the same moment (the rot already running, not a replay) | not run |

## Adversarial audit follow-up (2026-10-03)

The [offline report](audits/2026-10-03/report.md) supersedes broad acceptance
inferences from the passing recovery checks. Findings were confirmed within
their stated fixtures; current fixes are tracked below and in the
[remediation log](audits/2026-10-03/remediation.md). The live matrix remains open.

| Finding | Offline status | Required remediation / live evidence |
| --- | --- | --- |
| F01 reload event ownership | Fixed on remediation branch; 100-generation owner/weak-reference regression | Real reload/editor/pending-work sessions remain pending |
| F02 disabled spawning | Fixed; disabled updates cannot replay queued work | Native hook/counter behavior, host restart and client resync |
| F03 stop/live ownership | Fixed; stop retains factors, size records and combined alive cap | Native cap, tuning, late-join size and despawn checks |
| F04 aggregate repeat backlog | Fixed; 32 legal timers remain within 64 jobs / 8,000 pending for 10,000 updates | Native frame/memory pressure and practical budget tuning |
| F05 pause | Fixed; 200-second pause freezes real feed/repeat/timeout clocks | Native maintenance and resume without a catch-up burst |
| F06 partial delivery | Fixed; direct fanout exposes failure and retries latest living sizes; actual Realms fixture passes | Native rejection occurrence/ordering, overhead and mixed peers remain pending |
| F07 numeric import | Fixed; nine numeric fields reject NaN/infinity on both runtimes for presets/cards | Native paste/import workflow; finite and legacy formats retained |

## Known risks
- Hooks on `PacingManager.add_aggroed_minion` and the two `MinionSpawnManager` counters must tolerate clients (nil managers) and hot reload.
- Engine query errors: use `get_occluded_positions` / `occluded_positions_in_group` inside pcall (RealmsEvent avoided `get_random_occluded_position`).
- Very large waves: unit/network object limits are real. Current mitigation is per-wave/alive caps and drip-feed, with 1,000 pending entries per job; aggregate work is now capped at 64 jobs / 8,000 pending entries, with skipped admissions/ticks on pressure (F04 remediation).
- Ballot/vote state can go stale if the host leaves mid-vote: clear state on game-state exit and peer-left.
- Host is the only driver; if host has no living humans (ghost host alone), skip and retry.

## Unverified assumptions (check before relying)
1. Whether the shooting-range mission counts as `is_hub` for `BreedLoader` (breed packages). Known since 1.5.4: the Psykhanium (`shooting_range`) has NO main path, so hidden-position search cannot work there; `/rw_test` uses a ring fallback (see CHANGELOG 1.5.4). Whether villains/breed packages exist there is still unverified (matrix row 42).
2. Whether `Managers.connection.combined_hash` mismatches with mods that alter network lookups.
3. (RESOLVED, see below) counter coverage.
4. Whether `mod:hook` on `PacingManager.add_aggroed_minion` is reached for aggro through `MinionPerceptionExtension:aggro()` (call at `minion_perception_extension.lua:349`) in all paths (spawn-time aggro at :133-146).
5. Realms native DLL behaviour (not analysed).
6. `VersusMode.lua` was sampled by grep only, not read fully.

- 2026-09-29 (user report, CRASH): out of memory, `Not enough memory reserved for heap 'lua_heap', reserved: 1073741824, required: 1075838976` (assertion in `heap_allocator.cpp:260`), log `console-2026-09-29-04.44.24-85a45457-9c32-45e0-a2f0-e1f3c500b388.log`. Analysis (the log has FpsDoctor heap readings every 10 s):
  - Timeline: 04:44 game start (mods loaded, RealmsWaves at 04:44:46); 05:00 mission op_no_mans_land (SoloPlay/Realms host), heap floor 261 MB; **05:19:25 and 05:23:58: RealmsWaves and creature_spawner loaded again = two mod hot reloads**; 05:42 floor **515 MB**; heap spikes to 796 MB at 05:44:03 (coincides with a character/profile switch and inventory level load: not RealmsWaves) and 784 MB at 05:45:44 (unidentified); 05:44:32 the ONLY RealmsWaves activity in the whole log, `/rw_test mutants` (heap afterwards stayed 540-600 MB, i.e. the wave did not visibly inflate it); 05:45:59 `creature_spawner` "Despawning all units"; 05:46:00 "Out of memory" message box; 05:46:08 crash needing 1075 MB.
  - Conclusion: NOT proven to be RealmsWaves. Most likely a large baseline (111 mods, plus the floor doubling across two hot reloads) leaving little headroom, then a large transient allocation (unknown source, +250 MB twice before, more at the end) hit the fixed 1 GB Lua heap. Wave units could have added to it (each minion holds Lua state), and RealmsWaves' limits now allow 1000 alive.
  - Things found in RealmsWaves that could add garbage/stack on reload, all fixed in 1.4.2 (see CHANGELOG): unthrottled failed position searches, stale hooks after reload, no memory guard.
  - Still unknown: what allocated the spikes at 05:44:03/05:45:44 and at the crash. Next time, run `/rw_status` (prints the Lua heap) before and after a wave and keep FpsDoctor on; if the heap grows by tens of MB per wave, report the numbers.
- 2026-09-29 (user report): editor opened, but rows showed no hover highlight and (by the user's description) only the row name and the bottom buttons responded. Root cause and fix in CHANGELOG 1.2.1: `visibility_function` receives the hotspot's own content for passes with a `content_id`; flags must be read via `content.parent`. Lesson: when a UI element is "dead", check what table each pass callback receives (`S\managers\ui\ui_widget.lua:411-446`); tests must emulate that, not just call functions with the widget content. In-game re-check pending.
- 2026-09-29: 1.2.0 modifiers implemented and tested offline (see CHANGELOG). Found while auditing buffs: `havoc_toughened_skin` errors outside Havoc (unguarded `extension("havoc")`), hence the Havoc-only gate. Offline only; in-game rows 17-22 pending.
- 2026-09-29: first in-game open of the wave editor CRASHED (log `console-2026-09-29-00.46.55-a45d7909-*.log`): `wave_editor_view.lua:290: attempt to index field 'title_text' (a nil value)` in `_apply_screen` <- `on_enter`. Cause: my `_create_widgets` override shadowed `BaseView._create_widgets` (`S\ui\views\base_view.lua:140-156`, called from `_on_view_requirements_complete` :110-123 to build the static widgets). Fixed in 1.1.2 (renamed `_create_editor_widgets`). Lesson: RealmsEvent avoided this by naming its helpers `_create_row_widgets` etc.; my offline stub had created static widgets itself, hiding the bug. The stub now mirrors the real flow and a guard test lists every BaseView method name (`BASEVIEW_NAMES` in `tools/editor_test.py`, 79 names from base_view.lua) and fails on any accidental override. Lesson for tests: stubs must reproduce the framework's call flow, not shortcut it.

## Test tooling (in `tools/`, needs Python `lupa`; set env `PYLIBS` to the folder installed with `pip install --target`)
- `check_lua.py`: compiles every Lua file (Lua 5.5 via lupa; stricter than LuaJIT).
- Known limitation (1.3.0): spread offsets are not re-checked for line of sight; only the base point is hidden. A large radius can place a unit in view. Also, `Positions.spread` relies on `NavQueries.position_on_mesh(world, pos, 2, 2)` and `ray_can_go(world, a, b, nil, 2, 2)` with no traverse logic (`S\utilities\nav_queries.lua:7-25, 91+`); untested in the game.
- Known risk (1.4.0): 500 units per wave / 1000 alive were requested; nothing in the mod prevents it, but the engine (unit count, network objects, frame time) may not cope. Untested.
- `logic_test.py` (147 checks; was 62 in 1.2.0): recipe parser (incl. `a|b`, caps, round trip, modifiers `[a+b]`), wave settings API (`Events.get/set_def/reset/build_pool`, legacy recipe), votes, director state machine (random, vote, 5 s interval, hub, client, version mismatch), budget-bypass hooks, the spawner `execute.lua` with stubbed game APIs (expansion, modifier buffs, Havoc gating, contained buff errors, caps, `one_of`), 20,000-roll weight simulation.
- `editor_test.py` (106 checks; loads the game's real `callback()` from the source clone, mirrors the real BaseView flow and guards against overriding BaseView methods): loads the REAL editor view/blueprint/component files against stubbed engine classes (fake `BaseView`, `UIWidget.create_definition`, text-input template) and clicks through list, scroll, toggle, chance stepper, detail, count stepper, remove, picker, rename popup, recipe popup with validation, numeric popup with range check, cooldown, enabled, reset, back navigation, custom-slot workflow. It cannot prove the engine renders or accepts the passes; it does catch nil-index/logic bugs.

## Resolved during implementation
- Unverified #3 (counter coverage): grep of the game source (commit `0f0cb45`) shows every reader of the enemy counts goes through `MinionSpawnManager:num_spawned_minions()` or `:total_allocated_num_enemies()` (terror_event_manager.lua:435, pacing_manager.lua:449, horde_pacing.lua:79 and :516, auto_event.lua:509 and :689, server_metrics_manager.lua:178); the private field `_num_spawned_minions` is only touched inside minion_spawn_manager.lua. So hooking those two methods is complete for this version.
- `SpawnPointQueries.group_from_position(nav_world, nav_spawn_points, position, above, below)` takes `nav_world` FIRST (spawn_point_queries.lua:265), unlike `occluded_positions_in_group(nav_world, nav_spawn_points, group, positions)`. `get_occluded_positions` filters by distance to EVERY player (max distance must be satisfied for all players), which is why RealmsWaves does its own nearest-player filtering.
- DMF hooks by class-name string are queued until the class exists (`hooks.lua` delayed hooks), so hooking `PacingManager` / `MinionSpawnManager` at load is safe.
- Aggro happens inside `spawn_network_unit`, before `spawn_minion` returns the unit, so the bypass uses a "spawning" flag (`Bypass.begin_spawn/end_spawn`) to catch the unit in `add_aggroed_minion`.

## Known trade-offs of the bypass
- **Stimmed minions Havoc condition does not apply to wave units** (found 2026-09-28): the bypass skips `PacingManager.add_aggroed_minion`, which is also where the `minion_aggroed` event that `MutatorStimmedMinions` listens for is fired. Details in doc 03, "Havoc conditions / mutators vs. wave units". FIXED in 1.1.1 (hook re-sends `minion_aggroed` for tracked units); offline test `bypass:*` in `logic_test.py`; in-game check still pending (needs a Havoc order with stimmed minions).
- Skipping `PacingManager.add_aggroed_minion` for wave units also skips `side_system:add_aggroed_minion`, so wave units are absent from the side's aggroed lists. Those lists feed music intensity (`wwise_state_group_*`) and terror-event queries (`TerrorEventQueries.num_aggroed_minions_in_level`). Effect: wave units do not raise the combat music intensity or count for scripted "N enemies aggroed" conditions. Accepted; revisit if it looks wrong in play.
- Positions use `side.valid_player_units` (includes bots). LOS is hidden from bots too, which is harmless.

## Results log

Moved to [06-results-log.md](06-results-log.md) on 2026-10-04 (doc 06 had reached the 100 KB limit).
