# Bruno Movies-tab scroll-hitch — handoff

**For the next thread.** This is where the vertical-scroll-hitch investigation stands as of
2026-06-27. Read this + `BRUNO_PERF_LOGGING.md` + `BRUNO_PERF_INVARIANTS.md` (esp. INV-1, INV-10)
before touching the shelf/scroll path.

---

## How to work this — read before anything else

**1. Measure before you change. This is the whole discipline that was missing.** Across 7 threads the
failure mode was *change-and-hope* — landing structural fixes without a measured before/after. **Both
structural fixes currently on `main` (the CollectionHStack fork reuse, the art-cycle rework) are
UNMEASURED** (see Honest status below). Your **first** move is not a code change — it's to capture a
baseline on the current `main` with the telemetry (`BRUNO_PERF_LOGGING.md`) + a screen recording, and
establish the real numbers. Every subsequent change needs a measured delta against that baseline. If
you can't measure it, don't land it.

**2. Use subagents and the experts — this is not optional, it's how this work succeeds.** This whole
investigation was driven by orchestration, and the two best findings came from experts, not from
first-principles guessing:
- **`bruno-expert`** — the project/Swiftfin/Jellyfin authority. Use it to ground in the codebase
  ("where does X live", how Bruno differs from stock), to mine the **prior-attempt/regression history**
  (it produced the dead-end list this session), to keep changes compliant with INV-1..10 and the
  F1–F9 map, and to update `docs/PROJECT_TRACKER.md`. Invoke it at the *start* of any unit of work.
- **`swift-xcode-expert`** — the Swift/SwiftUI/tvOS-focus-engine/UIKit/Instruments/SPM authority. The
  held-scroll regression root cause (focused-subtree mutation stalling press-and-hold auto-repeat) came
  from it citing Apple focus docs — not from inference. Use it for focus-engine mechanics, profiling
  strategy, the fork patch, and anything language/toolchain.
- **Orchestration model that worked:** you (orchestrator) spawn one focused subagent per task in an
  **isolated worktree**; each implements exactly its task, compile-verifies (headless `xcodebuild` tvOS
  sim, `CODE_SIGNING_ALLOWED=NO -skipMacroValidation`, symlink the gitignored `Carthage` first),
  commits on its own branch, and returns a structured report; you **review the actual diff** (don't
  trust the report alone) and cherry-pick onto your integration branch when it's architecturally sound;
  land on `main` only after a combined build. Keep changes surgical and reversible.

**3. Ground, don't guess.** Before acting on a hypothesis, confirm it — with a profiler trace, a
`_printChanges()` reading, or an expert citing docs. Several "facts" this session turned out softer
than stated (the `@StateObject` allocation was assumed dominant but lightening it barely moved the
needle; `posterStyle` adds no shadow on tvOS). Verify before you build on a claim.

## Honest status: known unknowns (answers to the obvious questions)

Be skeptical of this handoff's confident phrasing — here is what was and was **not** actually done:

1. **Was the fork fix (`466aeb3f`) measured?** No. The device test was a deliberate *land-blind* call —
   the owner said "don't stop for my checks, go to the end of perf" to keep momentum, not because of a
   device gap. The owner **is running on the sim now**, so a capture setup exists (sim + the new
   telemetry + screen recording). Lever 0 = measure it.
2. **Is the redraw-churn reading (Movies shelves redraw 1–2×/sec, Home `—`) still live?** Unknown — it
   was taken on the **wave-1 build (Step 0 + the now-REVERTED conditional-insertion Step 1), BEFORE the
   fork reuse and BEFORE the art-cycle rework**. So it predates *both* structural fixes and was measured
   on code that no longer exists. Treat it as a **stale, pre-fix reading** — re-measure on current `main`
   before treating lever 1 as real. (Also: 1–2×/sec is *continuous*, but `visibleShelfCount` grows are
   *occasional* — so there is likely a continuous redraw source separate from the grow. Find it.)
