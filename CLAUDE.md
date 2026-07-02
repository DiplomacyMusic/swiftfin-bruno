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

**Docs are tiered:** `docs/` = canonical & active · `docs/reference/` = stable specs · superseded
docs are **deleted** (recover from git; there is no `docs/archive/`). Assessment set:
`Documentation/fable-plans/` (provenance / nav graph / duplication register, 2026-07-01).

**Where code lives:** Bruno UI in `Swiftfin tvOS/Views/BrunoHomeView/`, engine in `Shared/Objects/Bruno/`;
everything else is upstream Swiftfin — reuse, don't refactor. **One connected pipeline:** a shelf is a
seeded descriptor (`BrunoHomePlan`) → realized to a paging VM (`BrunoHomeViewModel`) → rendered
(`BrunoShelfView`/`PosterHStack`); "show all" routing funnels through exactly TWO routers —
`brunoRouteToShowAll()` for browse surfaces, `brunoHomeRouteToShowAll()` for Home shelves. Trace a
change through the maps first — local edits ripple.

**Agents:** Swift/SwiftUI/Xcode mechanics → `swift-xcode-expert`; "where/how does Bruno do X" → `bruno-expert`.

**Workflow:** Work in a worktree → open a PR; the owner merges. Don't push `main` directly. Keep edits in
the worktree (so the desktop app's file links resolve).

**Maintenance:** All those worktrees pile up — each built one spawns a ~5 GB Xcode DerivedData folder, and
deleting a worktree orphans its DerivedData. `Scripts/cleanup-worktrees.sh` reclaims both: it removes a
worktree only when its branch is merged into the default branch **and** its tree is clean (never the main
checkout, the current worktree, or unmerged/dirty work — `git worktree lock` one to shield it), then
deletes DerivedData folders whose source project no longer exists (including the worktrees it just
removed). **Defaults to `--dry-run`** (prints what it would remove + reclaimed sizes,
deletes nothing); pass `--apply` to delete. To run it by hand, double-click
`Scripts/cleanup-worktrees.command` — it shows the dry-run preview, asks to confirm, then applies. A
launchd LaunchAgent (`Scripts/com.bruno.cleanup-worktrees.plist`) runs it daily — install steps are in
that plist's header.

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
unnoticed across many commits, and a coarse history makes the culprit unfindable. **Commit each verifiable step _before_ you start the next — don't batch.** If you've made 3+ logical
changes with nothing committed, stop and commit now; the end of the task must never be your first commit
(a single fat end-of-work commit fails this rule). Onboarding-critical — see the Working agreement in
`.claude/CERTIFICATION.md`.
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
