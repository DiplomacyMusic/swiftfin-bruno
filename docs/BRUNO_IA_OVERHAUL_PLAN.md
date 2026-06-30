# Bruno IA Overhaul — Plan + Code/Architecture Guidance

**Status:** mostly SHIPPED, 2026-06-30. Most of §1–5, §7, §8 landed on `main`
(app PRs #73 + #74 merged; #75 open) plus two server-side migrations. The
remaining work — §6 (reactive Decades hero + double-tap pill nav), Asian Cinema
composed shelves, the Cultural Touchstones lane, Cities seed-eligibility, art
assets, and on-device verification — is **not built** (see *Deferred / open*
below). This doc is now a RECORD: each section keeps the original plan + adds a
**DONE** / **DEFERRED** marker with commit/PR, and **corrects the
Implementation framings the build proved wrong** (the plan guessed several seams
incorrectly — those corrections are inline and flagged ⛔ **FRAMING CORRECTED**).

**Header branch citation superseded.** The original citations were verified
against branch `claude/vigilant-albattani-40f55e` (commit `6ec18cab`). That is
**superseded by this push** (branch `claude/cranky-grothendieck-84b30d`,
commits `e2235ed3` · `ba45d41f` · `ce925ac1` · `6f152722` · `24ef9c46` ·
`a6cd169b`; PRs #73/#74 merged, #75 open) — trust the inline DONE/CORRECTED
markers and `docs/CHANGELOG.md` (2026-06-30) over the original framings where
they disagree. Focus-engine guidance still from `swift-xcode-expert` (tvOS focus
engine, WWDC23 session 10162).

**How to read this:** each section restates the owner intent (unchanged), then
the original **Implementation** block, then a DONE/DEFERRED/CORRECTED marker.
The pipeline is unchanged: `BrunoHomePlan` → `BrunoHomeViewModel` →
`BrunoShelfView` / `BrunoCategoryShelves`, "show all" via `brunoRouteToShowAll`.

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

> **✅ DONE (migration landed) — SERVER `654b7d0` + APP `6f152722` (PR#74) + hotfix `24ef9c46` (PR#75).**
> The coordinated server+app migration shipped.
> - **SERVER (`MovieCollection/enrich/migrate_curated_retire.py`, `654b7d0`, LIVE):**
>   Curated un-favorited; **"Oscars"** (`547afd1e…`) + **"Roger Ebert"** (`5ccea933…`)
>   parent groups created + favorited over the existing Oscar×6 / Ebert×2 children;
>   **Asian Cinema** / **Film School Classics** / **Critically Acclaimed** favorited
>   directly. Net: **14 favorited groups**.
> - **APP (`6f152722`):** `rank` / `drillStyle` / `lens` entries for the 5 new groups
>   (`BrunoCategoryShelves.swift` — see `:103-145`); new accessor
>   `BrunoLibrarySnapshot.promotedCuratedBoxSets` (`:106-109`); the 4 `curatedBoxSets`
>   consumers repointed; `BrunoRecommendedShelf` hub-drop reorder; Ebert toggle
>   id→name repoint.
> - **§8 generator** RETARGETED to `promotedCuratedBoxSets` (rode in `6f152722`,
>   `BrunoHomePlan.swift:342,625`) — see §8 (NOT an "open design call" anymore).
> - **Hotfix `24ef9c46` (PR#75):** §1 regressed Roger Ebert / Oscars card art;
>   restored (roger ebert→Curated02, oscars→Curated01) in `BrunoCollectionArtwork.swift`.
>
> ⛔ **FRAMING CORRECTED (the plan's audit guessed several seams wrong):**
> 1. **Gold-tile "Oscars" show-all (audit §"Show all" #1, `:533`):** the audit said
>    repoint `id == "curated-oscars"` → `name == "oscars"` to keep the six gold tiles.
>    **WRONG.** That gold-tile gate lives in `BrunoCategoryShelves.shelf(for:)` which
>    iterates the SHELVES (`categories`), but `consolidateOscars` only ever fed
>    `cardRowCategories` (the card ROW) — so the gate is **effectively unreachable from
>    the real drill**. With the real favorited **"Oscars"** group, the `.shelves` drill
>    naturally fans out to the SIX captioned reverse-chron shelves (carrying the §4
>    lead-spread), **not** a gold-tile card row. The gold-tile "preservation" as framed
>    does not apply. ⚠ **OPEN on-device design call:** keep the natural 6-shelf drill
>    (current behavior) vs. rebuild the gold tiles. The `:533` `curated-oscars` gate was
>    left in place (now dead — see #3 below).
> 2. **Ebert toggle (audit #2, `:103`):** the `curated-ebert` id → `name == "roger
>    ebert"` repoint in `brunoRouteToShowAll` **worked cleanly** — the group's 2 children
>    resolve up/down (`BrunoCategoryCardRow.swift:103-106`). Correct as audited.
> 3. **Recommended hub-drop (nav audit) needed an EXTRA nuance the plan missed:** Asian
>    Cinema / Film School / Critically Acclaimed are now favorited groups that are
>    **FILM-bearing**, so they hit the `favoriteGroupBoxSets` hub-drop and would be
>    dropped. Fixed by moving the curated-resolution block **ABOVE** the hub-drop
>    (mirrors Rewatchables — `BrunoRecommendedShelf.swift:70-86`). The Oscars / Roger
>    Ebert PARENT hubs still drop (they're not in `promotedCuratedBoxSets`, only their
>    children are).
> 4. **Anti-scatter ("DELETE consolidateOscars/consolidateEbert/cardRowCategories") —
>    NOT done.** They were **left in place** (now unreachable — no Curated drill exists
>    to reach them). Additionally the migration **ORPHANED** `curatedRandomShelves` (the
>    PR#71 random Rewatchables/Oscar/Ebert×genre feature, `BrunoBoxSetShelvesView.swift`)
>    and the `parent == "curated"` block (`BrunoHomePlan.swift:337`) — the plan did not
>    anticipate this. **OPEN owner call:** delete vs. re-home the dead
>    `consolidate*` / `curatedRandomShelves` / `parent=="curated"` code.
>
> **DEFERRED within §1:** Asian Cinema composed shelves (R1 below — NOT built; it's a
> flat `.grid` of 38 films today); demote Cultural Touchstones (the Decades "All"-lane
> prepend — NOT built; Touchstones retired with Curated but the best-of-lane feature
> wasn't added); Cities seed-eligibility (§8 cities source — NOT built); art assets for
> the 3 flat promotes (gradient until added).

### Remove: Curated
The Curated tile is the group named "Curated", surfaced because it's a favorited
group BoxSet (`snapshot.curatedBoxSets`, `BrunoLibrarySnapshot.swift:99-101`).

**Implementation.** "Retiring" the card is two moves: (a) **un-favorite the Curated
group** server-side (it drops out of `favoriteGroupBoxSets` → `fromSnapshot` stops
building its card on all three surfaces) — drop/re-rank in `rank(for:on:)`
(`BrunoCategoryShelves.swift:96-109`) is the belt-and-suspenders app side; and
(b) redistribute its children (below). **Resolved (owner 2026-06-30):** the
promoted children become **their own favorited groups** (data-only), not app-side
synthetic promotion — see the Promote section. ⚠ Un-favoriting Curated empties
`snapshot.curatedBoxSets`, which several routes key off — do it **only** as part of
the coordinated §1 migration with the `curatedBoxSets` repoints (Nav-pathway safety
audit + Show-all audit), or Home/Recommended/show-all destinations regress.

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
  existing BoxSets (reuse the `enrich/create_cities_group.py` mechanic verbatim):
  **"Oscars"** parent over the six `Oscar *` BoxSets, **"Roger Ebert"** parent over
  the two `Ebert Thumbs Up/Down` BoxSets — same shape as Cities (parent + child
  BoxSets, generic `.shelves` drill). ⚠ **Name it "Roger Ebert", not "Roger"** — a
  director collection "Roger Donaldson" exists (verified); a bare "Roger" group is
  ambiguous. (Card *label* can still read "Roger" via `lens`/display.)
- ⚠ **Anti-scatter — DELETE the app-side consolidation once the server groups exist
  (efficiency pass).** Real "Oscars"/"Roger Ebert" parent groups make
  `consolidateOscars` + `consolidateEbert` + the `cardRowCategories` split
  (`BrunoBoxSetShelvesView.swift:128-167`) **dead code** — the collapse is now
  data-driven. Remove them with this migration; do **not** keep both the server
  groups and the app-side synthetic collapse (that's exactly the scatter to avoid).
- **Coordinate with retiring Curated** so there's no transitional double-surfacing
  (a promoted child showing as both a Curated shelf and a top-level card). Do the
  favoriting + the Curated un-favorite + the app seams (+ the dead-code removal) as
  **one migration**, not piecemeal — favoriting alone (before the seams) renders
  them with default `.grid` + `.max` rank + no lens (degraded). Server migration is
  scriptable now; gate it on the app seams being ready.

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
    non-empty) — each a runtime genre filter over the Asian Cinema film set
    (films carry TMDB `Genres`, verified). ⚠ The set is ~38 films, so some genre
    shelves will be sparse (drop a shelf under a min-count, e.g. <5).
  - **REUSE, not bespoke (efficiency pass 2026-06-30): no new view, no new
    `drillStyle` machinery.** All three shelf kinds are just **synthetic
    `BrunoCollectionCategory`s** (label-only stub `boxSet` + a `children` film
    list) fed into the **existing generic `.shelves` drill** (`BrunoBoxSetShelvesView`)
    — the exact pattern `curatedRandomShelves` (`:695-827`), `consolidateOscars`
    (`:144`), and the per-year decade shelves (`:617`) already use. So: a small
    **`asianCinemaShelves` builder** that returns `[WKW category, Bong category,
    Action category, …]` and hands them to `BrunoBoxSetShelvesView` as `subGroups`.
    The WKW/Bong categories wrap the existing director BoxSets' children; the genre
    categories **reuse `BrunoCoreGenre.matches`** (`BrunoGenresView.swift:236`) /
    the films' `.genres` for the filter — don't hand-roll genre logic. Net-new code
    ≈ one builder function, **zero new view/drillStyle**. No pills.
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

> **✅ DONE (mechanism) — `a6cd169b` (PR#75, open).** `BrunoCategoryCardRow` gains a
> `twoRow` flag (default false) gated on `isTabRoot` (Collections hub only, so the
> shared `rank()`/`fromSnapshot` other consumers — Home footer/spine — are untouched,
> exactly per finding 5). Two `CollectionHStack` rows split by a `row1Names` set, each
> wrapped in `.focusSection()` (`BrunoCategoryCardRow.swift:30-79`;
> `BrunoCategoryShelves.swift:389` passes `twoRow: isTabRoot`).
> ⚠ **OPEN owner tweak:** the final row membership (`row1Names`) is a design call —
> adjust the set to taste.

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

> **✅ DONE — `ba45d41f` (PR#73, merged).** `BrunoStudiosGridView.swift:52` repoints
> the grid backdrop `BrunoStudiosBackdrop` → `Studio04`; the studios TILE art
> (`BrunoCollectionArtwork.swift`) pinned to `["Studio04"]` (same lock pattern as the
> Coppola/Ebert tiles).
>
> ⛔ **FRAMING CORRECTED.** The Implementation block below (and §9.5) said (a) the
> Studios **tile** is "a code-drawn gradient" that must "switch from gradient to the
> same Image asset," and (b) §3 needs to "import Studio04 into the tvOS asset catalog."
> **BOTH STALE.** (a) The tile already used **bundled art** (cycled Studio01–05), not a
> gradient — so it was a 1-line PIN, not a gradient→image switch. (b) `Studio04.imageset`
> **already existed** in `Assets.xcassets/BrunoCollections` (byte-identical to the NAS
> file) — **no import was needed.** Actual work = a 1-line tile pin + 1-line grid
> repoint. `BrunoStudiosBackdrop.imageset` is now unreferenced but left in the catalog
> (the "dropped imagesets stay" convention).

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

> **✅ DONE — `e2235ed3` (PR#73, merged).** `BrunoOscar.spreadLeads(_:category:seed:)`
> (`Shared/Objects/Bruno/BrunoOscarAward.swift`): after `reverseChronological`, rotates
> only the top lead band (≈6) of each of the six Oscar category shelves by a per-category
> seeded offset, so one recent award year no longer dominates the lead slot of all six.
> Offset is a pure fn of `(category, rowOrderSeed)` — no `Date()`; seed captured once per
> load like `shuffleSeed` (INV-3 safe). Wired in `BrunoBoxSetShelvesView.swift` (seed
> capture ~:559, oscarCategory branch ~:600). The owner's cheap per-shelf heuristic, as
> planned — no cross-shelf rebalance. (Carries through into the natural 6-shelf "Oscars"
> drill per §1 correction #1.)

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

> **✅ DONE — `ce925ac1` (PR#73, merged).** Directors get a pinned marquee shortlist
> (`BrunoBoxSetGridView.recognizableDirectors`, incl. Chazelle / Cameron Crowe / Eggers)
> above the A–Z grid — same daily-rotated, stable-membership pattern as Studios
> `topStudios` (INV-2/10 respected).

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

> **✅ DONE — SERVER-SIDE, `MovieCollection/enrich/create_hughes_override.py`
> (MovieCollection repo `50e4177`, owner-authorized, additive/idempotent/reversible,
> LIVE-applied). NOT an app commit.** The 8 written/produced-not-directed films were
> nested under the existing "John Hughes" director BoxSet (`7583e7…`), now **14
> children** (6 directed + 8).
>
> ⛔ **FRAMING CORRECTED.** The Implementation below framed this as a **display-layer
> override** ("no server data changed / presentation only") implemented in "the
> per-director query that feeds the grid." **That seam DOES NOT EXIST.** Director tiles
> route to the **stock upstream `ItemView`**; a director's films are resolved
> **server-side as the BoxSet's children** — there is no app-side per-director query to
> union into. Correct framing: solved **DATA-side** by nesting the films under the
> BoxSet (owner authorized the collection builder). **No app code.**

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

> **✅ DONE — `ce925ac1` (PR#73, merged). See §7 for the shared work item + the
> ⛔ framing correction** (the "add the band once to `BrunoBoxSetGridView`" framing was
> under-scoped — it required a `CollectionVGrid`→`ScrollView`+`LazyVGrid` conversion).

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

> **⬜ NOT STARTED — the highest-risk tier (perf + focus engine), deferred whole.**
> Neither the reactive per-decade hero nor the double-tap-down two-state pill nav is
> built. The Implementation guidance below stands as the build brief for a future
> session. On-device verification is mandatory for this section.

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

> **✅ DONE — `ce925ac1` (PR#73, merged).** New shared
> `BrunoBrandHeroBand.swift` (extracted from `BrunoStudiosGridView`'s body: full-bleed
> backdrop + tall title header + descending blur) — ONE band, not a copy per grid.
> `BrunoBoxSetGridView` gains a `heroAsset: String?` path wired for Directors / Movie
> Stars / Box Sets at the Collections card row + Home auteurs show-all
> (`BrunoHomeShowAll`). Hero stand-in art = each category's card art via new
> `BrunoCollectionArtwork.heroAsset(for:)` (`:72`) (owner: "use card title/BGs as
> stand-in", swap for bespoke later).
>
> ⛔ **FRAMING CORRECTED — "add the band once to `BrunoBoxSetGridView`" was
> UNDER-FRAMED.** `BrunoBoxSetGridView` is a **recycling UIKit `CollectionVGrid`** with
> **no scroll/stack wrapper** — unlike the Studios `LazyVGrid`-in-`ScrollView` template
> the band came from. Dropping the band on it was **not** a trivial add: it required a
> `CollectionVGrid` → `ScrollView` + `LazyVGrid` **conversion** (owner approved losing
> recycling on these bounded Collections grids). Implemented as a `heroAsset` path that
> **only** converts when a hero is requested (`BrunoBoxSetGridView.swift:79-104`); the
> New Releases / Oscar grids keep the recycling `CollectionVGrid` untouched, sharing
> `cell(for:)` so both draw identical tiles.
>
> ⚠ **DEFERRED follow-up:** fold Studios + Rewatchables onto the shared band (they still
> carry their own copies); on-device focus-feel pass (sim focus timing differs).

⚠ **DECADES hero stays REACTIVE (§6) — NOT started.** Directors / Movie Stars / Box
Sets got the static brand band above; the reactive per-decade Decades hero (highest-risk
tier) is not built.

**Implementation. Owner decision 2026-06-30: STATIC brand art** — a fixed
atmospheric image per grid, no live movie pick. This keeps them *out* of the INV-6
scroll-blur exception (a fixed image isn't scroll-coupled — red-team finding 6
resolved) and needs **no anti-repetition**. *INV-1:* fixed grid row height below
the hero; *INV-8:* top-down reveal preserved. Only **Decades** keeps a reactive
movie hero (§6), carrying the §6 anti-repetition rule.

⚠ **REUSE — extract ONE shared band, don't add three more copies (efficiency
pass).** Studios (`BrunoStudiosGridView.swift:47-115`) and Rewatchables
(`BrunoRewatchablesView.swift:92-140`) each already hand-roll their **own** brand
band (`GeometryReader` + `Image(asset)` + title `header`) — that's **two bespoke
copies already**. Directors / Movie Stars / Box Sets all route to the **single**
`BrunoBoxSetGridView`, so the right move is **one** reusable
`BrunoBrandHeroBand(asset:title:)` component added **once** to `BrunoBoxSetGridView`
(covers all three grids in one place), parameterized by asset + title. Ideally
refactor Studios + Rewatchables onto it too; at minimum **do not copy-paste a third,
fourth, fifth band** — that's the scatter to avoid. One component, five call sites.

---

## 8. Curated Explore Generator (Home Feed) — retarget or retire

> **✅ DONE — RETARGETED (rode in `6f152722`, PR#74).** No longer an "open design
> call" — the retarget recommendation was taken. Both the explore generator
> (`BrunoHomePlan.explore` `"curated"`/`"world"`, `:342`) and the Collections
> procedural tail ×6 family (`:625`) now draw from
> `snapshot.promotedCuratedBoxSets` (the union of the promoted groups' children)
> instead of the emptied `snapshot.curatedBoxSets`. The Ebert/Oscar caption branch
> survives the regrouping (name-resolved). INV-3 seeded-purity intact.
>
> ⚠ **DEFERRED:** the **Cities** seed-eligibility source (a `"cities"` generator
> source) is NOT built — see §1 *New: Cities* / §8 follow-up.

The Home feed generator draws from the Curated server group; once Curated is
retired its data source changes.

**Implementation.** The generator is `BrunoHomePlan.explore(key:)` cases
`"curated"` / `"world"` — `BrunoHomePlan.swift:337-346`, calling
`boxSetShelf(snapshot.curatedBoxSets, …)` (`:341`). The Collections procedural
tail's ×6 Curated family is the analogous path (`collectionsTail`
`BrunoHomePlan.swift:625-639`). **Recommendation: retarget, don't retire** — the
Home feed loses curated variety if dropped, and the promoted collections *are* the
curated content that justified the generator. Repoint `boxSetShelf`'s source from
`snapshot.curatedBoxSets` to the **union of the promoted groups' children** (Oscar
/ Roger Ebert / Asian Cinema / Film School / Critically Acclaimed) via a new
accessor (e.g. `promotedCuratedBoxSets`), and keep the Ebert/Oscar caption branch —
now **name-resolved** per the Show-all audit fix, so it survives the regrouping.
Same repoint covers the `collectionsTail` ×6 family. *INV-3:* the pick stays
seeded-pure over `(seed, snapshot, now)`. This is the one remaining **design**
call; the data/disposition decisions are all closed (§9a). Lands with the §1
migration (it shares the `curatedBoxSets` repoint).

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
3. **Coordinated server+app migration (§1) — the big one.** Favorite the promotes
   + create "Oscars"/"Roger Ebert" parent groups + un-favorite Curated + land the
   rank/drillStyle/lens seams + **the ~6 `curatedBoxSets`/synthetic-id repoints**
   (Nav + Show-all audits) + delete `consolidateOscars`/`consolidateEbert`, as
   **one step** (avoid transitional double-surfacing + destination regressions).
   Asian Cinema's composed shelves (reuses `.shelves` + `BrunoCoreGenre`) and the §8
   generator retarget ride here (they share the repoint).
4. **Highest-risk (perf + focus):** §6 reactive Decades hero (reintroduces the
   backdrop-reload cost the code deliberately avoided, + the anti-repetition buffer)
   and the §6 double-tap-down pill nav (focus-engine state machine, INV-7/10,
   on-device verification required). Build last, behind the shared-idiom refactor.
5. **Design call only:** §2 two-row layout (card placement — no nav impact if
   layered on `fromSnapshot`). §8 generator → **retarget recommended** (rides the §1
   migration).

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

### Efficiency + data-verification pass (round 2, 2026-06-30)

Second adversarial pass — lens: **maximize reuse / don't scatter**, and **verify
every "create / net-new / missing" server-data claim against the live server.**

**Data-existence — all "create/missing" claims verified (no more unverified
assumptions like the WKW/Bong miss):**
- Household names **Chazelle / Cameron Crowe / Robert Eggers** — all **exist** as
  director collections (4 films each). Plan's "confirmed present" is now grounded.
- **Oscar (×6) + Ebert (×2) collections — they EXIST** as children of Curated
  (verified in the 13-member list). **Nothing needs generating.** What's absent is
  *only* a favorited top-level **parent-group wrapper** that would make one "Oscar"
  / one "Roger" card drill into those existing children. (Correction 2026-06-30: an
  earlier draft mis-said "Oscars/Roger/Ebert don't exist" — false; the underlying
  BoxSets are present, only the wrapper is missing.) So this is not creation of
  content, it's **wrapping existing collections** — and the app *already* wraps them
  synthetically (`consolidateOscars`/`consolidateEbert`), so even the wrapper exists
  in app logic today. Two reuse paths (see §1): (A) make the wrapper real server
  data (a parent BoxSet over the existing children) — owner's pick; or (B) promote
  the existing app-side synthetic wrapper to top level (no new server data). Either
  way, zero new *collections*.
- **Metacritic / AFI / Rotten Tomatoes** — genuinely **absent** → Critically
  Acclaimed subgroupings are real future work, correctly deferred.
- 8 decade BoxSets exist (Touchstones best-of lane host). Wong Kar-Wai / Bong Joon
  Ho / Hughes films / Studio04 / Oscar tags — all previously verified.

**Reuse — three places the plan was about to add scattered new code; corrected
above:**
- R1. **Asian Cinema** → not a bespoke view: synthetic `BrunoCollectionCategory`s
  fed to the **existing** `.shelves` drill (the `curatedRandomShelves`/per-year
  pattern), genre filter via **existing** `BrunoCoreGenre.matches`. ≈1 builder fn,
  zero new view. (§1)
- R2. **Static brand heroes** → Studios + Rewatchables are already **two** bespoke
  band copies; extract **one** `BrunoBrandHeroBand(asset:title:)` added once to the
  shared `BrunoBoxSetGridView` (covers all three new grids) instead of 3 more
  copies. (§7)
- R3. **Anti-scatter** → real Oscars/Roger-Ebert server groups make the app-side
  `consolidateOscars`/`consolidateEbert`/`cardRowCategories` split **dead code** —
  delete it in the migration; never run both mechanisms. (§1)
- Affirmed: Cities `.shelves`, Critically Acclaimed `.grid`, Film School `.grid`,
  Decades reactive hero (existing `decadeBestOf`/`featuredItem`), Oscar offset (at
  the existing per-shelf build site) all **reuse** existing drillStyles/data — no
  new mechanisms. The owner's "real favorited groups" choice is the *less*-scattered
  path (one data model: favorited-group→children, like Cities/Decades/Directors).

---

## Nav-pathway safety audit (2026-06-30)

Owner constraint: **no change may alter a nav pathway or end destination except
the explicit requests** (Curated promotions, Cities, the pill-nav, reactive
Decades hero). Audited every change against `docs/BRUNO_NAV_MAP.md`.

### Shipped changes — nav-NEUTRAL (verified)
- **Em-dash tolerance** — *actively preserves* destinations, doesn't change them.
  The recognizer `BrunoOscarCategory(boxSetName:)` is consumed by the item-detail
  **Recommended shelf** (§10, `BrunoRecommendedShelf.swift:90` → `.oscar` captioned
  grid) and the Home **{Curated} show-all** (§2b, `BrunoHomeShowAll.swift:90`).
  Making it tolerant of the dash-free name is exactly what keeps those routes
  intact post-rename; the strict version would have *broken* them. No new false
  matches (Oscar Buzz/Bait → nil). ✅
- **Cities seam** — purely additive name-keyed cases (`"cities"`); changes no
  existing group's `rank`/`drillStyle`/`lens`. Cities (a favorited group) is
  *dropped as a nav hub* by the §10 classifier (`favoriteGroupBoxSets`, line 70) —
  consistent with every other group. Its child `Chicago Movies` keeps its existing
  (Genres) Recommended routing. ✅

### ⚠ Curated restructure — REQUIRES updating 4 `curatedBoxSets` consumers or 3
destinations regress (this is the load-bearing finding)

`snapshot.curatedBoxSets = group("Curated")` (`BrunoLibrarySnapshot.swift:99`).
Retiring Curated (un-favorite) **empties it**, and moving the Oscar/Ebert BoxSets
under new "Oscars"/"Roger Ebert" groups **removes them from it**. Four consumers
key off it — three are nav pathways/destinations:

| Consumer | File | Effect if not updated |
|---|---|---|
| Item-detail **Recommended** Oscar/Ebert routing (§10) | `BrunoRecommendedShelf.swift:83-91` | **DESTINATION REGRESSION** — the `.oscar`/`.ebert` branch is gated on `curatedBoxSets.contains(id)` (`:83`); once moved, the gate fails → Oscar/Ebert tiles fall through to `.filmsGrid`/drop, losing the captioned Oscar grid + Ebert toggle |
| Home **{Curated} show-all** Ebert/Oscar grid (§2b) | `BrunoHomeShowAll.swift:90,100` | DESTINATION — Ebert/Oscar Home-shelf show-alls stop resolving |
| Home **{Curated} explore generator** (§2b/§8) | `BrunoHomePlan.swift:342` | CONTENT source empties → shelf vanishes (the §8 retarget/retire decision) |
| Collections **procedural tail** ×6 Curated family | `BrunoHomePlan.swift:625` | CONTENT source empties |

**Fix (do in the §1 migration, in lockstep):** detect Oscar/Ebert by **name**
(`BrunoOscarCategory(boxSetName:)` / `hasPrefix("ebert")`) **un-gated from
`curatedBoxSets`**, or repoint these accessors at the new "Oscars"/"Roger Ebert"
groups. The recognizer is already tolerant, so hoisting the Oscar/Ebert checks out
of the `curatedBoxSets` gate makes §10 robust to the regrouping. Resolve §8
(retarget vs retire the Curated explore generator) **before** un-favoriting Curated.

### Planned changes — nav-NEUTRAL by design
- **Two-row layout (§2):** reorders card *positions* only; every card keeps its
  `drillStyle` destination. Safe **iff** implemented as a Collections-only row-map
  on top of `fromSnapshot` (finding 5) — `rank()` still feeds the Home footer/spine
  unchanged.
- **Oscar offset heuristic (§4):** reorders *within* a shelf; show-all destination
  (`brunoBoxSetGrid`) unchanged.
- **Static brand heroes (§7):** non-interactive image band; no tap target, no route.
- **Cultural Touchstones lane (§1):** *adds* a shelf to the Decades "All" view; no
  existing decade shelf's show-all changes.
- **Pill-nav + reactive Decades hero (§6):** explicit requests; change focus/scroll
  *behavior* and the hero *image*, not any show-all destination. Porting to
  Movies/Kids leaves their shelf destinations intact.

### By-design ripple to call out (not a regression, but a structure change)
Favoriting a group surfaces it on **three** surfaces at once — Collections tab,
Home **"Browse the Collection"** spine (§2a), Home **terminal footer** (§2c) — all
via `fromSnapshot`. So the promoted cards (Oscar/Roger/Asian Cinema/Film
School/Critically Acclaimed) + Cities will appear on **Home**, not just
Collections; retiring Curated removes it from all three. Consistent and intended
under the name-driven model, but it *is* a Home-surface change — bless it explicitly.

### "Show all" end-card audit (Home + Collections shelves)

Traced both routers end-to-end for every shelf's trailing "Show all" card.

**Home shelves — `brunoHomeRouteToShowAll` (`BrunoHomeShowAll.swift`):**
`.resume`/`.nextUp`/`.recentlyAdded` (stock libraries), `.year`/`.decade`/`.eras`
(Decades pill, off `decadeBoxSets`/favorited Decades group), `.auteurs`
(`directorBoxSets`), and the `default` query-backed grids (genre/studio/director/
acclaimed/critics/series/romance/seasonal) — **all independent of Curated; safe.**
The **only** Curated-coupled Home show-alls are the two caption branches
(`:88-113`): `.ebertStars` and `.oscar`, which resolve via `snapshot.curatedBoxSets`.
If Curated is retired / Oscar-Ebert regrouped, those `if let` resolves fail and the
show-all **falls through to the plain paged grid** (`:119`) — graceful (still shows
the films) but **loses the Ebert toggle / captioned reverse-chron Oscar grid**.

**Collections shelves — `brunoRouteToShowAll` (`BrunoCategoryCardRow.swift`):**
`.grid` (Directors/Studios/Movie Stars/Film School/Critically Acclaimed →
`brunoBoxSetGrid`), `.items` (Boxed Sets), `.rewatchables`, `.genres`, and `.shelves`
(Decades/Cities → `brunoCategoryShelves`) — **all safe / unaffected.** The promoted
**singles** (Asian Cinema custom, Film School `.grid`, Critically Acclaimed `.grid`)
and **Cities** `.shelves` get clean standard routes — nothing existing to break.

**⚠ The load-bearing show-all finding — Oscar/Ebert special destinations are keyed
on SYNTHETIC ids.** Both destinations the owner wants *unchanged* are gated on the
ids that `consolidateOscars`/`consolidateEbert` mint:
- **Oscar gold tiles** — `BrunoCategoryShelves.swift:518` `if category.boxSet.id ==
  "curated-oscars"` renders the six gold category tiles. A real "Oscars" group has a
  different id → check fails → drill renders as plain shelves, **no gold tiles.**
- **Ebert toggle** — `BrunoCategoryCardRow.swift:75` `if category.boxSet.id ==
  "curated-ebert"` routes to `brunoEbert` (Up⇄Down toggle). A real "Roger Ebert"
  group → check fails → routes to generic `.shelves` → **2 shelves, not the toggle**
  (violates "Roger drill-down unchanged").

**Recommendation (keeps the owner's one-data-model priority AND preserves every
destination):** go Path A (real groups) uniformly, and in the §1 migration **repoint
the id-keyed sites from synthetic-id to NAME** — small, local, and it lets the
consolidation code be deleted:
1. `BrunoCategoryShelves.swift:518` — `id == "curated-oscars"` → `name == "oscars"`
   (gold tiles for the real Oscars group).
2. `BrunoCategoryCardRow.swift:75` — `id == "curated-ebert"` → `name == "roger ebert"`
   (Ebert toggle for the real group); also the single-Ebert branch (`:122`).
3. `BrunoHomeShowAll.swift:90,100` + `BrunoRecommendedShelf.swift:83` — resolve
   Ebert/Oscar **by name, un-gated from `curatedBoxSets`** (from the prior audit).

With those four repoints, **every Home + Collections + item-detail show-all reaches
the identical destination it does today** — gold tiles, Ebert toggle, captioned
Oscar grid all intact — while the data model collapses to one favorited-group shape
and `consolidateOscars`/`consolidateEbert`/`cardRowCategories` are deleted. (Path B —
keep the app-side synthesis, promote the synthetic cards — touches zero rendering
code but keeps two promotion mechanisms; available if you'd rather not touch the
id checks, but it's the *more*-scattered option.)