3. **What drives `visibleShelfCount += 4`?** Scroll-position: a `Color.clear.frame(height:1).onAppear`
   sentinel at the bottom of the `LazyVStack` bumps it (`BrunoCategoryShelves`). `visibleShelfCount` is
   `@State` on the container, so a grow re-evaluates `BrunoCategoryShelves.body` → `ForEach(prefix)`
   reconciles existing shelves by stable id and appends new ones. The open question (untested): does that
   body re-eval re-feed the EXISTING `BrunoShelfRow`s (→ `CollectionHStack.updateUIView` → `reload`)?
   Likely yes — that's the prime redraw-churn hypothesis. Confirm with `_printChanges()`.
4. **Did anyone run `Self._printChanges()` on the shelf bodies?** No. Genuinely untried. It's your first
   cheap static step.
5. **What concretely makes `BrunoLabelArtCard` heavier than `PosterButton`?** We have only the aggregate
   fps gap + inference. There is **no per-component breakdown** and **no profile** attributing the
   143 ms. The leading guess (the art-cycle `@StateObject` + prefetcher alloc) is *suspect* because
   lightening it (wave-1 Step 1) barely helped. Note `posterStyle(.portrait)` adds **no** shadow/corner
   on tvOS, so those aren't cell costs. Where the 143 ms actually goes is **unknown** — profile it.
6. **Any real Instruments trace?** No. Everything to date is the on-screen HUD (`BrunoFrameMonitor`) +
   frame-difference analysis of screen recordings — *inference*, not attribution. No `.trace` exists. A
   **Time Profiler / SwiftUI / Animation Hitches** capture on device or sim is the single highest-value
   thing missing; it would tell you where the 143 ms goes instead of guessing. Do this early.
