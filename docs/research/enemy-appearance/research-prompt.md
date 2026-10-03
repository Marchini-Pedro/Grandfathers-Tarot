# Enemy appearance research prompt

Investigate feasible ways to recolour or visually tint the entire body of selected enemies in Grandfather's Tarot, a Darktide mod whose internal name is **RealmsWaves**.

This is a reusable research brief. Preparing or reading this file does not itself execute the investigation.

## Scope and workspace

Project:

`C:\XboxGames\Warhammer 40,000- Darktide\Content\mod_creations\Grandfathers-Tarot`

Installed mods:

`C:\XboxGames\Warhammer 40,000- Darktide\Content\mods`

Game source reference:

`C:\XboxGames\Warhammer 40,000- Darktide\Content\Darktide-Source-Code`

Another Codex session is actively making significant architecture improvements and bug fixes. Your task is a separate research and documentation effort. Investigate thoroughly, but do not modify runtime code, installed mods, dependencies, shared documentation, Git branches, or the other session's work.

Write your findings into two dedicated Markdown files under:

`docs/research/enemy-appearance/`

If that destination already contains relevant work, preserve it and build on it without overwriting unrelated changes. Preserve this reusable prompt. Keep any required updates to shared documentation in the handoff for the coordinating session.

Record the project and source revisions you inspect. If relevant files change during the investigation, distinguish the snapshots rather than attributing findings to an inconsistent version.

## 1. Understand the objective and existing evidence

My friend reports that applying stim effects can change enemy colour, but the visible effect appears to cover mostly the upper body. We want to investigate an alternative that recolours, tints, or overlays the whole enemy.

Treat this observation as a reported result, not a confirmed diagnosis. We do not yet know whether the limitation comes from the shader, a texture mask, material compatibility, mesh coverage, attached equipment, or how the effect is applied.

The preferred outcome is:

- A configurable colour for an individual enemy or a selected wave/group.
- Coverage of head, torso, arms and legs, with explicit findings about armour, clothing, shields, weapons and other attached meshes.
- Unselected enemies remain visually unchanged.
- Appearance changes do not require gameplay buffs or changes to enemy stats.
- Effects can be removed cleanly.

Distinguish actual surface recolouring, additive tint/emission, translucent overlays, silhouette fills, outlines and particle effects. Alternatives are useful, but do not describe an outline or aura as full-body recolouring.

Read applicable project guidance and existing findings first. Relevant starting points include:

- `CLAUDE.md`
- `README.md`
- `docs/README.md`
- `docs/03-findings-realms-and-game-source.md`
- `docs/04-design-and-rationale.md`
- `docs/05-implementation-plan.md`
- `docs/06-verification-and-open-issues.md`
- `docs/07-learnings-and-gaps.md`

Existing documentation contains leads involving `stimmed_color`, material setters, visual-loadout overrides and network lookup constraints. Re-check the relevant claims against the available source version; do not repeat a broad audit of systems already documented.

The existing `scripts/mods/RealmsWaves/catalog/colors.lua` concerns UI/name colours. Do not mistake a UI colour setting for evidence that enemy models can be recoloured.

## 2. Research across multiple sources

Investigate:

- The local Darktide source checkout.
- Installed mods and their implementations.
- Public GitHub repositories, issues and discussions.
- NexusMods descriptions, changelogs, comments and available source.
- Darktide modding documentation, forums, Reddit and technical discussions.
- The Darktide Modders Discord, using the access investigation in section 2A.
- Relevant Fatshark/Stingray engine references when they help explain an API or rendering limitation.
- Other credible resources discovered through these references.

Use community posts to discover leads, then verify implementation claims against source or reproducible evidence wherever possible.

If sub-agents are available, delegate independent read-only investigations of game source, installed mods and web/Discord references. Have one agent consolidate the two final documents to avoid conflicting edits.

Record source revisions, mod versions and research dates. Explain mismatches between current web information, installed mods and the local source snapshot. Do not treat an inaccessible page or missing asset as evidence that a method cannot work.

## 2A. Investigate knowledge from the Darktide Modders Discord

Include the public Darktide Modders Discord as a potential research source. Investigate whether its relevant discussions can be searched through available tools, supported APIs, public archives, or existing authorized access.

A publicly joinable server is not necessarily anonymously readable or indexed by search engines. Establish which access routes actually work before assuming you can search its messages.

The user's supplied screenshot identifies these promising channels:

- `#making-mods`
- `#reverse-engineering-bundles`
- `#dmf`
- `#creation-showcase`
- `#mod-requests`
- `#mod-bugs`
- `#using-mods`
- The visible Realms Server thread, if relevant.

Confirm their current names and availability. The screenshot does not establish server/channel IDs or access for this agent. If the screenshot is not available in this session, treat the list as user-provided leads.

### A. Try practical access routes

Work through the routes available in this environment:

1. **Public web discovery.** Search for discussions, published archives, GitHub issues, documentation, NexusMods comments and Reddit posts that quote or link relevant Discord discoveries. Follow referenced repositories and code snippets.

