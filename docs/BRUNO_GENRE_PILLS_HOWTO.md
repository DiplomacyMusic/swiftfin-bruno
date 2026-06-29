# Bruno tvOS — How to add genre pills to a curated drill-down grid

> **Reusable recipe.** This generalizes the Rewatchables implementation
> (`Swiftfin tvOS/Views/BrunoHomeView/BrunoRewatchablesView.swift`) so you can drop the same
> **"Browse by" genre pill filter** onto any Bruno curated drill-down — next up: the **Ebert** drill-down.
> Read `docs/BRUNO_PERF_INVARIANTS.md` (INV-7, INV-10) and `docs/BRUNO_MOVIES_GENRE_SURFACE.md` §3
> (genre-layers hard rule) before you start.

The pattern: a curated BoxSet's members are already loaded into memory as a flat `[BaseItemDto]` and
rendered in a grid. We add a pill row above the grid that **filters that in-memory array** by each film's
tagged genre — no refetch, instant. The pills reuse the Movies-tab `BrunoCoreGenre` buckets so the look +
feel matches everywhere.

---

## 0. Preconditions — does this surface qualify?

This recipe assumes the drill-down is a **custom Bruno grid view** that owns its view-model and holds all
members in memory (like `BrunoRewatchablesView` + `BrunoRewatchablesViewModel`). Two checks first:

1. **Is it a Bruno grid, or stock `ItemLibrary`?** If the "Show all" still routes to the stock paged
   `ItemLibrary`/`BrunoQueryLibrary` (no custom hero, server-side paging), there is no in-memory array to
   filter and no place to host the pills. **First convert it to a Bruno custom grid** — clone
   `BrunoRewatchablesView` (hero band + `LazyVGrid` over a one-page member fetch). *The Ebert "Show all"
   grid is stock `ItemLibrary` today (see the `bruno-rewatchables-oscars` memory) — so step 0 for Ebert is
   that conversion; only then do steps 1–6 apply.*
2. **Does the member set fit one page?** The in-memory filter is only "instant" because every member is
   already loaded (Rewatchables: ~214 in one `limit: 300` page). If the curated set is larger, page it to
   completion in the VM first, or switch to a server-side `Genres=` query instead of this client filter.

If both hold, proceed.

---

## 1. Fetch `.genres` in the view-model

The filter reads each film's **raw TMDB genres** off `BaseItemDto.genres`. `.MinimumFields` does **not**
include `.genres`, so it comes back `nil` and every pill auto-hides unless you ask for it explicitly:

```swift
// in the VM's member fetch
parameters.fields = .MinimumFields + [.tags, .genres]   // .tags stays for whatever caption you already show
```

