# Bruno IA Overhaul — Plan + Code/Architecture Guidance

**Status:** planning, 2026-06-30. Owner intent captured; this doc layers the
code seams, existing patterns to copy, determinism/INV risks, and the data
gates onto each intent item. Citations verified by `bruno-expert` against
branch `claude/vigilant-albattani-40f55e` (commit `6ec18cab`) and
`swift-xcode-expert` (tvOS focus engine, WWDC23 session 10162).

**How to read this:** each section restates the owner intent (unchanged), then
adds an **Implementation** block: *Seam* (file:line), *Pattern to copy*,
*Determinism/INV*, and *Data gate / open question* where one exists. Nothing
here is built yet — it tells the implementing session where each change lands so
local edits don't ripple silently through the one connected pipeline
(`BrunoHomePlan` → `BrunoHomeViewModel` → `BrunoShelfView` / `BrunoCategoryShelves`,
"show all" via `brunoRouteToShowAll`).

---

## 0. The pipeline these changes ride on (orientation)

- **Top card strip:** `BrunoCategoryCardRow.swift:25-54` — a `CollectionHStack`
  (7 cols) of code-drawn `BrunoCategoryTile`s; each tile's tap calls
  `brunoRouteToShowAll(category, …)` (`:41`).
- **Card model:** `BrunoCollectionCategory` — `BrunoCategoryShelves.swift:23-88`
  (`Identifiable, Codable`; disk-cached).
- **Card list build:** `BrunoCollectionCategory.fromSnapshot(_:)` —
  `BrunoCategoryShelves.swift:143-182`. Maps `snapshot.favoriteGroupBoxSets` →
  categories, drops "genres", appends synthetic "Boxed Sets".
- **Fixed order:** `rank(for:on:)` — `BrunoCategoryShelves.swift:96-109`.
- **Browse router:** `brunoRouteToShowAll(_:router:namespace:)` —
  `BrunoCategoryCardRow.swift:62-209` (switches on `drillStyle`).
- **Home router:** `brunoHomeRouteToShowAll` — `BrunoHomeShowAll.swift`.

The card strip + drill-ins are all **server-group-driven by name string** — no
hardcoded IDs. A favorited group BoxSet becomes a card automatically; only its
`rank` / `drillStyle` / `lens` are name-keyed switches.

---

## 1. Card Architecture — retire Curated, promote four, demote one, add Cities

### Remove: Curated
The Curated tile is the group named "Curated", surfaced because it's a favorited
group BoxSet (`snapshot.curatedBoxSets`, `BrunoLibrarySnapshot.swift:99-101`).

**Implementation.** "Retiring" the card is two moves: (a) drop or re-rank it in
`rank(for:on:)` (`BrunoCategoryShelves.swift:96-109`) so it no longer appears in
the strip, and (b) redistribute its children (below). The children are *server
data* under the Curated group; promoting them to top level means they must each
become their own favorited group BoxSet **or** be re-pointed by name in the
card-build switch. **Owner decision needed:** are Roger/Oscar/Asian Cinema/Film
School being made their own favorited server groups, or do they stay children of
Curated and get *surfaced* as top-level cards via app-side promotion? The former
is data-only (cleanest); the latter needs new synthetic categories in
`fromSnapshot`.

### Promote to top level: Roger, Oscar, Asian Cinema, Film School
Today these are Curated children, consolidated into "Ebert"/"Oscars" tiles only
*inside* the Curated drill-in (`consolidateOscars`/`consolidateEbert`,
`BrunoBoxSetShelvesView.swift:136-167`).

**Implementation.**
- *Roger (Ebert):* drill-down unchanged — it already has its one-tile toggle
  (`PROJECT_TRACKER.md:39`). Promotion = give it a top-level `rank` slot + a
  `drillStyle`/`lens`. Its grid route already exists.
