# Bruno Navigation Map (tvOS)

> **How to read this.** This is the canonical map of every Bruno tvOS surface, the shelves on each,
> exactly what data each shelf draws from, and where its "Show all" lands. Use it to **de-dupe and
> streamline** content pages, shelf sources, and routing. "Lens/eyebrow" is the uppercased kicker over
> a shelf title. "Derived from" names the exact query/library/items source — trace it to the cited
> file. "Show-all destination" is the route the See-All/Show-all card pushes (and which filter it
> carries). As of #41 (D1+D2) **every Home shelf now also has a trailing "Show all"** (via
> `brunoHomeRouteToShowAll`, §2) that reaches the same destination as the equivalent browse instance;
> browse surfaces have always had one. Section 8 is the
> bug list: every place a shelf's Show-all disagrees with the equivalent card/destination elsewhere.
>
> All paths are repo-relative to the Bruno root. tvOS-only unless noted.
>
> **Last verified against code at commit `40da403f`** (post #37–#41: raised explore caps, sub-genre +
> Rewatchables generators, New Releases spine shelf, Rewatchables + Oscars surface, Home Show-all
> unification; 2026-06-28). Live library counts in §0.

---

## 0. Live library snapshot — real sizes at each nav node

> Real sizes from the live server (Jellyfin 10.10.3 at the host in `BRUNO_NOTES.md` §SDK), captured
> 2026-06-28. **Refresh:** `/Items?…&Limit=0` → `TotalRecordCount` for grid totals; favorited BoxSets'
> `ChildCount` for parent sizes; `/Items?ParentId={group}` (**no type filter** — see Terminology in
> `BRUNO_CODE_MAP.md`) for member/child sizes. Counts drift as the library grows.

**Full grids (terminal surfaces):**

| Grid | Items |
|---|---|
| Movies — `brunoMoviesGrid` / Movies-tab A–Z | **1270** |
| TV Shows — `brunoTVGrid` (§5) | **44 series** (2849 episodes) |
| Kids (§6) | **52** = 48 movies + 4 shows |

