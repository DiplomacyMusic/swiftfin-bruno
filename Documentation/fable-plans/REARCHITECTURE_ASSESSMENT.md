# REARCHITECTURE_ASSESSMENT — duplication, fork drift, and doc drift

Authored 2026-07-01 (Fable assessment thread). Verified against worktree HEAD `53685816`.
Companion docs: `NAVIGATION_MAP.md`, `SHELF_PROVENANCE.md`, `REFACTOR_PLAN.md` (same folder).
All findings below were verified against code with file:line evidence, not taken from older
handoff docs. Where a canonical doc disagreed with code, the doc was fixed in this thread and
the fix is logged in §5.

## Executive summary

- **The engine layer is clean.** `Shared/Objects/Bruno/` (19 files) has one RNG, one query
  type, one paging helper, one snapshot. Two exceptions: one dead file
  (`BrunoStaticItemsLibrary.swift`) and one dead accessor (`curatedBoxSets`).
- **The view layer accretes duplication by copy-porting.** The dominant pattern: a feature
  ships on one surface, then is ported to a sibling surface by copying the body and tweaking
  flags. Three PRs of evidence on the shelf-caption pair alone (Oscars, Ebert, Rewatchables
  each added a flag on one side and an enum branch on the other). One doc
  (`docs/BRUNO_GENRE_PILLS_HOWTO.md`) institutionalizes copying as the porting method.
- **The fork-seam story in the docs is fiction.** `docs/BRUNO_CODE_MAP.md` §2 claimed a
  "COMPLETE sanctioned list" of 4 modified upstream files; the real diff vs merge-base
  `c235dace` touches ~22 upstream source files (§3 below). Fixed in the code map this thread.
- **No rewrite is warranted.** Bruno is a working, private, lowest-priority app with ten
  load-bearing perf invariants encoded redundantly in exactly the duplicated code. The right
  move is a short sequence of small, verifiable consolidations (`REFACTOR_PLAN.md`), most of
  which delete code, plus the doc corrections already landed.

---

## 1. Ranked duplication findings (worst maintenance pain first)

Full evidence (line ranges both sides, INV anchors, verification protocol) lives with each
proposal in `REFACTOR_PLAN.md`. This section is the ranked register.

