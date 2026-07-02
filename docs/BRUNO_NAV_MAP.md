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
> Section 10 maps the item-detail "Recommended" shelf (reached by tapping any poster), which is now
> Bruno-routed.
>
> All paths are repo-relative to the Bruno root. tvOS-only unless noted.
>
> **Last verified against code at commit `53685816`** (2026-07-01, Fable assessment pass; prior full
> pass `e409fd5f` 2026-06-29). The 2026-07-01 pass corrected, against the shipped IA overhaul
> (#73/#74/#75 + same-day hotfixes): the two different `shelfCap` meanings (§2), the whole Collections
> tab (§3: two-row card strip, Curated retired, preview caps 30/16, procedural tail), the Movies
> sub-genre preview caps (§4), and the Recommended fail-open rule (§10). The §0 live counts still date
> to 2026-06-28 and predate the §1 Curated-retirement migration; re-run the §0 refresh to update them.
> Deeper provenance (producer scripts, seeds, caps): `Documentation/fable-plans/SHELF_PROVENANCE.md`.
> Screen-level graph + stock handoffs: `Documentation/fable-plans/NAVIGATION_MAP.md`.

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

All browse See-All / card-tap routing funnels through one function:
`brunoRouteToShowAll(_:router:namespace:)`
(`Swiftfin tvOS/Views/BrunoHomeView/BrunoCategoryCardRow.swift:110-266`), switching on
`BrunoCollectionCategory.drillStyle` (`.genres | .shelves | .items | .grid | .rewatchables`). Both shelf
headers (`BrunoCategoryShelves.swift:543`, after an Ebert special case at `:538-544`) and gradient tiles
(`BrunoCategoryCardRow.swift:88`) call it, so they cannot diverge — except where the **inputs** differ
(see §4). Home shelves use the second router, `brunoHomeRouteToShowAll` (§2).

---

## 2. Home (`BrunoHomeView`)

Engine: `Shared/Objects/Bruno/BrunoHomePlan.swift` (pure `build(seed:snapshot:now:)`, spine + explore
tail). View: `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeView.swift`; rows render via `BrunoShelfView`
→ `PosterHStack`, each with a trailing **"Show all"** card. Explore tail grows +2
per page across `exploreBlockCount = 5` blocks, hard ceiling `tailCeiling = 120`.

**`shelfCap = 18` caps the NUMBER OF SHELVES in the initial plan** (`BrunoHomePlan.dedupedAndCapped`,
`BrunoHomePlan.swift:584`) — it is NOT a per-shelf item cap. Per-shelf items come from the shelf's
`BrunoQuery.limit` (default 60; New Releases 20, Critics 15), paged by the shelf VM and revealed
incrementally (`BrunoShelfMetrics` reveal constants). The per-row "Max 18" values in the tables below
are historical; treat the Derived-from column's own limits as authoritative. There is a SECOND, unrelated
`shelfCap = 30` on browse surfaces (§3). **Show-all: every Home shelf has one** (#41 D1+D2) — routed off
`shelf.kind` / `shelf.source` via `brunoHomeRouteToShowAll` (`BrunoHomeShowAll.swift:35`; sole caller
`BrunoShelfView.swift:205`); per-kind destinations are the §2a/§2b "Show-all" columns. The terminal
footer (below) still re-surfaces the collection cards.

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
| Eras | Browse by Decade | `.items(decadeBoxSets.reversed())` (newest-decade-first), portrait tiles; dropped if < `minItems`(3) | n/a | **D2** `brunoCategoryShelves(Decades)` overview; a tile-tap deep-links that decade's pill | shelf (tiles) |
| Browse by Director | Auteurs | `.items(directorBoxSets.prefix(14))`, portrait tiles | 14 | `brunoBoxSetGrid("Directors", portrait, artCarousel)`; tile-tap → item detail | shelf (tiles) |
| {Year} & Around | A Year in Film | 3rd distinct seeded year (pre-Collections) | 18 | **D2** `brunoCategoryShelves(Decades, decade)` — pill pre-set | shelf |
| Browse the Collection | Collections | **(#46)** `BrunoCollectionCategory.fromSnapshot` → the SAME branded `BrunoCategoryCardRow` tiles as the Collections tab, incl. the Boxed Sets tile; drops empty-children groups | n/a | each tile routes via `brunoRouteToShowAll` to its curated drill-in — **1:1 with the Collections tab** | shelf (tiles) |

Spine notes: adjacency rule drops any shelf whose `kind` equals the previous shelf's; content dedupe by
`dedupeKey` across the whole session; `year` is excluded from the explore pool so the tail never adds a
4th colliding year (`BrunoHomePlan.swift:42-49`).

### 2b. Explore tail (seeded generators, +2/page, reseeds per block)

Initial build appends up to 5 distinct keys; `appendExplore` walks `exploreKeys` (shuffled per session —
this table is in canonical, not execution, order) per scroll page. Same 18-item cap. Each tail shelf also
gets a trailing "Show all" (#41) → its own paged query (or the Decades pill, for the decade generator).
`exploreKeys` holds **11** entries: the 10 generator rows below plus `world`, which aliases to the same
`{Curated}` generator (`BrunoHomePlan.swift:337` — `case "curated", "world"`), so the Curated lens can recur.

| Shelf | Lens/eyebrow | Derived from (`explore(key:)`, `BrunoHomePlan.swift:254`) | Max |
|---|---|---|---|
| Acclaimed & Unwatched | Hidden Gems | `minCommunityRating≥8.1 & isUnplayed`, sort communityRating desc | 18 |
| Critics' Highest Rated | Top of the Library | `minCommunityRating≥7.5`, sort communityRating desc, `limit=15` | 15 |
| {Genre} | If You Like | `seededPick(genres)` → `genreQuery` (modern years; no salt) — distinct from spine | 18 |
| {Studio} | From the Vault | `boxSetShelf(studioBoxSets)` → `parentQuery` | 18 |
| Hidden in the {Decade} | Lost in Time | `boxSetShelf(decadeBoxSets)` → `parentQuery` | 18 |
| Spotlight on {Director} | Director Spotlight | `boxSetShelf(directorBoxSets)` → `parentQuery` (different salt than spine) | 18 |
| {Curated} | Curated | `boxSetShelf(promotedCuratedBoxSets)` (§1 migration repoint, `BrunoHomePlan.swift:342` — the pool is the Oscars + Roger Ebert children plus the 3 flat promotes; the retired `curatedBoxSets` accessor is dead), " — " stripped for display. **#65:** an Ebert/Oscar pick (`BrunoShelfCaption`, `BrunoQuery.swift:18`) renders portrait with the per-poster star / *Winner (Year)* caption, and its trailing "Show all" reaches the **Ebert toggle** / **Oscar** grid (`brunoHomeRouteToShowAll` caption branch, `BrunoHomeShowAll.swift:97-125`) instead of the plain paged query; all other promoted picks stay `.none`/landscape → paged query grid | 18 |
| {Seasonal} Picks | In Season | `seasonalShelf` — date-aware (Dec christmas / Oct halloween / Jul july), else seeded | 18 |
| {Sub-genre} | Deeper Cuts | `case "subgenre"` (#38) → `seededPick(genreBoxSets, salt 97)` → `parentQuery(salt 97)`; `.subgenre` kind, `subgenre:<id>` dedupe (distinct Kind ⇒ never collapses into the genre-NAME shelf) | 18 |
| Rewatchable {Genre} | The Rewatchables | `case "rewatchables"` (#40) → `rewatchablesShelf` — `rewatchablesBoxSet` parentID ∩ a seeded broad genre (Comedy/Drama/Action/Thriller/Crime/Adventure), seeded shuffle; `.rewatchables` kind; nil if no Rewatchables BoxSet | 18 |

### 2c. Home terminal footer (renders only once `exploreExhausted`)

`BrunoHomeView.swift:177-205`. Re-surfaces the collection group cards then 3 pills.

| Element | Source | Destination |
|---|---|---|
| Group cards | `BrunoCategoryCardRow(viewModel.collectionCategories)` | each via `brunoRouteToShowAll` (same as Collections tab — see §3) |
| Show all Movies | pill | `brunoMoviesGrid` → `BrunoMediaView(.movie)` A–Z |
| Show all TV | pill | `brunoTVGrid` → `BrunoMediaView(.series)` A–Z |
| Back to Top | pill | scroll to hero |

---

## 3. Collections (`BrunoCollectionsView` → `BrunoCategoryShelves`)

`Swiftfin tvOS/Views/BrunoHomeView/BrunoCollectionsView.swift` + shared
`BrunoCategoryShelves.swift`. **Rewritten 2026-07-01 for the shipped §1 Curated retirement +
two-row strip + procedural tail.** Category set from `BrunoCollectionCategory.fromSnapshot`
(`BrunoCategoryShelves.swift:156`) + the synthetic "Boxed Sets" (from the snapshot's cached
`franchiseBoxSets`). Fixed rank order via `rank(for:)` (`:96`): New Releases, Oscars, Roger Ebert,
Critically Acclaimed, Rewatchables, Film School Classics, Asian Cinema, Directors, Movie Stars,
Boxed Sets, Decades, Studios, Seasonal, Cities (Seasonal promoted to 2nd during its Oct–Dec window).
"Genres" is dropped from every group-tile surface (it IS the Movies tab).

The surface has three parts, top to bottom:

1. **Two-row card strip** — `BrunoCategoryCardRow(twoRow: true)`, Collections hub only. Owner-placed
   membership, hardcoded in `row1Order`/`row2Order` (`BrunoCategoryCardRow.swift:45-51`). Row 1
   ("how to browse"): New Releases · Directors · Movie Stars · Decades · Studios · Boxed Sets ·
   Cities. Row 2 ("what to watch"): Roger Ebert · Rewatchables · Oscars · Seasonal · Asian Cinema ·
   Film School Classics · Critically Acclaimed. Unlisted groups append to Row 2.
2. **Static preview shelves** — one per category, EXCEPT Roger Ebert and Cities (excluded: their
   children are BoxSet posters, not movies — `BrunoCategoryShelves.swift:437-439`; their cards still
   work). The curated-named shelves (Oscars, Critically Acclaimed, Rewatchables, Film School
   Classics, Asian Cinema, Seasonal) shuffle their RELATIVE order once per launch
   (`shuffledCuratedOrder`, `:327`); browse hubs keep their slots.
3. **Procedural tail** — `BrunoHomePlan.collectionsTail` (`BrunoHomePlan.swift:599`), seeded per
   launch (`BrunoCollectionsViewModel.tailSeed`), rendered below the statics with the same
   cap-and-grow window. Families: guaranteed Ebert Thumbs Up + Down (captioned; the ONLY Ebert
   movie shelves in Collections now), Year in Film ×3, Best of the Decade ×3, Rewatchable
   {Decade}s ×3, promoted-curated ×6 (captioned), Director in Focus ×6, Actor in Focus ×6
   (from the Movie Stars group). Fully seed-shuffled (`:696`); deduped by id + content, no
   adjacency rule. Each tail shelf renders via `BrunoShelfView` with a Home-style Show-all.

**Preview caps (raised 2026-06-30):** weighted-random 16 for BoxSet-children groups
(Efraimidis–Spirakis on `childCount^0.6`, day-seeded — `weightedPreview`,
`BrunoCategoryShelves.swift:711`); plain `prefix(30)` otherwise (`shelfCap = 30`, `:313` — note this
is a DIFFERENT constant from `BrunoHomePlan.shelfCap = 18`, which caps Home shelf COUNT).

| Shelf | Lens/eyebrow | Derived from | Preview | Show-all destination | notes |
|---|---|---|---|---|---|
| New Releases | Home Premiere | flat group, members are movies, `showsDate` | 30 | `brunoBoxSetGrid(portrait, showsDate, newest-first)` | |
| Oscars | Academy Awards | Oscars group's 6 `Oscar <Category>` BoxSets | weighted 16 (`0x91A3`) — in practice all 6 | `.shelves` → `brunoCategoryShelves(parent, subGroups: children)` → six captioned shelves (§3b) | inline tile tap opens stock `.item` BoxSet detail (divergence, §8 #7) |
| Roger Ebert | Roger Ebert | group with 2 Ebert BoxSets | NO inline shelf | card → `brunoEbert(up, down)` toggle grid directly (`BrunoCategoryCardRow.swift:123-127`) | |
| Critically Acclaimed / Film School Classics / Asian Cinema | Critics' Picks / Required Viewing / World Cinema | flat promoted film groups (§1) | 30 | `.grid` → `ItemLibrary(parent)` | |
| Rewatchables | Always Worth Rewatching | flat favorited group, members are movies | 30 | `.rewatchables` → `BrunoRewatchablesView` (§3c) | |
| Directors | Auteurs | Directors group boxSet children | weighted 16 (`0x91A3`) | `brunoBoxSetGrid(portrait, artCarousel, hero band, Household Names)` | |
| Movie Stars | Movie Stars | Movie Stars group boxSet children | weighted 16 (`0x91A3`) | `brunoBoxSetGrid(portrait, artCarousel, hero band)` | |
| Boxed Sets | Franchises | synthetic: snapshot `franchiseBoxSets` (see Terminology, `BRUNO_CODE_MAP.md`) | weighted 16 (`0xB075`) | `.items` → `brunoBoxSetGrid(landscape, collectionLabel, hero band)` | |
| Decades | Through the Years | Decades group boxSet children; cards backed by `decadeBestOf` covers | 30 | `.shelves` → drill-in (§3a) | inline decade-tile tap ALSO opens the pill view (`BrunoCategoryShelves.swift:593`, rerouted 2026-06-30) |
| Studios | From the Vault | Studios group boxSet children | weighted 16 (`0x5747`) | `brunoStudiosGrid` (Household Names + A–Z) | |
| Seasonal | In Season | Seasonal group children (ranks 2nd only Oct–Dec) | 30 | `.grid` default | static-cover treatment was tried and REVERTED 2026-06-30 |
| Cities | On Location | Cities group (Chicago Movies, …) | NO inline shelf | `.shelves` → generic shelf-per-city drill | |

`drillStyle(for:)` (`BrunoCategoryShelves.swift:118`): genres→`.genres`, decades→`.shelves`,
oscars→`.shelves`, roger ebert→`.shelves` (special-cased to the toggle grid in the router),
cities→`.shelves`, rewatchables→`.rewatchables`, everything else→`.grid`. Boxed Sets is built
explicitly as `.items`.

### 3a. Decades drill-in (`BrunoBoxSetShelvesView`, `isDecades==true`)

`Swiftfin tvOS/Views/BrunoHomeView/BrunoBoxSetShelvesView.swift`. Pill row ("All" + each decade).
"All" shows one shelf per decade; selecting a decade pill swaps to per-year shelves
(`loadYearShelves` `:685`, debounced ~500 ms, memoized). Per-year built in `yearCategories` (`:738`).

| Shelf | Lens/eyebrow | Derived from | Max | Show-all destination (filter carried) | shelf/grid |
|---|---|---|---|---|---|
| Best of the {Decade} | (decade lens) | `bruno-sig:<NN>` tag, significance-desc; shown only if ≥8 tagged films | 15 | `.grid` `gridParent=decade, gridYear=nil` → `ItemLibrary(decade)` **unfiltered** — significance order is NOT carried | shelf |
| {Year} | A Year in Film | Per-year bucket of the decade's complete fetch, premiere-desc | all in year | `.grid` `gridParent=decade, gridYear=year` → `ItemLibrary(decade, years:[year])` — **year filter carried** | shelf |
| Other | (decade lens) | Out-of-window / yearless films | all | `.grid` `gridParent=decade, gridYear=nil` → `ItemLibrary(decade)` unfiltered | shelf |
| {Decade} (non-splittable, e.g. "1950s & Earlier") | — | Whole bucket as one grid | all | `ItemLibrary(decade)` unfiltered | shelf |

### 3b. Oscars drill-in (`BrunoBoxSetShelvesView` with `subGroups`) — replaces the retired Curated drill-in

**The Curated drill-in is GONE (§1 migration, 2026-06-30).** The Curated group was unfavorited on the
server; its film-bearing children were promoted (Oscars + Roger Ebert parent groups; Asian Cinema /
Film School Classics / Critically Acclaimed as flat top-level groups). The old in-app consolidation
machinery (`consolidateOscars` / `consolidateEbert` / `cardRowCategories` / `curatedRandomShelves`,
`BrunoBoxSetShelvesView.swift:128-169/:704`) is now dead-in-practice — it keyed off a drill parent
literally named "Curated", which no route produces. Deletion is a pending owner call (tracker).

The live path: the **Oscars card** routes `.shelves` with the six real `Oscar <Category>` BoxSets as
`subGroups` (`BrunoCategoryCardRow.swift:129-132`), so `BrunoBoxSetShelvesView` fans out one shelf per
category through its normal `performLoad`:

| Shelf | Lens/eyebrow | Derived from | Preview | Show-all destination | shelf/grid |
|---|---|---|---|---|---|
| {Oscar Category} ×6 | Academy Awards | the six Oscar BoxSets, each fetched with `.tags`; **reverse-chron by award year** + per-category seeded lead-spread (`BrunoOscar.spreadLeads`, IA §4) | 13 fetch (`perShelfFetch`) | `.grid` → **`brunoBoxSetGrid`** in Oscar mode (`oscarParent` pages the FULL category, reverse-chron, captioned) — NOT stock `ItemLibrary` | shelf |

**Oscars order + caption:** each shelf (and its "Show all" grid) orders films **newest-first by award
year** and renders a per-poster *Winner (Year)* / *Nominee (Year)* line (`BrunoOscarContentView`).
Source is the per-item tag `oscar:<CATEGORY>:<won|nom>:<YEAR>`, stamped by the producer's unified
`Apply-Enrich-Tags.command` (idempotent; supersedes `p9_oscars.py`). Degrades gracefully pre-stamp:
no tag ⇒ blank (height-reserving) caption line, order falls back to premiereDate. The old gold-tile
gate (`BrunoCategoryShelves.swift:579`, synthetic id `curated-oscars`) is unreachable; keep-vs-rebuild
is an open owner design call (tracker).

### 3c. Rewatchables drill-in (`BrunoRewatchablesView`)

`Swiftfin tvOS/Views/BrunoHomeView/BrunoRewatchablesView.swift` (#40). The favorited "Rewatchables"
BoxSet (flat — members are movies) is rendered as a **single cinematic flat grid** (portrait, 7-across
`LazyVGrid`, `:155`) under a full-bleed `RewatchablesHero` band, in the item-detail `CinematicScrollView`
shape — **not** broad-genre shelves. A **"Browse by" genre pill row** above the grid sub-filters it in
place (no per-genre shelves, no per-bucket Show-all). Each poster is captioned **"Episode NN"** from the
`rewatchables-ep:NN` tag (`showsEpisode` prop, `BrunoCategoryShelves.swift:236`/`:511`); a poster tap
opens stock `.item` detail (`BrunoRewatchablesView.swift:158`).

| Surface | Lens/eyebrow | Derived from | Max | Destination | shelf/grid |
|---|---|---|---|---|---|
| **GRID** — Rewatchables | Always Worth Rewatching | The Rewatchables BoxSet (flat), filtered in place by the "Browse by" genre pill | all (pill-filtered) | poster tap → `.item` detail | terminal grid |

---

## 4. Movies / Genres (`BrunoMoviesView` → `BrunoGenresView`)

`Swiftfin tvOS/Views/BrunoHomeView/BrunoMoviesView.swift` resolves the "Genres" group boxSet from the
snapshot and hands it to `BrunoGenresView` (core-genre pills + a shelf per sub-genre), which loads
through the shared `BrunoBoxSetShelvesViewModel`. Sub-genre rows show the FULL membership — no
modern-year filter (that filter applies only to the HOME genre shelves via `BrunoHomePlan.genreQuery`);
`recencyBiased` here drives the per-launch row reshuffle + the newest-first Show-all sort (pre-1985
films sink to the bottom of the grid, never hidden). Row order: per-launch seeded reshuffle
(`rowOrderSeed`), 6 lead genres pinned first (`priorityGenreOrder`,
`BrunoBoxSetShelvesView.swift:440`). Pills are the owner-authored `BrunoCoreGenre.all` exact-name
buckets (`BrunoGenresView.swift:39-94`); a pill filters the loaded shelves in place (debounced 500 ms).
**84** sub-genre BoxSets total (live, §0). Trailing "All Movies" pill → `brunoMoviesGrid`.

| Shelf | Lens/eyebrow | Derived from | Preview | Show-all destination (filter carried) | shelf/grid |
|---|---|---|---|---|---|
| {Sub-genre} | If You Like | Genre group boxSet child; fetch 60, day-seeded child shuffle | `prefix(30)` (`shelfCap = 30`; the weighted `0xC0DE` preview applies only to the Collections-hub Genres card path, which is dropped) | `ItemLibrary(genre boxSet, sortBy:premiereDate desc)` — **recency sort carried** | shelf |
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
| 1 | **Decades → Best of the {Decade}** (§3a) | significance-ordered top ≤15 (`bruno-sig`) | `ItemLibrary(decade)` **unfiltered, default sort** | Show-all drops the curation entirely — you get the whole decade, not "the best of." `gridYear=nil`, no sig filter. (`BrunoBoxSetShelvesView.swift:781-787`, `yearCategory :836`) |
| 2 | **Decades → Other** (§3a) | out-of-window/yearless subset | `ItemLibrary(decade)` unfiltered | "Other" Show-all yields the full decade, not just the Other bucket (no filter exists for it). |
| 3 | **Genre row (Movies / spine) vs Genre Show-all grid** | modern-only (years ≥ `modernCutoff`) | `ItemLibrary(genre, premiereDate desc)` — **all years** | Deliberate (owner: classics sink to bottom, not hidden), but the inline set ≠ grid set. Flag for de-dupe awareness, not a bug. (`BrunoHomePlan.genreQuery :367`; route `BrunoCategoryCardRow.swift:196`) |
| 4 | **Home spine "Eras" / "Browse by Director" / "Browse the Collection" tiles** | portrait tiles | **Resolved by #41 (D2) + #46.** Eras tile-tap deep-links the decade pill (#41 D2); **Browse the Collection now renders the Collections-tab `BrunoCategoryCardRow` 1:1, so its tiles route via `brunoRouteToShowAll`** (#46). | Residual narrowed to **Browse by Director (Auteurs) only**: a Director tile-tap still opens stock `.item` detail. |
| 5 | **Curated drill-in sub-collection Show-all** (§3b) vs **Curated tab card** | sub-collection preview | `ItemLibrary(curated boxSet)` no year filter | Curated never carries a year/era filter on Show-all, unlike Decades. Confirm this is intended (curated is hand-picked, so likely fine). |
| 6 | **Boxed Sets card → `.items`** vs other group cards → `.grid` | franchise boxSets | `brunoBoxSetGrid(category.children)` (landscape) | Boxed Sets routes off `category.children` while Directors/Studios route off the filtered `boxSetChildren`. Different code paths in `brunoRouteToShowAll` (`.items` `:133` vs `.grid` `:150`); verify Boxed Sets children never include the group itself. |
| 7 | **Oscars inline shelf tile vs Oscars card/Show-all** (2026-07-01) | 6 statuette BoxSet tiles; a tile TAP opens stock `.item` BoxSet detail (`BrunoCategoryShelves.swift:595`) | card/Show-all → the six captioned reverse-chron shelves (§3b) | Same inline-tap-goes-stock pattern as Directors (see `Documentation/fable-plans/NAVIGATION_MAP.md` §5 J4). Not a bug, but the stock BoxSet page lacks the Winner/Nominee captions. |

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

---

## 10. Item detail — "Recommended" shelf (any poster tap → `ItemView`)

Tapping any poster anywhere opens the stock `ItemView` detail page. Its **"Recommended"** shelf
(`ItemView.SimilarItemsHStack`, `Swiftfin tvOS/Views/ItemView/Components/SimilarItemsHStack.swift:16`)
renders Jellyfin's `/Items/{id}/Similar` result. As of **#66** it is **Bruno-routed**: a snapshot-backed
classifier drops the nav-hub BoxSets, keeps movie/series tiles, and reroutes each genuine collection to
its branded Bruno destination — reusing existing `bruno*` routes, none invented. Mounted (only when
`viewModel.similarItems` is non-empty) by all three content views: `MovieItemContentView.swift:31`,
`SeriesItemContentView.swift:33`, `CollectionItemContentView.swift:110`. Stays one homogeneous
`PosterHStack` (INV-1/-10) — only which tiles show and where a tap lands change.

Engine: `Swiftfin tvOS/Views/BrunoHomeView/BrunoRecommendedShelf.swift` —
`brunoRecommendedTarget(_:snapshot:)` (`:56`, the classifier, first match wins),
`brunoRecommendedDisplayItems(_:snapshot:)` (`:128`, drops `.drop` tiles, preserves endpoint order),
`routeBrunoRecommended(_:snapshot:router:namespace:)` (`:138`, the tap router). Identity resolves off
the warm `BrunoLibrarySnapshot.loadShared`. **FAIL-OPEN rule (hotfix `6ec18cab`, supersedes the
original #66 behavior):** only a POSITIVELY-recognized nav hub is dropped; an unrecognized BoxSet —
including anything seen before the snapshot is warm — keeps its tile and routes to stock `.item`
(`BrunoRecommendedShelf.swift:115-121`). Dropping unrecognized tiles emptied the whole shelf on
Director/Actor/Studio detail pages (their similar items are all BoxSets and the snapshot is often
cold). Do not change this back to drop.

| Tile class | Detected by (`brunoRecommendedTarget`) | Destination (`routeBrunoRecommended`) |
|---|---|---|
| Movie / series | not `.boxSet` | `.item` detail (unchanged) |
| Rewatchables | `rewatchablesBoxSet.id` (resolved *before* the hub-drop) | `brunoRewatchables(parent)` — episode-captioned grid |
| Ebert (name "ebert…") | **`promotedCuratedBoxSets`** (§1; resolved *before* the hub-drop) | `brunoEbert(up, down, showingDown)` — Up⇄Down toggle grid |
| Oscar (`BrunoOscarCategory` resolves) | `promotedCuratedBoxSets` | `brunoBoxSetGrid(oscarCategory, oscarParent)` — captioned grid |
| Other promoted set (Asian Cinema / Film School / Critically Acclaimed) | `promotedCuratedBoxSets` | `.library(ItemLibrary(parent))` — films grid (film-bearing groups must NOT be hub-dropped) |
| Nav hub (Directors/Decades/Studios/Oscars parent/Roger Ebert parent/…) | `favoriteGroupBoxSets` | **dropped** |
| Decade | `decadeBoxSets` (+ "Decades" group as parent) | `brunoCategoryShelves(Decades, decade)` — pill pre-set |
| Genre | `genreBoxSets` | `.library(ItemLibrary(parent, premiereDate desc))` — newest-first |
| Director / Studio / Seasonal / Franchise | director/studio/seasonal/franchise BoxSets | `.library(ItemLibrary(parent))` — films grid |
| Unresolved BoxSet / cold snapshot | falls through | **FAILS OPEN → stock `.item` detail** (never dropped) |

Note: director / studio / seasonal / franchise / other-curated all converge on `.library(ItemLibrary(parent:))`,
which also sidesteps recursing back into the stock `CollectionItemContentView`. The Home "Browse by
Director (Auteurs)" tile-tap residual (§8 #4 / §9 #4) is unchanged — that tile still opens the stock
`.item` detail; only the detail page's *own* Recommended shelf is now branded.
