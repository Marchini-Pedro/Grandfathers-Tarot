# Workshop recovery and review (2026-10-03)

Remote baseline: `Marchini-Pedro/Grandfathers-Tarot`, `main` at
`1460711a046f3d8949e5546335a296fd4216c5f3`.
The supplied `RealmsWaves_updated` repository is a direct descendant: 25
additional commits through `6b95382`, with no remote-only commits. Those
commits are preserved on `feature/workshop-recovery`. The supplied copy's
origin points to a different repository (`The-grandfather-s-Tarot`);
the recovery clone uses the repository requested by Eduardo.

The recovered history implements the Cauldron/Mirror workshop redesign,
enemy shelf and factions, scalable live card previews, attack timing and
gunner stat fixes, custom boss health naming, and one random enemy choice
per group retained through a wave's repeats.

Eight uncommitted files add Deck sorting (threat, rarity, enemy count,
face), persistent card order, and hold-to-drag swaps within the visible
page. They are preserved as received before review fixes. No sorting or
drag regression tests accompanied these edits. Validation is pending.

The original supplied folder is untouched. Remote `main` stays at the
baseline until the feature has been confirmed in game, as required by
the supplied project's process rules. Eduardo authorized committing and
synchronizing the recovery branch with GitHub; his account has push
permission. Offline validation cannot establish engine frame time,
rendering correctness, or multiplayer behavior in a real mission.
