# BRUNO_CODE_MAP

Orientation map for the Bruno tvOS fork. If you're landing cold, read this first, then
`docs/BRUNO_NAV_MAP.md` for shelf/IA detail and `docs/PROJECT_TRACKER.md` for current status.

_Last verified at commit `78dc256f`._

---

## 1. What Bruno is

Bruno is an **additive tvOS fork of Swiftfin** (the SwiftUI Jellyfin client) for **private home use** —
one cinephile's ~635-movie / 19-series Jellyfin library. It replaces the stock tvOS Home with a
"real-streamer" experience: a rotating hero spotlight over an endless vertical scroll of horizontal
shelves, each a different lens (genre, director, studio, decade, curated set, seeded explore feeds),
driven by a pure seeded `BrunoHomePlan.build(seed:)` so Home feels alive and never the same twice. iOS
stays stock Swiftfin + rebrand; **all Bruno UI is tvOS-only** (the tvOS `PosterHStack` action signature is
why). Brand: accent `#A1CCE0`, Oswald display / Inter body, warm-umber dark theme.

---

## 2. Layering: upstream Swiftfin vs the Bruno layer

Bruno is a thin, intentionally-isolated layer riding on an upstream Swiftfin checkout. Almost everything
Bruno lives in two places:

- **Bruno views** — `Swiftfin tvOS/Views/BrunoHomeView/` (the whole tvOS UI surface).
- **Bruno engine/model** — `Shared/Objects/Bruno/` (plan, RNG, queries, snapshot, paging libraries).

**Rule of thumb — "is this file ours or upstream?"**

1. Path contains `/Bruno` or filename starts with `Bruno` → **ours**, edit freely.
2. Brand seams — `Shared/Extensions/Color.swift` (`Color.bruno.*`), `Font+Bruno.swift`,
   `Shared/Services/SwiftfinDefaults.swift` accent defaults → **ours (small, additive)**.
3. **Integration seams** (the only non-Bruno-named edits): `Shared/Coordinators/Tabs/{TabItem,MainTabView}.swift`
   (tvOS Home → `BrunoHomeView`, tab IA), `Swiftfin tvOS/App/SwiftfinApp.swift` (DEBUG-gated snapshot /
   autosignin branches). Keep these **minimal and inert** — gated, no behavior change for upstream paths.
4. Everything else → **upstream Swiftfin**. Don't refactor it; reuse it (`PosterHStack`,
   `PagingLibraryViewModel`, `ItemLibrary`, `NavigationCoordinator`, stock item/detail/player views).

Guardrails: additive + tvOS-only; **no `.pbxproj` edits** (file-system-synchronized group); never hardcode
BoxSet/library IDs; no secrets in the repo; land finished work on `main`.

---

## 3. Home data flow (the pipeline)

Home is a four-stage pipeline: a **plan of descriptors** is built deterministically, then **realized** into
live paging view models, then **rendered** as shelves. Determinism is sacred — same `(seed, snapshot)` ⇒
same Home (asserted in DEBUG by `BrunoHomePlan+SelfCheck`).

```
library snapshot ──▶ BrunoHomePlan.build(seed) ──▶ BrunoHomeViewModel ──▶ views
   (facts)              (shelf descriptors)          (realize + reveal)     (render)
```

| Stage | Key file | Role |
|---|---|---|
| 1. Snapshot | `Shared/Objects/Bruno/BrunoLibrarySnapshot.swift` | Pure facts about the library (genres, studios, decade/director/curated BoxSet IDs, years) the plan reads. Discovered dynamically, never hardcoded. |
| 2. Plan | `Shared/Objects/Bruno/BrunoHomePlan.swift` | `static func build(seed:snapshot:now:) -> [BrunoShelf]` — the spine + explore tail as **descriptors** (`BrunoShelf` = title + `BrunoQuery`/items source). Pure; seeded via `BrunoRNG`. `appendExplore`/`explore(key:)` grow the tail. |
| 3. Realize | `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeViewModel.swift` | Holds the seed, streams shelves in top-down (INV-8/9), dispatches `.appendExplore`. Each shelf gets a `BrunoShelfViewModel` wrapping a `PagingLibraryViewModel<BrunoQueryLibrary>` (or static `ResumeItemsLibrary`/`NextUpLibrary`/`RecentlyAddedLibrary`). |
| 4. Render | `BrunoShelfView.swift` (+ `BrunoShelfRow.swift`) | `BrunoShelfView` renders a home shelf via stock tvOS `PosterHStack` (browse-only, no Show-all). `BrunoShelfRow` is the browse-surface variant with a trailing "Show all" card. Mounted under the cap-and-grow `LazyVStack` in `BrunoHomeView.swift`. |