### F1. Two shelf-row engines: `BrunoShelfView` vs `BrunoShelfRow` (~55% overlap)
The Home shelf (`BrunoShelfView.swift`, 283 ln; VM + lazy reveal) and the browse shelf
(`BrunoShelfRow.swift`, 191 ln; plain array + callbacks) duplicate: twin `Card` enums with
the `"bruno-show-all"` sentinel (`:224-237` vs `:69-79` — INV-2's own text says "mirror
BrunoShelfRow.Card", i.e. the doc admits every fix lands twice); the same caption-view
dispatch (ShelfView switches on `shelf.kind`/`caption` `:94-122`; ShelfRow re-derives it from
an 8-flag explosion `:28-57` with a hand-kept precedence chain `:106-116`); the same
CollectionHStack config block (third copy in `BrunoCategoryCardRow.row` `:94-98`); the same
INV-4 prefetch wiring. **Cost:** every new shelf flavor is a two-sided edit; a missed side is
a silent divergence. **Proposal:** do NOT merge the views (their data models differ);
extract the three shared units (shared Card enum, caption-driven label builder replacing the
flags, one HStack-style modifier). Blast radius: `BrunoCategoryShelves.swift:586` (sole
ShelfRow caller), `BrunoHomeView.swift:148`, `BrunoCategoryShelves.swift:454`, DEBUG
previews. Constraints: INV-1/2/4/10 anchors must survive verbatim in the single copies.

### F2. The genre pill row, ported verbatim three times (+ a Kids sibling)
`BrunoGenresView.corePanel` (origin, `:238-323`) was copy-ported to
`BrunoRewatchablesView` (`:214-276`) and `BrunoEbertView` (`:218-343`, self-labelled
"Verbatim"); `BrunoKidsView` (`:198-238`) is a fourth structural twin. ~90% body overlap:
identical five-piece state, focus choreography (`defaultFocus` once-then-yield), 500 ms
debounced commit. **Worse:** a byte-identical `tmdbGenresByCoreID` bucket-to-TMDB-genre
table is duplicated at `BrunoRewatchablesView.swift:179-209` and
`BrunoEbertView.swift:298-327` — a curation edit to one silently misses the other.
**Proposal:** extract `BrunoPillFilterRow<ID: Hashable>` + move the TMDB table next to
`BrunoCoreGenre` as one function. The table dedupe alone is a 20-line, near-zero-risk win.
**Strategic note:** IA overhaul §6 (reactive Decades hero, the highest-risk open item) says
"build behind a shared-idiom refactor" — this extraction IS that refactor; do it first.

### F3. The cinematic hero-over-grid scaffold: 1 shared band + 3 private copies (~220 dup lines)
`BrunoBrandHeroBand.swift:35-97` was extracted (IA §7) but only `BrunoBoxSetGridView`
consumes it. Verbatim private copies survive in `BrunoStudiosGridView.swift:46-116`,
`BrunoRewatchablesView.swift:91-150` ("A LITERAL copy", its own header), and
`BrunoEbertView.swift:106-170` ("A clone", its own header). Already a tracker item.
**Proposal:** fold all three onto the band (Ebert needs the backdrop asset to be re-render
capable for its verdict flip; trivial). Pure visual code; screenshot-diff verifiable. The
INV-6 owner-override comment must travel with it.

### F4. Two focus-art-cycling stacks — duplication PLUS a latent reuse bug
Canonical: `BrunoFocusArtCycle` + `BrunoArtCycleViewModel` (key-aware reload; carries the
`// INV-10` anchor). Older: private `FocusCyclingArt` + `BrunoChildArtViewModel` inside
`BrunoArtCarouselCard.swift:160-317` with a one-shot `guard !loaded` (`:275`) instead of the
key-aware guard. Carousel cards DO live inside the forked, cell-reusing CollectionHStack, so
Stack B is exactly the pattern INV-10 exists to eliminate: a recycled Studios/Directors card
can retain the previous collection's frames. **This is a correctness asymmetry, not just
duplication.** Consumers of Stack B: `BrunoShelfRow.swift:97`, `BrunoShelfView.swift:264`,
`BrunoBoxSetGridView.swift:153`, `BrunoStudiosGridView.swift:137`, plus `BrunoEraCard`.
**Proposal:** rebuild Stack B on `BrunoFocusArtCycle`. Highest-care item: INV-10 territory,
needs the held-scroll + recycle-flash protocol on device.

### F5. Three copies of the tile lockup/composite: `BrunoCategoryTile` / `BrunoLabelArtCard` / `BrunoEraCard`
Shared: dimmed-cover background, bottom wash gradient, uppercased title + accent underline
lockup. `BrunoEraCard` additionally hardcodes the amber palette that
`BrunoCategoryTile.palette["decades"]` defines — a palette change misses it (this is the
known two-decade-card-surfaces trap: Home Eras renders `BrunoEraCard`, Collections
"Through the Years" renders `BrunoLabelArtCard`). **Proposal:** extract `BrunoTileLockup` +
`BrunoDimmedCoverBackground`; keep the three cards (their focus/button shells legitimately
differ).

### F6. Twin Show-all cards (cheapest win)
`BrunoShowAllCard.swift:23-74` vs the private `showAllCard` in
`BrunoShelfRow.swift:151-190` — byte-identical except aspect handling. Bonus rot evidence:
`BrunoShelfRow.swift:19-20` still claims "PosterHStack's trailing slot is a no-op" while
`BrunoShelfView.swift:172` uses exactly that slot. **Proposal:** delete the private copy,
one-line replacement. Zero risk.

### F7. Menu bars — healthy; two papercuts only
`BrunoScrollingMenuBar` (tab roots, env coordinator) vs `BrunoCoverMenuBarRow` (covers,
`BrunoTabBridge` dismiss-then-switch) share almost nothing but the height frame; the split
is essential. Papercuts: the unused "explicit mode" init in `BrunoScrollingMenuBar`
(`:39-46, :73-77`, "Not used yet"), and the misnamed file `BrunoHeroMenuBar.swift` (contains
`BrunoCoverMenuBarRow`). No consolidation.

### F8. Four caption content views, ~80% copy-paste (lowest urgency)
`BrunoTitleDateContentView` / `BrunoRewatchablesContentView` / `BrunoEbertContentView` /
`BrunoOscarContentView` are geometry-faithful clones differing only in the line-2 string
(~8 lines each). They are frozen by discipline today; the Oscar third-line backlog item will
force edits, better on one body. Consumed by BOTH row engines plus three grids — consolidate
only together with F1's caption unification.

**Hero-count answer** (the "how many heroes exist" question): 2 live systems
(`BrunoHeroView` in multi-item and single-item modes; `BrunoBrandHeroBand`) plus the 3
private band copies F3 removes.

---

## 2. Dead-code inventory (each verified by call-site grep, 2026-07-01)

| Symbol | Location | Verdict |
|---|---|---|
| `BrunoStaticItemsLibrary` + `NavigationRoute.brunoItemsGrid` | `Shared/Objects/Bruno/BrunoStaticItemsLibrary.swift` (whole file, 59 ln) | dead; zero callers; superseded by `brunoBoxSetGrid` |
| `BrunoLibrarySnapshot.curatedBoxSets` | `BrunoLibrarySnapshot.swift:99-101` | dead; zero callers; replaced by `promotedCuratedBoxSets` |
| `consolidateOscars` / `consolidateEbert` | `BrunoBoxSetShelvesView.swift:136-169` | dead-in-practice; sole caller gated on a drill parent named "Curated", which no route produces post-retirement |
| `cardRowCategories` consolidation branch | `BrunoBoxSetShelvesView.swift:128-130` + param `BrunoCategoryShelves.swift:231` | vestigial; only differs from `categories` in the dead branch |
| `curatedRandomShelves` | `BrunoBoxSetShelvesView.swift:704-823` | dead-in-practice (same "curated" gate). NOT the same thing as the alive Collections tail (`BrunoHomePlan.collectionsTail`) |
| `"curated-oscars"` / `"curated-ebert"` synthetic-id branches | `BrunoCategoryShelves.swift:579`, `BrunoBoxSetShelvesView.swift:145/:163` | dead-in-practice; live Oscars/Ebert paths use the real favorited groups |
| `BrunoScrollingMenuBar` explicit mode | `BrunoScrollingMenuBar.swift:39-46,:73-77` | unused seam ("Not used yet") |
| web `getCollectionItems` | `bruno-web/src/api/jellyfin.js` | defined, unused (reference repo; leave) |

**Tracker correction (important):** `docs/PROJECT_TRACKER.md` cited `BrunoHomePlan.swift:337`
as the orphaned "parent == curated explore block". That case (`"curated", "world"`) is ALIVE:
it sits in `exploreKeys`, is walked by the tail, and reads `promotedCuratedBoxSets`. The dead
curated code is the `BrunoBoxSetShelvesView` cluster above. The tracker row was corrected in
this thread.

**Verified alive (do not delete):** `BrunoCollectionProbe` and `BrunoPreviewSupport`
(DEBUG-only tools mounted from `SwiftfinApp.swift`), `BrunoItemPaging` (4 callers),
`BrunoRecencyBias`, `BrunoInputMonitor`, `BrunoTopShelfCredentials`, `BrunoDevAutoLogin`.

---

## 3. Fork drift — Bruno vs upstream Swiftfin

### 3a. The real upstream-touch surface (vs merge-base `c235dace`)

The code map claimed 4 sanctioned upstream edits. The actual diff touches ~22 upstream
source files. Grouped by intent (line anchors are post-image):

- **Tab/IA seams (documented):** `TabItem.swift` (Home -> BrunoHomeView `:55`, 7-tab IA,
  `brunoUtilityTabBar()`), `MainTabView.swift` (93-line custom tab host that keeps hidden
  tabs mounted), `TabCoordinator.swift:42-48`, `RootCoordinator.swift:29-33`, plus the NEW
  file `Shared/Coordinators/Tabs/BrunoTabBridge.swift`.
- **Perf seams (documented):** `PosterButton.swift` (INV-10 FocusShadowPoster),
  `SwiftfinApp.swift` tvOS (DEBUG branches).
- **UNDOCUMENTED before this thread:** `PosterHStack.swift` (a `.trailing{}` slot added for
  the Show-all card — load-bearing for #41), `ImageView.swift`, `ItemLibrary.swift:261-264`,
  `SimilarItemsHStack.swift` + `CollectionItemContentView.swift` (#66 Recommended),
  `SettingsView.swift` (48-line insertion), `VideoPlayerSettingsView.swift` +
  `MediaPlayerProxy+VLC.swift` (night-mode audio), `UserSession.swift` +
  `UserSessionManager.swift` (Top Shelf creds), `SwiftfinApp+ValueObservation.swift`,
  `DataCache.swift`, `Strings.swift`, iOS `SwiftfinApp.swift` (1 line), `Color.swift`,
  `SwiftfinDefaults.swift`, `Font+Bruno.swift` (new), `AudioNightMode.swift` (new shared),
  and the `Package.resolved` repoint of CollectionHStack to the
  `DiplomacyMusic/CollectionHStack@bruno-hosting-reuse` fork (INV-10).

`docs/BRUNO_CODE_MAP.md` §2 was corrected in this thread to stop claiming completeness at 4
files and to point here. Maintenance rule going forward: when you touch a NEW upstream file,
add it to the code-map §2 list in the same commit.

### 3b. Reimplementation verdicts

- `BrunoMediaView` vs stock `PagingLibraryView`: **justified.** Stock cannot host Bruno's
  per-cell labels or the branded hero; the one-shot full-library fetch is fine at ~1300
  items. Real drift is internal: `BrunoPosterGrid` vs `BrunoBoxSetGridView.lazyGrid` are two
  7-up poster LazyVGrids that could be one (optional, low value).
- `BrunoShelfView` vs stock `LatestInLibraryView` pattern: **no drift**; it reuses stock
  `PosterHStack`/`PosterButton` deliberately.
- `BrunoStaticItemsLibrary` vs stock `ItemLibrary`: moot; dead, delete.

---

## 4. Structural risks that are NOT duplication (recorded, no action proposed)

1. **Routing vocabulary is scattered.** Bruno `NavigationRoute` factories live inside the
   view files they open (see `NAVIGATION_MAP.md` §3 for the registry). Acceptable for this
   codebase size; the registry table is the mitigation.
2. **Name-keyed server contract.** Group resolution is case-insensitive NAME matching
   ("genres", "decades", "roger ebert", the `BrunoCoreGenre` member names, the
   `row1Order`/`row2Order` strips). A server rename silently reroutes or hides content.
   Mitigation is documentation (done: SHELF_PROVENANCE §2/§3) plus the existing fallbacks.
3. **Two `shelfCap` constants with different meanings** (plan shelf-count 18 vs browse
   preview items 30). Renaming one is a candidate cleanup; documented prominently in
   SHELF_PROVENANCE §5 either way.
4. **The IA overhaul is mid-flight.** §6 (reactive Decades hero), Asian Cinema composed
   shelves, Cities seed-eligibility, and franchise art are open; any consolidation that
   touches `BrunoBoxSetShelvesView` or the pill rows should sequence around them
   (see REFACTOR_PLAN ordering).

---

## 5. Documentation drift — verified and fixed this thread

Fixes already landed (each its own commit on this branch):

1. **bruno-web** (`cff94af` in that repo): EXECUTED/ABANDONED status banners on
   `NATIVE_FORK_PLAN.md` and `EXECUTION_HANDOFF.md` (they read as live build contracts; a
   cold model could re-run them); README roadmap marked historical; "7 group tiles" claims
   flagged. The §4 decisions and design tokens remain the durable content.
2. **`docs/pipeline/FILING_MAP.md`** (`72216113`): the governing claim "nothing in Swift
   reads item tags" was false since the caption work; reframed as "membership cannot be
   selected by tag" + dated update note covering the Curated retirement.
3. **`docs/pipeline/README.md`** (`72216113`): p1..p7 -> p1..p9; live favorited-group list;
   FILING_MAP is Bruno-authored, not a snapshot; recorded the scheduling truth: the daily
   10:00 job was launchd (not cron) and was DISABLED 2026-06-28 (HTTP 414); all producer
   runs are manual.
4. **`docs/PROJECT_TRACKER.md`** (`53685816` + this thread's follow-up): three claims
   invalidated by post-sync reverts (Seasonal covers, one-shuffled-sequence, Romance fix
   untracked); the `BrunoHomePlan.swift:337` dead-code citation corrected (§2 above).
5. **`docs/BRUNO_NAV_MAP.md` / `docs/BRUNO_CODE_MAP.md`**: corrected in place this thread
   (see those commits): NAV_MAP §2 shelfCap semantics, §2b `promotedCuratedBoxSets`, §3
   Collections rewrite (two-row strip, retired Curated, caps 30/16, procedural tail, new
   drill-ins), §10 Recommended fail-open; CODE_MAP §2 seam-list honesty, §4/§5 anchors.
6. **Code comments**: stale "7 favorited groups" header in `BrunoLibrarySnapshot.swift`,
   the rotted trailing-slot claim in `BrunoShelfRow.swift:19-20`, and provenance one-liners
   at the shelf-generation sites (see the comments commit).

Known remaining drift NOT fixed here (out of scope or producer-side):
`MovieCollection/enrich/PLAN.md` still marks p9 "deferred" (the Bruno-side snapshot is the
newer copy); `BRUNO_NOTES.md` §Live library snapshot totals predate the migration (already
marked superseded in place); `docs/BRUNO_IA_OVERHAUL_PLAN.md` is a living plan and was left
untouched.