- *Oscar:* consolidated Academy Awards card — the six-category drill-in already
  exists (`BrunoOscarCategory`, `BrunoOscarAward.swift:19-44`; six gold tiles
  `BrunoCategoryShelves.swift:516-521`). Promotion = top-level `rank` slot; reuse
  the existing `consolidateOscars` one-tile collapse for the card face.
- *Asian Cinema:* drill-down = genre shelves + Wong Kar Wai + Bong Joon Ho
  shelves, **no filter pills.** This is a `.shelves` drill (like Curated) but with
  a hand-authored shelf set. Seam: a new `drillStyle` branch or a dedicated
  shelves view modeled on `BrunoBoxSetShelvesView.performLoad`
  (`:506-679`) but with the director shelves added as `bruno-sig`-style synthetic
  shelves. No pill state → simpler than Decades.
- *Film School:* contents **untouched** — pure promotion, give it a `rank` slot
  and keep its existing drill route.

*Determinism/INV:* new synthetic top-level categories must mint **stable string
ids** (INV-2) — never an index. Follow the existing `curated-oscars` /
`curated-ebert` id convention.

### Demote: Cultural Touchstones
Never top-level. Surfaces as (a) a shelf inside the Decades drill-down and (b) a
seeded section above the alphabetical content in the All Movies grid — *same
structural pattern as Studios*.

**Implementation.** Pattern (b) is exactly the Studios "Household Names" section
(`BrunoStudiosGridView.swift:67-75`, the pinned section above the A–Z grid). The
All Movies grid would get an analogous seeded section sourced from the Cultural
Touchstones group members. Pattern (a) is a synthetic shelf appended in the
Decades drill (`shownCategories`, `BrunoBoxSetShelvesView.swift:111-123`). Remove
its `rank` slot so it never renders as a card.

### New: Cities (data-seeded, Chicago first)
Must accommodate adding cities without code changes.

**Implementation.** The server-group-seeded path is fully name-driven:
`fetchGroupBoxSets` (`BrunoLibrarySnapshot.swift:195-204`) discovers any
favorited group; `fetchChildren` (`:206-216`) reads members (⚠ `ParentId` with
**no type filter** — documented trap, `BRUNO_CODE_MAP.md:240-243`);
`fromSnapshot` (`BrunoCategoryShelves.swift:143-182`) turns it into a card by
name. So a "Cities" favorited group with Chicago as first child surfaces
automatically **once** Cities gets a single `rank`/`drillStyle`/`lens` entry —
after that, new cities are pure data. *Existing hook:* the Movies genre buckets
already reference `"chicago movies"` (`BrunoGenresView.swift:44,51,57,…`), so a
Chicago seed partially exists on the genre side. **Data gate (owner):** the
Cities group BoxSet must be created and favorited on the server with Chicago as a
child before the card can appear.

### Everything else under Curated
**Data gate:** flag for owner disposal *after* the full Curated member list is
confirmed (see Data Needs). No code until the list is in hand.

---

## 2. Two-Row Card Layout

Single strip → two equal-height rows, same card size, normal up/down focus.
Row 1 (what to watch): New Releases · Oscar · Roger · Rewatchables · Seasonal.
Row 2 (how to browse): Decades · Directors · Movie Stars · Studios · BoxSet.
Asian Cinema / Film School / Cities placed by design.

**Implementation.** Today the strip is one `CollectionHStack` (7 cols) at
`BrunoCategoryCardRow.swift:36-39`. Two rows = either two `CollectionHStack`s
stacked in a `VStack`, or one grid. **Recommendation:** two explicit
`CollectionHStack` rows wrapped in `.focusSection()` each, so up/down between
rows is a clean focus-section traversal and left/right stays within a row. The
row membership is no longer `rank`-sorted into one line — it's two explicit
ordered arrays. This means `rank(for:on:)` (`:96-109`) is partly superseded by a
row-assignment map (which card → which row + position). Keep ids stable (INV-2);
keep the tile cells structurally stable (INV-10 — no conditional focusable
insertion). Row height is fixed (INV-1) — both rows must use the same metric.

