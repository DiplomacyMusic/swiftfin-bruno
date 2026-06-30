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
after that, new cities are pure data. *Content already exists* (§9.3): the
`Chicago Movies` BoxSet (`c443b3c4…`, 23 films) is live but unfavorited and
ungrouped — the same one the Movies genre buckets reference as `"chicago movies"`
(`BrunoGenresView.swift:44,51,57,…`). **The only missing piece is the favorited
"Cities" parent group** with Chicago Movies as its first child (mirrors
Decades/Directors). Ready to create on owner confirmation (§9a.3).

### Everything else under Curated — RESOLVED to two members
The full Curated list is now in hand (§9): the only members not in the owner's
plan are **Critically Acclaimed** (`e09ff623…`) and **Oscar Buzz**
(`fb9e649d…`). Owner disposal decision pending (§9a.1) — fold Oscar Buzz into the
promoted Oscar card, or retire both.

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
`id` final tie-break so the sort stays total (INV-3-safe). **Data gate — CLEARED
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
gate — RESOLVED + metadata-verified (§9.2):** the override IDs are in hand. ⚠
Correction: **Ferris Bueller's Day Off is directed by Hughes** (already in the
collection) — no override needed for it. Recommended override set (canonical six,
all confirmed `John Hughes (Writer/Producer)` in library metadata): Home Alone
`d8ae5f93…`, Home Alone 2 `2dc62db2…`, Pretty in Pink `13cea2f3…`, Some Kind of
Wonderful `5be2b6f0…`, National Lampoon's Vacation `89ba42db…`, Christmas
Vacation `a488f440…`. *INV-2:* the merged list must keep stable ids and de-dup if
a film appears in both sets.

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
| Critically Acclaimed | `e09ff623404dc3392e0c950b85af0c55` | ⚠ **not in plan — disposal** |
| Oscar Buzz | `fb9e649d842803f8bab9446a8fd6e7d9` | ⚠ **not in plan — disposal** |

So "everything else under Curated" = exactly **Critically Acclaimed** + **Oscar
Buzz**. (Note: server name is **"Film School Classics"**, not "Film School"; the
owner's "Roger" = the two Ebert Thumbs Up/Down BoxSets.)

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

Recommended override set = the **first six** (canonical "John Hughes movies").
European Vacation + Maid in Manhattan are real Hughes writing credits but feel
off-brand for the grid — ⚠ owner picks whether to include them. (The 2015
*Vacation* reboot is **not** Hughes — excluded.) These IDs feed the §5
display-layer union.

**3. Cities server group — content exists, wrapper missing.** No favorited
"Cities" group exists (the 9 favorited groups are New Releases, Directors,
Decades, Genres, Studios, Curated, Seasonal, Movie Stars, Rewatchables). **But a
`Chicago Movies` BoxSet already exists** (`id=c443b3c45f21b44f1c7f53d641cadb81`,
**23 films**) — unfavorited, one of the 459 total BoxSets, and the same one the
Movies genre buckets already reference as `"chicago movies"`
(`BrunoGenresView.swift:44…`). So the *content* is ready; the only missing piece
is a **favorited "Cities" parent group with Chicago Movies as a child** — the
exact structural shape of Decades (8 children) / Directors (138). ⚠ This is a
live-server mutation (create + favorite a group BoxSet via
`MovieCollection/Build-Jellyfin-Collections.command`), so it needs the owner's
go-ahead — I can execute it on confirmation (see §9a).

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

### 9a. Remaining owner decisions (narrow — not data lookups)

1. **Curated leftovers** — dispose / fold / promote **Critically Acclaimed** and
   **Oscar Buzz**? (Oscar Buzz could fold into the promoted Oscar card; Critically
   Acclaimed overlaps Ebert + Cultural Touchstones.)
2. **Hughes deep cuts** — include *European Vacation* + *Maid in Manhattan* in the
   override, or just the canonical six?
3. **Cities group creation** — confirm and I'll create + favorite a "Cities" group
   with **Chicago Movies** as its first child (additive, mirrors Decades/Directors);
   or you create it. Also confirm Chicago Movies (23 films) is the intended seed
   vs a hand-curated Chicago list.

---

## 10. Open Bug (low priority, not blocking)

**Shelf-vanish:** in Movies, all shelves briefly disappeared mid-scroll (~3–4
shelves deep), then returned on navigation. First confirmed occurrence. Likely
related to the cap-and-grow reveal window (INV-8, `visibleShelfCount`
`BrunoCategoryShelves.swift:303,379-401`) or the `dataPrefix`-must-track-reveal
trap noted in prior shelf-depth work. Not blocking IA work; log if it recurs.

---

## Sequencing recommendation (lowest-risk → highest)

1. **Unblocked now (data resolved §9):** §1 promotions (rank slots) + retire
   Curated, §3 Studio04 backdrop pin, §5 household-names list + John Hughes
   override (IDs in hand), §4 Oscar year-dedup (tags live), §7 static drill-down
   heroes — all reuse existing patterns with low determinism risk and have **no
   remaining data gate.**
2. **One-confirmation-away:** §1 Cities card — needs the favorited "Cities" group
   created (one command, §9a.3); content (Chicago Movies, 23 films) already exists.
3. **Highest-risk (perf + focus):** §6 reactive Decades hero (reintroduces the
   backdrop-reload cost the code deliberately avoided) and the §6 double-tap-down
   pill nav (focus-engine state machine, INV-7/10, on-device verification
   required). Build these last, behind the shared-idiom refactor, and verify on a
   real device.
4. **Decision-gated:** §2 two-row layout (design call) and §8 Curated-Explore
   retarget (blocked on §1 shape).
