# Bruno tvOS — Movies tab = the Genre Browse surface

> **Read this before touching the Movies tab, the genre browse shelves, or the menu-bar wiring.**
> Since PR #19 (`05ae924a`, commits `01e05da7` + `d685b68c`) the **Movies tab is no longer an A–Z grid —
> it IS the genre-browse surface.** This file is the interconnection + fragility map for that surface:
> how the pieces connect, what is load-bearing, and the known gaps. It is the sibling of
> `BRUNO_PERF_INVARIANTS.md` (which owns the Home-spine perf invariants INV-1..9) — cross-referenced below.
>
> Findings here were produced by a code-grounded audit (map → adversarial verify → completeness critic;
> 79 findings, 0 refuted) and each is anchored to `file:line` (lines drift — match the symbol/string).

---

## 1. What the Movies tab is now

`TabItem.movies` (`Shared/Coordinators/Tabs/TabItem.swift`) renders **`BrunoMoviesView`** (was
`BrunoMediaView(itemType: .movie)`). **TV Shows is unchanged** — still `BrunoMediaView(itemType: .series)`.

- `BrunoMoviesView` is a **thin, chrome-less pass-through**. On first appear it loads the shared library
  snapshot and resolves the **"Genres" group BoxSet**, then renders
  `BrunoGenresView(parent: group, core: nil, isTabRoot: true, onShowAll: …)`.
- `BrunoGenresView` (cinematic hero + the "Browse by" core-genre pills + one shelf per sub-genre) is the
  same view that the pushed `.brunoGenres` cover uses — re-parented as a **tab root** via `isTabRoot`.
- The old **A–Z movie grid is preserved** behind a trailing **"All Movies"** pill that lazily pushes
  `NavigationRoute.brunoMoviesGrid` (a `BrunoMediaView` cover that fetches only on push).
- **Fallback:** if the Genres group is `nil` (or the snapshot is empty), `BrunoMoviesView` renders
  `BrunoMediaView` (the A–Z grid) so the tab is never blank — *with one hole, see G4.*
- **Terminal footer ("end pills").** At the *hard end* of the surface — gated on
  `visibleShelfCount >= categories.count` (every shelf mounted) and appended last — `BrunoCategoryShelves`
  renders a bottom pill row: **"Show all Movies"** (→ `.brunoMoviesGrid`) + **"Back to Top"** (`scrollTo`
  the hero `.id(.top)` + pull focus via `heroFocused`). It's gated on the `showAllMoviesAction` param, so
  **only the Movies tab** gets it (Collections is deferred — passes nil). **Zero UI/layout impact until the
  user scrolls to the true end** (it isn't in the tree until everything's mounted, and sits below the last
  shelf). Home has its own equivalent footer (`BrunoHomeView`, gated on `exploreExhausted`): **Show all
  Movies + Show all TV** (→ `.brunoMoviesGrid` / `.brunoTVGrid`) **+ Back to Top**, beside the collections
  cards.

---

## 2. The end-to-end call chain (in one place)

Two **independent network paths** feed this surface; nothing else documents both together.