2. **Existing connectors or integrations.** Inspect available tools for a Discord connector or an existing authorized integration. Determine what it can actually search/read; do not assume such a connector exists or covers this server.

3. **Existing browser/UI access.** If suitable browser tools and an authorized signed-in session are available, inspect the server and use its native search within the supported workflow. The screenshot alone does not establish an accessible session. Read relevant pins, replies and threads around search hits.

4. **Supported API access.** Check current official Discord documentation and existing authorized credentials/integrations. Relevant documented routes include:

   - `GET /guilds/{guild.id}/messages/search`
   - `GET /channels/{channel.id}/messages`
   - `GET /channels/{channel.id}/messages/{message.id}`

   Verify authentication, bot installation/access, `VIEW_CHANNEL`, `READ_MESSAGE_HISTORY` and applicable `MESSAGE_CONTENT` requirements. Use targeted queries and bounded pagination; respect rate limits.

   Check whether an approved OAuth2/local RPC integration is genuinely available. Do not confuse the `guilds` scope with message-history access, or `messages.read` with a general-purpose REST permission.

   Use supported authentication. Do not extract personal Discord tokens, build a self-bot, or attempt to bypass access restrictions.

5. **User-provided material.** If direct access is unavailable, identify the smallest useful input: message links, copied discussion excerpts, relevant attachments, or an existing authorized export. Analyse any supplied material and follow its technical references.

Do not build or install a new integration merely to complete this research. If a route needs unavailable credentials, server-admin installation or additional approval, record that prerequisite and continue through the other routes.

Verify current behaviour against these official references before attempting API access:

- [Discord Message Resource: search and history endpoints](https://docs.discord.com/developers/resources/message#search-guild-messages)
- [Discord OAuth2: scopes and bot authorization](https://docs.discord.com/developers/topics/oauth2)
- [Discord Permissions](https://docs.discord.com/developers/topics/permissions)
- [Discord Rate Limits](https://docs.discord.com/developers/topics/rate-limits)
- [Discord native search](https://support.discord.com/hc/en-us/articles/115000468588-How-to-Use-Search-on-Discord)
- [Discord's guidance on automated user accounts](https://support.discord.com/hc/en-us/articles/115002192352-Automated-User-Accounts-Self-Bots)

### B. Search systematically

Begin with exact symbols already found in the local source:

- `stimmed_color`
- `Unit.set_vector3_for_materials`
- `override_slot`
- `minion_visual_loadout_extension`
- `mutator_minion_visual_override`

Then expand to related terminology:

- Enemy/minion recolour, recolor, tint, full body.
- Shader, material, material instance, material parameter.
- Texture mask, emissive, glow, overlay.
- Outline, highlight, silhouette, stencil.
- Mesh, submesh, attachment, armour, equipment, LOD.
- Visual loadout, cosmetic override, resource/package loading.
- Havoc, stim/stimm, rotten armour/armor, corrupted enemies.

Look for unsuccessful experiments, engine limitations and corrections as well as working implementations. Search historical and recent discussions; a useful technique may predate the current patch.

Where native Discord search is available, try focused queries such as:

- `in:making-mods stimmed_color`
- `in:reverse-engineering-bundles shader`
- `in:dmf material`
- `in:creation-showcase recolor`
- `in:making-mods tint has:file`
- `in:making-mods material has:link`

Run variants separately and adapt to the terms used by participants. Expand from useful hits to surrounding replies, linked threads and code.

Search for AI-assisted mod experiments and discoveries too, but evaluate them using the same evidence standards. An AI-generated API name or an unexecuted snippet is a lead, not proof.

### C. Turn discussions into verifiable findings

For each useful discovery, record:

- Channel/thread and discussion date.
- Message permalink, when available.
- Concise technical claim and relevant context.
- Referenced mod, repository, file, API or attachment.
- Whether it was proposed, attempted, demonstrated, corrected or abandoned.
- Applicable game/mod versions.
- Whether local source or an independent implementation corroborates it.
- The next experiment needed if it remains uncertain.

Follow discussions to their latest relevant correction or resolution. Distinguish a working result from speculation and preserve contradictory evidence. Search snippets alone are insufficient to establish success.

Preserve technical content and necessary attribution; avoid copying unrelated conversation. Note when a Discord citation requires membership to view, and link a public implementation when one exists.

### D. Handle access failure usefully

Add a "Discord research coverage" subsection to `findings.md` describing:

- Access routes attempted and their actual outcomes.
- Channels, queries and date ranges covered.
- Authentication, permission, indexing or tool limitations.
- Whether each result came from Discord directly or a secondary reference.
- Specific queries or message inputs that would close the remaining gaps.

Do not claim the server contains no relevant knowledge because you could not access it or a limited search returned no results.

Continue the local-source and public-web investigation if Discord is unavailable. Include promising Discord-derived leads in the existing recommendations and experiment plans, keeping the two-document research deliverable.

## 3. Trace why the stim effect has partial coverage

Follow the actual path from effect activation to the visible result:

- Buff or mutator activation.
- Visual/material parameter application.
- Which unit, materials and attached units receive the parameter.
- Mesh creation, visual loadout and equipment attachment.
- Updates, resets and competing effects.
- Shader or material definitions, if accessible.

Investigate whether:

- Only certain materials support the parameter.
- A shader mask restricts where it appears.
- Lower-body meshes or equipment are separate units.
- A setter's recursive option reaches every relevant attachment.
- Materials are applied or replaced after the colour is set.
- LOD changes or other effects overwrite the result.

Do not assume that repeating the same setter on more meshes will overcome a shader mask. If shader or asset data is unavailable, identify the exact missing evidence and the smallest experiment that would resolve the question.

## 4. Explore and compare candidate methods

Investigate these as hypotheses, not presumed supported features:

- Existing per-unit or per-material colour parameters.
- Material-instance overrides, including whether instances are shared between enemies.
- Existing alternative materials or visual-loadout variants.
- Reusing the visual portion of an existing effect without its gameplay behaviour.
- Existing outline/highlight systems, including any filled-silhouette modes.
- Existing overlay, emissive or damage/status-effect rendering paths.
- Effects applied separately to body parts and attached equipment.
- Pre-existing cosmetic or asset variants that approximate the desired appearance.

Also consider less conventional approaches where there is a credible engine or source basis: decals, mesh overlays, secondary passes, attached visual shells, texture/material replacement or stencil/post-processing selection.

For each method, establish:

- The concrete API, symbol, hook or existing implementation.
- Whether ordinary mod Lua can access it.
- Whether suitable materials/resources exist and can be loaded.
- Whether it accepts arbitrary RGB colours or only predefined variants.
- Whether it covers the whole body and equipment.
- Whether it can target one enemy without affecting others.
- Whether it preserves textures and lighting.
- Whether it supports dark colours, especially black, rather than only added glow.
- Whether it requires new assets, native functionality or engine changes.
- Its likely complexity, performance cost and maintenance burden.

An API's existence does not prove that an enemy material supports it. A plausible parameter name is not a verified shader parameter.

## 5. Account for lifecycle, multiplayer and compatibility

Evaluate:

- Host versus client responsibilities.
- Local appearance versus appearance visible to every player.
- Whether all peers need the mod.
- Clients without the mod or using different versions.
- Late joins and unit creation/registration timing.
- Resource/package loading on each peer.
- Existing network lookup and RPC constraints; do not assume custom replicated names are safe.
- Death, despawn, unit pooling if present, mission changes and mod reload/disable.
- Restoration of previous appearance and interaction with other effects that write the same parameters.
- LOD changes, dismemberment, ragdolls and attached equipment.
- Conflicts with marking, highlighting or visual mods.
- Horde-scale costs, including material duplication and per-frame updates.

Prefer existing per-unit mechanisms and event-driven changes when they satisfy the requirements. Distinguish measured costs from estimates.

## 6. Define small experiments without changing the live mod

For the strongest candidates, provide a minimal, reversible proof-of-concept plan:

- Exact entry point and prerequisites.
- Referenced APIs and a short snippet or pseudocode.
- A known working baseline and an untreated control enemy.
- Expected result and clear failure criteria.
- Cleanup/restoration steps.
- Logs, screenshots or observations needed to judge the result.

Label unexecuted snippets and experiments clearly. Put proposed snippets in the research documents; do not install or execute them as part of this research-only task.

Include a compact validation matrix covering representative humanoids, heavily armoured enemies, shielded enemies, non-humanoid enemies and bosses; body/equipment coverage; different lighting and viewing distances; and host/client visibility.

The plan must verify that a successful visual experiment does not unintentionally change gameplay behaviour.

Do not claim in-game success from static source inspection or an offline stub test.

## 7. Produce two useful documents

Write `docs/research/enemy-appearance/findings.md` with:

- A short conclusion and current confidence.
- The stim-effect trace and explanation of partial coverage, or unresolved hypotheses.
- Local and web evidence with file:line references, symbols and direct URLs.
- Discord findings and the Discord research coverage subsection.
- A comparison table of candidate methods.
- Distinct labels for reported observations, source-supported findings, in-game verified results, hypotheses and unknowns.
- Relevant dead ends and what evidence rules them out.
- Version limitations and unanswered questions.

Write `docs/research/enemy-appearance/experiments-and-recommendation.md` with:

- Ranked recommendations with reasons.
- The smallest credible route to the preferred outcome.
- An explicit statement if full-body surface recolouring remains unproven.
- Useful fallback appearances and how they differ from the preferred result.
- Minimal experiment plans and the validation matrix.
- Lifecycle, multiplayer and resource-loading requirements.
- Suggested integration points for the agent changing RealmsWaves.
- A handoff list of existing documentation that should later be updated by the coordinating session.

Keep each Markdown file under the project's 100 KB limit. Use relative links between documents and precise, dated references. Leave existing shared docs untouched during this parallel investigation. Run the documentation size check after writing the reports.

Be broad in discovery and detailed on the strongest candidates. Do not force a positive conclusion: a well-supported limitation, accompanied by a practical fallback or decisive next experiment, is a useful result.

Finish with a brief summary identifying the most promising approach, the largest unresolved question, the first experiment to run, Discord access/coverage, and links to both research documents.

