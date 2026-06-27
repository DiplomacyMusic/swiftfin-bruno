# Bruno Movies-tab scroll-hitch — handoff

**For the next thread.** This is where the vertical-scroll-hitch investigation stands as of
2026-06-27. Read this + `BRUNO_PERF_LOGGING.md` + `BRUNO_PERF_INVARIANTS.md` (esp. INV-1, INV-10)
before touching the shelf/scroll path.

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

### 1. Redraw churn (CONFIRMED lever — most promising)
The wave-1 HUD showed **Movies genre shelves redraw 1–2×/sec during scroll** (`redraws/s 2×
genre-shelf:…`) while **Home shows `—`** (no body re-eval). That SwiftUI body churn drives
`CollectionHStack.updateUIView → reload(using:)` that Home never pays.
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
