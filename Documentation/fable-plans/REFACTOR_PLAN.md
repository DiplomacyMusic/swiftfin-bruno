# REFACTOR_PLAN — sequenced consolidations for Opus

Authored 2026-07-01 (Fable assessment thread). Companion: `REARCHITECTURE_ASSESSMENT.md`
(the findings F1-F8 referenced below), `NAVIGATION_MAP.md`, `SHELF_PROVENANCE.md`.

## Ground rules for every step

- Bruno is the owner's LOWEST-priority project. Each step below is optional and independent;
  stop anywhere. Never bundle steps in one PR.
- Read `docs/BRUNO_PERF_INVARIANTS.md` before starting. The duplicated code encodes INV
  anchors redundantly; a consolidation must leave exactly one copy of each anchor, verbatim.
- Every step: work in a worktree, one logical change per commit, PR to
  `DiplomacyMusic/swiftfin-bruno --base main`, owner merges. Fresh worktrees need the
  Carthage symlink before the compile gate (`ln -s <main-checkout>/Carthage Carthage`).
- Compile gate (all steps):
  `xcodebuild -project Swiftfin.xcodeproj -scheme "Swiftfin tvOS"
  -destination 'generic/platform=tvOS Simulator' -skipMacroValidation build
  CODE_SIGNING_ALLOWED=NO` parsed for `error:`.
- Definition of done for the whole plan is NOT "all steps done"; it is "each landed step
  deleted more code than it added and its verification passed".

## Sequencing logic

Quick deletions first (steps 1-3, near-zero risk). The pill-row extraction (step 4) comes
BEFORE the IA overhaul's §6 Decades work because that plan explicitly wants a shared idiom
first. The band fold (step 5) is independent visual work. The caption/card unification
(step 6) is the biggest payoff and prepares F8. The art-cycle unification (step 7) is last:
INV-10 territory, on-device verification required.

---

### Step 1 — Delete the twin Show-all card (F6)

- Delete `showAllCard` from `BrunoShelfRow.swift:151-190`; render
  `BrunoShowAllCard(type: .portrait, title: ..., action: onShowAll)` in the `.showAll` case.
- Fix the rotted comment at `BrunoShelfRow.swift:19-20` (the trailing slot is NOT a no-op;
  `BrunoShelfView.swift:172` uses it) if the comments pass from the assessment thread has
  not already fixed it.
- **DoD:** compile gate green; browse shelf trailing card renders and focuses identically
  (sim: Movies tab, any shelf end). Net negative diff (~40 lines).

### Step 2 — Dedupe the TMDB bucket table (part of F2)

- Move `tmdbGenresByCoreID` + `filmMatches` (byte-identical at
  `BrunoRewatchablesView.swift:179-209` and `BrunoEbertView.swift:298-327`) to one place
  next to `BrunoCoreGenre` (e.g. `BrunoCoreGenre.matchesTMDBGenres(of:)` in
  `BrunoGenresView.swift` or a new `BrunoCoreGenre+TMDB.swift`).
- **DoD:** compile green; Rewatchables and Ebert pill filtering produce identical film sets
  (sim spot-check 2 pills each). ~30 lines deleted.

### Step 3 — Dead-code deletion (owner approval REQUIRED first)

The tracker marks this an owner call; get a yes before deleting. Two sub-batches:

3a (safe, no behavior question):
- `Shared/Objects/Bruno/BrunoStaticItemsLibrary.swift` (whole file; zero callers).
- `BrunoLibrarySnapshot.curatedBoxSets` (`BrunoLibrarySnapshot.swift:99-101`; zero callers).

3b (the retired-Curated cluster; behavior-dead but larger):
- `consolidateOscars` / `consolidateEbert` / `isCurated` / the `"curated"` case of
  `lensEyebrow` (`BrunoBoxSetShelvesView.swift:96-98/:128-169/:367`).
