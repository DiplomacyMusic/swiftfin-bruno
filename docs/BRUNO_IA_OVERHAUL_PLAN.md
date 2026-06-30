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

### Promote to top level: Roger, Oscar, Asian Cinema, Film School, Critically Acclaimed
Today these are Curated children, consolidated into "Ebert"/"Oscars" tiles only
*inside* the Curated drill-in (`consolidateOscars`/`consolidateEbert`,
`BrunoBoxSetShelvesView.swift:136-167`).

⚠ **Prerequisite — promotion REQUIRES favoriting server-side, not just a `rank`
slot (red-team finding 1).** `fromSnapshot` builds cards **only** from
`snapshot.favoriteGroupBoxSets` (`BrunoCategoryShelves.swift:144`). These five are
**children of Curated, not favorited groups** (verified absent from the favorited
list), so a `rank`/`drillStyle`/`lens` entry does **nothing** until each is
favorited — exactly what made Cities appear. **Mechanism — owner decision
2026-06-30: make them real favorited groups (data-only, like Cities).**
- Singles → favorite directly: **Asian Cinema** (`f96882e8…`), **Film School
  Classics** (`61b1fa77…`), **Critically Acclaimed** (`e09ff623…`).
- Consolidated → create favorited **parent groups** whose children are the
  existing BoxSets: **"Oscars"** parent over the six `Oscar *` BoxSets, **"Roger"**
  (or "Ebert") parent over the two `Ebert Thumbs Up/Down` BoxSets — same shape as
  the Cities group (parent + child BoxSets, `.shelves` drill). This replaces the
  app-side `consolidateOscars`/`consolidateEbert` synthetic collapse with real
  server groups (cleaner; one promotion mechanism, not two).
- **Coordinate with retiring Curated** so there's no transitional double-surfacing
  (a promoted child showing as both a Curated shelf and a top-level card). Do the
  favoriting + the Curated un-favorite + the app seams as **one migration**, not
  piecemeal — favoriting alone (before the seams) renders them with default `.grid`
  + `.max` rank + no lens (degraded). Server migration is scriptable now; gate it
  on the app seams being ready.

**Implementation (per card).**
- *Roger (Ebert):* once the "Roger" parent group exists, its `.shelves` drill shows
  the Up/Down shelves; the one-tile toggle grid (`PROJECT_TRACKER.md:39`) stays.
  `rank` + `drillStyle .shelves` + `lens`.
- *Oscar:* the "Oscars" parent group's `.shelves` drill fans out the six category
  shelves (the existing gold-tile treatment, `BrunoOscarCategory`,
  `BrunoOscarAward.swift:19-44`). `rank` + `.shelves` + `lens`. The app-side
  `consolidateOscars` collapse is no longer needed once the parent group is real.
- *Asian Cinema:* **flat 38-movie BoxSet (verified) — NOT sub-BoxSets, so the
  generic `.shelves` drill can't iterate it (red-team finding 2).** Owner decision
  2026-06-30: **no new BoxSets** — compose the drill from data that already exists:
  - *Wong Kar-Wai* shelf ← the existing `Wong Kar-Wai` director BoxSet
    (`824f5063…`, 4 films, under Directors).
  - *Bong Joon Ho* shelf ← the existing `Bong Joon Ho` director BoxSet
    (`01fd8535…`, 5 films).
  - *Genre shelves* — Action · Romance · Thriller · Drama · Comedy · (Sci-Fi if
    non-empty) — each a **runtime genre filter over the Asian Cinema film set**
    (films carry TMDB `Genres`, verified). ⚠ The set is ~38 films, so some genre
    shelves will be sparse (drop a shelf under a min-count, e.g. <5). This is a
    **bespoke composed view** (2 director-collection refs + N genre-filtered
    shelves), its own `drillStyle`/view — *not* the generic `.shelves`. No pills.