**Group tiles → members → child film sizes** (parent = # member BoxSets; child = films inside each member):

| Group tile (parent) | Members | Child films min / median / max | Σ films | Largest children |
|---|---|---|---|---|
| Genres | **84** | 2 / 31 / **596** | 5259 | Drama 596 · Comedy 384 · Thriller 280 |
| Directors | **121** | 2 / 4 / 33 | 618 | Spielberg 33 · Scorsese 23 · Soderbergh 21 |
| Studios | **95** | 4 / 7 / 100 | 1292 | Warner Bros 100 · Paramount 96 · Universal 89 |
| Curated | **14** | 23 / 175 / 560 | 2417 | Ebert Thumbs Up 560 · Oscar—Screenplay 261 |
| Decades | **8** | 33 / 133 / 255 | 1127 | 1990s 255 · 2010s 253 · 2000s 228 |
| Movie Stars | **27** | 3 / 12 / 25 | 355 | De Niro 25 · Hanks 22 · Cruise 22 |
| Seasonal | **6** | 3 / 35 / 66 | 203 | Halloween 66 · 4th of July 59 |
| New Releases | **53** | flat — members are *movies*, not BoxSets | 53 | (newest-first) |
| Boxed Sets (franchises) | **54** | 2 / 3 / 12 | 172 | James Bond 12 · Star Wars 9 · M:I 7 |

Shelf caps (Home 18 · browse preview 14 · weighted 16) sit *on top of* these pools — e.g. the Drama
genre shelf previews 14 of **596**. **BoxSet accounting:** 416 `BoxSet` primitives = 8 group tiles + 354
member BoxSets + 54 standalone franchises (New Releases' 53 children are movies, not BoxSets). Library
views: `Movies` · `Shows` · `Kids Movies` · `Kids Shows` · `Collections`.

**New since this capture (#40):** a flat **Rewatchables** favorited group (members are *movies*, like New
Releases) now ranks into Collections — its live size isn't in the tables above; re-run the §0 refresh to
capture it. The per-category Oscar BoxSets are now consolidated under one synthetic **"Oscars"** tile
(app-side; no server change).

---

## 1. Surface tree

Tab order (tvOS) — `Shared/Coordinators/Tabs/MainTabView.swift:38-44`, tabs defined in
`Shared/Coordinators/Tabs/TabItem.swift`:

```
Search        (utility, icon-only)  → stock SearchView + fixed brunoUtilityTabBar()        TabItem.swift:124
Home          (DEFAULT)             → BrunoHomeView                                          TabItem.swift:47
  └─ footer (at feed end): Show all Movies → brunoMoviesGrid · Show all TV → brunoTVGrid · Back to Top
Collections                         → BrunoCollectionsView → BrunoCategoryShelves            TabItem.swift:101
  ├─ Genres card        → brunoGenres(parent, core:nil)  → BrunoGenresView
  ├─ Decades card       → brunoCategoryShelves(parent)   → BrunoBoxSetShelvesView (pill drill)
  │     └─ per-decade pill → per-year shelves → ItemLibrary(decade, year)
  ├─ Curated card       → brunoCategoryShelves(parent)   → BrunoBoxSetShelvesView (card row)
  │     └─ sub-collection shelf → ItemLibrary(curated boxSet)
  ├─ Studios card       → brunoStudiosGrid(items)        → BrunoStudiosGridView
  ├─ Directors / Movie Stars card → brunoBoxSetGrid(portrait, artCarousel) → BrunoBoxSetGridView
  ├─ Boxed Sets card    → brunoBoxSetGrid(landscape, collectionLabel)
  └─ New Releases card  → brunoBoxSetGrid(portrait, showsDate, newest-first)
Movies                              → BrunoMoviesView → BrunoGenresView(Genres group)        TabItem.swift:79
  ├─ per-sub-genre shelf "Show all" → ItemLibrary(genre boxSet, newest-first)
  └─ trailing "All Movies" pill → brunoMoviesGrid → BrunoMediaView(.movie) A–Z grid
TV Shows                            → BrunoMediaView(itemType:.series) A–Z grid (no shelves) TabItem.swift:89
Kids                                → BrunoKidsView (single grid + All/Movies/TV/Pixar/Disney)TabItem.swift:113
Settings      (utility, icon-only)  → stock SettingsView + fixed brunoUtilityTabBar()        TabItem.swift:147
```

All See-All / card-tap routing funnels through one function: `brunoRouteToShowAll(_:router:namespace:)`
(`Swiftfin tvOS/Views/BrunoHomeView/BrunoCategoryCardRow.swift:62-168`), switching on
`BrunoCollectionCategory.drillStyle` (`.genres | .shelves | .items | .grid`). Both shelf headers
(`BrunoCategoryShelves.swift:433`) and gradient tiles (`BrunoCategoryCardRow.swift:41`) call it, so
they cannot diverge — except where the **inputs** differ (see §4).

---

## 2. Home (`BrunoHomeView`)

Engine: `Shared/Objects/Bruno/BrunoHomePlan.swift` (pure `build(seed:snapshot:now:)`, spine + explore
tail). View: `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeView.swift`; rows render via `BrunoShelfView`
→ `PosterHStack`, each with a trailing **"Show all"** card (`BrunoShelfView.swift:131`). Spine cap `shelfCap = 18`; explore tail grows +2
per page across `exploreBlockCount = 5` blocks, hard ceiling `tailCeiling = 120`.

**Per-shelf max items = 18 (`shelfCap`)** unless noted. **Show-all: as of #41 (D1+D2) every Home shelf
has one** — routed off `shelf.kind` / `shelf.source` via `brunoHomeRouteToShowAll`; per-kind
destinations are the §2a/§2b "Show-all" columns. The terminal footer (below) still re-surfaces the
collection cards.

### 2a. Spine (fixed order, contents reseed by seed)

| Shelf | Lens/eyebrow | Derived from | Max | Show-all | shelf/grid |
|---|---|---|---|---|---|
| Continue Watching | Pick Up Where You Left Off | `source:.resume` (ResumeItemsLibrary, live user-state) | live | `.library(ResumeItemsLibrary())` | shelf |
| Up Next | Next Episode | `source:.nextUp` (NextUpLibrary, live) | live | `.library(NextUpLibrary())` | shelf |
| Just Added | New to the Library | `source:.recentlyAdded` (RecentlyAddedLibrary, live; newest by dateCreated — added to the library) | live | `.library(RecentlyAddedLibrary())` | shelf |
| New Releases | Home Premiere | `newReleasesShelf` — `BrunoQuery includeItemTypes=[.movie] sortBy=[.premiereDate] desc, limit 20`, **no shuffle** (ordered, newest publicly-released first); derived live query, distinct from Just Added (dateCreated) | 18 | full paged own query (`BrunoQueryLibrary`) | shelf |
| {Year} & Around | A Year in Film | `yearShelf` — `BrunoQuery years=[year-2…year+2]`, seeded shuffle. 1st of 3 distinct seeded years | 18 | **D2** `brunoCategoryShelves(Decades, decade:"…s")` — Decades pill pre-set to the year's decade | shelf |
| Spotlight on {Director} | Director Spotlight | `seededPick(directorBoxSets)` → `parentQuery(parentID, movie+series)` | 18 | full paged own query (`BrunoQueryLibrary`) | shelf |
| {Genre} | If You Like | `seededPick(genres)` → `genreQuery` (years ≥ `modernCutoff` only) | 18 | full paged own query (`BrunoQueryLibrary`) | shelf |
| Classic Romance | Vintage Hearts | Romance genre + years < `modernCutoff`; only if Romance genre + ≥2 vintage years | 18 | full paged own query (`BrunoQueryLibrary`) | shelf |
| Series in the Library | Television | `BrunoQuery includeItemTypes=[.series]`, seeded shuffle | 18 | full paged own query (`BrunoQueryLibrary`) | shelf |
| {Year} & Around | A Year in Film | 2nd distinct seeded year (mid-spine) | 18 | **D2** `brunoCategoryShelves(Decades, decade)` — pill pre-set | shelf |
| {Studio} | From the Vault | `seededPick(studioBoxSets)` → `parentQuery` | 18 | full paged own query (`BrunoQueryLibrary`) | shelf |
| Eras | Browse by Decade | `.items(decadeBoxSets)`, portrait tiles; dropped if < `minItems`(3) | n/a | **D2** `brunoCategoryShelves(Decades)` overview; a tile-tap deep-links that decade's pill | shelf (tiles) |
| Browse by Director | Auteurs | `.items(directorBoxSets.prefix(14))`, portrait tiles | 14 | `brunoBoxSetGrid("Directors", portrait, artCarousel)`; tile-tap → item detail | shelf (tiles) |
| {Year} & Around | A Year in Film | 3rd distinct seeded year (pre-Collections) | 18 | **D2** `brunoCategoryShelves(Decades, decade)` — pill pre-set | shelf |
| Browse the Collection | Collections | **(#46)** `BrunoCollectionCategory.fromSnapshot` → the SAME branded `BrunoCategoryCardRow` tiles as the Collections tab, incl. the Boxed Sets tile; drops empty-children groups | n/a | each tile routes via `brunoRouteToShowAll` to its curated drill-in — **1:1 with the Collections tab** | shelf (tiles) |

Spine notes: adjacency rule drops any shelf whose `kind` equals the previous shelf's; content dedupe by
`dedupeKey` across the whole session; `year` is excluded from the explore pool so the tail never adds a
4th colliding year (`BrunoHomePlan.swift:42-46`).

### 2b. Explore tail (seeded generators, +2/page, reseeds per block)

Initial build appends up to 5 distinct keys; `appendExplore` walks `exploreKeys` (shuffled per session —
this table is in canonical, not execution, order) per scroll page. Same 18-item cap. Each tail shelf also
gets a trailing "Show all" (#41) → its own paged query (or the Decades pill, for the decade generator).
`exploreKeys` holds **11** entries: the 10 generator rows below plus `world`, which aliases to the same
`{Curated}` generator (`BrunoHomePlan.swift:334` — `case "curated", "world"`), so the Curated lens can recur.

| Shelf | Lens/eyebrow | Derived from (`explore(key:)`, `BrunoHomePlan.swift:251`) | Max |
|---|---|---|---|
| Acclaimed & Unwatched | Hidden Gems | `minCommunityRating≥8.1 & isUnplayed`, sort communityRating desc | 18 |
| Critics' Highest Rated | Top of the Library | `minCommunityRating≥7.5`, sort communityRating desc, `limit=15` | 15 |
| {Genre} | If You Like | `seededPick(genres)` → `genreQuery` (modern years; no salt) — distinct from spine | 18 |
| {Studio} | From the Vault | `boxSetShelf(studioBoxSets)` → `parentQuery` | 18 |
| Hidden in the {Decade} | Lost in Time | `boxSetShelf(decadeBoxSets)` → `parentQuery` | 18 |
| Spotlight on {Director} | Director Spotlight | `boxSetShelf(directorBoxSets)` → `parentQuery` (different salt than spine) | 18 |
| {Curated} | Curated | `boxSetShelf(curatedBoxSets)`, " — " stripped for display | 18 |
| {Seasonal} Picks | In Season | `seasonalShelf` — date-aware (Dec christmas / Oct halloween / Jul july), else seeded | 18 |
| {Sub-genre} | Deeper Cuts | `case "subgenre"` (#38) → `seededPick(genreBoxSets, salt 97)` → `parentQuery(salt 97)`; `.subgenre` kind, `subgenre:<id>` dedupe (distinct Kind ⇒ never collapses into the genre-NAME shelf) | 18 |
| Rewatchable {Genre} | The Rewatchables | `case "rewatchables"` (#40) → `rewatchablesShelf` — `rewatchablesBoxSet` parentID ∩ a seeded broad genre (Comedy/Drama/Action/Thriller/Crime/Adventure), seeded shuffle; `.rewatchables` kind; nil if no Rewatchables BoxSet | 18 |

### 2c. Home terminal footer (renders only once `exploreExhausted`)

`BrunoHomeView.swift:177-202`. Re-surfaces the collection group cards then 3 pills.

| Element | Source | Destination |
|---|---|---|
| Group cards | `BrunoCategoryCardRow(viewModel.collectionCategories)` | each via `brunoRouteToShowAll` (same as Collections tab — see §3) |
| Show all Movies | pill | `brunoMoviesGrid` → `BrunoMediaView(.movie)` A–Z |
| Show all TV | pill | `brunoTVGrid` → `BrunoMediaView(.series)` A–Z |
| Back to Top | pill | scroll to hero |

---

## 3. Collections (`BrunoCollectionsView` → `BrunoCategoryShelves`)

`Swiftfin tvOS/Views/BrunoHomeView/BrunoCollectionsView.swift` + shared
`BrunoCategoryShelves.swift`. Category set from `BrunoCollectionCategory.fromSnapshot`
(`BrunoCategoryShelves.swift:144`) + appended synthetic "Boxed Sets". Fixed order via
`rank(for:)` (`:99`). One capped inline shelf per category; **inline preview cap = 14** but
`shelfItems(for:)` (`:472`) populates the **full** child set for `.grid`/`.items` box-set groups (the
row IS the full set there). "Genres" card is dropped (it moved to the Movies tab). Seasonal only
ranks in during the Halloween→Christmas window. Each header's "Show all" → `brunoRouteToShowAll`.

| Shelf | Lens/eyebrow | Derived from | Max items | Show-all destination (filter carried) | shelf/grid |
|---|---|---|---|---|---|
| New Releases | Home Premiere | Flat group, no boxSet children, `showsDate=true` | 14 preview | `brunoBoxSetGrid(portrait, showsDate, newest-first)` — children sorted by premiereDate desc | shelf |
| Directors | Auteurs | Directors group's boxSet children; weighted preview (salt `0x91A3`) | 16 weighted (full set on Show-all) | `brunoBoxSetGrid(portrait, artCarousel)` — boxSet children only | shelf |
| Movie Stars | Movie Stars | Actor group boxSet children | full set | `brunoBoxSetGrid(portrait, artCarousel)` | shelf |
| Boxed Sets | Franchises | Standalone **franchise** BoxSets — every BoxSet not absorbed by a group (**54 live**, §0); **runtime-synthetic, NOT a Jellyfin group** (lens "Franchises"; see Terminology in `BRUNO_CODE_MAP.md`); weighted (salt `0xB075`) | 16 weighted of 54 | `brunoBoxSetGrid(landscape, collectionLabel)` — `category.children` (`.items`) | shelf |
| Decades | Through the Years | Decades group boxSet children; newest-first | 14 preview | `brunoCategoryShelves(parent: Decades)` → drill-in (§3a) | shelf |
| Curated | Hand-Picked | Curated group boxSet children | 14 preview | `brunoCategoryShelves(parent: Curated)` → drill-in (§3b) | shelf |
| Rewatchables | Always Worth Rewatching | Favorited "Rewatchables" group (#40); flat — members are **movies**, not boxSets (like New Releases); present only if the server has the group (rank 7) | 14 preview | `brunoRewatchables(parent)` → `BrunoRewatchablesView` — broad-genre shelves with "Episode NN" captions (§3c) | shelf |
| Studios | From the Vault | Studios group boxSet children; weighted (salt `0x5747`) | 16 weighted | `brunoStudiosGrid(items)` — cinematic landscape grid (curated **"Household Names"** top section + full A–Z grid) | shelf |
| Seasonal | In Season | Seasonal group boxSet children (only Oct–Dec) | 14 preview | per `drillStyle(for:)` default `.grid` | shelf |

`drillStyle(for:)` (`BrunoCategoryShelves.swift:115`): Genres→`.genres`, Decades→`.shelves`,
Curated→`.shelves`, Rewatchables→`.rewatchables`, everything else→`.grid`. Boxed Sets is built
explicitly as `.items`.

### 3a. Decades drill-in (`BrunoBoxSetShelvesView`, `isDecades==true`)

`Swiftfin tvOS/Views/BrunoHomeView/BrunoBoxSetShelvesView.swift`. Pill row ("All" + each decade).
"All" shows one shelf per decade; selecting a decade pill swaps to per-year shelves
(`loadYearShelves` `:530`, debounced ~500 ms, memoized). Per-year built in `yearCategories` (`:575`).

| Shelf | Lens/eyebrow | Derived from | Max | Show-all destination (filter carried) | shelf/grid |
|---|---|---|---|---|---|
| Best of the {Decade} | (decade lens) | `bruno-sig:<NN>` tag, significance-desc; shown only if ≥8 tagged films | 15 | `.grid` `gridParent=decade, gridYear=nil` → `ItemLibrary(decade)` **unfiltered** — significance order is NOT carried | shelf |
| {Year} | A Year in Film | Per-year bucket of the decade's complete fetch, premiere-desc | all in year | `.grid` `gridParent=decade, gridYear=year` → `ItemLibrary(decade, years:[year])` — **year filter carried** | shelf |
| Other | (decade lens) | Out-of-window / yearless films | all | `.grid` `gridParent=decade, gridYear=nil` → `ItemLibrary(decade)` unfiltered | shelf |
| {Decade} (non-splittable, e.g. "1950s & Earlier") | — | Whole bucket as one grid | all | `ItemLibrary(decade)` unfiltered | shelf |

### 3b. Curated drill-in (`BrunoBoxSetShelvesView`, `isDecades==false` → card row)

| Shelf | Lens/eyebrow | Derived from | Max | Show-all destination | shelf/grid |
|---|---|---|---|---|---|
| {Curated sub-collection} | Hand-Picked | Each curated group boxSet child (Oscar, Ebert, …); server order; weighted preview (salt `0xC0DE`) | 14 preview | `.grid` → `ItemLibrary(curated boxSet)` — no year filter | shelf |
| {Oscar — Category} (the 6, inside the Oscars drill-in) | OSCAR / Academy Awards | Oscar boxSet child; **reverse-chron by award year** (newest first, not shuffled) | 14 preview | `.grid` → **`brunoBoxSetGrid`** (full set paged, reverse-chron, captioned) — NOT stock `ItemLibrary` | shelf |

**Oscars consolidation (#40):** the per-category Oscar BoxSets are folded into a single synthetic
**"Oscars"** tile here; tapping it opens `brunoCategoryShelves(parent: «synthetic Oscars», subGroups: its
children)` — a shelf per Oscar category — instead of one tile per category (`BrunoCategoryCardRow.swift:72`).

**Oscars order + caption:** each of the six Oscar shelves (and their "Show all" grids) orders films
**newest-first by award year** and renders a per-poster second line — *Winner (Year)* / Nominee (Year)
— for THAT shelf's category (`BrunoOscarContentView`). Source is a per-item tag
`oscar:<CATEGORY>:<won|nom>:<YEAR>` written by the producer (`MovieCollection/enrich/p9_oscars.py`,
owner-run LIVE, mirrors p7); the app reads it like `rewatchables-ep:` / `bruno-sig:`. The drill-in
replaces the day-shuffle with a deterministic reverse-chron sort for Oscar sub-groups only
(`BrunoBoxSetShelvesView.performLoad`), and the "Show all" redirects off the stock `ItemLibrary` to
`brunoBoxSetGrid` (which pages the full category + renders the caption). Degrades gracefully pre-stamp:
no tag ⇒ blank (height-reserving) caption line, order falls back to premiereDate.

### 3c. Rewatchables drill-in (`BrunoRewatchablesView`)

`Swiftfin tvOS/Views/BrunoHomeView/BrunoRewatchablesView.swift` + `BrunoRewatchablesContentView.swift`
(#40). The favorited "Rewatchables" BoxSet (flat — members are movies) bucketed client-side into broad-genre
shelves; each poster captioned **"Episode NN"** from the `rewatchables-ep:NN` tag (`captionsEpisodes`,
`BrunoCategoryShelves.swift:216`). Full-bleed `RewatchablesHero` brand art.

| Shelf | Lens/eyebrow | Derived from | Max | Show-all destination | shelf/grid |
|---|---|---|---|---|---|
| Rewatchable {Genre} | (broad genre) | The Rewatchables BoxSet ∩ one broad genre (client-bucketed) | capped preview | `.genreGrid` → portrait grid of that bucket's exact films (`BrunoCategoryCardRow.swift:91`) | shelf |

---

## 4. Movies / Genres (`BrunoMoviesView` → `BrunoGenresView`)

`Swiftfin tvOS/Views/BrunoHomeView/BrunoMoviesView.swift` resolves the "Genres" group boxSet from the
snapshot and hands it to `BrunoGenresView` (core-genre pills + a shelf per sub-genre). Genre categories
are `recencyBiased` → row is modern-only, Show-all grid sorts newest-first (pre-1985 sink to the
bottom). Sub-genre membership is the full set (no year filter, recency-biased), per-launch reshuffled,
6 lead genres pinned. Preview cap 14; **84** sub-genre BoxSets total (live, §0). Trailing "All Movies"
pill → `brunoMoviesGrid`.

| Shelf | Lens/eyebrow | Derived from | Max | Show-all destination (filter carried) | shelf/grid |
|---|---|---|---|---|---|
| {Sub-genre} | If You Like | Genre group boxSet child; weighted preview (salt `0xC0DE`) | 14 preview / full sub-genre on Show-all | `ItemLibrary(genre boxSet, sortBy:premiereDate desc)` — **recency sort carried** | shelf |
| — (tab footer) | — | — | — | trailing "All Movies" → `brunoMoviesGrid` → `BrunoMediaView(.movie)` | — |

Fallback: if no Genres group exists, the Movies tab renders `BrunoMediaView(.movie)` A–Z grid directly
(`BrunoMoviesView.swift:51`).

---

## 5. TV Shows (`BrunoMediaView`, GRID)

`Swiftfin tvOS/Views/BrunoHomeView/BrunoMediaView.swift`, `itemType:.series`, `heroEyebrow:"Featured
Series"`. No shelves.

| Surface | Derived from | Max | Destination |
|---|---|---|---|
| **GRID** — All TV Shows | `Paths.getItems includeItemTypes=[.series] sortBy=[.sortName]`, paged to completion; hero = top backdrop-bearing, hero-eligible items | all series (**44** live · 2849 eps, §0) | terminal |

---

## 6. Kids (`BrunoKidsView`, GRID)

`Swiftfin tvOS/Views/BrunoHomeView/BrunoKidsView.swift`. Merged kids libraries via
`BrunoCombinedLibrary`; one grid filtered in place by a pill row (debounced ~500 ms).

| Surface | Derived from | Max | Destination |
|---|---|---|---|
| **GRID** — All / Movies / TV Shows / Pixar / Disney | All merged kids items, filtered by `KidsFilter.matches` (type or studio; Disney excludes Pixar) | all filtered (**52** live: 48 mv + 4 tv, §0) | rebuilt in place per filter |

---

## 7. Standalone grids reached by Show-all

| Surface (file) | Source | Notes |
|---|---|---|
| `brunoMoviesGrid` / `brunoTVGrid` → `BrunoMediaView` | A–Z full library by type (**Movies 1270 · TV 44** live, §0) | pushed COVER (own `BrunoCoverMenuBarRow`); lazy load on first appear |
| `brunoBoxSetGrid` → `BrunoBoxSetGridView` | static `items:` array passed by `brunoRouteToShowAll` | portrait/landscape, optional artCarousel/showsDate/collectionLabel; NOT paged |
| `brunoStudiosGrid` → `BrunoStudiosGridView` | static studio boxSets | cinematic 4-col landscape grid: a daily-seeded **"Household Names"** top section (≤12 curated recognizable studios present — 3 rows of 4 — stable membership, order rotates per day via `BrunoRNG`) above the full A–Z grid (top names NOT excluded) |
| `.library(ItemLibrary(parent:filters:))` | live paged Jellyfin query scoped to a boxSet, carrying `ItemFilterCollection` | the only path that carries a real server filter (years / sort) |

---

## 8. Show-all destination matrix — known mismatches & gaps

Routing is centralized, so true divergence comes from **different inputs to the same function** or from
**routes that drop a filter the inline shelf applied**. Flagged cases:

| # | Where | Inline shelf shows | Show-all lands on | Mismatch |
|---|---|---|---|---|
| 1 | **Decades → Best of the {Decade}** (§3a) | significance-ordered top ≤15 (`bruno-sig`) | `ItemLibrary(decade)` **unfiltered, default sort** | Show-all drops the curation entirely — you get the whole decade, not "the best of." `gridYear=nil`, no sig filter. (`BrunoBoxSetShelvesView.swift:617-624`, `yearCategory :673`) |
| 2 | **Decades → Other** (§3a) | out-of-window/yearless subset | `ItemLibrary(decade)` unfiltered | "Other" Show-all yields the full decade, not just the Other bucket (no filter exists for it). |
| 3 | **Genre row (Movies / spine) vs Genre Show-all grid** | modern-only (years ≥ `modernCutoff`) | `ItemLibrary(genre, premiereDate desc)` — **all years** | Deliberate (owner: classics sink to bottom, not hidden), but the inline set ≠ grid set. Flag for de-dupe awareness, not a bug. (`BrunoHomePlan.genreQuery :330`; route `BrunoCategoryCardRow.swift:156`) |
| 4 | **Home spine "Eras" / "Browse by Director" / "Browse the Collection" tiles** | portrait tiles | **Resolved by #41 (D2) + #46.** Eras tile-tap deep-links the decade pill (#41 D2); **Browse the Collection now renders the Collections-tab `BrunoCategoryCardRow` 1:1, so its tiles route via `brunoRouteToShowAll`** (#46). | Residual narrowed to **Browse by Director (Auteurs) only**: a Director tile-tap still opens stock `.item` detail. |
| 5 | **Curated drill-in sub-collection Show-all** (§3b) vs **Curated tab card** | sub-collection preview | `ItemLibrary(curated boxSet)` no year filter | Curated never carries a year/era filter on Show-all, unlike Decades. Confirm this is intended (curated is hand-picked, so likely fine). |
| 6 | **Boxed Sets card → `.items`** vs other group cards → `.grid` | franchise boxSets | `brunoBoxSetGrid(category.children)` (landscape) | Boxed Sets routes off `category.children` while Directors/Studios route off the filtered `boxSetChildren`. Different code paths in `brunoRouteToShowAll` (`.items` `:73` vs `.grid` `:127`); verify Boxed Sets children never include the group itself. |

The **non-mismatches** worth recording (verified identical): a Director shelf header "Show all" and a
Director card tap both hit `.grid → brunoBoxSetGrid(portrait, artCarousel)` with the same
`boxSetChildren`; a Decade shelf header "Show all" and a Decades card both hit
`.shelves → brunoCategoryShelves(Decades)`. Per-year Decade Show-all **does** carry the year filter
(`gridYear=year`, mismatch #1 is only the "Best of" / "Other" buckets).

---

## 9. Open questions / unverified

| # | Question |
|---|---|
| 1 | ~~Do the Collections / Movies / TV / Kids heroes auto-rotate like Home?~~ **ANSWERED (2026-06-28):** three multi-item auto-rotating heroes — **Home** (`BrunoHomeViewModel` `.prefix(5)`), **Kids** (`BrunoKidsView` `.prefix(5)`), **TV Shows** (`BrunoMediaView` `.prefix(5)`). **Movies / Collections / Decades / Genres covers are single-item** (`BrunoCategoryShelves` `items: [featured]`). Multi-item heroes now expose a focusable page-dot pager; single-item keep the whole-card Button. |
| 2 | Boxed Sets (`.items`) Show-all: confirm `category.children` are all `.boxSet` and never include the parent group, so the landscape grid can't list the group itself. |
| 3 | "Best of the {Decade}" (mismatch #1): is dropping the significance order on Show-all intended, or should it route to a tag-filtered/sig-ordered library? Currently it cannot (Jellyfin has no `bruno-sig` server filter). |
| 4 | **Answered by #41 (D2) + #46.** Eras tile-tap → decade pill (#41); Browse the Collection now renders the Collections-tab row 1:1 with tiles routing via `brunoRouteToShowAll` (#46). Only a **Browse-by-Director (Auteurs)** tile-tap still lands on stock `.item` detail — open whether to brand that last tap. |
| 5 | Seasonal appears in Collections only Oct–Dec (`rank` window) but the Home explore tail can surface it year-round (date-aware keyword, seeded fallback). Confirm that asymmetry is desired. |
| 6 | `BrunoMediaView` A–Z grids (Movies fallback / TV / `brunoMoviesGrid` / `brunoTVGrid`) are reachable from multiple entry points (tab root, Movies "All Movies" pill, Home footer) — candidate for de-dup if the owner wants a single canonical "all movies" surface. |
