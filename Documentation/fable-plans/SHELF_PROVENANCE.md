# SHELF_PROVENANCE — where every shelf comes from

Authored 2026-07-01 (Fable assessment thread). Verified against worktree HEAD `53685816`
(post IA-overhaul, post same-day reverts). All paths are repo-relative.

**How this doc relates to the canonical maps.** `docs/BRUNO_NAV_MAP.md` stays canonical for
per-surface layout and Show-all destinations. This document answers a different question:
for any shelf that can appear anywhere, WHERE does its content come from. It covers the
producer scripts, the server objects, the app-side query, the code path, the ordering, and
the caps. It also covers bruno-web and the Top Shelf extension, which the nav map does not.
Read this when you need to trace content; read the nav map when you need to trace navigation.

**The test this doc must pass:** a model can answer "where does this shelf come from" for any
shelf without reading code.

---

## 0. The four provenance layers

Every Bruno shelf is the end of this chain. When a shelf looks wrong, walk the chain top down.

```
LAYER 1  Producer scripts (MovieCollection, owner-run, manual)
         write BoxSets + favorites + item tags + artwork to the Jellyfin server
LAYER 2  Jellyfin server objects
         favorited group BoxSets, member BoxSets, movies, item tags
LAYER 3  BrunoLibrarySnapshot (Shared/Objects/Bruno/BrunoLibrarySnapshot.swift)
         one async fetch of library facts; cached in memory (5 min) and on disk (24 h, seed-keyed)
LAYER 4  Shelf construction (three independent builders)
         a) BrunoHomePlan.build / .appendExplore / .collectionsTail  (seeded descriptors)
         b) BrunoCollectionCategory.fromSnapshot + BrunoBoxSetShelvesViewModel  (browse categories)
         c) direct fetches in surface view models (Kids, Media, Ebert, Rewatchables, hero)
```

Two hard rules that govern everything:

1. **Membership is BoxSet-only.** The app cannot select films by tag. Any "set of films" must
   ship as a Jellyfin BoxSet (usually under a favorited group). `BrunoQuery`
   (`Shared/Objects/Bruno/BrunoQuery.swift`) speaks only genre-name, parentID, years, rating,
   person, studio, IsUnplayed/IsFavorite.
2. **Tags are read for display and ordering only.** Captions (`ebert-stars:`, `oscar:`),
   episode numbers (`rewatchables-ep:`), and best-of ordering (`bruno-sig:`) come from item
   tags, fetched only when needed (`BrunoQueryLibrary.swift:56-57`, drill-in
   `fetchChildren` at `BrunoBoxSetShelvesView.swift:1070`).

---

## 1. Layer 1 — the producer (MovieCollection, outside this repo)

Location: `/Users/danielbrunelle/Documents/Claude/MovieCollection` (local-only git repo, no
remote). Full seam doc: `docs/pipeline/README.md`.

**Scheduling truth (verified 2026-07-01): there is NO automated run.** The old daily 10:00
launchd job (`com.diplomacy.jellyfin-collections`) was disabled 2026-06-28 after failing with
HTTP 414; its plist is renamed `*.disabled` in `~/Library/LaunchAgents/`. `crontab -l` is
empty. Every producer run is owner-run by hand. Consequence for the app: server-side changes
appear only after an owner run PLUS the app-side cache TTLs below.

| Producer entry point | Server objects it creates or mutates |
|---|---|
| `Build-Jellyfin-Collections.command` | Directors, Decades, Genres (broads + combos + romance sub-genres), Studios, Seasonal, New Releases BoxSets; the group tiles; generated card art; studio blurbs. Favorites the group tiles. Live-writes, no dry-run mode. |
| `enrich/p6_project.py` (`LIVE=1`) | ~87 BoxSets from the feature store: sub-genre and discovery shelves under Genres, the six `Oscar <Category>` sets, Ebert Thumbs Up/Down, seasonal extras, the favorited Movie Stars group. |
| `enrich/p7_brunosig.py` | `bruno-sig:<NN>` tags (0-100 significance) on movies. |
| `enrich/p8_rewatchables.py` | Flat favorited Rewatchables BoxSet (~214 films) + `rewatchables-ep:<N>` tags. |
| `Apply-Enrich-Tags.command` | `ebert-stars:<n>`, `ebert-verdict:<up|down>`, `oscar:<CATEGORY>:<won|nom>:<YEAR>` tags (idempotent, strips and re-adds; supersedes `p9_oscars.py`). |
| One-off migrations (2026-06-30) | `migrate_curated_retire.py` (un-favorite Curated; favorite Oscars, Roger Ebert, Asian Cinema, Film School Classics, Critically Acclaimed), `create_cities_group.py` (favorited Cities group), `create_hughes_override.py` (John Hughes nesting). |
| `Apply-BoxedSet-Art.command`, `Apply-Studio-Logos.command` | Artwork only (franchise Thumbs, studio logos/cards). No membership changes. |