*Open question:* with Curated retired and four cards promoted, the strip grows
from ~10 to ~13 entries — confirm the two-row split absorbs all of them (Row 1 =
5, Row 2 = 5, leaves Asian Cinema/Film School/Cities = 3 to place). 5+5+3 = 13
fits two rows of up to 7. Final placement is the owner's design call.

---

## 3. Studios Backdrop — Studio04 / pinned mountain

Studios card tile + full grid both use one static backdrop (the Paramount
mountain), never rotating — the one hard visual lock.

**Implementation.** The Studios grid backdrop today is
`Image("BrunoStudiosBackdrop")` (`BrunoStudiosGridView.swift:52`) — a full-bleed
still loaded via `Image(_:)` because the app's `ImageView` is URL-only.
⚠ **Asset-name discrepancy:** the owner says **Studio04** (Paramount mountain);
the live code references **`BrunoStudiosBackdrop`** (bruno-expert found no
`Studio04` symbol in this file). **Owner to confirm:** is `Studio04` a new asset
to swap in, or a rename of the existing `BrunoStudiosBackdrop`? The card *tile*
backdrop lives in `BrunoCategoryTile` / `BrunoCollectionArtwork` (code-drawn
gradient today, not a still) — pinning the same mountain image on both the tile
and the grid means the tile must switch from gradient to the same `Image` asset.
*INV-6:* the Studios grid **already** has an owner-sanctioned INV-6 exception
(scroll-coupled blur over the `LazyVGrid`, `PROJECT_TRACKER.md:87-89`,
file header `BrunoStudiosGridView.swift:28-32`). Pinning the backdrop stays
inside that exception — no new perf risk, just no rotation logic.

---

## 4. Oscar Shelves — Year De-duplication across the six shelves

A single Oscar year dominates lead slots across all six category shelves. Spread
the top visible slots so no year dominates multiple shelves' leads.

**Implementation.** Each of the six shelves is sorted independently by
`BrunoOscar.reverseChronological(_:category:)` (`BrunoOscarAward.swift:75-85`,
award-year desc → premiere desc → id), applied per-shelf in
`BrunoBoxSetShelvesView.performLoad` (`:598-602`). There is **no cross-shelf
coordination today** — this is net-new logic. The natural seam is the drill-in
assembly where all six are visible at once (`performLoad` Oscar branch `:598-602`,
or the `consolidateOscars` assembly `:136-149`). Approach: after each shelf is
reverse-chron sorted, run a **seeded de-dup pass over the lead slots** — walk the
six shelves' slot 0/1, and where the same year (or same film) repeats, demote the
duplicate and pull up the next distinct-year candidate. *Determinism (INV-3):*
the tie-break/spread must be seeded from `(seed, snapshot)` — **not `Date()`** —
so the same launch yields the same spread; use the existing `rowOrderSeed`
(`BrunoBoxSetShelvesView.swift:431-433`). Keep `reverseChronological`'s stable
`id` final tie-break so the sort stays total (INV-3-safe). **Data gate:** the
Oscar per-item tags `oscar:<CAT>:<won|nom>:<year>` (`BrunoOscarAward.swift:63-70`)
must be applied server-side (`Apply-Enrich-Tags.command apply`,
`PROJECT_TRACKER.md:38`) for the year data to exist.

---

## 5. Directors Card

### Household Names (pin Chazelle, Cameron Crowe, Eggers)
Mirror the Studios pinned-shortlist feature.

**Implementation.** The canonical model is `BrunoStudiosGridView`:
`recognizableStudios` (`:154-187`, ~32 names in editorial order) ∩ what's present
(`normalizeStudio`, `:194-196`), capped at `topStudioLimit = 12` (`:190`, 3 rows
of 4), order rotated (not membership) by day-seed
`BrunoRNG.shuffled(…, seed: daySeed)` (`:216`; `daySeed` `:200-203`), rendered as
the "Household Names" section above the A–Z grid (`:67-75`). Directors gets the
same structure in its grid view (currently `BrunoBoxSetGridView`, which has no
such section — net-new). Add a `recognizableDirectors` shortlist including the
owner hard-adds **Chazelle, Cameron Crowe, Eggers** (server BoxSets confirmed
present). *Determinism (INV-3):* reuse the `daySeed` rotation so order varies
day-to-day but membership is stable; *INV-2:* stable ids; *INV-10:* the pinned
cells must be structurally stable.