Note: a `BrunoShelf` descriptor carries a `BrunoQuery`; `BrunoQueryLibrary` turns that into a
`retrievePage(environment:pageState:)` paging library. See `BrunoShelf.swift`, `BrunoQuery.swift`.

---

## 4. Key files index

### Home / shelves
| File | Role |
|---|---|
| `Shared/Objects/Bruno/BrunoHomePlan.swift` | Seeded plan: spine shelves + explore tail (descriptors). |
| `Shared/Objects/Bruno/BrunoHomePlan+SelfCheck.swift` | DEBUG determinism assert (same seed ⇒ same plan). |
| `Shared/Objects/Bruno/BrunoShelf.swift` | Shelf descriptor model (title, source, kind). |
| `Shared/Objects/Bruno/BrunoRNG.swift` | Seeded mulberry32 — the determinism core. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeView.swift` | Home screen: hero + cap-and-grow shelf `LazyVStack` + footer. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeViewModel.swift` | Realizes the plan, top-down reveal, `.appendExplore`. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfView.swift` | Renders one home shelf via `PosterHStack`. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfRow.swift` | Browse-surface shelf with trailing "Show all" card. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfViewModel.swift` | Per-shelf façade over `PagingLibraryViewModel`. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeCache.swift` | Seed-keyed / source-restricted home cache (INV-5). |

### Browse / category surfaces
| File | Role |
|---|---|
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoCollectionsView.swift` | Collections tab: category row + one capped shelf per group. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoMoviesView.swift` | Movies tab → genre browse (delegates to `BrunoGenresView`). |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoGenresView.swift` | Genre shelves surface (core-genre pills + per-genre shelves). |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoCategoryShelves.swift` | Generic shelf-list surface (headers w/ Show-all callback). |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoBoxSetShelvesView.swift` | Decades/Curated drill-in: pills → per-year/sub shelves. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoBoxSetGridView.swift` | Full poster grid for a BoxSet (Show-all destination). |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoStudiosGridView.swift` | Cinematic studios grid (backdrop + scroll-coupled blur). |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoMediaView.swift` | A–Z movie/TV grids (terminal "All Movies"/"All TV"). |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoKidsView.swift` | Merged kids libraries with All/Movies/TV/studio filters. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoArtCarouselCard.swift` | Portrait art card with focus-cycling artwork. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoCategoryTile.swift` / `BrunoCategoryCardRow.swift` | Category tiles + the centralized Show-all router. |

### Menu / hero
| File | Role |
|---|---|
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoHeroView.swift` | Hero spotlight banner (auto-advance, routes to detail/player). |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoHeroWordmark.swift` | Wordmark overlay on the hero. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoScrollingMenuBar.swift` | Tab-root menu bar (scrolling row, first row of the VStack). |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoHeroMenuBar.swift` | `BrunoCoverMenuBarRow` (pushed-cover menu; dismiss-then-switch). |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoMenuBar.swift` / `BrunoSelectorCard.swift` | Menu bar primitives / selector cards. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoAmbientBackground.swift` | Ambient backdrop behind shelves (INV-6). |

### Query / data
| File | Role |
|---|---|
| `Shared/Objects/Bruno/BrunoQuery.swift` | A Jellyfin query (parentID / genre / filters / sort / limit). |
| `Shared/Objects/Bruno/BrunoQueryLibrary.swift` | `BrunoQuery` → `BaseItemKindLibrary` paging library. |
| `Shared/Objects/Bruno/BrunoStaticItemsLibrary.swift` | Static items as a paging library (BoxSet children). |
| `Shared/Objects/Bruno/BrunoItemPaging.swift` | Paging helpers over JellyfinAPI. |
| `Shared/Objects/Bruno/BrunoRecencyBias.swift` | Recency-bias ordering helper for browse shelves. |
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoPosterPrefetcher.swift` | Poster image prefetch (prefetch width == cell width, INV-3). |