```
MainTabView (tvOS)                       ← mounted-tab switcher (no pinned bar; each tab injects its own row)
  └─ BrunoMoviesView                     (thin pass-through; @StateObject BrunoMoviesViewModel; @Router)
       ├─ .load(): BrunoLibrarySnapshot.loadShared(client,userID)   ← PATH A (snapshot, 300s cache)
       │     └─ resolve group: favoriteGroupBoxSets.first { name?.lowercased() == "genres" }
       ├─ if group → BrunoGenresView(isTabRoot: true, onShowAll:{ router.route(to:.brunoMoviesGrid) })
       │     └─ BrunoBoxSetShelvesViewModel.load(parent: group)  → .performLoad()  ← PATH B (deep fan-out)
       │           ├─ BrunoBoxSetShelvesCache hit? → return (300s, per (userID,parentID))
       │           ├─ fetchChildren(parentID, limit:100)  → the ~80 sub-genre BoxSets   ⚠ G5
       │           ├─ withTaskGroup: per sub-genre fetchChildren(limit: childFetch=60) ← 1+N (~20+) requests
       │           ├─ per row: BrunoRNG.shuffled(children, seed: shuffleSeed+index)    (day-stable item order)
       │           └─ rows: recencyBiased ? BrunoRNG.shuffled(ordered, rowOrderSeed) : ordered  ← row order
       │     → BrunoCategoryShelves(categories: shownCategories, header: corePanel,
       │                            namesShowAllCards: true, isTabRoot: isTabRoot, …)
       │              (injects BrunoScrollingMenuBar [tab root] or BrunoCoverMenuBarRow [cover] as row 0)
       │           └─ BrunoShelfRow(showAllTitle: "<genre>") per category   (height-pinned, INV-1)
       └─ else → BrunoMediaView(itemType:.movie)   (A–Z fallback; rotating hero — differs from happy path)
```

- **PATH A** (snapshot) decides *whether* the tab is genre-mode or A–Z fallback.
- **PATH B** (deep fan-out) builds the actual genre shelves. It is the SAME view-model
  (`BrunoBoxSetShelvesViewModel`) used by the pushed Genres/Decades/Curated drill-ins — so the Movies tab
  root and a nested `.brunoGenres` cover **share one `BrunoBoxSetShelvesCache` entry** (same `(userID,
  Genres-parentID)` key → same row order + same 300s staleness for both).

---

## 3. Server-curation assumptions (this surface is NOT self-sufficient)

The whole surface assumes a **specific owner-authored Jellyfin curation**. It matches by **name, never by
id**, case-insensitively:

- A set of favorited **group BoxSets** (Directors, Studios, Decades, Curated, Seasonal, **Genres**, …).
- A **"Genres" group** whose children are **sub-genre BoxSets** (the ~80: 16 broad TMDB-built genres +
  curated/personal sub-genres like Noir, Heist, Cubicle, Coming of Age…). See `reference/GENRE_RECS_ARCHITECTURE.md`
  §"Current architecture" and `bruno-enrich-pipeline` / `bruno-genre-layers` memory.