**Tag grammars (exact):** `bruno-sig:<NN>` · `rewatchables-ep:<N>` ·
`oscar:<CATEGORY>:<won|nom>:<YEAR>` with CATEGORY in {BEST_PICTURE, DIRECTING, ACTING,
CINEMATOGRAPHY, SCORE, SCREENPLAY} · `ebert-stars:<n>` (halves, e.g. `3.5`) ·
`ebert-verdict:<up|down>`.

**Franchise BoxSets are NOT producer-made.** TMDB "X Collection" sets are left untouched by
the builder; only their art is repainted. The app derives the franchise list itself (layer 3).

---

## 2. Layer 3 — the snapshot (what the app knows about the library)

`BrunoLibrarySnapshot.load` (`Shared/Objects/Bruno/BrunoLibrarySnapshot.swift:138`) fetches,
concurrently: favorited BoxSets (limit 50), each group's children (`ParentId={group}`, NO type
filter, limit 200), genre names (limit 60), production years (from 400 newest movies), ALL
BoxSets (limit 1000, for the franchise derivation), and a best-of film per decade (highest
`bruno-sig:`, else highest rating).

Accessor map (all resolve group children by case-insensitive NAME, never by hardcoded id):

| Accessor | Server group | Consumed by |
|---|---|---|
| `directorBoxSets` | Directors | Home spotlight + Auteurs shelves, Collections tail, Directors grid |
| `actorBoxSets` | Movie Stars | Collections tail Actor-in-Focus |
| `decadeBoxSets` | Decades | Home Eras + decade generator, Decades drill-in, Recommended classifier |
| `studioBoxSets` | Studios | Home studio shelves, Studios grid |
| `genreBoxSets` | Genres | Home subgenre generator, Recommended classifier |
| `promotedCuratedBoxSets` | children of Oscars + Roger Ebert, plus the 3 flat promotes (Asian Cinema, Film School Classics, Critically Acclaimed) | Home curated generator, Collections tail, Ebert/Oscar routing, Recommended classifier. **This replaced `curatedBoxSets` in the 2026-06-30 §1 migration.** |
| `curatedBoxSets` | Curated (retired, now empty) | legacy accessor; do not use for new work |
| `seasonalBoxSets` | Seasonal | Home seasonal generator |
| `rewatchablesBoxSet` | Rewatchables (flat, members are movies) | Rewatchables shelves + grid |
| `franchiseBoxSets` | derived: all BoxSets minus groups minus group children minus director-name dupes | the synthetic Boxed Sets tile |
| `decadeBestOf` | derived per decade from `bruno-sig:` tags | Eras card covers, Decades card covers |
| `genres` / `years` | live genre names / production years | genre + year shelves |

**Freshness:** in-memory snapshot cache 5 min (`loadShared`, `:358`); Home disk payload 24 h,
keyed by (seed, userID) (`BrunoHomeCache`); drill-in caches 5 min memory + 7 day disk
stale-while-revalidate (`BrunoBoxSetShelvesCache`/`DiskCache`,
`BrunoBoxSetShelvesView.swift:1101/:1144`). Shuffle forces a fresh snapshot pull.

---

## 3. Shelf census — native app

Column key. **Source**: the layer-4 builder. **Query/filter**: what is fetched.
**Order**: what the user sees. **Owner**: Bruno or stock Swiftfin.

### 3a. Home spine (`BrunoHomePlan.build`, `Shared/Objects/Bruno/BrunoHomePlan.swift:56`)

Fixed order; contents reseed by the day-stable seed (Shuffle re-rolls). The spine is
deterministic: same (seed, snapshot, now) gives the same Home (INV-3, DEBUG-asserted).
`BrunoHomePlan.shelfCap = 18` caps the NUMBER OF SHELVES in the initial plan, not items per
shelf. Per-shelf items come from `BrunoQuery.limit` (default 60), paged by
`PagingLibraryViewModel`, revealed incrementally by `BrunoShelfMetrics` reveal constants.