### Routing
| File | Role |
|---|---|
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoCategoryCardRow.swift` | **`brunoRouteToShowAll()`** — single source of truth for every Show-all destination (drill-style switch). |
| `Shared/Coordinators/Tabs/TabItem.swift` | 7-tab IA; tvOS Home → `BrunoHomeView`. |
| `Shared/Coordinators/Tabs/MainTabView.swift` | Tab host; injects per-tab content. |

### Perf
| File | Role |
|---|---|
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfMetrics.swift` | Fragile pinned constants (shelf-row height etc., INV-1). |
| `Shared/Objects/Bruno/BrunoPerfLog.swift` | DEBUG on-disk telemetry (JSONL). |
| `Shared/Objects/Bruno/BrunoDebugInstrument.swift` / `BrunoDebugCore.swift` / `BrunoDebugOverlayView.swift` | DEBUG HUD: FPS / nav-layout / log windows. |
| `Shared/Objects/Bruno/BrunoInputMonitor.swift` | DEBUG input monitor (held-auto-repeat diagnosis, INV-10). |

---

## 5. Where do I change X?

- **Add a Home shelf** → add a descriptor in `BrunoHomePlan.swift` (`build` for the spine, `explore(key:)`
  for the tail). Keep it pure/seeded. If it needs a new data source, add a `BrunoQuery` shape and let
  `BrunoQueryLibrary` page it. The DEBUG self-check (`BrunoHomePlan+SelfCheck.swift`) must still pass.
- **Change a Show-all destination** → `brunoRouteToShowAll()` in `BrunoCategoryCardRow.swift`. This is the
  *only* place — both shelf-header Show-all and category-tile taps go through it so they can't diverge.
  Switch on `category.drillStyle` (`.genres` / `.shelves` / `.items` / `.grid`); pass filters via
  `ItemFilterCollection` in the `ItemLibrary` constructor.
