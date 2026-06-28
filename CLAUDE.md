# CLAUDE.md

How work gets done in this repo. **Read this file, and anything it points you to, in full — do not skim.**

## Orientation — read before touching code

**Bruno** is an additive, **tvOS-only** fork of Swiftfin (the Jellyfin SwiftUI client) for one private home
library. Before changing anything, read these in full (no skimming):

- **`docs/BRUNO_CODE_MAP.md`** — architecture, the Home data-flow pipeline, key-files index, "where do I
  change X", and the documentation map.
- **`docs/BRUNO_NAV_MAP.md`** — every tvOS surface and, per shelf, its data source · title · "show all"
  destination. Read before touching any shelf, pathway, or routing.
- **`docs/PROJECT_TRACKER.md`** — current status (the heartbeat). **`BRUNO_NOTES.md`** — verified
  toolchain / SDK signatures / architecture (wins over older plans on drift).

**Docs are tiered:** `docs/` = canonical & active · `docs/reference/` = stable specs ·
`docs/archive/` = superseded (do not treat as current).

**Where code lives:** Bruno UI in `Swiftfin tvOS/Views/BrunoHomeView/`, engine in `Shared/Objects/Bruno/`;
everything else is upstream Swiftfin — reuse, don't refactor. **One connected pipeline:** a shelf is a
seeded descriptor (`BrunoHomePlan`) → realized to a paging VM (`BrunoHomeViewModel`) → rendered
(`BrunoShelfView`/`PosterHStack`); all "show all" routing funnels through `brunoRouteToShowAll()`. Trace a
change through the maps first — local edits ripple.

**Agents:** Swift/SwiftUI/Xcode mechanics → `swift-xcode-expert`; "where/how does Bruno do X" → `bruno-expert`.

**Workflow:** Work in a worktree → open a PR; the owner merges. Don't push `main` directly. Keep edits in
the worktree (so the desktop app's file links resolve).

## 1. Think before coding
State assumptions; if uncertain, ask. Multiple interpretations → present them, don't pick silently.
Simpler approach exists → say so, push back when warranted. Unclear → stop, name it, ask.

## 2. Simplicity first
Minimum code that solves the problem; nothing speculative — no unrequested features, abstractions,
configurability, or handling for impossible cases. If 200 lines could be 50, rewrite it. "Would a senior
engineer call this overcomplicated?" → simplify.

## 3. Surgical changes
Every changed line traces to the request. Don't improve / refactor / reformat adjacent code that isn't
broken; match existing style. Remove orphans **your** change created; leave pre-existing dead code
(mention it, don't delete).

## 4. Goal-driven execution
Turn the task into a verifiable goal and loop until met ("fix the bug" → write the failing test first,
then make it pass). Multi-step work → state a brief plan with one verify step each. Report real results;
never claim green you didn't see.

## 5. Commit at high resolution
Commit early and often — **one logical change per commit**, message saying what + why. Frequent atomic
commits keep the `git bisect` window tight when a regression surfaces — and Bruno's worst regressions
(perf/scroll/focus/determinism) are **silent**: they don't crash or fail a build, so they can sit
unnoticed across many commits, and a coarse history makes the culprit unfindable. Don't batch hours of work into one fat commit; land each verifiable step as its own commit.
Commits stay on the worktree branch; the owner merges via PR. **This repo is a fork of
`jellyfin/Swiftfin`,** so `gh pr create` defaults the base to upstream — always pass
`--repo DiplomacyMusic/swiftfin-bruno --base main` to keep the PR inside the fork.

## Performance invariants — non-negotiable
Home/browse scroll is fast because of ten non-obvious rules (fixed row height, stable ids,
prefetch-width == cell-width, seed-keyed cache, top-down reveal, …). **Before UX-polishing shelves, read
`docs/BRUNO_PERF_INVARIANTS.md`** (INV-1..10 + quick-ref; code anchored `// INV-n`; constants in
`BrunoShelfMetrics`). Restyle freely — keep the ten intact.

**Scroll/focus "stall"?** A focus-engine held-repeat **freeze**, not a render hitch —
`docs/BRUNO_PERF_PLAYBOOK.md` + INV-10. It carries the root cause, the measurement protocol, the
on-disk `BrunoPerfLog` telemetry schema, and the declined levers; don't re-derive — it's documented.

---
Working if: fewer stray diffs, fewer overcomplication rewrites, and clarifying questions land before mistakes.