- `curatedRandomShelves` + its call site (`BrunoBoxSetShelvesView.swift:670-674/:704-823`).
- The `cardRowCategories` param (`BrunoCategoryShelves.swift:231/:416`) and its passer
  (`BrunoBoxSetShelvesView.swift:185`) — after this the card row always mirrors categories.
- The `"curated-oscars"` gold-tile branch (`BrunoCategoryShelves.swift:579-584`).
- Do NOT touch `BrunoHomePlan.swift:337` (`case "curated", "world"`): it is ALIVE and reads
  `promotedCuratedBoxSets`.
- Do NOT confuse `curatedRandomShelves` (dead) with `BrunoHomePlan.collectionsTail` (alive,
  the Collections procedural tail).
- **DoD:** compile green; sim: Collections hub renders all cards + shelves + tail; Oscars
  card opens six captioned shelves; Roger Ebert card opens the toggle grid. Update
  `docs/BRUNO_NAV_MAP.md` and the tracker row in the same PR. Net ~-250 lines.

### Step 4 — Extract the shared pill row (F2) — do BEFORE IA §6

- New `BrunoPillFilterRow<ID: Hashable>`: owns the state quintuple
  (`focused`/`selected`/`commitTask`/`filterRowAppeared`/`didEnterChipRow` +
  `@FocusState focusedChip`), the "Browse by" header option, the All chip, the
  once-then-yield `defaultFocus` dance, and the 500 ms debounced commit. Optional trailing
  pill slot (the Movies "All Movies" escape).
- Adopt in `BrunoGenresView`, `BrunoRewatchablesView`, `BrunoEbertView`, `BrunoKidsView`.
  Keep semantics bit-exact: `selectsOnFocus`, debounce duration, INV-7 first-paint no-op,
  non-toggling selection.
- **DoD:** compile green. Sim protocol per surface: (a) cold-enter fires NO filter (hero
  shows unfiltered set); (b) fast scrub commits exactly once on settle; (c) UP-from-content
  returns to the active pill; (d) DOWN-from-hero lands on All. Ebert only: verdict flip
  still resets the filter. THEN the IA §6 Decades work can build on this row.

### Step 5 — Fold the three private hero bands onto `BrunoBrandHeroBand` (F3; existing tracker item)

- Replace the private scaffolds in `BrunoStudiosGridView.swift:46-116` (also adopt
  `BrunoBrandHeroSectionTitle`), `BrunoRewatchablesView.swift:91-150`,
  `BrunoEbertView.swift:106-170` with the shared band. Ebert: make the backdrop asset a
  re-renderable input (it swaps on verdict flip).