- **Tune scroll/focus perf** → **read `docs/BRUNO_PERF_INVARIANTS.md` first** (INV-1..10). Constants live in
  `BrunoShelfMetrics.swift`; reveal cadence/cap-and-grow in `BrunoHomeView.swift`/`BrunoHomeViewModel.swift`;
  prefetch in `BrunoPosterPrefetcher.swift`. Diagnose with `docs/BRUNO_PERF_HANDOFF.md` +
  `docs/BRUNO_PERF_LOGGING.md` (don't re-derive). The scroll "stall" is a focus-engine freeze
  (held-auto-repeat), not a render hitch — root cause traced to FocusShadowPoster; see **INV-10** in
  `docs/BRUNO_PERF_INVARIANTS.md`.
- **Change the top menu** → tab set/order in `Shared/Coordinators/Tabs/TabItem.swift`; the scrolling bar UI
  in `BrunoScrollingMenuBar.swift` (tab roots) and `BrunoHeroMenuBar.swift` (pushed covers). Hero/menu
  vertical-stack magic numbers: `docs/BRUNO_HERO_LAYOUT_MAP.md`; the UP-nav focus model:
  `docs/BRUNO_HERO_UPNAV.md`.

For full shelf taxonomy, per-tab surfaces, and Show-all routing detail, see **`docs/BRUNO_NAV_MAP.md`**
(this map links there rather than duplicating it).

---

## 6. Documentation map

Load-bearing (read/keep current): **`CLAUDE.md`** (working principles + perf-doc pointers),
**`docs/BRUNO_PERF_INVARIANTS.md`** (INV-1..10, read before any shelf UX work), **`docs/PROJECT_TRACKER.md`**
(canonical living status board), and the two orientation maps **`docs/BRUNO_NAV_MAP.md`** (IA/shelves/routing)
and **`docs/BRUNO_CODE_MAP.md`** (this file). Everything else is reference spec or a dated one-off handoff.

| Doc | Status | Recommendation |
|---|---|---|
| `CLAUDE.md` | load-bearing | keep |
| `docs/PROJECT_TRACKER.md` | load-bearing | keep (the heartbeat) |
| `docs/BRUNO_PERF_INVARIANTS.md` | load-bearing | keep (add INV quick-ref table at top) |
| `docs/BRUNO_NAV_MAP.md` | load-bearing | keep (IA/shelf detail) |
| `docs/BRUNO_CODE_MAP.md` | load-bearing | keep (this file) |
| `BRUNO_NOTES.md` | load-bearing | keep (verified toolchain/SDK/arch) |
| `NATIVE_FORK_PLAN.md` | reference | keep (historical plan; BRUNO_NOTES overrides on drift) |
| `prototype/design_handoff_bruno/PRODUCT_SPEC.md` | load-bearing | keep (product contract) |
| `README.md` | reference | keep |
| `docs/BRUNO_PERF_HANDOFF.md` | active handoff | keep (scroll-hitch diagnosis) |
| `docs/BRUNO_PERF_LOGGING.md` | active handoff | keep (telemetry guide) |
| `docs/BRUNO_HERO_UPNAV.md` | active handoff | keep (UP-nav focus model) |
| `docs/BRUNO_HERO_LAYOUT_MAP.md` | active handoff | keep (hero/menu layout knobs) |
| `docs/BRUNO_MOVIES_GENRE_SURFACE.md` | active handoff | keep (Movies/genre fragility map) |
| `docs/DEPLOYMENT_HANDOFF.md` | active handoff | keep (real-device run) |
| `docs/UI_FIXPASS2_HANDOFF.md` | active handoff | keep (live UI handoff) |
| `docs/STUDIO_GRID_HANDOFF.md` | reference spec | keep (unbuilt; move to docs/reference/) |
| `docs/GENRE_RECS_ARCHITECTURE.md` | reference spec | keep (unbuilt; move to docs/reference/) |
| `docs/TOP_SHELF_SETUP.md` | reference | keep (owner checklist) |
| `docs/PERF_SHELVES.md` | reference | keep (scaffold-jank options) |
| `docs/swift-reference.md` | reference | keep (swift-xcode-expert sources) |
| `docs/STATUS.md` | stale handoff | merge into DEPLOYMENT_HANDOFF as a prerequisites note |
| `docs/UI_DEEP_WORK_HANDOFF.md` | stale handoff | merge into UI_FIXPASS2_HANDOFF (superseded) |
| `docs/SIM_VIEWING_HANDOFF.md` | stale handoff | archive (superseded by DEPLOYMENT) |
| `docs/OVERNIGHT_TESTING_HANDOFF.md` | stale handoff | archive (one-off T0 testing notes) |
| `docs/UI_POLISH_ROADMAP.md` | stale handoff | archive (superseded by UI_FIXPASS2) |
| `docs/overnight-loop-log.md` | noise | delete (historical build log; STATUS was the deliverable) |

> This map only documents the cleanup; per the task it does **not** modify any other doc.

### Ordered cleanup plan
1. **Delete** `docs/overnight-loop-log.md` (pure historical noise).
2. **Merge** `docs/STATUS.md` → `DEPLOYMENT_HANDOFF.md` (as a "Prerequisites / already verified" note), then remove STATUS.
3. **Merge** `docs/UI_DEEP_WORK_HANDOFF.md` → `UI_FIXPASS2_HANDOFF.md`, then remove the old one.
4. **Archive** the superseded one-offs to `docs/archive/`: `SIM_VIEWING_HANDOFF.md`, `OVERNIGHT_TESTING_HANDOFF.md`, `UI_POLISH_ROADMAP.md`.
5. **Move** reference specs to `docs/reference/`: `STUDIO_GRID_HANDOFF.md`, `GENRE_RECS_ARCHITECTURE.md`, `TOP_SHELF_SETUP.md`, `PERF_SHELVES.md`, `swift-reference.md`.
6. **Add** an INV quick-reference table at the top of `BRUNO_PERF_INVARIANTS.md`.
7. Leave `PROJECT_TRACKER.md`, `BRUNO_NAV_MAP.md`, `BRUNO_CODE_MAP.md`, `CLAUDE.md`, `BRUNO_NOTES.md` front-and-center.