7. **Per-thread dead-end list?** This session's reverts: the conditional-insertion art-cycle
   (`if isFocused { ArtCycleOverlay }`, broke held-scroll, net-reverted). Earlier threads (from
   `bruno-expert`'s history mining + git + `PROJECT_TRACKER.md`): `ceba7e18` content-inset/full-bleed
   ambient (reverted, menu-bar drift); hero `.onMoveCommand` removal (reverted). For the **complete**
   list, ask `bruno-expert` to re-mine `git log -p` + `docs/PROJECT_TRACKER.md` + the memory files —
   that's the canonical source, not this doc.
8. **Were the declined levers declined on UX or perf-ineffective grounds?** Mixed, mostly **without
   measurement**: brand-shadow-on-browse = UX/brand (and moot — no tvOS shadow on the genre cell);
   `.hoverEffect` removal = deferred on unverified focus-appearance risk ("measure first" — never
   measured); item-level pop-in = UX; `drawingGroup()` = functional (breaks focus); `dataPrefix` =
   measured-ineffective (already `== cards.count`). So if a profile proves one of the *unmeasured* ones
   is the dominant cost, it is **not** permanently off-limits — bring the data to the owner and let them
   make the UX call. Don't unilaterally reattempt; don't treat them as eternally sacred either.
9. **Acceptance bar for "smooth"?** Never formally set — that's a gap. Propose one and **confirm with
   the owner** before declaring done. Reasonable: match Home (~45 fps / `drag ~54 ms`), or a hard
   ceiling like ≤2 dropped frames (~33 ms) per row-step with no visible hitch on a held up-scroll. Get a
   verifiable number agreed up front.
10. **Reuse-correctness contract + sample data?** Contract = INV-10 (cells must not hold per-item
    `@State` offscreen, must not mutate the focused subtree on focus, per-item art must be key-aware).
    Known cells are believed safe (`PosterButton` pure; `BrunoFocusArtCycle` now key-aware) but this is
    **not runtime-verified**. **Critically: the telemetry has never actually been run** — it compiles,
    but no `BrunoPerfLog` session has been captured and `bruno-pull-perf.command` has never been
    confirmed end-to-end. **Your literal first action: smoke-test the telemetry** (enable it, capture a
    short session, run the pull script, confirm the JSONL is well-formed) before relying on it. No sample
    JSONL exists yet.

**The one-line version:** lots was built, almost nothing was measured. Thread #8's job is to *measure
first* (smoke-test telemetry → baseline current `main` → profile the 143 ms), using `bruno-expert` and
`swift-xcode-expert` to ground each step, and only then change code — with a measured delta for every change.

---

## The problem

Holding the remote **up** to scroll the **Movies** tab (genre surface: `BrunoCategoryShelves` →
`BrunoShelfRow` → `BrunoLabelArtCard`) hitches on nearly every focus row-step. High regression risk,
many prior failed attempts.

### Diagnosis (measured, on-device HUD + frame analysis)
- **Original Movies:** ~11 effective fps; **~143–163 ms main-thread stall per focus row-step**
  (`drag 150ms·8f`); one ~551 ms stall per `visibleShelfCount += 4` shelf-grow.
- **Original Home** (same architecture, lighter `PosterButton` cell): ~45 fps, `drag ~54ms`.
- The Home/Movies contrast isolated the **heavier Movies cell** + the shared **per-dequeue
  `UIHostingController` mint floor** in `CollectionHStack` as the dominant costs.

---

## What landed on `main` (newest first)

| commit | what |
|---|---|
| `1df5a932` | telemetry: input capture + hosting-reuse counters |
| `47b51f12` | telemetry: counts/load/conflict signals + exact timestamps + pull script |
| `7000d763` | telemetry: `BrunoPerfLog` foundation (JSONL, toggle, mem, tee) |
| `ad20ad7f` | docs: INV-10 rewrite (structural stability) |
| `86acd5f5` | **fix:** held-scroll regression in `BrunoFocusArtCycle` |
| `8815d7bd` | docs: tracker + INV-10 |
| `466aeb3f` | **fix:** repoint `CollectionHStack` → fork with hosting-controller reuse |
| `7985aaf0` | (net-reverted) defer art-cycle `@StateObject` to focus |
| `60d858df` | instrument Movies surface for the HUD |

**Net functional changes shipped:**
1. **`CollectionHStack` hosting-controller reuse** (the structural floor fix). Dep repointed to
   `DiplomacyMusic/CollectionHStack@bruno-hosting-reuse` (currently `dfc1352a`): the cell keeps its
   `UIHostingController` alive and swaps `rootView` instead of re-minting per dequeue. See
   `[[bruno-collectionhstack-fork]]` + INV-10.
2. **`BrunoFocusArtCycle` is structurally stable** (art layer always in the tree, work gated via
   `.onChange(of: isFocused)`, per-item art loaded **key-aware** so reuse never flashes stale art).
   This *replaced* the first attempt (`7985aaf0`) which focus-gated by **conditional view insertion**
   (`if isFocused { ArtCycleOverlay }`) and **broke held-scroll** (Apple focus engine resets-in-place
   when the focused cell mutates its subtree mid-focus-update). Don't reintroduce that pattern (INV-10).
3. **DEBUG telemetry** (`BrunoPerfLog`) — see `BRUNO_PERF_LOGGING.md`.

> Note: the `7985aaf0` "cell lightening" was net-reverted, so unfocused genre cells again allocate the
> (cheap) `@StateObject`. It was a modest, inconsistent win and caused the regression; the real levers
> are the fork reuse (shipped) + the redraw churn (open, below).

---

## What is NOT done — the open levers

### 0. Measure the fork's impact (do this first)
The hosting-controller reuse (`466aeb3f`) + the regression fix are on `main` but **not yet measured**
(device test was skipped before landing, by request). Build `main`, enable the HUD + perf logging,
and re-record **Movies + Home** held/repeated up-scroll. Compare per-step `drag` ms and the `hosts`
counters (`reuseSwaps` should dominate `mints`). This tells you how much the floor fix bought.

### 1. Redraw churn (most promising — but RE-MEASURE first; the reading is stale)
The wave-1 HUD showed **Movies genre shelves redraw 1–2×/sec during scroll** (`redraws/s 2×
genre-shelf:…`) while **Home shows `—`** (no body re-eval). That SwiftUI body churn drives
`CollectionHStack.updateUIView → reload(using:)` that Home never pays. **Caveat (see Honest status
#2): that reading was taken on the wave-1 build — before the fork reuse AND before the art-cycle
rework — so it predates both structural fixes. Re-measure on current `main` to confirm it's still
live before investing in this lever.**
- **Hypothesis:** `visibleShelfCount` grow re-evaluating the whole `BrunoCategoryShelves` body, or a
  per-scroll `@Published`/state publish feeding the shelves.
- **How to confirm:** with perf logging on, look at `redraw` (teed `nav`) + `counts` + `frame` events
  during scroll; temporarily add `let _ = Self._printChanges()` to `BrunoCategoryShelves.body` /
  `BrunoShelfRow.body` (DEBUG, remove before commit) to see which input invalidates them.
- **Fix shape:** stabilize the inputs so the shelves don't re-evaluate per focus move (the way Home's
  `BrunoShelfView` doesn't). Keep INV-2 (stable ids) / INV-8 (windowing) intact.

### 2. INV-1 height-conflict watch (cheap to check)
The telemetry now emits `conflict` events if any shelf row's measured height deviates from the pinned
`BrunoShelfMetrics` value. If those fire during scroll, INV-1 is leaking on the labelArt path → cheap
re-pin. If they never fire, INV-1 holds and this isn't the problem.

### 3. Grow-stagger (only if the ~550 ms grow stall survives)
If the `visibleShelfCount += 4` mega-stall persists after the above, reduce the increment (whole
shelves below the fold — NOT item-level pop-in, which is a declined UX change). See
`BrunoCategoryShelves.swift` grow site.

### Stop condition
If, after the above, the per-row `drag` floor persists and the call tree attributes it to irreducible
per-content SwiftUI graph building, **stop and surface to the owner** that the only remaining fix is
the `bebdfe30` UIKit-drawn-cell rewrite (multi-week, highest risk). Do **not** reattempt the declined
cheap levers (drop/ungate brand shadow on browse, remove `.hoverEffect`, item-level pop-in,
`drawingGroup()` on cells, `dataPrefix` tuning).

---

## Measurement protocol

1. Build `main` for the sim (or device). `ln -s <repo>/Carthage Carthage` in a fresh worktree if the
   build complains about a missing TVVLCKit xcframework (Carthage is gitignored).
2. Settings → Debug Overlays → enable FPS + NAV/LAYOUT + LOG + **Perf logging → disk**.
3. Saturate caches (scroll Movies to bottom and back), then do the held/repeated up-scroll.
   You do **not** need a continuous hold — discrete up-presses populate the same per-step `drag` log.
4. `./Scripts/bruno-pull-perf.command` → `PerfLogs/session-*.jsonl`.
5. Analyze + correlate with the recording via the shared `t`/`f` clock (see `BRUNO_PERF_LOGGING.md`).

**Constraints that still hold:** no UX/design changes (brand shadow, focus art-cycle, reveal cadence,
card geometry); honor INV-1..10 and the F1–F9 map in `BRUNO_MOVIES_GENRE_SURFACE.md` (esp. **F5: no
explicit `init`** on `BrunoCategoryShelves`/`BrunoShelfRow`/`BrunoGenresView`). Self-driving the sim is
unreliable (auto-login SIGTRAP, flaky nav) — capture is human-in-the-loop.

---

## Key files

- `Swiftfin tvOS/Views/BrunoHomeView/BrunoCategoryShelves.swift` — Movies scroll container, windowing
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfRow.swift` — the row + INV-1 pin
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoFocusArtCycle.swift` — the genre cell's art cycle (INV-10)
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfMetrics.swift` — the only place to touch heights/widths
- `Shared/Objects/Bruno/BrunoPerfLog.swift` + `BrunoDebugCore.swift` + `BrunoInputMonitor.swift` — telemetry
- Fork: `DiplomacyMusic/CollectionHStack@bruno-hosting-reuse` — `HostingCollectionViewCell` (reuse + DEBUG counters)
- `docs/BRUNO_PERF_LOGGING.md`, `docs/BRUNO_PERF_INVARIANTS.md`, `docs/BRUNO_MOVIES_GENRE_SURFACE.md`
