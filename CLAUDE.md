# GrandfathersTarot (Darktide mod)

Read `README.md` and `docs\README.md` first, then `docs\04-design-and-rationale.md` and `docs\05-implementation-plan.md`.

## Standing rules (from the user)
1. **Keep the docs current, continuously.** Every change to code, behaviour, settings, protocol, or a finding must be reflected in `docs\` in the SAME work session, before you report back: update the affected findings/design docs, tick or add items in `docs\05-implementation-plan.md`, and append a dated line to the results log in `docs\06-results-log.md` (what changed, why, what was or was not tested). Add a `docs\CHANGELOG.md` entry per commit. Never leave docs describing old behaviour.
2. **Branches and commits (set by the user 2026-10-01).**
   - Every new feature (and every batch of fixes to a feature the user has not yet confirmed) lives on its own branch `feature/<name>`, created from an UP-TO-DATE `main`: `git fetch origin`, make sure `main` equals `origin/main`, then `git switch -c feature/<name>`. Docs-only or process fixes may go straight to `main`.
   - Separate coherent sets of changes into well-delimited commits (a fix, a rename, a new option, the tests, the docs are not one blob). Small commits, clear messages. Commit messages go through `git commit -F <file>` (no BOM).
   - **Merge a feature branch into `main` only after the USER confirms the feature works 100 percent in game.** Until then the branch stays open and later fixes go on it. Never merge on your own judgement, even when all offline tests pass.
   - Git is at `C:\Program Files\Git\cmd\git.exe` (may not be on PATH). Use the configured repo-local identity. Check `git remote -v` and authenticated push permissions; do not assume repository ownership or visibility. Remote: `https://github.com/Marchini-Pedro/Grandfathers-Tarot.git`.
   - **Keep local and remote in sync (set by the user 2026-10-04).** Push each commit to `origin` right after it is made (the user's session limit can end a session at any moment; work that exists only locally is lost to the team). Never end a turn with unpushed commits; say what was pushed. A commit you cannot push yet (no permission, hook failure) must be reported, not left silently.
   - **Fetch before coding (set by the user 2026-10-04).** Before any substantial change: `git fetch --all --prune`, then compare the current branch with its upstream and `main` with `origin/main` (`git status -sb`, `git log HEAD..@{u}`), and pull (fast-forward) anything newer. List `git branch -r` and check for another branch already working on the same feature (the user works with a friend); if one exists, stop and ask before duplicating it.
3. **Record what you learn, in .md files**: every attempt and error, discovery, actionable gap and insight goes into `docs\07-learnings-and-gaps.md` (dead ends too, with what was tried), besides the CHANGELOG and the results log (`docs\06-results-log.md`, split from doc 06 on 2026-10-04). **Keep every .md under 100 KB**: `python tools\check_docs.py` lists sizes and fails at 100 KB; when a file reaches it, split it into granular files (keep the old name as the index).
4. **Tests must be extensive and meaningful, including the edge cases that can emerge in a real game**: a player joining mid-match, a non-host player crashing, leaving or dying, players with different mod combinations (GrandfathersTarot missing, older version, other mods hooking the same functions), host-only code running on a client, a unit despawning or dying in the middle of an effect, nil targets, restarts and hot reloads. When you add a feature, add tests for these, not only for the happy path.
5. Do NOT re-audit TwitchVersus, RealmsEvent, VersusMode, Realms or the game source. Their findings are in `docs\01`-`03` with file:line citations. Only re-check when a doc's audited version (see `docs\README.md`) no longer matches the install; then fix the doc in place. (New questions about game behaviour that the docs do not answer are fine to look up; write the answer into the docs.)
6. Never edit `mods\TwitchVersus` or `mods\RealmsEvent` (Vortex-managed). Copy code from them instead.

## README maintenance

- Review the root `README.md` in the same session as any change to user-visible
  behavior, settings/defaults, installation, dependencies, commands,
  compatibility, release status or known limits. Include necessary README
  edits with the corresponding change; internal changes need no cosmetic edit.
- Keep the README useful to a new player: short description and development
  status, main features, requirements/install, first use, essential commands,
  current limits and links for contributors. Aim for about 120 lines; clarity
  and essential caveats take priority over an exact count.
- Edit the existing section and remove superseded or redundant text. Combine
  overlapping bullets, use tables for comparisons, and link detailed option
  references, audits, test counts and release history instead of copying them.
  Do not append a "What's new" section for every commit or release.
- Keep `docs\README.md` a compact technical index. Put change history in
  `docs\CHANGELOG.md`, current work in doc 05, verification in doc 06 and
  discoveries in doc 07. Preserve useful details in the appropriate document
  before removing their only explanation from a README.
- Verify names, defaults, commands, paths and versions against code/metadata.
  Check relative links and snippets. Distinguish implementation, offline tests,
  in-game acceptance, merge status and published releases; none implies another.
  Do not copy machine-specific paths or old branch status as current guidance.

## Practical notes
- For an explicitly requested deep audit, use `docs\audits\adversarial-audit-prompt.md`. Its default scope is investigation and Markdown reports; proposed code fixes require a later instruction. Do not execute the brief merely because it is linked here.
- Game source clone for reference: `..\..\Darktide-Source-Code\scripts\` (relative to this folder).
- Lua for the Darktide Mod Framework (DMF). Lessons learned in-game are in the results log (e.g. never put a bare `%` in DMF localization text; DMF runs all localized strings through `string.format`).
- Run `python tools/run_tests.py --runtime lua55 --output-dir test-results/lua55` and `python tools/run_tests.py --runtime luajit21 --output-dir test-results/luajit21` after every change. Install pinned dependencies with `python -m pip install -r tools/requirements-test.txt`. The runner discovers all `*_test.py` harnesses, compiles Lua, checks documentation sizes and enforces [coverage floors](docs/10-ci-and-coverage.md). Individual legacy scripts remain runnable: `check_lua.py` (compile), `logic_test.py`, `editor_test.py`, `entry_test.py` (loads the real entry script with stubs), `hud_test.py` (the wave HUD: arithmetic, widget definitions, the element driven through a whole draw, an audit of every pass it would draw, allocation per frame). `hud_preview.py` and `deck_preview.py` (not tests) draw the Spread's shapes and the Deck's tiles into PNGs so they can be looked at without the game (need Pillow; the Deck one reads the JSON that `DECK_DUMP=<file> python tools/editor_test.py` writes; `HOTSPOTS=1` outlines the click areas). `ui_preview.py` (not a test) draws ANY screen of the editor from the real widgets: `UI_DUMP_DIR=<existing folder> python tools/editor_test.py` writes one JSON per screen (deck, detail, detail2, picker, mods, face, popup, settings, presets), `python tools/ui_preview.py <dir>/detail.json out.png [--scale 2]` draws it. Look at a screen with it after every layout change: it found overlaps and clipped text the tests did not. A failed check is also written to stderr at once, so a harness crash cannot hide it.
- Offline checks use repository-owned fixtures and need no installed game, Realms mod or sibling source clone. `RW_LUA_RUNTIME` selects `lua55` (default) or `luajit21` for individual scripts. `PYLIBS` remains an optional explicit Python dependency path. Coverage uses Lua line hooks with LuaJIT tracing disabled; allocation probes suspend the hook and restore its prior state.
- The game's console logs are in `%APPDATA%\Fatshark\MicrosoftStore\Darktide\console_logs`; check the newest one after the user reports a problem.