| Shelf | Source + query | Order | Owner |
|---|---|---|---|
| Continue Watching | stock `ResumeItemsLibrary` (live user state) | server resume order | stock lib, Bruno render |
| Up Next | stock `NextUpLibrary` | server | stock lib, Bruno render |
| Just Added | stock `RecentlyAddedLibrary` (dateCreated = added to library) | newest added first | stock lib, Bruno render |
| New Releases | `BrunoQuery` movies, sortBy premiereDate desc, limit 20 (`newReleasesShelf`, `:434`) | newest world premiere first, never shuffled | Bruno |
| {Year} & Around ×3 | `BrunoQuery years=[y-2...y+2]`, 3 distinct seeded years (`yearShelf`, `:415`) | seeded shuffle | Bruno |
| Spotlight on {Director} | seeded pick of `directorBoxSets` then `parentID` members (`:96`) | seeded shuffle | Bruno |
| {Genre} (If You Like) | seeded genre name, years >= `BrunoRecencyBias.modernCutoff` only (`genreQuery`, `:367`) | seeded shuffle | Bruno |
| Classic Romance | Romance genre, years < modernCutoff (`classicRomanceShelf`, `:378`); dropped if no Romance genre or < 2 vintage years | seeded shuffle | Bruno |
| Series in the Library | `BrunoQuery includeItemTypes=[.series]` (`:130`) | seeded shuffle | Bruno |
| {Studio} From the Vault | seeded pick of `studioBoxSets` then parentID members (`:146`) | seeded shuffle | Bruno |
| Eras (decade tiles) | `.items(decadeBoxSets.reversed())` (`:159`), covers from `decadeBestOf` | newest decade first | Bruno |
| Browse by Director (Auteurs) | `.items(directorBoxSets.prefix(14))` (`:172`) | server order | Bruno |
| Browse the Collection | `.items` = `BrunoCollectionCategory.fromSnapshot` tiles, Genres tile dropped (`:185`) | `rank(for:)` fixed order | Bruno |

### 3b. Home explore tail (`explore(key:)`, `BrunoHomePlan.swift:254`)

11 keys, walked shuffled, +2 shelves per scroll page, 5 reseed blocks, hard ceiling 120
mounted sections. Dedupe across the whole session by `dedupeKey`.

| Key | Shelf | Source + query | Order |
|---|---|---|---|
| `acclaimed` | Acclaimed & Unwatched | rating >= 8.1 AND IsUnplayed | rating desc, seeded shuffle |
| `critics` | Critics' Highest Rated | rating >= 7.5, limit 15 | rating desc, NOT shuffled |
| `genre` | {Genre} | seeded genre name, modern years only | seeded shuffle |
| `subgenre` | {Sub-genre} (Deeper Cuts) | seeded pick of `genreBoxSets`, parentID members (`:299`) | seeded shuffle |
| `studio` | {Studio} | seeded pick of `studioBoxSets` | seeded shuffle |
| `decade` | Hidden in the {Decade} | seeded pick of `decadeBoxSets` | seeded shuffle |
| `spotlight` | Spotlight on {Director} | seeded pick of `directorBoxSets`, different salt than spine | seeded shuffle |
| `curated`, `world` | {Promoted curated set} | seeded pick of **`promotedCuratedBoxSets`** (`:337`); Ebert/Oscar picks render portrait with star/Winner captions (`BrunoShelfCaption`) | seeded shuffle; caption drives the `.tags` fetch |
| `seasonal` | {Seasonal} Picks | date-aware (Dec christmas / Oct halloween / Jul july) else seeded pick of `seasonalBoxSets` (`:490`) | seeded shuffle |
| `rewatchables` | Rewatchable {Genre} | `rewatchablesBoxSet` parentID INTERSECT one of 6 broad genres (`:523`) | seeded shuffle |

### 3c. Home hero, footer, Show-all

- **Hero**: 30 movies with rating >= 8.2, Horror filtered out (`brunoHeroEligible`), 5 shown
  in a fresh RANDOM order per entry (`BrunoHomeViewModel.loadHero`, `:409`). Deliberately not
  seeded. Superset persisted; picks never persisted (INV-5).
- **Terminal footer** (after tail exhaustion): the `fromSnapshot` category tiles again + Show
  all Movies / Show all TV pills (`BrunoHomeView.swift:178-196`).