(Identical idiom to `BrunoLibrarySnapshot.swift`'s `.MinimumFields + [.genres]`.)

---

## 2. Add the filter state to the View

```swift
@State private var selectedCore: BrunoCoreGenre?      // COMMITTED filter; nil ⇒ "All"
@State private var focusedCore: BrunoCoreGenre?       // transient highlight; nil ⇒ "All" chip
@State private var commitTask: Task<Void, Never>?     // pending debounced commit
@State private var filterRowAppeared = false          // INV-7 cold-enter guard
@State private var didEnterChipRow = false            // defaultFocus arm/disarm

@FocusState private var focusedChip: String?
```

---

## 3. Add the bucket → TMDB-genre map + the predicates

`BrunoCoreGenre.members` are curated sub-genre **BoxSet names** — they do **not** match raw TMDB genre
strings on items. So bridge each bucket id to the broad TMDB genre(s) under it, and match `item.genres`.

```swift
// BROAD ONLY: each bucket maps to its broad TMDB genre(s) and nothing else. Standalone-core genres
// (Western, Music, Mystery, War, Animation) are deliberately NOT folded into a broader bucket — a film
// carrying only one of those reaches via "All". "International" has no TMDB-genre equivalent, so it
// matches no film and auto-hides via shownCores.
private static let tmdbGenresByCoreID: [String: Set<String>] = [
    "action-adventure": ["action", "adventure"],
    "comedy": ["comedy"],
    "drama": ["drama"],
    "romance": ["romance"],
    "scifi-fantasy": ["science fiction", "fantasy"],
    "thriller": ["thriller"],
    "crime": ["crime"],
    "horror": ["horror"],
    "history": ["history"],
    "family": ["family"],
]

private func filmMatches(_ item: BaseItemDto, _ core: BrunoCoreGenre) -> Bool {
    guard let tmdb = Self.tmdbGenresByCoreID[core.id] else { return false }
    let genres = Set((item.genres ?? []).map { $0.lowercased() })
    return !genres.isDisjoint(with: tmdb)
}

/// Full set for "All", else only films whose TMDB genres fall in the selected bucket. In-memory ⇒ instant.
private var shownFilms: [BaseItemDto] {
    guard let selectedCore else { return viewModel.films }   // rename `films` to your VM's array
    return viewModel.films.filter { filmMatches($0, selectedCore) }
}

/// Only buckets matching ≥1 loaded film — a pill can never filter to an empty grid (the G3 guard).
private var shownCores: [BrunoCoreGenre] {
    BrunoCoreGenre.all.filter { core in viewModel.films.contains { filmMatches($0, core) } }
}
```

**Map-key rule (verify every time):** each key MUST equal a `BrunoCoreGenre.all` `id`
(`BrunoGenresView.swift`). A typo'd key returns `nil` from the lookup → that whole pill silently auto-hides.
The 10 keys above are the current ids; `"international"` is intentionally omitted (no TMDB equivalent).

**Genre-string fidelity:** values are lowercased **raw TMDB genre names** — `"science fiction"` (NOT
"sci-fi", NOT the combined "Sci-Fi & Fantasy"), `"war"`, `"animation"`, etc. Both sides are lowercased, so
the compare is case-insensitive. Cross-check against `docs/reference/GENRE_RECS_ARCHITECTURE.md` (the 16
broad names) + `docs/pipeline/GENRE_MAP.md` if you add any.

**Genre-layers hard rule:** this only ever **reads** `item.genres`. Never write/lock raw TMDB Genres.

---

## 4. Add the pill row (verbatim choreography from `BrunoGenresView`)

```swift
private var pillRow: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Browse by".uppercased())
            .font(.brunoBody(20, weight: .semibold))
            .tracking(3)
            .foregroundStyle(Color.bruno.accent)
            .padding(.horizontal, 50)

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 24) {
                BrunoSelectorCard(title: "All", isSelected: focusedCore == nil, selectsOnFocus: true) {
                    commitFocus(nil)
                }
                .focused($focusedChip, equals: "all")

                ForEach(shownCores) { core in
                    BrunoSelectorCard(
                        title: core.title,
                        isSelected: focusedCore?.id == core.id,
                        selectsOnFocus: true
                    ) {
                        commitFocus(core)
                    }
                    .focused($focusedChip, equals: core.id)
                }
            }
            .padding(.horizontal, 50)
            .padding(.vertical, 8)
        }
        .focusSection()
        .backport
        .defaultFocus($focusedChip, "all", priority: didEnterChipRow ? .automatic : .userInitiated)
        .onChange(of: focusedChip) { _, newValue in
            if newValue != nil { didEnterChipRow = true }
        }
    }
    .task { filterRowAppeared = true }   // INV-7: only after first paint
}

private func commitFocus(_ core: BrunoCoreGenre?) {
    guard filterRowAppeared else { return }
    guard focusedCore?.id != core?.id || selectedCore?.id != core?.id else { return }
    focusedCore = core
    commitTask?.cancel()
    commitTask = Task {
        try? await Task.sleep(for: .milliseconds(500))   // scrub-coalesce: re-filter once, not per pill
        guard !Task.isCancelled else { return }
        guard focusedCore?.id == core?.id, selectedCore?.id != core?.id else { return }
        selectedCore = core
    }
}
```

---

## 5. Wire it in + bind the grid

Insert `pillRow` directly above the grid in the scrolling `VStack`, and point the grid's `ForEach` at
`shownFilms`:

```swift
VStack(spacing: 0) {
    header.frame(height: proxy.size.height - 150).padding(.bottom, 50)   // your existing hero band
    pillRow.padding(.bottom, 30)                                         // ← add
    grid
}
// ...
ForEach(shownFilms, id: \.id) { item in ... }   // was viewModel.films
```

## 6. Cancel the debounce on teardown

```swift
.onDisappear {
    commitTask?.cancel()
    commitTask = nil
}
```

---

## Invariants & gotchas (don't skip)

- **INV-7 (no filter on cold enter):** `filterRowAppeared` (flipped in `.task`) makes `commitFocus` a no-op
  until first paint, so the focus engine's initial `selectsOnFocus` assignment can't fire a filter. The
  grid shows the full set on entry.
- **INV-10 (structural stability / held-scroll):** safe because (a) `BrunoSelectorCard`'s focus ring is an
  always-present opacity-toggled overlay (no `if isFocused { ... }` insertion), and (b) `shownCores` filters
  the **fixed** `BrunoCoreGenre.all` against a **once-loaded** member array, so pill count/identity never
  change on focus. Don't introduce focus-conditional view insertion or a pill set that mutates after load.
- **The `defaultFocus` re-arm caveat:** `BrunoGenresView` resets `didEnterChipRow` via an `onHeroFocused`
  callback because it has a **focusable hero** above the pills. A plain drill-down whose header is
  non-focusable `Text` (Rewatchables) needs **no** re-arm: `didEnterChipRow` latches `true` on first chip
  focus and `.automatic` thereafter correctly restores the last-focused pill on UP-from-grid. **If your
  surface has a focusable hero/band above the pills, port the re-arm too** or DOWN-from-hero won't reliably
  land on "All".
- **Determinism (INV-3):** untouched — this never goes near `BrunoHomePlan.build`.
- **Perf note:** `shownCores`/`shownFilms` are computed properties recomputed per body pass (mirrors
  `BrunoGenresView.shownCoreGenres`). Fine at a few hundred members; if a much larger curated set ever
  profiles hot during scrub, hoist them to a stored value computed once when members load.
- **Build:** worktree builds need `Carthage/` symlinked from the main checkout
  (`ln -s <main>/Carthage <worktree>/Carthage`) or the headless build fails on `TVVLCKit.xcframework`.
  Focus traversal is the owner's on-device check (tvOS focus can't be driven headlessly).

---

## Reference implementation & sources

| Concern | Where |
|---|---|
| Reference implementation (copy this) | `Swiftfin tvOS/Views/BrunoHomeView/BrunoRewatchablesView.swift` |
| Pill primitive | `Swiftfin tvOS/Views/BrunoHomeView/BrunoSelectorCard.swift` |
| `BrunoCoreGenre` buckets + ids + the original choreography | `Swiftfin tvOS/Views/BrunoHomeView/BrunoGenresView.swift` |
| Genre-layers hard rule + the two genre data models | `docs/BRUNO_MOVIES_GENRE_SURFACE.md` §3 |
| Perf invariants (INV-7, INV-10, INV-3) | `docs/BRUNO_PERF_INVARIANTS.md` |
| Raw-TMDB genre-name source of truth | `docs/reference/GENRE_RECS_ARCHITECTURE.md` · `docs/pipeline/GENRE_MAP.md` |
