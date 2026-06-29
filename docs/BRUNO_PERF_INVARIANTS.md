# Bruno tvOS — Performance Invariants

> **Read this before doing UX polish on the Home / browse shelves.**
>
> The Bruno tvOS Home is fast because of a handful of non-obvious rules. Most of them are invisible
> in the code unless you know to look. This doc is the contract: **what each rule is, why it exists,
> what breaks if you violate it, and how to make the change you want without violating it.**
>
> If you just want to restyle — see [Safe to touch](#safe-to-touch-restyle-freely) at the bottom. Most
> visual polish touches none of these invariants.
>
> **Sibling doc:** the **Movies tab is now the genre browse surface** — its interconnection + fragility map
> (menu-bar tab-root rule, the `"genres"` string contract, the three seeds, known gaps) lives in
> [`BRUNO_MOVIES_GENRE_SURFACE.md`](BRUNO_MOVIES_GENRE_SURFACE.md). Read that before touching the Movies tab.

The rules are anchored in code as `// INV-n:` comments at each load-bearing site. Grep `INV-` to find
them. The fragile *constants* live in one place — `BrunoShelfMetrics` (`Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfMetrics.swift`)
— so you change a value once and every consumer follows.

---

## Quick reference

| INV | Rule (one line) | Anchor / where it lives |
|---|---|---|
| INV-1 | Shelf rows are height-pinned (portrait 460 / landscape 348), placeholder == loaded. | `BrunoShelfMetrics`; `BrunoShelfView`, `BrunoShelfRow` |
| INV-2 | Shelf identity is stable and domain-derived (`shelf.id`, never index); reuse the same VM per id. | `BrunoHomeViewModel` (`ForEach`, `hydrate`) |
| INV-3 | Settled spine is deterministic, append-only in plan order (same seed ⇒ same home). | `BrunoHomePlan.build`, `streamReveal` |
| INV-4 | Prefetch width == cell width (portrait 200 / landscape 300, q90), mirror `PosterImage`. | `BrunoShelfMetrics`, `BrunoPosterPrefetcher` |
| INV-5 | Disk item-cache is seed+user keyed and excludes live user-state rows (resume/nextUp/recentlyAdded/hero picks). | `BrunoHomeCache` (`persistPayload`) |
| INV-6 | Ambient background is a sibling layer at low res (maxWidth 480), not a scroll `.background`. | `BrunoAmbientBackground` |
| INV-7 | ⚠️ **OVERRIDDEN (#45):** launch focus rests on the **menu bar** (`TabCoordinator.pendingBarFocus`), not the hero — owner's call; see `BRUNO_HERO.md`. Anti-race half still holds: streaming/placeholder shelves stay non-focusable until they carry real content. | `BrunoHomeView`, `BrunoHeroView`, `MainTabView` |
| INV-8 | Reveal cadence is strictly top-down regardless of completion order; hero auto-advance gated on settle. | `streamReveal`, `BrunoHomeView` |
| INV-9 | Every reveal/transition animation honors reduce-motion (collapse to instant). | `BrunoHomeView` (`reduceMotion`) |
| INV-10 | Shelf cells are structurally stable across focus; gate work (not view presence), load per-item data key-aware, no `.id` in the package. | `BrunoFocusArtCycle` (`// INV-10`), forked CollectionHStack |

---

## How Home loads (the mental model)

1. **Hero first.** `BrunoHomeViewModel` publishes the hero the moment it lands (~1–2s), so the banner
   paints while the shelves are still loading. The paint gate gives up the spinner as soon as the hero
   (or any shelf) exists.
2. **Shelves stream in, top-down.** All ~18 shelves load concurrently, but each is *revealed* only once
   every shelf above it has settled — so the spine fills downward and never shifts content under you.
3. **Instant relaunch.** The last session is persisted to disk (`BrunoHomeCache`). On relaunch Home
   paints that payload immediately, then revalidates from the network and reconciles in place.
4. **Posters pre-warm.** Each shelf warms its row's images so a revealed/scrolled row isn't blank.

Every one of those steps depends on the invariants below.

---

## The invariants

### INV-1 — Shelf rows are height-pinned (portrait AND landscape)
**What:** Every shelf row is pinned to a fixed height — `BrunoShelfMetrics.shelfRowHeight` (460,
portrait/7-col) or `BrunoShelfMetrics.landscapeShelfRowHeight` (348, landscape/4-col), via
`shelfRowHeight(for:)`. Sites: `BrunoShelfView`, `BrunoShelfRow`. **Landscape must be pinned too** —
leaving it at intrinsic height made landscape rows hard-snap (no intervening frames) on up-navigation.
**Why:** Two reasons, both load-bearing. (a) `CollectionHStack` computes its height lazily and reschedules
layout on the *next* runloop; if the `LazyVStack` re-reads that intrinsic height on a vertical focus move,
you get the up/down "hitch". (b) A constant spine geometry is what lets shelves stream in and reconcile
*under live focus* without shifting rows.
**Break symptom:** the vertical-scroll hitch returns; or shelves visibly shift/jump as they load or refresh.
**Safe change:** change the value in `BrunoShelfMetrics` (one place). Keep the placeholder/empty and loaded
states the *same* height. Don't make a row's height depend on its content.

### INV-2 — Shelf identity is stable and domain-derived
**What:** `ForEach` over shelves keys on `BrunoShelfViewModel.id` = `shelf.id` (a domain string like
`"genre-Western"`), never an array index, and it never changes across a shelf's loading→loaded→reconciled
life. Reconcile reuses the *same* VM instance for a matching id.
**Why:** the tvOS focus engine restores focus by view identity. Stable ids let us mutate the shelf array
(stream in, reconcile after relaunch) without tearing down rows — so focus survives.
**Break symptom:** focus jumps to a random shelf while content loads or after a background refresh.
**Safe change:** when you add/reorder shelves, keep ids derived from stable domain data. Never switch the
`ForEach` to `.enumerated()` / indices. Never rebuild a VM for an id that already exists on screen — update
its items in place (`BrunoShelfViewModel.hydrate(items:)`).
**Cell-level corollary (the #41→#43 regression).** The same rule applies one level down, to the CELLS in a
row: anything fed to `CollectionHStack(uniqueElements:)` must key its `id` off `item.id` (a constant
sentinel for a trailing "Show all" card), **never `self`**. A wrapper enum with `var id { self }` makes
identity the full *mutable* item value, which churns on every in-place update (streaming reveal, SWR
reconcile filling lean fields); the forked CollectionHStack's live hosting-controller reuse then paints a
stale async poster onto the re-identified cell — right label, wrong art. Fixed at `PosterHStack.Card` and
`BrunoShelfView.CarouselCard`; mirror `BrunoShelfRow.Card`.

### INV-3 — The settled spine is deterministic and in plan order
**What:** Shelves are *revealed* in plan order and the final `sections` array is exactly plan order;
`shouldDisplay` / `seenDedupeKeys` are computed on that settled set. The plan (`BrunoHomePlan.build`) is pure
given `(seed, snapshot)`.
**Why:** "same seed ⇒ same home" is a product contract (`BrunoHomePlan.selfCheckPassed()` asserts it in
DEBUG). Revealing in completion order, or filtering on a transient set, breaks reproducibility.
**Break symptom:** home order flickers or differs run-to-run; the DEBUG self-check assert fires.
**Safe change:** if you touch the streaming code, keep the reveal append-only in plan order (see
`streamReveal`). Don't sort by completion time.
**Carve-out (Genres/Movies surface only):** the genre browse shelves (`BrunoBoxSetShelvesViewModel.performLoad`,
the Movies tab) intentionally reshuffle their *row order* per launch / every 6h (`rowOrderSeed`) so the
tab feels fresh — this sub-surface is deliberately NOT deterministic across launches. The seed is read
once per load, so order is stable within a session (no mid-session reorder; INV-7 safe). This carve-out
does NOT apply to the Home spine, which stays fully deterministic under the rule above.

### INV-4 — Prefetch width == cell width
**What:** The poster prefetcher requests the *same* image width as the poster cell: `portrait 200 /
landscape 300, quality 90`, sourced from `BrunoShelfMetrics`. Those mirror the **stock-private** constants in
`Shared/Components/PosterImage.swift`.
**Why:** the Nuke cache key is salted by `maxWidth`. Warm a different width and you populate a *different*
key — the cell still misses, and you've wasted bandwidth.
**Break symptom:** prefetch silently does nothing; revealed shelves are blank for a beat anyway.
**Gotcha:** `Swiftfin tvOS/Components/PosterButton.swift` declares its own `…MaxWidth = 500` — those are
**dead/unused**. The width that actually hits the wire is `PosterImage`'s 200/300. Mirror PosterImage, not
PosterButton.
**Safe change:** if you change poster display size, update `BrunoShelfMetrics` to match whatever width
`PosterImage` ends up requesting. Both the cell and the prefetcher read from there.
**Genre browse surface (resolved):** the prewarm is now wired on **both** the Home shelf row
(`BrunoShelfView`) and the shared browse row (`BrunoShelfRow`, used by the genre/Movies tab + Collections),
each warming at the cell width (portrait 200) `.onAppear` / cancelling `.onDisappear`. See
[`BRUNO_MOVIES_GENRE_SURFACE.md`](BRUNO_MOVIES_GENRE_SURFACE.md) §8 G6.

### INV-5 — The disk item-cache is seed-keyed and source-restricted
**What:** `BrunoHomeCache` persists: the library snapshot, the hero *superset pool*, and realized items for
`.query` shelves only — stamped with the day-stable `seed` and `userID`. It **never** persists
`.resume` / `.nextUp` / `.recentlyAdded` (live user-state) or the 5 random hero picks.
**Why:** the day-stable seed means a cached spine is still valid later the same day. But Shuffle reseeds → new
`shelf.id`s → the seed guard makes the old payload a clean miss. Live rows carry `userData` (watched/resume) —
a stale "Continue Watching" is a *correctness* bug, not just stale art. The hero is intentionally random per
entry, so only its pool is durable.
**Break symptom:** Shuffle shows yesterday's shelves; or "Continue Watching" shows finished/removed items;
or the hero looks frozen on the same 5.
**Safe change:** keep `(seed, shelf.id)` as the item-cache key. If you add a new shelf source that is
user-state-dependent, exclude it from `persistPayload` (treat it like `.resume`). Persist pools, not picks.

### INV-6 — Ambient background is a sibling layer at low resolution
**What:** `BrunoAmbientBackground` is a sibling `ZStack` layer (not a `ScrollView` `.background`) and requests
`maxWidth: 480`. It's one fixed backdrop, not the rotating one.
**Why:** a radius-90 blur in the scroll view's `.background` re-rasterizes every scroll frame. As a sibling it
stays out of the per-frame compositing path. 480px is visually identical once blurred + 50% opacity, for ~7×
less decode.
**Break symptom:** scroll-frame stutter returns; memory/decode spikes.
**Safe change:** restyle the ambient freely (color, opacity, gradient) but keep it a sibling layer and keep
the decode small. Don't bind it to the rotating hero backdrop.

### INV-7 — Focus lands on the hero until a real shelf exists
> **⚠️ OVERRIDDEN (#45, owner's call):** launch first-focus no longer lands on the hero — it rests on the
> **menu bar** (the Home pill, via `TabCoordinator.pendingBarFocus`), and the cold-load frame is
> deliberately focusable so the remote is never dead during load. The full focus model lives in
> `docs/BRUNO_HERO.md`. Only the **anti-race half below still holds.**

**What (anti-race, still in force):** Shelves only become focusable once they carry real content (they
don't render until `items.isNotEmpty`), so focus never lands on an empty/placeholder card.
**Why:** if focus could land on an empty/placeholder card that then fills with art, the art appears to
"change under the ring" — unsettling on a 10-ft screen.
**Break symptom:** the focus ring sits on a blank/loading card and the poster swaps beneath it.
**Safe change:** if you add a skeleton/placeholder row, make it **non-focusable** until it has real items.
Launch first-focus is the **menu bar** now (not the hero) — see the override above + `BRUNO_HERO.md`.

### INV-8 — Reveal cadence is top-down regardless of completion order
**What:** Shelves are loaded in parallel but revealed strictly top-down (`streamReveal` flushes consecutive
completed shelves). The hero's auto-advance is held (`autoAdvanceEnabled`) until the spine has settled.
**Why:** revealing in completion order makes the page twinkle (random pop-in) and can insert a shelf *above*
the one you're looking at. A held auto-advance keeps a backdrop swap from competing with the fill. Together
they read as an intentional cinematic stagger, not "still loading."
**Break symptom:** shelves pop in out of order / content jumps; or the hero rotates while the page is still
assembling.
**Safe change:** keep the reveal append-only and ordered. Tune the fade/stagger/drift in `BrunoHomeView`
(the `.transition` + `.animation(value:)`) freely — that's cosmetic. Keep auto-advance gated on settle.

### INV-9 — Every reveal animation honors reduce-motion
**What:** The shelf stream-in fade+drift, the scroll-reset animation, and the hero drift all collapse to an
instant state when `accessibilityReduceMotion` is on.
**Why:** accessibility contract (and the design spec mandates it).
**Break symptom:** motion plays for users who asked for none.
**Safe change:** any new entrance/transition you add must branch on `reduceMotion` (it's already an
`@Environment` in `BrunoHomeView`). Collapse to opacity-only or instant.

### INV-10 — Shelf cells: structurally stable across focus, no stale per-item state on reuse
**What:** A shelf cell's view-tree **structure must not change when it gains/loses focus**, and it must not
carry per-item state that survives into the next element it's recycled for. Heavy per-cell machinery
(view models, prefetchers, timers, cycle logic) must be gated by **work**, not by **view presence**: keep
the layer permanently in the tree and start/stop its work via `.onChange(of: isFocused)` / `.task(id:)`.
The genre cell is the reference example: `BrunoFocusArtCycle` keeps its `artLayer` (and its `@StateObject
BrunoArtCycleViewModel`) **always present**; gaining focus only flips an internal `active`/`rolling` Bool and
kicks the cycle via `.onChange(of: isFocused)`, and the art set is loaded **key-aware** (clears + reloads
when the card's `parentID`/fallback identity changes), with visibility gated on the *current* item's frames
so a recycled cell can never flash the previous item's art. The in-repo anchor `// INV-10` belongs at the
always-present `artLayer` + `.onChange(of: isFocused)` site in `BrunoFocusArtCycle`.
**Why (two independent reasons, both load-bearing):**
1. **Reuse correctness.** `CollectionHStack` is the **fork** `DiplomacyMusic/CollectionHStack@bruno-hosting-reuse`
   (`466aeb3f`), which **reuses** the cell's `UIHostingController` and swaps its `rootView` on recycle instead
   of rebuilding a fresh controller per dequeue (the perf win — it lifts the per-cell `UIHostingController`-mint
   floor; see INV-1). SwiftUI carries `@State` across a same-type `rootView` swap at the same slot, so per-item
   state left alive on a recycled cell can **leak into the next element**. Key-aware loading (clear+reload on
   item change) is what makes the always-present view model safe.
2. **tvOS focus auto-repeat.** Press-and-hold scrolling is a paced sequence of discrete focus updates; the
   engine only continues the repeat if the focused branch is **settled** each tick. If a cell mutates its own
   subtree *during* its focus update (e.g. `if isFocused { SomeView() }` inserting a node as focus lands), it
   invalidates the self-sizing UICollectionView cell and the engine resolves it as a reset-in-place
   (`setNeedsFocusUpdate` → preferred focus, not the next row) — so a held scroll **stalls after a few rows**.
   The bridged UICollectionView nesting amplifies this. Keeping the focused subtree structurally constant is
   what keeps held-scroll advancing.
**Break symptom:** (a) stale per-item state on a recycled cell (wrong art mid-cycle, stale highlight, a timer
for the previous item); (b) **held/press-and-hold scroll advances only a few rows then stops** (must lift and
re-press); (c) if you "fix" reuse the wrong way, the per-cell hitch returns.
**Break recipe (don't):** (a) per-item `@State` that must reset between elements WITHOUT keying/identity →
stale on reuse. (b) `.id(item.id)` *inside* the CollectionHStack package → forces a full subtree rebuild per
`rootView` swap, DEFEATING the reuse win. (c) **`if isFocused { HeavyView() }` (conditional view insertion on
focus)** → structurally mutates the focused cell mid-focus-update and stalls held-scroll auto-repeat. This was
shipped (`7985aaf0`) and reverted (`86acd5f5`) precisely because it broke held-scroll — do not reintroduce it.
**Safe recipe:** keep the heavy layer **always in the tree**; gate its *work* via `.onChange(of: isFocused)` /
`.task(id:)` and its *visibility* via a Bool (`active`); load per-item data **key-aware** (clear+reload on
item change) so reuse shows the right item with no stale flash; never add `.id` in the package. If a cell
genuinely needs resettable per-item `@State`, attach `.id(item.id)` at the **Bruno call site** (e.g. in
`BrunoShelfRow`'s cell builder), accepting it trades away reuse for that shelf. Cross-ref: INV-1 (height-pin)
and INV-2 (stable shelf identity — INV-10 is the cell-level analogue: the cell has NO per-item identity by
design, so its art must come from item data + keyed load, not surviving state).
**Reference commits:** hosting-controller-reuse fork `466aeb3f`; structurally-stable + key-aware design
`86acd5f5` (which **supersedes** the focus-gated-insertion approach `7985aaf0` that stalled held-scroll).

---

## Safe to touch (restyle freely)

None of these go near the invariants — change them without ceremony:

- Poster **corner radius, shadow, focus ring, hover/scale** styling.
- Shelf **eyebrow / title** text, font, tracking, color (Oswald + accent).
- **Spacing rhythm** between shelves and within headers (the 8/10/16/40 system).
- Hero **scrim** gradients, copy, pill styling, meta line.
- **Colors and fonts** (the `Color.bruno.*` / `brunoDisplay`/`brunoBody` tokens).
- The **stream-in animation** itself — fade duration, drift distance, stagger feel (keep INV-9).
- The **"Show all" card** look in `BrunoShelfRow`.

If a change touches a `// INV-n` site, re-read that invariant here first. When in doubt, the safe move is
almost always: **keep row height fixed, keep shelf ids stable, and read widths/heights from
`BrunoShelfMetrics`.**

---

## Where things live

| Concern | File |
|---|---|
| Fragile constants (INV-1, INV-4) | `Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfMetrics.swift` |
| Streaming reveal, hydrate, reconcile (INV-2/3/8) | `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeViewModel.swift` |
| Reveal choreography, paint gate (INV-7/8/9) | `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeView.swift` |
| Shelf row + height pin + prefetch wiring (INV-1/4) | `BrunoShelfView.swift`, `BrunoShelfRow.swift` |
| Disk cache (INV-5) | `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeCache.swift` |
| Snapshot (Codable) | `Shared/Objects/Bruno/BrunoLibrarySnapshot.swift` |
| Poster prefetch (INV-4) | `Swiftfin tvOS/Views/BrunoHomeView/BrunoPosterPrefetcher.swift` |
| Ambient layer (INV-6) | `Swiftfin tvOS/Views/BrunoHomeView/BrunoAmbientBackground.swift` |
| Hero auto-advance gate (INV-8) | `Swiftfin tvOS/Views/BrunoHomeView/BrunoHeroView.swift` |
| Structurally-stable, work-gated cell state — `// INV-10` anchor (INV-10) | `BrunoFocusArtCycle` (always-present `artLayer` + `.onChange(of: isFocused)` + key-aware `BrunoArtCycleViewModel.load`) |
| Forked cell-reuse package (INV-10) | SPM dep `DiplomacyMusic/CollectionHStack@bruno-hosting-reuse` (`HostingCollectionViewCell`) |