- **Show-all**: every Home shelf routes through `brunoHomeRouteToShowAll`
  (`BrunoHomeShowAll.swift:35`, sole caller `BrunoShelfView.swift:205`). Query shelves open
  their own paged query (`BrunoQueryLibrary`); year/decade/Eras deep-link the Decades pill
  surface; captioned Ebert/Oscar shelves open the toggle/captioned grids.

### 3d. Collections tab (`BrunoCollectionsView` + `BrunoCategoryShelves`)

Three parts, top to bottom:

1. **Two-row card strip** (`BrunoCategoryCardRow`, `twoRow: true`). Owner-placed membership,
   hardcoded in `row1Order`/`row2Order` (`BrunoCategoryCardRow.swift:45-51`). Row 1 browse
   hubs: New Releases, Directors, Movie Stars, Decades, Studios, Boxed Sets, Cities. Row 2
   curated: Roger Ebert, Rewatchables, Oscars, Seasonal, Asian Cinema, Film School Classics,
   Critically Acclaimed. Tiles route via `brunoRouteToShowAll` by `drillStyle`.
2. **Static category preview shelves** (`BrunoCategoryShelves`, one per category from
   `fromSnapshot`). Roger Ebert and Cities previews are EXCLUDED (their children are BoxSet
   posters, not movies; `BrunoCategoryShelves.swift:437-439`). The curated-named shelves
   shuffle their relative order once per launch (`shuffledCuratedOrder`, `:327`); browse hubs
   keep their slots. Preview caps: weighted-random 16 for BoxSet-children groups
   (Efraimidis-Spirakis on childCount^0.6, day-seeded, `weightedPreview` `:711`); plain
   `prefix(30)` otherwise (`shelfCap = 30`, `:313`).
3. **Procedural tail** (`BrunoHomePlan.collectionsTail`, `BrunoHomePlan.swift:599`), seeded
   with a per-launch nonce (`BrunoCollectionsViewModel.tailSeed`). Families: guaranteed Ebert
   Thumbs Up + Down (captioned), Year in Film ×3, Best of the Decade ×3, Rewatchable
   {Decade}s ×3 (parentID INTERSECT decade years), promoted-curated ×6 (captioned),
   Director in Focus ×6, Actor in Focus ×6 (from `actorBoxSets`). The whole tail is
   seed-shuffled at the end (`:696`); deduped by id + content, NO adjacency rule.

### 3e. Collections drill-ins

| Drill-in | Trigger | Shelf construction | Order |
|---|---|---|---|
| Decades overview | Decades card / Eras Show-all | one shelf per decade BoxSet (`BrunoBoxSetShelvesViewModel.performLoad`) | decades newest-first; children day-seeded shuffle |
| Decade pill selected | pill commit (debounced 500 ms) | that decade's COMPLETE film set fetched once (`loadYearShelves`, `:858`), rebucketed: "Best of the {Decade}" (top 15 by `bruno-sig:`, shown only if >= 8 tagged), one shelf per year, then "Other" | best-of: significance desc; years: newest year first, premiereDate desc inside |
| Oscars | Oscars card (`drillStyle .shelves` with `subGroups` = the six category BoxSets) | six shelves via `performLoad` provided-subGroups path | reverse-chron by `oscar:` award year + per-category seeded lead-spread (`BrunoOscar.spreadLeads`); Winner/Nominee captions |
| Roger Ebert | Roger Ebert card | NO shelf drill: opens the merged Up/Down toggle grid directly (`brunoRouteToShowAll` `.shelves` special case, `BrunoCategoryCardRow.swift:123`) | see 3g |
| Cities | Cities card (`.shelves`) | generic shelf per city child (Chicago, ...) | server order, day-seeded child shuffle |
| Rewatchables | Rewatchables card (`.rewatchables`) | single flat portrait grid, `BrunoRewatchablesView` | BoxSet order; "Browse by" pills sub-filter in place by raw TMDB genres; "Episode NN" captions from `rewatchables-ep:` |
| Boxed Sets | Boxed Sets card (`.items`) | static landscape grid of `franchiseBoxSets` | weighted preview 16 on the shelf; grid lists all |
| Directors / Movie Stars | cards (`.grid` with BoxSet children) | `brunoBoxSetGrid` portrait art-carousel grid + Household Names marquee (Directors) | A-Z; marquee curated list |
| Studios | Studios card | `brunoStudiosGrid` cinematic grid | daily-seeded Household Names section + full A-Z |