- **Every sub-genre BoxSet is movie-only** on the server — which is *why there is no movies-only filter in
  the app* (a `type == .movie` filter on the group's children would match `.boxSet` and **blank the page**).
- The sub-genre BoxSets carry **`.genres`** on their items (needed by the hero child-safety filter, see F7).

> **Two genre data models coexist — do not confuse them.** `snapshot.genres` = raw **TMDB genre name
> strings** (feeds Home's "IF YOU LIKE" rows via `BrunoHomePlan.genreQuery`, server-side `Genres=` match).
> The **Genres-group sub-BoxSets** = the curated shelves this Movies tab renders. They are different
> systems. `reference/GENRE_RECS_ARCHITECTURE.md` is about the FORMER (an unbuilt Home rec lens) — it does **not**
> describe this Movies tab.

---

## 4. The `"genres"` string contract + the `recencyBiased` overload

**The literal lowercased string `"genres"` is matched in (at least) FOUR independent, drift-prone sites
with no shared constant**, and they must all agree on the server group name:

| # | Site | Role |
|---|------|------|
| 1 | `BrunoMoviesViewModel.load` — `favoriteGroupBoxSets.first { $0.name?.lowercased() == "genres" }` | gates whether the Movies tab is genre-mode or A–Z fallback |
| 2 | `BrunoBoxSetShelvesViewModel.performLoad` — `parent.displayTitle.lowercased() == "genres"` → `recencyBiased` | gates the genre-specific behaviors (below) |
| 3 | `BrunoCollectionCategory.fromSnapshot` — `guard name.lowercased() != "genres"` | drops the Genres card from Collections hub + Home terminal footer |
| 4 | `BrunoLibrarySnapshot.genreBoxSets { group("Genres") }` (case-insensitive) | the accessor #1 *bypasses* (it scans `favoriteGroupBoxSets` instead — a 4th rule that must agree) |

> **Degrades LOUDLY, not silently:** if the server group is renamed, the Movies tab cleanly **falls back to
> the A–Z grid** (site #1 misses) — a visible, debuggable failure, not a subtle one. *Safe recipe:* if you
> ever touch this, introduce ONE shared `genresGroupName`/`genresGroupBoxSet` resolver so all four sites
> share a single case-insensitive rule.

**`recencyBiased` is an overloaded "is-this-the-Genres-surface" flag** — keyed on site #2 — that drives
**three unrelated behaviors** at once: (a) a deeper child fetch (`childFetch = 60` vs `perShelfFetch`),
(b) the per-launch/6h **row-order reshuffle**, (c) the **newest-first** sort on the per-genre "Show all"
grid (`BrunoCategoryCardRow`). Decades/Curated take the non-`recencyBiased` branch and keep server order.
The name is now a misnomer (the old "modern recency bias" filter it referred to was deleted) — kept because
it still gates (a)/(b)/(c).

---

## 5. The three seeds (different cadence + scope, all compose here)

| Seed | Scope | Cadence | Where |
|------|-------|---------|-------|
| `shuffleSeed` | **within-shelf** film order | day-stable (`/86400`) | `BrunoBoxSetShelvesViewModel`, per row `+index` |
| `rowOrderSeed` = `launchNonce &+ (now/21600)` | **row order** (genre surface only) | per **cold launch** + 6h bucket — *but see G2* | read **once** in `performLoad` |
| `weightedPreview` salt `0xB075`/`0xC0DE` | the ≤14-card **preview sample** | day-stable | `BrunoCategoryShelves` |

The Featured Film **hero rotates with `rowOrderSeed`** for free: `BrunoGenresView` computes
`brunoFeaturedItem(in: viewModel.categories)` over the shuffled array and holds it in `@State`, recomputing
only on `viewModel.categories.map(\.id)` change → fixed for the session (INV-7 safe).

---

## 6. Fragility surface (What / Why / Break / Safe)

### F1 — Menu-bar rule: inject it as the first scrolling ROW, and keep `.top` un-ignored
**What:** the menu bar is no longer pinned by `MainTabView`. Each surface injects it as the **first row of
its `LazyVStack`**, above the hero: a tab root injects `BrunoScrollingMenuBar()` (gated by `isTabRoot`); a
pushed cover injects `BrunoCoverMenuBarRow()`. The row scrolls up and off-screen like every other shelf.
Each component already applies `.frame(height: BrunoMenuBar.barHeight)` + `.focusSection()` internally, so
the call site adds only `.zIndex(1)` (paint above the hero's upward backdrop spill). The deepest surface
must still NOT `.ignoresSafeArea(.top)` — `.top` is kept so the bar row stays title-safe and the hero
bleeds correctly.
**Why:** the custom bar exists so UP-from-content focuses the bar (stock `TabView` had no focus binding).
As its own `.focusSection()` row there is one focusable per vertical region, so UP/DOWN traverse cleanly
between rows (shelf ↔ hero ↔ bar) with no special routing.
**Break:** drop the row at a tab root → no bar / no way to leave the tab; `.ignoresSafeArea(.top)` →
the bar row and hero geometry shift up off the title-safe band.
**Safe:** `BrunoMoviesView` and `BrunoGenresView(isTabRoot:true)` stay thin — no ambient `ZStack`, no
`.ignoresSafeArea`, no `.safeAreaInset` at the wrapper. The deepest surface (`BrunoCategoryShelves`) owns
ambient + a **partial** drop `.ignoresSafeArea(edges: [.horizontal, .bottom])` (**never `.top`**); the
behind-the-pills bleed is `BrunoAmbientBackground`'s own all-edge ignore. **`BrunoCollectionsView` is the
proven precedent** (same `BrunoCategoryShelves`, respects `.top`).

### F2 — the `isTabRoot` bar branch is safe ONLY because `isTabRoot` is a constant `let`
**What:** `BrunoGenresView` passes `isTabRoot` down to `BrunoCategoryShelves`, which picks the bar row with
`if isTabRoot { BrunoScrollingMenuBar() } else { BrunoCoverMenuBarRow() }` as row 0 of its `LazyVStack`.
**Why:** the two branches are different concrete view subtrees → toggling `isTabRoot` at runtime would
re-root row 0 (lose `@State`, focus, scroll — the INV-7/8 class of bug). `isTabRoot` is set at `init` and
**never mutated**, so the branch is fixed for the instance's whole life → no identity churn.
**Break:** if `isTabRoot` ever became a `@State`/dynamic value, flipping it would tear down the bar row
(and risk churning the rows below) mid-session.
**Safe:** keep `isTabRoot` a stored `let`. Never drive the bar branch off mutable state.

### F3 — `rowOrderSeed` must be read **exactly once**, in `performLoad`
**What:** the seed is read once per load and the resulting order is published to `categories`.
**Why:** reading it from a SwiftUI body / computed property would re-evaluate per pass and **reorder rows
under the focus ring mid-session** (INV-2 identity / INV-7), violating the INV-3 carve-out's "stable within
a session" guarantee.
**Break:** genre rows visibly reshuffle while scrolling/filtering; focus jumps.
**Safe:** any new per-launch randomness for this surface is read once in `performLoad`, never in a `var`/body.

### F4 — `BrunoMenuBar.barHeight` is a single source feeding multiple sites
**What:** `BrunoMenuBar.barHeight` (= **116**) sizes the menu-bar ROW (`.frame(height:)` inside both
`BrunoScrollingMenuBar` and `BrunoCoverMenuBarRow`) AND feeds the hero `topBleed` in `BrunoHeroView`. The
bar row now occupies the same barHeight above the hero that the old pinned `Color.clear` inset used to
reserve, so the hero geometry is unchanged (there is no `Color.clear` inset anymore).
**Break:** if the row's frame and the hero's `+ barHeight` topBleed desync (one hard-coded, the other from
the constant), the hero backdrop spill drifts (a lighter strip shows above the hero).
**Safe:** keep all sites reading `BrunoMenuBar.barHeight`; keep it `>=` the bar's intrinsic height (~108pt).

### F5 — These View structs rely on the **synthesized memberwise init**
**What:** `BrunoCategoryShelves.namesShowAllCards`, `BrunoShelfRow.showAllTitle`, and `BrunoGenresView`'s
`isTabRoot`/`onShowAll` defaults exist only because Swift synthesizes the memberwise init (SE-0242 gives
optionals an implicit `nil`; explicit `= false` for the bool).
**Why/Break:** adding **any** explicit `init` to these structs silently **drops the defaults**, breaking
every call site that omits the param (e.g. `BrunoCollectionsView`'s `BrunoCategoryShelves(...)`). The same
file already shows the trap — `BrunoCollectionCategory` has an explicit init.
**Safe:** don't add an explicit `init` to these Views; if you must, re-add every default + every existing
call site's arg.

### F6 — The "All Movies" pill is **pure navigation**
**What:** `BrunoSelectorCard(title:"All Movies", isSelected:false, selectsOnFocus:false){ onShowAll() }`,
tagged `.focused($focusedChip, equals:"show-all")`.
**Why/Break:** `selectsOnFocus:false` means **scrubbing across it must not push** the grid; it has no
`commitFocus` and `isSelected` is always `false`, so it **never touches the genre filter**. If someone sets
`selectsOnFocus:true` or routes a `commitFocus` through it, a focus scrub would navigate / re-filter.
**Safe:** keep it press-only, filter-free. (Caveat: it IS part of focus *restoration* via `$focusedChip` —
UP-from-shelves can land on it; a subsequent **Select** then pushes the grid. That's intended.)

### F7 — INV-7 cold-enter guard + decoupled hero + `.genres` child-safety
**What:** `filterRowAppeared` gates `commitFocus` so the focus engine's *initial* pill assignment can't fire
a genre filter on first paint; the hero is computed **once** from the full unfiltered set and held in
`@State`. The hero pool is filtered by `brunoHeroEligible` (rejects Horror) — which **silently no-ops unless
every fetch requests `.genres`** (`fetchChildren` adds `.genres` to `MinimumFields`).
**Break:** cold enter flashes a filtered hero/shelves; or a Horror still appears on the hero if a fetch
forgets `.genres`.
**Safe:** keep the `filterRowAppeared` guard; keep `.genres` on every child fetch feeding a hero.

### F8 — In-cover tab switch order (BrunoTabBridge): dismiss FIRST
**What:** the menu bar inside a pushed cover switches tabs through a global weak `BrunoTabBridge` singleton;
it must `router.dismiss()` **then** set `selectedTabID`. On tvOS even default `.push` routes present as
**fullScreenCovers**, so this applies to `.brunoGenres` and `.brunoMoviesGrid` alike.
**Break:** wrong order → dismiss races the tab switch (stuck cover / wrong tab).
**Safe:** preserve dismiss-then-select.

### F9 — Route identity is the `id` string; tvOS covers are single-slot
**What:** every Bruno route presents as a `fullScreenCover(item:)` keyed on `NavigationRoute.id`.
`brunoMoviesGrid` uses a **constant** id (`"bruno-movies-grid"`); `brunoGenres`/boxSet/studios parametrize
id by parent/core/title.
**Break:** coarse or title-only ids are latently fragile under the single-slot cover (two routes hashing to
the same id can't coexist). No live collision today.
**Safe:** keep ids unique per distinct destination; prefer parent-id over title in the key.

---

## 7. Perf-invariant interactions (see `BRUNO_PERF_INVARIANTS.md`)

- **INV-1 (height pin):** holds — `BrunoShelfRow` is structurally portrait-only and pins
  `BrunoShelfMetrics.shelfRowHeight`; `BrunoLabelArtCard` is byte-identical geometry. The `Show all ·
  <genre>` label is INV-1-neutral.
- **INV-2 (stable ids):** holds across the row shuffle + core filter — order only permutes;
  `BrunoCollectionCategory.id` is domain-derived (its own identity system, distinct from the Home spine's
  `BrunoShelfViewModel.id` the INV-2 doc literally describes).
- **INV-3 (determinism):** **intentional carve-out** for this sub-surface (genre row order nondeterministic
  per launch/6h) — documented in `BRUNO_PERF_INVARIANTS.md` under INV-3. Home spine unchanged.
- **INV-6 / INV-7:** ambient sibling + hero-first-focus carry over via `BrunoCategoryShelves`.
- **INV-8:** the top-down `streamReveal` is **not** used here; the surface uses the same cap-and-grow
  `visibleShelfCount` window (minus streaming).
- **INV-4 (prefetch) — GAP (G6):** the poster prewarm is wired only on the **Home** shelf row
  (`BrunoShelfView` / `BrunoPosterPrefetcher`); the genre browse row (`BrunoShelfRow`) — **now the primary
  Movies tab** — has **no prefetcher**. Missing-benefit, not a width-mismatch risk.

---

## 8. Known gaps & latent issues

> Each has a concrete safe-recipe. None block the shipped feature; several are owner decisions.
> **G1–G4 + G7 were fixed in the gap-fixes pass** (owner-directed); the rest remain open/latent.

- **G1 (✅ FIXED) — Genres tile was still on Home's mid-feed "Browse the Collection" shelf.** The
  `fromSnapshot` guard covered the **Collections hub** + **Home terminal footer**, but a **third** builder —
  `BrunoHomePlan` `appendItemsShelf(id:"collections", title:"Browse the Collection", items: …)` — was
  unguarded. **Fixed:** that shelf's `items` now `.filter { $0.name?.lowercased() != "genres" }` (matching the
  other three sites), so Genres lives **only** on the Movies tab.
- **G2 (✅ comment fixed; behavior accepted) — the reshuffle is effectively cold-launch-only on the Movies
  tab.** `BrunoBoxSetShelvesViewModel` is a `@StateObject`; `performLoad` runs **once per mount** and
  `MainTabView` keeps tabs mounted → the seed is re-read only on **cold launch** (new `launchNonce`) or a
  rare RAM-eviction remount; the 6h bucket only bites on a genuine reload (the per-genre drill-in cover, which
  remounts). Owner accepted cold-launch-only. **Fixed:** the misleading "also reshuffles every 6h without a
  relaunch" comment now states the cold-launch-only reality (code unchanged — the 6h bucket still helps the
  remounting cover).
- **G3 (✅ FIXED) — a core-genre pill matching zero sub-genres → silent blank surface.** The empty-state guard
  checked the **unfiltered** `viewModel.categories` while the populated branch handed the **filtered**
  `shownCategories`, and `BrunoCategoryShelves` has no empty guard → hero + pills over a blank shelf area.
  **Fixed by prevention:** the pill row now renders only `shownCoreGenres` (core buckets that match ≥1 loaded
  sub-genre), so a core that would yield zero shelves is **never selectable** — the blank state is
  unreachable. (Also kills dead pills, e.g. a Romance pill with no romance sub-genre.)
- **G4 (✅ FIXED) — Genres group present but childless → dead "No genres yet" screen, no escape.** The A–Z
  fallback fired only when the group was `nil`; a resolved-but-empty group (server hiccup) showed
  `BrunoGenresView`'s empty-state with no path to any film (the "All Movies" pill lived only in the populated
  branch). **Fixed:** the empty-state now renders an **"All Movies" escape button** when `onShowAll != nil`
  (the tab root), so the Movies tab is never a dead end.
- **G5 (✅ raised to 120) — sub-genre fetch was hard-capped at `limit:100`** (single page, not
  `BrunoItemPaging.fetchAll`). ~80 today, so the bump to **120** is headroom; if the curated set ever
  approaches it, page to completion like `loadYearShelves` (a comment at the site says so).
- **G6 (✅ FIXED) — the genre browse surface had no poster prefetcher** (Home's `BrunoShelfView` warmed
  its rows; the shared `BrunoShelfRow` did not). **Fixed:** `BrunoShelfRow` now holds a
  `BrunoPosterPrefetcher` and warms its shelf's posters at portrait width (INV-4) `.onAppear` /
  cancels `.onDisappear` — fires per-row as shelves scroll in/out. Covers the genre/Movies tab + Collections.
- **G7 (✅ FIXED) — debounce comment drift:** `commitFocus` sleeps **500 ms** (owner-confirmed intentional),
  but four doc-comments said **"~150 ms"** (3.3× off). **Fixed:** the four comments in `BrunoGenresView` +
  `BrunoBoxSetShelvesView` now say ~500 ms; the code constant is unchanged.
- **G8 — Long `Show all · <genre>` labels** rely on `lineLimit(2)` + `minimumScaleFactor(0.7)`; past 70%
  scale they **truncate with an ellipsis** (latent, not a confirmed live clip — depends on the longest genre
  name).
- **G9 (✅ FIXED) — the pills covered only 5 keyword buckets**, so 8 of the 16 broad genres and ~all
  colloquial sub-genres (Noir, Heist, Coming of Age, Biopic…) vanished the moment any pill was tapped.
  **Fixed:** `BrunoCoreGenre` is now **11 owner-curated pill buckets** (Action & Adventure · Sci-Fi &
  Fantasy · Comedy · Drama · Romance · Crime · Thriller · Horror · History · Family · International) with an
  **explicit, exact-match `members: Set<String>`** map (hand-assigned in the G9 bucket sheet) instead of
  substring keywords — so every one of the 80 genres lands under ≥1 pill (nothing invisible), duplication is
  intentional (e.g. Heist under Action/Comedy/Crime/Thriller), and there are no accidental substring matches.
  **Maintenance note:** exact-name match — if a genre BoxSet is renamed on the server, add the new name to
  its bucket(s) in `BrunoCoreGenre.all` (else it falls out of the pills, still reachable via "All").
- **G10 — Decades-only machinery is dead weight on this VM.** `BrunoGenresView` reuses
  `BrunoBoxSetShelvesViewModel` and inherits `yearShelvesByDecadeID` / `loadYearShelves` / `leadingYear` /
  the Best-of significance shelf — never exercised from the genre Movies tab. Also: the entire `.genres`
  `drillStyle` path + the cover-mode (`isTabRoot == false`) of `BrunoGenresView` is now **inert-but-fully-
  wired** (the `.brunoGenres` route is still live but no longer reached from any tile after G1 is closed).
  *Safe:* leave it — removing it must unwind two exhaustive switches + a string-switch and would delete
  `BrunoGenresView`'s only `isTabRoot == false` meaning (CLAUDE.md §3).

---

## 9. Build / QC reality

- **Compile (headless):** needs `-skipMacroValidation`; the worktree needs `Carthage/` symlinked from the
  main checkout (see `bruno-tvos-build-verify`). `** BUILD SUCCEEDED **`, 0 errors for this work.
- **Run in sim:** a worktree build with ad-hoc signing produces bundle id **`org.jellyfin.swiftfin`** (NOT
  `com.diplomacymusic.bruno`) — a separate app. Auto-login (`BrunoDevAutoLogin`) needs the home server
  reachable, else it SIGTRAPs at launch (`bruno-sim-autologin-crash`).
- **Focus is on-device.** Tab/genre **focus cannot be driven headlessly** — `osascript` key codes register
  (the hero carousel responds) but won't reliably move focus from the hero to the menu bar to switch tabs.
  So the Movies-tab render / single-bar / "All Movies" push / focus-restoration checks are the **owner's
  on-device step** (the plan scopes them there). Sim is good for: build runs, Home renders, no crash.

---

## 10. Where things live

| Concern | File |
|---|---|
| Movies tab root + lazy A–Z route | `Swiftfin tvOS/Views/BrunoHomeView/BrunoMoviesView.swift` |
| Genre surface (hero + pills + shelves), `isTabRoot`/`onShowAll` | `Swiftfin tvOS/Views/BrunoHomeView/BrunoGenresView.swift` |
| Genre fan-out, 3 seeds, `recencyBiased`, cache (PATH B) | `Swiftfin tvOS/Views/BrunoHomeView/BrunoBoxSetShelvesView.swift` |
| Shared browse renderer + `fromSnapshot` (genres-skip) + `brunoFeaturedItem` | `Swiftfin tvOS/Views/BrunoHomeView/BrunoCategoryShelves.swift` |
| Shelf row + `showAllTitle` + height pin (INV-1) | `Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfRow.swift` |
| The menu-bar pill row + `barHeight` | `Swiftfin tvOS/Views/BrunoHomeView/BrunoMenuBar.swift` |
| Tab-root scrolling bar row | `Swiftfin tvOS/Views/BrunoHomeView/BrunoScrollingMenuBar.swift` |
| Cover scrolling bar row | `Swiftfin tvOS/Views/BrunoHomeView/BrunoHeroMenuBar.swift` (`BrunoCoverMenuBarRow`) |
| Mounted-tab switcher (no pinned bar) | `Shared/Coordinators/Tabs/MainTabView.swift` |
| Snapshot + group resolution + the 2 genre data models | `Shared/Objects/Bruno/BrunoLibrarySnapshot.swift` |
| The mid-feed "Browse the Collection" tile shelf (G1) | `Shared/Objects/Bruno/BrunoHomePlan.swift` |
| `modernCutoff` (Home only — NOT this surface) | `Shared/Objects/Bruno/BrunoRecencyBias.swift` |
| Perf invariants INV-1..9 + the INV-3 carve-out | `docs/BRUNO_PERF_INVARIANTS.md` |
| The unbuilt Home "IF YOU LIKE" rec lens (NOT this) | `docs/reference/GENRE_RECS_ARCHITECTURE.md` |
