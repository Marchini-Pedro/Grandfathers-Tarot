# Workshop recovery and review (2026-10-03)

Current status: [PR #1](https://github.com/Marchini-Pedro/Grandfathers-Tarot/pull/1)
merged the recovery into `main` at `64f76f3` on 2026-10-03. The remote recovery
branch was deleted. The recorded recovery checks passed; the subsequent
[adversarial audit](audits/2026-10-03/report.md) identified seven baseline defects
and two surviving mutation gaps. The approved [remediation](audits/2026-10-03/remediation.md)
fixes all seven and closes both gaps offline on a separate feature branch.
The game checks below remain open. No new release or runtime version bump accompanied the merge.

Remote baseline: `Marchini-Pedro/Grandfathers-Tarot`, `main` at
`1460711a046f3d8949e5546335a296fd4216c5f3`.
The supplied `RealmsWaves_updated` repository is a direct descendant: 25
additional commits through `6b95382`, with no remote-only commits. Those
commits were preserved on `feature/workshop-recovery` and are now in `main`. The supplied copy's
origin points to a different repository (`The-grandfather-s-Tarot`);
the recovery clone uses the repository requested by Eduardo.

The recovered history implements the Cauldron/Mirror workshop redesign,
enemy shelf and factions, scalable live card previews, custom boss health naming, and one random enemy choice
per group retained through a wave's repeats.

Eight uncommitted files add Deck sorting (threat, rarity, enemy count,
face), persistent card order, and hold-to-drag swaps within the visible
page. They are preserved as received before review fixes. No sorting or
drag regression tests accompanied the supplied edits; the checks and fixes
described below complete their offline validation.

The original supplied folder is untouched. Recovery was prepared on a feature
branch for review under the supplied project's process rules; the PR is now
merged, as reported by Eduardo and confirmed in remote history. Eduardo authorized committing and
synchronizing the recovery branch with GitHub; his account has push
permission. Offline validation cannot establish engine frame time,
rendering correctness, or multiplayer behavior in a real mission.

Harness repair: all six tools now validate this checkout. Lua 5.5 and LuaJIT 2.1 pass the existing checks (30 compiled files, editor 650, entry 14, HUD 179, logic zero failures). Editor tests require the adjacent Darktide-Source-Code clone for the real engine callback helper. LuaJIT heap checks exclude compiler allocations; game frame time remains unmeasured.

The supplied repo also has feature/attack-timing at c7141cb, with nine commits absent from the workshop branch. Both histories are integrated into the recovery feature branch. Conflict resolution preserves the boss-name hook, stat hooks on both buff classes, combo protection, explosion scaling, and both sets of regression tests.

Deck completion: persistent stable sorts and page-local swaps now have 44 new editor checks. Fixed stale-target drops, page/screen/reload cancellation, lost cursor, accidental unarmed releases and double-toggle behavior. Mutation tests detect reintroduced outside-drop, scroll and double-click bugs. Stubbed idle editor updates are about 0.006-0.007 ms and below 1 byte per update (interpreted heap measurement; no engine or renderer).

Runtime fixes: repeat queues now stay at 1000 per job, prepend with linear work, and skip overdue full-queue ticks in one step. Scale queues deduplicate ids, keep the latest arrival, defer missing handles, retry transient errors and remove completed entries in constant time. Failed sends retry current live sizes at the next cadence. Protocol rejects client-spoofed host messages. A minion stat reset marker fixes numerical collisions while preserving post-hook idempotence. Reintroducing the cap, stale-scale or numeric collision bugs fails regressions.

## Limits and next game checks

- Run a two-player Realms mission with the same recovered revision on both peers: late join, disconnect/rejoin during sized waves, repeated random groups, Havoc gunner fire/burst, high-speed boss combos, scaled burster blast, and mission restart.
- Check Deck sort persistence and drag/click behavior at multiple resolutions with real engine input, especially mouse leaving the window, scrolling, popups and cooldown animation. Offline widget previews do not render game fonts, textures or clipping.
- Real engine CPU/frame time, renderer cost and process RAM remain unmeasured. The recorded editor numbers are stubbed interpreted Lua timings and heap growth only. UI models and the HUD update in place; previews/repaint operations still allocate during explicit interactions/animation.
- (Updated 2026-10-03 on `feature/heresy-card-and-ui-pass`: the boss-health naming suppression was removed at the user's request; a custom health is now set exactly after the spawn and a boss below its normal health is called "Weakened" by the game on every machine, see `07`.) Size replication requires RealmsWaves on each peer; players without it see normal size. This existing presentation limit remains open and should be checked before adding a new metadata RPC.
- Animation speed itself has no confirmed per-unit API; the recovered option changes time between attacks, with protection for multi-hit chains, and /rw_anim remains a diagnostic.

The supplied folder and installed mods are preserved. Use this clone for future development; local `main` was synchronized with `origin/main` after the merge. The merge itself does not establish in-game verification.

Final validation (2026-10-03): all six tools pass on both Lua 5.5 and LuaJIT 2.1: 30 compiled files; 764 logic, 694 editor, 18 entry and 179 HUD checks (1655 assertions per runtime); 13 Markdown files below 100 KB. In-game and actual CPU/process RAM testing remain open.

## Subsequent adversarial evidence (2026-10-03)

The passing recovery results above apply to their tested paths: 1,000 is a
per-job queue bound, newest size means newest arrival, and the send retry
fixture rejects the entire call. The [audit report](audits/2026-10-03/report.md)
adds aggregate pressure, actual dependency partial-send behavior, event-manager
ownership and control lifecycles that those tests did not cover. It also finds
LuaJIT-only non-finite import acceptance. These findings are not yet fixed;
the report and live checklist define follow-up acceptance. Only Markdown and
isolated ignored diagnostics were written during the audit.