### John Hughes (display-layer override)
Include Hughes-produced-but-not-directed films (Ferris Bueller, Home Alone) in
his director grid. No server data changed — presentation only.

**Implementation.** This is a display-layer union: his director-grid member list
= (films where Hughes is director) ∪ (a hard-coded override list of library IDs).
The override is app-side, keyed on the specific item IDs. Seam: the Directors
drill-in member resolution (the per-director query that feeds the grid). **Data
gate (owner):** library IDs for the Hughes-produced-but-not-directed films — the
override list cannot be built without them. *INV-2:* the merged list must keep
stable ids and de-dup if a film appears in both sets.

### Hero — Directors grid (and Movie Stars grid)
Top-level Directors grid + top-level Movie Stars grid each need a cinematic hero
banner (craft-of-filmmaking imagery).

**Implementation.** Both grids route to `BrunoBoxSetGridView`, which has **no
hero today** (no `GeometryReader`/backdrop/header — bruno-expert confirmed). Net-
new. Two patterns to copy: the generic `BrunoHeroView` band
(`BrunoHeroView.swift:30`, used by Decades) or the bespoke brand-art band
(Studios `:105-115` / Rewatchables `BrunoRewatchablesView.swift:96,138`). For a
static atmospheric grid-hero, the Studios/Rewatchables brand-art band is the
closer fit (a fixed `Image` over the grid). See §7 (Drill-Down Heroes) — this is
the same work item.

---

## 6. Decades — reactive hero + double-tap-down nav

### Hero lockstep with selected decade (seeded, rotating)
The hero is the visual identity of the selected decade; updates as the user moves
through decade pills; sourced from a *seeded random pick* within that decade's
strong candidates (not always #1), rotating daily/per-session, stable within a
session. Hero + decade selection are one state, two expressions; warming /
prefetch / hero load all trigger together on decade change.

**Implementation — this is the biggest behavioral change.** Today the Decades
hero is `featuredItem` — `@State`, computed **once** from the full unfiltered set
when categories land (`BrunoBoxSetShelvesView.swift:79`, set at `:211-212`), and
deliberately **decoupled** from pill changes so a decade swap never reloads the
720pt backdrop (comment `:186-189`). The owner wants the *opposite*: make it
reactive per-decade. The data source already exists — `snapshot.decadeBestOf`
(`BrunoLibrarySnapshot.swift:44`, resolved by `fetchDecadeBestOf` `:222-239`) is
already threaded to the Decades *cards* (`decadeBestOf` param,
`BrunoCategoryShelves.swift:263`). So a seeded-per-decade hero binds the existing
`featuredItem` to the committed decade and picks via a seeded index into that
decade's candidate pool.

⚠ **Determinism (INV-3) is the hard constraint:** "seeded random pick that
rotates daily/per-session" must derive from `(seed, decade)` — **never
`Date()`** directly inside plan/render. Use the existing seed plumbing
(`rowOrderSeed` `:431-433`, or a `daySeed` like Studios `:200-203`) so the pick
is stable within a session and varies across sessions deterministically. ⚠
**Perf:** the existing decoupling exists *specifically* to avoid reloading the
720pt backdrop on every decade swap — making it reactive reintroduces that cost.
Mitigate: bind hero load to the **committed** decade (`selectedDecade`, `:52`),
not the **focused** decade (`focusedDecade`, `:58`), and reuse the ~500 ms commit
debounce (`commitFocus`, `:309-341`) so scrubbing pills doesn't thrash the
backdrop. Trigger warming + prefetch (`decadesNearFocus`, `:346-353`) + hero load
on the same commit. Verify no >100 ms stall on decade commit (INV-8 settle).

### Double-tap-down navigation (two-state pill nav)
State 1: Down from content → pills focus, hero fully visible above, pills at
bottom edge. State 2: Down again → pills stay focused, anchor to top edge, view
scrolls to reveal shelves. Third Down → into shelves. Port identically to Movies
(genre pills) and Kids (All/Movies/TV/Disney/Pixar pills).

**Implementation — focus-engine architecture (swift-xcode-expert).** The robust
tvOS approach is **not** to veto the Down move (tvOS resists that;
`onMoveCommand` is a notification, not a documented veto). Instead **control
focus topology per state:**

- Model an explicit idempotent enum: `enum PillNavStage { case heroVisible,
  pinnedTop, shelvesActive }` in `@State` / a `@MainActor` view model. Each Down
  does exactly one `advance()`, guarded `guard stage == .heroVisible else
  { return }` so held auto-repeat can't skip a state (INV-10 — the held-repeat
  freeze lives here).