- Move the INV-6 owner-override comment onto the band (the descending-blur look is the
  owner's explicit choice; never "fix" it to a sibling layer).
- **DoD:** compile green; screenshot-diff Studios / Rewatchables / Ebert before vs after
  (including the Ebert flip swapping the photo). Net ~-160 lines.

### Step 6 — Unify shelf captions and cards across the two row engines (F1 + F8)

Three sub-steps, one PR each:

6a. **Shared Card enum.** One `BrunoShelfCard` (item / show-all sentinel, id off `item.id`,
    `"bruno-show-all"` constant) consumed by `BrunoShelfView`, `BrunoShelfRow`, and the
    stock `PosterHStack.Card` if practical. The INV-2 cell-corollary comment moves to it.
6b. **Caption-driven labels.** `BrunoShelfRow` accepts a caption enum (extend
    `BrunoShelfCaption` with `titleDate` / `episode` / plain) instead of the four
    mutually-exclusive caption flags (`showsDate`/`showsEpisode`/`oscarCategory`/
    `showsEbertStars`); `BrunoCategoryShelves.shelf(for:)` maps category -> caption in one
    switch. Keep `labelArt`/`artCarousel`/`restCover` as a separate cell-style input.
6c. **One caption body.** Collapse the four content views (F8) into
    `BrunoTitleCaptionContentView(item:caption:)` + per-caption string providers. The
    geometry rules (two `lineLimit(1, reservesSpace: true)` lines, exact fonts, the
    no-SFSymbol-height-drift warning from `BrunoEbertContentView.swift:20-26`) live once,
    INV-1 anchored.
- Also extract the repeated CollectionHStack config into one `brunoShelfHStackStyle()`
  modifier (third copy in `BrunoCategoryCardRow.row`).
- **DoD per sub-step:** compile green; sim: Home curated shelf (star caption), Oscars
  drill-in shelf (Winner caption), Rewatchables shelf (Episode caption), Decades per-year
  shelf (date caption), New Releases (date) all render byte-identically; held-scroll a genre
  shelf (INV-10, no stall); `brunoPerfHeightWatch` emits no conflict events (INV-1).

### Step 7 — Retire the second focus-art-cycle stack (F4) — LAST, on-device

- Rebuild `FocusCyclingArt`/`BrunoChildArtViewModel`
  (`BrunoArtCarouselCard.swift:160-317`) on `BrunoFocusArtCycle`/`BrunoArtCycleViewModel`
  (key-aware load). Map `BrunoEraCard`'s rest composite to the band's `background:` closure;
  while there, take the F5 lockup/composite extraction so `BrunoEraCard` stops hardcoding
  the decades palette.
- **DoD:** compile green; DEVICE protocol (not sim-only): held-scroll a Studios row and a
  genre shelf to the end (no INV-10 stall); scroll fast through a Directors carousel row and
  re-focus recycled cells (no wrong-item art flash); Eras cards still show best-of covers.
  This is the one step with real regression surface; if the owner declines device time,
  skip it and leave F4 documented.

---

## Explicitly SKIPPED (decided, do not resurrect without new evidence)

| Candidate | Why skipped |
|---|---|
| Merging `BrunoShelfView` + `BrunoShelfRow` into one view | Their data models genuinely differ (VM + lazy reveal + snapshot routing vs plain array + callbacks). Step 6 removes the dangerous duplication; a full merge adds risk without deleting much more. |
| Merging the three tile cards (CategoryTile / LabelArtCard / EraCard) | Focus/button shells legitimately differ; extract the shared lockup/background (steps 6/7) and stop. |
| Menu-bar consolidation | The tab-root vs cover split is essential (env coordinator vs BrunoTabBridge). Optional 15-line deletion of the unused explicit-mode init; rename `BrunoHeroMenuBar.swift` -> `BrunoCoverMenuBar.swift` only if churn is cheap. |
| `BrunoMediaView` -> stock `PagingLibraryView` | Stock cannot host Bruno's labels/hero; one-shot paging is fine at this library size. |
| `BrunoPosterGrid` vs `BrunoBoxSetGridView.lazyGrid` merge | Two 7-up grids, but both small and stable; revisit only if a grid bug lands twice. |
| Centralizing Bruno `NavigationRoute` factories | Scattering is mitigated by the registry table in `NAVIGATION_MAP.md` §3; moving them buys nothing functional. |
| Renaming one of the two `shelfCap`s | Nice-to-have; do it opportunistically inside whichever step next touches the file, not as its own PR. |
| Any change to `Router` / player / `MainTabView` internals | Upstream engine; hard guardrail. |

## Verification appendix — the invariant checklist per step

| Step | INV-1 | INV-2 | INV-4 | INV-9 | INV-10 | Device needed |
|---|---|---|---|---|---|---|
| 1 Show-all card | check | check | - | - | - | no |
| 2 TMDB table | - | - | - | - | - | no |
| 3 dead code | - | - | - | - | - | no |
| 4 pill row | - | - | - | check (instant under reduce-motion) | check (no per-scrub rebuilds) | recommended |
| 5 band fold | - | - | - | - | - | no (screenshots) |
| 6 captions/cards | check (height pins) | check (card ids) | check (prefetch width) | - | check (held scroll) | recommended |
| 7 art cycle | check | check | check | check | CHECK (the whole point) | REQUIRED |