### 3f. Movies tab (the genre browse surface)

`BrunoMoviesView` resolves the Genres group from the snapshot and renders `BrunoGenresView`
(`isTabRoot: true`). Falls back to the A-Z grid if no Genres group exists.

- **Core pills**: `BrunoCoreGenre.all` (`BrunoGenresView.swift:39-94`), an owner-authored
  exact-name map of sub-genre BoxSet names to 11 buckets. A pill filters the loaded shelves
  in place (debounced 500 ms). A renamed server BoxSet falls out of its pill until the map
  is updated (still under "All").
- **Sub-genre shelves**: one per Genres-group child BoxSet, built by the SAME
  `BrunoBoxSetShelvesViewModel` the drill-ins use. Full membership (fetch 60), row order
  reshuffles per launch (`rowOrderSeed` = launch nonce + 6 h bucket), 6 lead genres pinned
  in fixed order (`priorityGenreOrder`). Preview shows `prefix(30)` of the day-shuffled
  children. Show-all: `ItemLibrary(genre BoxSet, premiereDate desc)` so pre-1985 films sink
  to the bottom (recency-bias rule).
- **All Movies pill** (top and footer): `brunoMoviesGrid`.

### 3g. Standalone Bruno surfaces

| Surface | Data | Order | File |
|---|---|---|---|
| Ebert toggle grid | BOTH Ebert BoxSets' full memberships (limit 1000) with `.tags` + `.genres`; flip toggle swaps set/sort/pills | Up: stars desc; Down: stars asc (`BrunoEbert.ordered`); star captions | `BrunoEbertView.swift` |
| Rewatchables grid | Rewatchables BoxSet members, pill row filters by broad TMDB genre in memory | BoxSet order; Episode NN captions | `BrunoRewatchablesView.swift` |
| All Movies / All TV (A-Z) | `Paths.getItems includeItemTypes=[type] sortBy=sortName`, paged to completion (`BrunoItemPaging.fetchAll`) | A-Z; hero = 5 random of top 30 backdrop-bearing | `BrunoMediaView.swift` |
| Kids | merged kids parent libraries (movies + series), `KidsFilter` pills (All/Movies/TV/Pixar/Disney; Disney excludes Pixar) filter in memory | merged order | `BrunoKidsView.swift` |
| BoxSet grid | static `items:` passed by the router; cinematic mode when `heroAsset` set; `oscarParent` mode pages the full category live | as passed (or reverse-chron for Oscar mode) | `BrunoBoxSetGridView.swift` |
| Studios grid | static studio BoxSets | Household Names (<= 12, membership stable, order rotates daily) + A-Z | `BrunoStudiosGridView.swift` |

### 3h. Item detail (stock `ItemView`) — the Recommended shelf