- **State 1:** render the shelves below `.focusDisabled(stage != .shelvesActive)`.
  With no focusable neighbor below, the engine's Down resolves to "no candidate,"
  and your `.onMoveCommand { if .down → advance + scroll }` runs the scroll while
  focus stays on the pill.
- **State 2:** `withAnimation(completion:)` runs the pill-pin + `scrollTo` then
  flips `stage = .shelvesActive`, enabling shelf focus. The **next** Down now
  resolves downward naturally — the engine does the handoff for free.
- **Pinning:** the pill row must be an **overlay / `safeAreaInset(.top)` layer
  outside the `ScrollView`**, never a `LazyVStack` pinned header (pinned headers
  are a layout, not a focus, affordance and drop focus at scroll boundaries). A
  stable, non-scrolling coordinate space keeps the focus frame steady.
- **Concurrency:** all of it `@MainActor`; the only async seam is
  `withAnimation(_:completion:)` (completion runs on main). **No `Task.sleep`
  debounce** — gate on stage equality, not time (time-based debounce against the
  remote's auto-repeat is exactly the INV-10 freeze).
- Keep focus appearance (scale/shadow) a pure GPU transform, value-driven — no
  state mutation that rebuilds the subtree on each focus tick (the
  `FocusShadowPoster` lesson, INV-10).

**Shared idiom — change once, not three times.** All three surfaces already
implement a two-state focused-vs-committed pill nav with the same idiom:
- Decades: `decadePanel` `BrunoBoxSetShelvesView.swift:248-303`
  (`selectedDecade :52` / `focusedDecade :58` / `@FocusState focusedChip :84`;
  `defaultFocus` two-state `:294-295`; `commitFocus` `:309-341`).
- Movies: `BrunoGenresView.corePanel` `:239-304` (`selectedCore :125` /
  `focusedCore :131` / `focusedChip :152`; `defaultFocus :295-296`).
- Kids: `BrunoKidsView.filterBar` `:198-223` (`filter :34` / `focusedFilter :38`
  / `focusedChip :43`; `defaultFocus :218-219`).

The "snap pills to top on focus" behavior is **already centralized** at
`BrunoCategoryShelves.swift:437-456` (and reproduced standalone in
`BrunoKidsView.swift:179-190`). The new double-tap-down state machine should be
factored as a shared modifier/component so all three adopt it identically — the
spec says any implementation that collapses the two states or loses pill focus on
the second tap does not meet the bar. *INV-7:* the cold-enter guards
(`didEnterChipRow` / `filterRowAppeared`) must be preserved — a fresh entry must
not fire a filter. **On-device verification is mandatory** (swift-xcode-expert):
held-Down through hero→pinned→shelves must land one stage per gear with no freeze
and no focus flicker — the sim's focus timing differs; do not certify from the
sim.

---

## 7. Drill-Down Heroes (Directors, Movie Stars, Box Sets new; Decades reactive)

All major drill-downs get a hero banner. Directors / Movie Stars / Box Sets are
net-new; Decades already has one (made reactive per §6).

**Implementation.** Directors / Movie Stars / Box Sets all route to
`BrunoBoxSetGridView` (no hero today). Add a hero band at the top of that grid —
copy either `BrunoHeroView` (`BrunoHeroView.swift:30`, the Decades pattern) or
the bespoke brand-art band (Studios `:105-115` / Rewatchables
`BrunoRewatchablesView.swift:96,138`). For static atmospheric imagery the brand-
art band (fixed `Image` over a flat grid) is the closer match and inherits the
Studios INV-6 exception (`PROJECT_TRACKER.md:87-89`) consciously. *INV-1:* fixed
grid row height below the hero; *INV-8:* top-down reveal preserved.

---

## 8. Curated Explore Generator (Home Feed) — retarget or retire

The Home feed generator draws from the Curated server group; once Curated is
retired its data source changes.

**Implementation.** The generator is `BrunoHomePlan.explore(key:)` cases
`"curated"` / `"world"` — `BrunoHomePlan.swift:337-346`, calling
`boxSetShelf(snapshot.curatedBoxSets, …)` (`:341`). The Collections procedural
tail's ×6 Curated family is the analogous path (`collectionsTail`
`BrunoHomePlan.swift:625-639`). **Owner decision needed:** retarget this
generator to the promoted collections (Roger/Oscar/Asian Cinema/Film School) or
retire it. If retarget: repoint `snapshot.curatedBoxSets` to a union of the
promoted groups' snapshot accessors. *INV-3:* whatever it draws from, the pick
must stay seeded-pure over `(seed, snapshot, now)`. **Blocked on §1** — can't
finalize until the Curated retirement shape (own-groups vs app-side promotion) is
decided.

