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

---

## 2. The end-to-end call chain (in one place)

Two **independent network paths** feed this surface; nothing else documents both together.

```
MainTabView (tvOS)                       ← owns the single shared BrunoMenuBar (tab roots get it free)
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
       │                            namesShowAllCards: true, …).if(!isTabRoot){ brunoHeroMenuBar() }
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
  curated/personal sub-genres like Noir, Heist, Cubicle, Coming of Age…). See `GENRE_RECS_ARCHITECTURE.md`
  §"Current architecture" and `bruno-enrich-pipeline` / `bruno-genre-layers` memory.
- **Every sub-genre BoxSet is movie-only** on the server — which is *why there is no movies-only filter in
  the app* (a `type == .movie` filter on the group's children would match `.boxSet` and **blank the page**).
- The sub-genre BoxSets carry **`.genres`** on their items (needed by the hero child-safety filter, see F7).

> **Two genre data models coexist — do not confuse them.** `snapshot.genres` = raw **TMDB genre name
> strings** (feeds Home's "IF YOU LIKE" rows via `BrunoHomePlan.genreQuery`, server-side `Genres=` match).
> The **Genres-group sub-BoxSets** = the curated shelves this Movies tab renders. They are different
> systems. `GENRE_RECS_ARCHITECTURE.md` is about the FORMER (an unbuilt Home rec lens) — it does **not**
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

### F1 — Tab-root menu-bar rule: no self-bar AND no `.top`-ignore at a tab root
**What:** `MainTabView` (tvOS) pins **one** `BrunoMenuBar` as a **focus PEER** of the content `ZStack`
under a single `.focusScope(rootNamespace)`, and reserves its height on the content via
`.safeAreaInset(.top){ Color.clear.frame(height: BrunoMenuBar.barHeight) }`. So **every tab root gets the
bar for free** — it must NOT self-apply `.brunoHeroMenuBar()` (→ double bar) and must NOT
`.ignoresSafeArea(.top)` (→ cancels the inset → focus-scroll drags the bar down, UP can't reach it). Both
are the **`e44e1e71`** regression ("double bar + scroll drift").
**Why:** the custom bar exists so UP-from-content focuses the bar (stock `TabView` had no focus binding).
**Break:** double menu bar on the Movies tab; or the bar rides the scroll / can't be reached by UP.
**Safe:** `BrunoMoviesView` and `BrunoGenresView(isTabRoot:true)` stay thin — no ambient `ZStack`, no
`.ignoresSafeArea`, no `.safeAreaInset` at the wrapper. The deepest surface (`BrunoCategoryShelves`) owns
ambient + a **partial** drop `.ignoresSafeArea(edges: [.horizontal, .bottom])` (**never `.top`**); the
behind-the-pills bleed is `BrunoAmbientBackground`'s own all-edge ignore. **`BrunoCollectionsView` is the
proven precedent** (same `BrunoCategoryShelves`, no self-bar, respects `.top`).

### F2 — `.if(!isTabRoot)` is safe ONLY because `isTabRoot` is a constant `let`
**What:** `BrunoGenresView` gates its menu bar with `.if(!isTabRoot) { $0.brunoHeroMenuBar() }`.
**Why:** the repo's `.if` swaps concrete view type between branches → toggling it at runtime would re-root
the subtree (lose `@State`, focus, scroll — the INV-7/8 class of bug). `isTabRoot` is set at `init` and
**never mutated**, so the branch is fixed for the instance's whole life → no identity churn.
**Break:** if `isTabRoot` ever became a `@State`/dynamic value, flipping it would tear down
`BrunoCategoryShelves` (shelf state / 720pt hero / reveal) mid-session.
**Safe:** keep `isTabRoot` a stored `let`. Never drive `.if` here off mutable state.

### F3 — `rowOrderSeed` must be read **exactly once**, in `performLoad`
**What:** the seed is read once per load and the resulting order is published to `categories`.
**Why:** reading it from a SwiftUI body / computed property would re-evaluate per pass and **reorder rows
under the focus ring mid-session** (INV-2 identity / INV-7), violating the INV-3 carve-out's "stable within
a session" guarantee.
**Break:** genre rows visibly reshuffle while scrolling/filtering; focus jumps.
**Safe:** any new per-launch randomness for this surface is read once in `performLoad`, never in a `var`/body.

### F4 — `BrunoMenuBar.barHeight` is a single source feeding multiple sites
**What:** `BrunoMenuBar.barHeight` (= **116**) feeds the content `Color.clear` inset AND the bar frame in
**both** `MainTabView` and `BrunoHeroMenuBar`, and the hero `topBleed` in `BrunoHeroView`.
**Break:** if the inset and the bar frame desync (one hard-coded, the other from the constant), UP-focus and
the hero backdrop drift.
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
- **G6 — No poster prefetcher on this (now primary) surface** — see INV-4 above.
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
| The shared menu bar + `barHeight` + tab-root wiring | `Shared/Coordinators/Tabs/MainTabView.swift`, `BrunoMenuBar.swift` |
| Cover-only menu bar contract | `Swiftfin tvOS/Views/BrunoHomeView/BrunoHeroMenuBar.swift` |
| Snapshot + group resolution + the 2 genre data models | `Shared/Objects/Bruno/BrunoLibrarySnapshot.swift` |
| The mid-feed "Browse the Collection" tile shelf (G1) | `Shared/Objects/Bruno/BrunoHomePlan.swift` |
| `modernCutoff` (Home only — NOT this surface) | `Shared/Objects/Bruno/BrunoRecencyBias.swift` |
| Perf invariants INV-1..9 + the INV-3 carve-out | `docs/BRUNO_PERF_INVARIANTS.md` |
| The unbuilt Home "IF YOU LIKE" rec lens (NOT this) | `docs/GENRE_RECS_ARCHITECTURE.md` |