- *Film School:* flat 52-movie BoxSet (verified) — favorite it; its drill is a flat
  `.grid` of the 52 (its existing route), `rank` + `lens`. (Earlier "contents
  untouched" holds; just needs favoriting to surface.)
- *Critically Acclaimed* (`e09ff623…`): **promote, content as-is** (owner
  decision 2026-06-30). Today it's a single flat BoxSet of films, so the
  promoted card's `drillStyle` is `.grid` (or `.items`) over its members — a `rank`
  slot + `lens` and it's done. **Forward-looking:** the owner intends to add
  subgroupings (Metacritic, AFI lists, Rotten Tomatoes, user scores, …). That
  turns it into a **group** whose children are per-source BoxSets — i.e. the same
  server-group→`.shelves` pattern as Curated/Asian Cinema/Decades (favorited
  parent group + child BoxSets, surfaced by name via `fromSnapshot`). So model the
  promotion to *not* hardcode it as a single terminal grid: when the child source
  BoxSets exist, `drillStyle(for:)` should resolve Critically Acclaimed to
  `.shelves` (one shelf per source), exactly like the §7 Cities pattern. No code
  needed for the subgroups until the server-side child BoxSets are created
  (additive — `bruno-collection-builder`); the card works as a flat grid until
  then and gains the shelves for free once the children land.

*Determinism/INV:* new synthetic top-level categories must mint **stable string
ids** (INV-2) — never an index. Follow the existing `curated-oscars` /
`curated-ebert` id convention.

### Demote: Cultural Touchstones
Never top-level. **Correction (owner 2026-06-30):** it does NOT surface as a
generic Decades shelf or an All-Movies-grid section. Each *specific* decade's
drill leads with a **"Best of the {Decade}"** shelf in the top lane (the
`bruno-sig` shelf built in `yearCategories`, `BrunoBoxSetShelvesView.swift`
~:934-950). Cultural Touchstones occupies **that exact top-shelf lane when the
"All" pill is selected** — the decade-overview state has no single decade, hence
no per-decade best-of, so it leads with Cultural Touchstones instead. One lane,
consistent whether All or a specific decade is focused.

**Implementation.** In the Decades drill, the **"All" branch** of `shownCategories`
(`BrunoBoxSetShelvesView.swift:111-123`) prepends a Cultural Touchstones shelf —
sourced from the `Cultural Touchstones` group members (`670dc402…`) — as its
first/top shelf, structurally mirroring the per-decade "Best of the {Decade}" top
shelf so the lane reads the same in both states. Otherwise unsurfaced: **no `rank`
slot** (never a card), no separate Decades shelf, no All-Movies-grid section.
*INV-2:* stable id (e.g. `decade-all-touchstones`), never an index. *INV-1:* the
prepended shelf keeps the pinned row height.

### New: Cities (data-seeded) — server group CREATED (2026-06-30)
One **Cities** top-level card; each city is a **child BoxSet rendered as a SHELF**
under it — **not** its own card (owner decision). Planned children: Chicago (live),
then New York, San Francisco, Paris, London, Tokyo, Seoul, Hong Kong — added as
more child BoxSets, no code change. The per-city shelves are **eligible as seeds
for the Home + Collections explore generators** (see §8).

**Server — DONE.** The favorited **"Cities"** group
(`id=72b9dd0157755a314917adabcdedced8`) is created and favorited, with the existing
`Chicago Movies` BoxSet (`c443b3c4…`, 23 films) nested as its first child
(`enrich/create_cities_group.py`, additive + reversible). It now shows up among the
favorited groups (10 total), so `fetchGroupBoxSets`
(`BrunoLibrarySnapshot.swift:195-204`) + `fromSnapshot`
(`BrunoCategoryShelves.swift:143-182`) will surface it automatically. *Note:*
`Chicago Movies` is now a child of **both** Genres and Cities (place-based — it
reads as a genre and a city); harmless, flag if de-dup is wanted.

**App — the seams (so it's a shelf-per-city drill, not cards):**
- `rank(for:on:)` (`BrunoCategoryShelves.swift:96-109`) — add a `"cities"` slot, or
  it falls to `.max` (last). Place per the §2 two-row design.
- `drillStyle(for:)` (`:116`) — add `"cities"` → **`.shelves`** so the card drills
  into one shelf per child city (the generic `.shelves` route opens
  `BrunoBoxSetShelvesView`, shelf-per-sub-group) rather than the default `.grid`
  (which would flatten all cities into one poster wall). This is the key line that
  makes cities shelves, not cards.
- `lens(for:)` — add `"cities"` → a label (e.g. "By City").
- **Seed-eligibility (§8):** to let the per-city shelves feed Home/Collections, the
  explore generators (`BrunoHomePlan.explore` / `collectionsTail`) gain a `"cities"`
  source that seeded-picks a city child and renders its members — same shape as the
  existing `"curated"` boxSetShelf path (`BrunoHomePlan.swift:337-346`). Determinism
  (INV-3): seeded over `(seed, snapshot)`, never `Date()`.
- **Adding a city later = pure data:** create + nest a new city BoxSet under the
  Cities group; no code change. Persisting Cities in the producer
  (`Build-Jellyfin-Collections.command` / p6) is a follow-up so a full rebuild
  re-creates it — the additive builder won't delete it in the meantime.

### Everything else under Curated — RESOLVED (fully)
The full Curated list is now in hand (§9). **Critically Acclaimed** → promoted
(above). **Oscar Buzz** (`fb9e649d…`) → **retire** (owner decision 2026-06-30):
it is not promoted and gets no `rank` slot, so once the Curated card is retired
and its children redistributed, Oscar Buzz is simply never referenced and drops
out of the app IA. **No server deletion is performed** — the BoxSet and its films
stay in the library, just unsurfaced; un-nesting/deleting it server-side is
available on request but unnecessary (additive model). Every Curated member is
now accounted for.

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

⚠ **Don't break `rank()`'s other two consumers (red-team finding 5).**
`rank()`/`fromSnapshot` is **shared** by the Collections hub, the Home feed's
**terminal footer**, AND the Home **"Browse the Collection" spine** shelf
(`BrunoCategoryShelves.swift:138-142`), and it also **drops empty groups**. The
two-row, hand-ordered layout is a **Collections-hub-only** presentation concern —
implement it as a row-assignment map *applied at the Collections card row*, layered
**on top of** `fromSnapshot` (which still returns the ranked, empty-dropped list
the other two surfaces depend on). Do **not** replace `rank()` itself, or the Home
footer/spine ordering changes too.

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
**Asset — RESOLVED (§9.5):** **Studio04** is an existing asset
(`/Volumes/Media Server NAS/Collections/Studio04.jpeg`, owner-confirmed). The
live code currently points the grid at a *different* existing asset,
`BrunoStudiosBackdrop`. §3 work = import `Studio04` into the tvOS asset catalog
and point both the tile and the grid at it. The card *tile*
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

**Implementation — owner decision 2026-06-30: the cheap per-shelf offset
heuristic, not a full cross-shelf rebalance** ("not a huge issue, just want some
variation"). ⚠ **Red-team finding 3:** the six shelves are loaded + sorted
**independently inside a per-subgroup loop** in `performLoad`
(`BrunoBoxSetShelvesView.swift:595-605`) — there is **no point where all six sorted
arrays coexist**, so a true cross-shelf lead-slot pass would need a new assembly
step (the earlier `:598-602` / `consolidateOscars` seams are the wrong layer:
one-shelf-at-a-time and category-descriptors-not-films respectively). The cheap
heuristic **avoids that** entirely: give each of the six shelves a **different
seeded rotation offset** so they don't all lead with the same recent year — e.g.
after `reverseChronological`, rotate shelf *i* by `seededOffset(category, seed)`
within its top band (or interleave by award-year bucket), applied right where each
shelf is built (`:600-602`), no cross-shelf coordination needed. Approximate (two
shelves *can* still occasionally collide) but cheap and local. *Determinism
(INV-3):* the offset is seeded from `(category, rowOrderSeed)`
(`BrunoBoxSetShelvesView.swift:431-433`) — **not `Date()`** — so the spread is
stable per launch; keep `reverseChronological`'s stable `id` tie-break so the base
sort stays total. **Data gate — CLEARED
(§9.4):** the Oscar per-item tags `oscar:<CAT>:<won|nom>:<year>`
(`BrunoOscarAward.swift:63-70`) are **already live on the server** (410 movies
tagged). §4 is data-unblocked; `PROJECT_TRACKER.md:38` ("needs apply") is stale
drift to re-sync.

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
same *structure* in its grid view (currently `BrunoBoxSetGridView`, which has no
such section — net-new). Add a `recognizableDirectors` shortlist including the
owner hard-adds **Chazelle, Cameron Crowe, Eggers** (server BoxSets confirmed
present).

⚠ **Layout differs from Studios — do NOT reuse `topStudioLimit = 12` (owner
2026-06-30).** Studios tiles are **landscape**, giving 4 per row → 3 rows of 4
(12). The Directors tiles are **portrait**, so more fit per row; the Household
Names section is **two rows** (not three), at roughly **6–9 tiles per row** (exact
count set by the portrait tile width / column count — match whatever the Directors
A–Z grid uses per row). So the cap is its own constant (`topDirectorLimit` = 2 ×
the portrait columns, ~12–18), not the Studios 12. *Determinism (INV-3):* reuse
the `daySeed` rotation so order varies day-to-day but membership is stable;
*INV-2:* stable ids; *INV-10:* the pinned cells must be structurally stable; *INV-1:*
the portrait row height matches the grid below it.

### John Hughes (display-layer override)
Include Hughes-produced-but-not-directed films (Ferris Bueller, Home Alone) in
his director grid. No server data changed — presentation only.

**Implementation.** This is a display-layer union: his director-grid member list
= (films where Hughes is director) ∪ (a hard-coded override list of library IDs).
The override is app-side, keyed on the specific item IDs. Seam: the Directors
drill-in member resolution (the per-director query that feeds the grid). **Data
gate — RESOLVED + metadata-verified (§9.2):** the override IDs are in hand. ⚠
Correction: **Ferris Bueller's Day Off is directed by Hughes** (already in the
collection) — no override needed for it. **Override set — owner decision
2026-06-30: include the deep cuts too (all eight)**, every one confirmed
`John Hughes (Writer/Producer)` in library metadata: Home Alone `d8ae5f93…`,
Home Alone 2 `2dc62db2…`, Pretty in Pink `13cea2f3…`, Some Kind of Wonderful
`5be2b6f0…`, National Lampoon's Vacation `89ba42db…`, Christmas Vacation
`a488f440…`, **European Vacation `f1512e65…`**, **Maid in Manhattan
`06808ccb…`**. *INV-2:* the merged list must keep stable ids and de-dup if a film
appears in both sets.

### Hero — Directors grid (and Movie Stars grid)
Top-level Directors grid + top-level Movie Stars grid each need a cinematic hero
banner (craft-of-filmmaking imagery).

**Implementation — owner decision 2026-06-30: STATIC brand art** (not a live
movie pick). Both grids route to `BrunoBoxSetGridView`, which has no hero today
(net-new). Copy the **bespoke brand-art band** (Studios `:105-115` / Rewatchables
`BrunoRewatchablesView.swift:96,138`) — a fixed `Image` over the grid — **not** the
`BrunoHeroView` movie-backdrop band. Because it's a fixed image, this **avoids both
the INV-6 scroll-blur exception creep (red-team finding 6) and the hero
anti-repetition work entirely** — there's no movie pick to rotate or de-dup. Same
treatment for Box Sets (§7). See §7 for the shared work item.

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

⚠ **Anti-repetition — block recent heroes for ≥5 launches (owner 2026-06-30).**
The seeded pick has been visibly repetitive — the same face keeps returning. The
hero picker must **exclude any movie shown as a hero in the last 5 days/launches**
from the candidate pool *before* the seeded pick. Implementation: persist a small
**recents ring buffer** of recent hero item-ids (per surface) in the app's
lightweight store (`UserDefaults`/`StoredValue`); on each pick, subtract the
recents from the candidate pool, seed-pick from the remainder, then push the
chosen id (cap 5, FIFO). Edge case: if a decade's strong-candidate pool is ≤5, fall
back to **least-recently-shown** rather than emptying the pool (never show nothing).

⚠ **Determinism — the recents buffer must NOT leak into `BrunoHomePlan.build`'s
purity (red-team finding 4).** The decade hero lives in `BrunoBoxSetShelvesView`,
*outside* `build(seed:snapshot:now:)`, so its pick = pure fn of `(seed, decade,
recentsSet)` is fine — `selfCheckPassed()` never sees it. **But** if the **Home**
movie hero is seeded *inside* `build` (which `selfCheckPassed()` asserts pure over
`seed`+`snapshot`+`now`), a mutating persisted recents buffer read in `build` would
make two calls differ and **fire the DEBUG assert**. So for any movie hero inside
`build`, the recents set must be threaded as an **explicit `build` parameter** (like
`now`) and **pinned in the self-check fixture** — never read ambiently. **Scope
(owner decision 2026-06-30):** the Directors/Movie Stars/Box Sets grid heroes are
**static brand art** (§5/§7) → no anti-repetition there. This rule applies only to
the **Decades** hero (outside `build`, simple) and any **Home** movie hero (inside
`build` → thread recents explicitly).

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
art band (fixed `Image` over a flat grid). **Owner decision 2026-06-30: these grid
heroes (Directors, Movie Stars, Box Sets) are STATIC brand art** — a fixed
atmospheric image per grid, **no live movie pick.** This deliberately keeps them
*out* of the INV-6 scroll-blur exception (a fixed image isn't scroll-coupled, so it
doesn't extend the Studios one-off — red-team finding 6 resolved) and means **no
anti-repetition** is needed here. *INV-1:* fixed grid row height below the hero;
*INV-8:* top-down reveal preserved. Only **Decades** keeps a reactive movie hero
(§6), and only it (+ any Home movie hero) carries the §6 anti-repetition rule.

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

## 9. Data Needs — RESOLVED against the live server (2026-06-30)

All five were cleared by querying the live Jellyfin server
(`http://192.168.50.19:8899`, creds in `MovieCollection/enrich/_config.py`) and
the NAS. **Four are fully resolved; three carry a narrow owner decision** (marked
⚠ — see §9a). Nothing below is an assumption — every ID/count came from the
server or library metadata.

**1. Curated member list — RESOLVED (13 members).** The "Curated" group
(`id=e10ffc104536930edc95f7321f4a3b74`) contains:

| Member (BoxSet) | id | IA disposition |
|---|---|---|
| Ebert Thumbs Up | `f1cc8bd59a4fd6fe32b5078815bfe91a` | → **Roger** (promote) |
| Ebert Thumbs Down | `ac158140fd2a90700a0288db828699e5` | → **Roger** (promote) |
| Oscar — Best Picture | `7a2ec4edd2960dcfbc7149b87581fcdd` | → **Oscar** (promote, consolidated) |
| Oscar — Directing | `98eb385f8acf6fad96fe417ea9b28e89` | → **Oscar** |
| Oscar — Acting | `be41c882dd2ba3dac0558b134f0ce43a` | → **Oscar** |
| Oscar — Cinematography | `2b3c9dc0d056be0652a87dea4807dc13` | → **Oscar** |
| Oscar — Score | `2b379a6dcd68cc78f96ab1af4f36f192` | → **Oscar** |
| Oscar — Screenplay | `e8e1d1d22294a46a6d77f6234b8dd795` | → **Oscar** |
| Asian Cinema | `f96882e8e7abb871c5365782fac56f2a` | → **Asian Cinema** (promote) |
| Film School Classics | `61b1fa77b4301a40d970f1e40cb9a34c` | → **Film School** (promote) |
| Cultural Touchstones | `670dc4025fb9dc6e671e38bad4a92861` | → **demote** (§1) |
| Critically Acclaimed | `e09ff623404dc3392e0c950b85af0c55` | → **promote** (content as-is; subgroupings later) |
| Oscar Buzz | `fb9e649d842803f8bab9446a8fd6e7d9` | → **retire** (unsurfaced; no server delete) |

Every Curated member is now dispositioned (owner decisions 2026-06-30): Critically
Acclaimed promoted, Oscar Buzz retired. (Note: server name is **"Film School
Classics"**, not "Film School"; the owner's "Roger" = the two Ebert Thumbs
Up/Down BoxSets.)

**2. John Hughes film IDs — RESOLVED + metadata-verified.** The "John Hughes"
director BoxSet (`id=7583e70920907af155e4065044f61c1d`) currently holds **6
directed films**: Sixteen Candles, The Breakfast Club, Weird Science, Ferris
Bueller's Day Off, Planes Trains and Automobiles, Uncle Buck. ⚠ **Ferris
Bueller's Day Off is already in — Hughes *directed* it** (library metadata:
`John Hughes (Director)`); the owner's premise that Hughes "didn't direct" it is
mistaken, so it needs no override. The produced/written-not-directed films, each
confirmed in library metadata as `John Hughes (Writer/Producer)` with the real
director, all present in the library:

| Film (year) | library id | real director | Hughes credit |
|---|---|---|---|
| Home Alone (1990) | `d8ae5f935be639f3b6670648397d088d` | Chris Columbus | Writer + Producer |
| Home Alone 2 (1992) | `2dc62db2083706afccb0e02493309cde` | Chris Columbus | Writer + Producer |
| Pretty in Pink (1986) | `13cea2f35f525423b506543240421785` | Howard Deutch | Writer + Producer |
| Some Kind of Wonderful (1987) | `5be2b6f08e78559f6c66e2d5ea5444d9` | Howard Deutch | Writer + Producer |
| National Lampoon's Vacation (1983) | `89ba42db2ad4c74827311587660c88a7` | Harold Ramis | Writer |
| National Lampoon's Christmas Vacation (1989) | `a488f44051d82c1a98d883b2f7fe0f39` | Jeremiah Chechik | Writer + Producer |
| *European Vacation (1985)* | `f1512e6582d0e123a25a6eda86ef29e3` | Amy Heckerling | Writer *(deep cut)* |
| *Maid in Manhattan (2002)* | `06808ccb4f4b4ffb8fd135d344fb2cfa` | Wayne Wang | Writer (story) *(deep cut)* |

Override set — **owner decision 2026-06-30: all eight** (the canonical six **plus**
European Vacation + Maid in Manhattan). The 2015 *Vacation* reboot is **not**
Hughes — excluded. These IDs feed the §5 display-layer union.

**3. Cities server group — CREATED + favorited; app seam IMPLEMENTED (2026-06-30).**
The favorited **"Cities"** group (`id=72b9dd0157755a314917adabcdedced8`) exists with
the existing `Chicago Movies` BoxSet (`c443b3c4…`, 23 films) nested as its first
child (`enrich/create_cities_group.py`) — now the 10th favorited group, surfaced
automatically. **App seam landed:** `rank` (`"cities": 10`, provisional — §2
finalizes placement), `drillStyle("cities") → .shelves`, `lens("cities") → "On
Location"` in `BrunoCategoryShelves.swift`. Verified the generic `.shelves` route
(`brunoRouteToShowAll`, `BrunoCategoryCardRow.swift:84`) opens
`BrunoBoxSetShelvesView` with neither `isDecades` nor `isCurated`, so
`shownCategories` returns one shelf per child city — **shelf-per-city, no pills, no
Oscar/Ebert consolidation** — exactly the intended structure. Seed-eligibility for
Home/Collections generators remains the follow-up (§1 → New: Cities, §8).

**4. Oscar tags applied — RESOLVED, already live.** The live server already has
**410 movies** tagged `oscar:<CAT>:<won|nom>:<YEAR>` (plus 679 with `ebert-*`,
213 with `rewatchables*`), e.g. *Collateral* → `oscar:ACTING:nom:2004`. §4
year-dedup is **data-unblocked now.** ⚠ Drift: `PROJECT_TRACKER.md:38` still says
the Oscar tags "need owner `Apply-Enrich-Tags.command apply`" — that's stale;
they're applied. Owner should re-sync the tracker line.

**5. Studio04 — RESOLVED, existing asset.** `Studio04.jpeg` exists in the NAS
(`/Volumes/Media Server NAS/Collections/Studio04.jpeg`) and the owner confirmed
it's existing. The code today uses a *different* existing asset,
`Image("BrunoStudiosBackdrop")` (`BrunoStudiosGridView.swift:52`). §3 work =
import `Studio04` into the tvOS asset catalog and point **both** the Studios card
tile and the grid backdrop at it (replacing `BrunoStudiosBackdrop` for this
surface). No data gate remains — purely an asset-catalog + code change.

### 9a. Owner decisions — ALL RESOLVED (2026-06-30)

No open data/disposition decisions remain. Resolved: Critically Acclaimed →
promote · Oscar Buzz → retire · Cities group → created + app seam landed
(shelf-per-city) · Hughes override → all eight (incl. both deep cuts) · Studio04 →
existing asset · Oscar tags → live · Curated list → fully dispositioned. The
remaining work is implementation + the §2 two-row design call.

---

## 10. Open Bug (low priority, not blocking)

**Shelf-vanish:** in Movies, all shelves briefly disappeared mid-scroll (~3–4
shelves deep), then returned on navigation. First confirmed occurrence. Likely
related to the cap-and-grow reveal window (INV-8, `visibleShelfCount`
`BrunoCategoryShelves.swift:303,379-401`) or the `dataPrefix`-must-track-reveal
trap noted in prior shelf-depth work. Not blocking IA work; log if it recurs.

---

## Sequencing recommendation (lowest-risk → highest)

1. **Done:** Cities group + app seam (`.shelves`), em-dash rename + app tolerance.
2. **Low-risk, ready:** §3 Studio04 backdrop pin, §5 household-names list + John
   Hughes override (8 IDs in hand), §5/§7 **static brand-art** grid heroes (no
   INV-6/anti-rep), §4 Oscar **cheap offset heuristic** — all reuse existing
   patterns, no data gate.
3. **Coordinated server+app migration (§1):** favorite the promotes + create
   "Oscars"/"Roger" parent groups + un-favorite Curated + land the rank/drillStyle/
   lens seams, as **one step** (avoid transitional double-surfacing). Asian Cinema's
   bespoke composed view (director collections + genre shelves) rides here.
4. **Highest-risk (perf + focus):** §6 reactive Decades hero (reintroduces the
   backdrop-reload cost the code deliberately avoided, + the anti-repetition buffer)
   and the §6 double-tap-down pill nav (focus-engine state machine, INV-7/10,
   on-device verification required). Build last, behind the shared-idiom refactor.
5. **Decision-gated:** §2 two-row layout (design call) and §8 Curated-Explore
   retarget (blocked on §1 shape).

---

## Red-team log (2026-06-30) — findings + resolutions

Adversarial pass over the plan, verified against live code/server. All six woven
into the sections above; logged here for traceability.

1. **Promotion needs favoriting, not just a `rank` slot** (HIGH). `fromSnapshot`
   builds only from favorited groups; the promotes are Curated *children*. → §1:
   make them real favorited groups (singles favorited; "Oscars"/"Roger" parent
   groups created), coordinated with Curated retirement + app seams.
2. **Asian Cinema is a flat 38-movie BoxSet, not sub-BoxSets** (HIGH) — generic
   `.shelves` can't iterate it. → §1: owner decision — compose from existing data
   (Wong Kar-Wai `824f5063…` + Bong Joon Ho `01fd8535…` director collections +
   runtime genre-filtered shelves), no new BoxSets; bespoke view.
3. **Oscar dedup seam doesn't exist where cited** (MED) — six shelves sorted
   independently in a loop, never co-located. → §4: owner picked the cheap
   per-shelf seeded-offset heuristic (local, no cross-shelf pass).
4. **Anti-repetition recents buffer vs `BrunoHomePlan.build` purity** (MED) — a
   mutating buffer read in `build` breaks `selfCheckPassed()`. → §6: thread recents
   as an explicit `build` param for any Home movie hero; Decades hero is outside
   `build` (fine). Grid heroes are static (no buffer at all).
5. **Two-row layout must not replace `rank()`** (MED) — `rank()`/`fromSnapshot`
   also feeds the Home footer + spine and drops empties. → §2: row-assignment map
   layered on top of `fromSnapshot`, not a `rank()` rewrite.
6. **INV-6 exception creep on grid heroes** (LOW-MED). → §5/§7: owner chose static
   brand art for Directors/Movie Stars/Box Sets heroes → no new scroll-blur
   surfaces, exception stays the Studios one-off.

**Net effect of the owner decisions:** the riskiest items got *cheaper*, not
harder — static grid heroes (no INV-6/anti-rep), cheap Oscar heuristic, data-only
promotion via favorited groups, and Asian Cinema reusing existing collections +
genre tags instead of new server data.