---

## 9. Data Needs — owner must supply (these gate dependent work)

1. **Curated member list** — full list of all server BoxSets in the Curated
   group by name. Gates §1 disposal decisions.
2. **John Hughes film IDs** — library IDs for produced-but-not-directed films.
   Gates §5 override.
3. **Cities server group** — favorited "Cities" group BoxSet with Chicago child,
   created on the server. Gates §1 Cities card.
4. **Oscar tags applied** — `Apply-Enrich-Tags.command apply` so
   `oscar:<CAT>:<…>:<year>` tags exist. Gates §4 year-dedup.
5. **Studio04 vs BrunoStudiosBackdrop** — confirm whether Studio04 is a new asset
   or a rename. Gates §3.

---

## 10. Open Bug (low priority, not blocking)

**Shelf-vanish:** in Movies, all shelves briefly disappeared mid-scroll (~3–4
shelves deep), then returned on navigation. First confirmed occurrence. Likely
related to the cap-and-grow reveal window (INV-8, `visibleShelfCount`
`BrunoCategoryShelves.swift:303,379-401`) or the `dataPrefix`-must-track-reveal
trap noted in prior shelf-depth work. Not blocking IA work; log if it recurs.

---

## Sequencing recommendation (lowest-risk → highest)

1. **Pure-data / unblocked-once-owner-supplies:** §1 promotions (rank slots),
   §3 backdrop pin, §5 household-names list, §7 static drill-down heroes — these
   reuse existing patterns with low determinism risk.
2. **Owner-data-gated:** §1 Cities, §5 John Hughes override, §4 Oscar dedup —
   blocked on Data Needs 1–4.
3. **Highest-risk (perf + focus):** §6 reactive Decades hero (reintroduces the
   backdrop-reload cost the code deliberately avoided) and the §6 double-tap-down
   pill nav (focus-engine state machine, INV-7/10, on-device verification
   required). Build these last, behind the shared-idiom refactor, and verify on a
   real device.
4. **Decision-gated:** §2 two-row layout (design call) and §8 Curated-Explore
   retarget (blocked on §1 shape).