Any poster tap opens stock `ItemView`. Its "Recommended" shelf renders Jellyfin
`/Items/{id}/Similar`, filtered and rerouted by Bruno (#66 + fail-open hotfix):

| Similar tile | Classifier result (`brunoRecommendedTarget`, `BrunoRecommendedShelf.swift:56`) | Tap destination |
|---|---|---|
| movie / series | `.item` | stock detail |
| Rewatchables BoxSet | `.rewatchables` | episode-captioned grid |
| promoted curated (Ebert / Oscar / flat promotes) | `.ebert` / `.oscar` / `.filmsGrid` (resolved BEFORE the hub drop) | toggle grid / captioned grid / films grid |
| other favorited group (nav hub) | `.drop` | not shown |
| decade BoxSet | `.decade` | Decades pill surface, pill pre-set |
| genre BoxSet | `.genreGrid` | newest-first films grid |
| director / studio / seasonal / franchise BoxSet | `.filmsGrid` | paged films grid |
| unrecognized BoxSet or cold snapshot | **`.item` (FAILS OPEN, stock detail)** | stock BoxSet detail |

The fail-open line is load-bearing: dropping unrecognized BoxSets emptied the whole shelf on
Director/Actor/Studio detail pages (their similar items are all BoxSets and the snapshot is
often cold). Do not change it back to drop. Everything else on `ItemView` (cast row, special
features, genres bar, Play) is stock Swiftfin, untouched.

### 3i. Top Shelf extension (`BrunoTopShelf/ContentProvider.swift`)

Two `TVTopShelfItemCollection` rows fetched directly with stored credentials
(`BrunoTopShelfCredentials`): Continue Watching (resume items, `:117`) and Latest (`:130`).
Independent of the app's snapshot/plan pipeline. Owner must still create the target/App
Group (tracker item).

---

## 4. Shelf census — bruno-web (proof of concept, reference only)

`/Users/danielbrunelle/Documents/Claude/Projects/bruno-web/src/` (one screen; decision
record, do not extend):

| Shelf | Query (`src/api/jellyfin.js`) | Order |
|---|---|---|
| Hero | first Recently Added movie | newest |
| Browse the Collection | `IncludeItemTypes=BoxSet&IsFavorite=true` | client sort by SortName |
| Recently Added | movies, `SortBy=DateCreated desc, Limit=20` | newest added |
| Surprise Me | movies, `SortBy=Random, Limit=20` | server random, UNSEEDED (predates the determinism rule) |

---

## 5. Caps, seeds, and determinism — the confusion killers

**Two different `shelfCap`s exist. They are unrelated.**

| Constant | Value | Means |
|---|---|---|
| `BrunoHomePlan.shelfCap` (`BrunoHomePlan.swift:26`) | 18 | max SHELF COUNT in the initial Home plan (`dedupedAndCapped`, `:584`) |
| `BrunoCategoryShelves.shelfCap` (`BrunoCategoryShelves.swift:313`) | 30 | max PREVIEW ITEMS per browse shelf (raised from 14, 2026-06-30) |

Other caps: `BrunoQuery.limit` default 60 (Home per-shelf page size); weighted previews
hardcode 16 (`shelfItems`, `BrunoCategoryShelves.swift:635/:647/:649`); drill-in preview
fetch 13 (`perShelfFetch`), genres 60; Eras tiles all decades; Auteurs 14 directors.

**Seed inventory** (every randomness source; anything not listed here must not be random):

| Seed | Lifetime | Drives |
|---|---|---|
| day seed (`Defaults[.brunoSeed]`, `BrunoHomeViewModel.resolveDaySeed`) | one day; Shuffle re-mints | Home spine + explore tail (INV-3 deterministic) |
| hero pick | every Home entry | the 5 hero spotlights (intentionally random) |
| `BrunoCollectionsViewModel.tailSeed` | per launch | Collections procedural tail lineup |
| `BrunoCategoryShelves.curatedShuffleSeed` | per launch | relative order of curated-named static shelves |
| `BrunoCategoryShelves.dailySeed` | per day | weighted previews (Studios/Directors/Boxed Sets rotation) |
| `BrunoBoxSetShelvesViewModel.shuffleSeed` | per day | drill-in child shuffles |
| `BrunoBoxSetShelvesViewModel.rowOrderSeed` (launch nonce + 6 h bucket) | per launch | Movies-tab genre row order, Oscar lead-spread |
| `BrunoMediaView` hero | per load | A-Z grid hero picks |

Determinism boundaries: the Home SPINE is the only surface under the strict INV-3 contract
(same seed, same home; DEBUG self-check asserts it). Browse surfaces sit inside the
documented INV-3 carve-out: order may reshuffle per launch or per day, but never mid-session,
and never from `Date()` read inside `BrunoHomePlan.build`.

---

## 6. Dead or legacy provenance paths (do not trace through these)

| Symbol | Status |
|---|---|
| `BrunoLibrarySnapshot.curatedBoxSets` | legacy; the Curated group is unfavorited so it resolves empty. Replaced by `promotedCuratedBoxSets`. |
| `consolidateOscars` / `consolidateEbert` / `cardRowCategories` non-nil branch / `curatedRandomShelves` (`BrunoBoxSetShelvesView.swift:128-169/:704`) | unreachable: they key off a drill parent literally named "Curated", which no route produces post-retirement. Owner call pending on delete vs re-home (tracker). |
| the `curated-oscars` gold-tile row (`BrunoCategoryShelves.swift:579`) | unreachable for the same reason; the live Oscars drill uses the real favorited group + `subGroups`. |
| `NavigationRoute.brunoItemsGrid` (`Shared/Objects/Bruno/BrunoStaticItemsLibrary.swift:46`) | zero callers found (2026-07-01). |
| web `getCollectionItems` (`bruno-web/src/api/jellyfin.js`) | defined, unused. |
