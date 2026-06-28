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
| `Swiftfin tvOS/Views/BrunoHomeView/BrunoPosterPrefetcher.swift` | Poster image prefetch (prefetch width == cell width, INV-4). |

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

Docs are organized in three tiers (reorg completed 2026-06-28 — every cross-reference repointed, verified
zero dangling):

- **`docs/` (top level) — canonical + active.** Read these.
- **`docs/reference/` — stable specs** (designs, checklists; some unbuilt). Consult when relevant.
- **`docs/archive/` — superseded one-off handoffs**, kept for history only; not current.
- **`docs/pipeline/` — snapshots of the external MovieCollection pipeline's design docs** (the server-side
  producer that builds the Jellyfin BoxSets Bruno renders; authoritative source is the separate
  MovieCollection repo). See `docs/pipeline/README.md` for the producer→viewer seam + data contract.

**Load-bearing (always keep current):** `CLAUDE.md`, `docs/PROJECT_TRACKER.md`,
`docs/BRUNO_PERF_INVARIANTS.md`, `docs/BRUNO_NAV_MAP.md`, `docs/BRUNO_CODE_MAP.md`, `BRUNO_NOTES.md`,
`prototype/design_handoff_bruno/PRODUCT_SPEC.md`.

| Doc | Tier | Role |
|---|---|---|
| `CLAUDE.md` | load-bearing | working principles + perf-doc pointers |
| `docs/PROJECT_TRACKER.md` | load-bearing | canonical status board (the heartbeat) |
| `docs/BRUNO_NAV_MAP.md` | load-bearing | IA / shelves / show-all routing |
| `docs/BRUNO_CODE_MAP.md` | load-bearing | architecture + this doc map |
| `docs/BRUNO_PERF_INVARIANTS.md` | load-bearing | INV-1..10 (+ quick-ref) — read before shelf UX |
| `BRUNO_NOTES.md` | load-bearing | verified toolchain / SDK / architecture |
| `prototype/design_handoff_bruno/PRODUCT_SPEC.md` | load-bearing | product contract / mockup |
| `docs/BRUNO_PERF_HANDOFF.md` | active | scroll-hitch diagnosis & levers |
| `docs/BRUNO_PERF_LOGGING.md` | active | DEBUG on-disk telemetry guide |
| `docs/BRUNO_STALL_HANDBOOK.md` | active | held-scroll freeze (focus-engine) handbook |
| `docs/BRUNO_HERO_UPNAV.md` | active | hero UP-nav focus model |
| `docs/BRUNO_HERO_LAYOUT_MAP.md` | active | hero/menu layout knobs |
| `docs/BRUNO_MOVIES_GENRE_SURFACE.md` | active | Movies/genre surface fragility map |
| `docs/DEPLOYMENT_HANDOFF.md` | active | real-device run (absorbed the old STATUS) |
| `docs/UI_FIXPASS2_HANDOFF.md` | active | live UI handoff (absorbed UI_DEEP_WORK) |
| `docs/BRUNO_CERTIFICATION_PLAN.md` | active (plan) | design for a pre-change cert / quality gate (SlateRunner-style) |
| `README.md` | reference | public-facing readme |
| `NATIVE_FORK_PLAN.md` | reference | historical one-shot plan (BRUNO_NOTES overrides on drift) |
| `docs/reference/STUDIO_GRID_HANDOFF.md` | reference | unbuilt Studios-grid redesign spec |
| `docs/reference/GENRE_RECS_ARCHITECTURE.md` | reference | unbuilt "IF YOU LIKE" rec-lens design |
| `docs/reference/TOP_SHELF_SETUP.md` | reference | Top Shelf extension owner checklist |
| `docs/reference/PERF_SHELVES.md` | reference | scaffold-jank options memo |
| `docs/reference/swift-reference.md` | reference | swift-xcode-expert doc sources |
| `docs/archive/SIM_VIEWING_HANDOFF.md` | archive | superseded sim-viewing notes |
| `docs/archive/OVERNIGHT_TESTING_HANDOFF.md` | archive | one-off T0 testing handoff |
| `docs/archive/UI_POLISH_ROADMAP.md` | archive | superseded UI roadmap |

**Merged/removed in the 2026-06-28 reorg:** `STATUS.md` → folded into `DEPLOYMENT_HANDOFF.md`
("Already verified" section); `UI_DEEP_WORK_HANDOFF.md` → folded into `UI_FIXPASS2_HANDOFF.md`;
`overnight-loop-log.md` → deleted (noise).

---

## 7. Terminology — `BoxSet` vs Franchise (don't conflate)

Jellyfin's collection primitive and Bruno's franchise card are both "box sets" in English. Keep them
distinct in code, docs, and prompts:

| Term | Means | In code |
|---|---|---|
| **`BoxSet`** (one word) | The **Jellyfin primitive** — `BaseItemKind.boxSet`, a collection container. Bruno ships *all* curation as BoxSets; the library holds **416** across every tier. Reserve "BoxSet" for the primitive only. | `IncludeItemTypes=[.boxSet]`, `BaseItemDto` |
| **Group tile** (group BoxSet) | A *favorited* BoxSet whose members are themselves BoxSets — the **8** tiles: New Releases, Directors, Decades, Genres, Studios, Curated, Seasonal, Movie Stars. | `snapshot.favoriteGroupBoxSets`, `BrunoCollectionCategory.fromSnapshot` |
| **Member BoxSet** | A BoxSet belonging to a group (a sub-genre, a director's set, a decade bucket, a studio set); its members are usually movies. | `snapshot.childrenByGroupName` |
| **Franchise** (the "Boxed Sets" card) | The **user-facing** grouping of *standalone* franchise/series collections (LOTR, Star Wars) — every BoxSet **not** absorbed by a group. Runtime-synthesized, lens **"Franchises"**, `drillStyle .items`. "Boxed Sets" is its **display label only**. | `franchiseBoxSets` — `BrunoCollectionsView.swift:93-122` |

**Rules of use**
- "BoxSet" = the Jellyfin primitive, never the franchise card.
- "Franchise" / "franchise set" = the user-facing concept; the code already names it `franchiseBoxSets` /
  lens "Franchises" — prefer these internally; treat "Boxed Sets" as the display string only.
- Group membership is **NOT** a `ParentId` relationship — member BoxSets come from the snapshot
  (`childrenByGroupName`), not a live `ParentId` query (which returns ~nothing for BoxSet children).
  Don't compute franchise/membership counts via `ParentId`.
- Optional UX cleanup (deferred): renaming the card's display label "Boxed Sets" → "Franchises" would
  erase the collision in the UI too. Flagged, not done.
