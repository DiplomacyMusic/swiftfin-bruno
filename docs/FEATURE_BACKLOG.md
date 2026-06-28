# Bruno tvOS Feature Backlog — New-Thread Action Plan

> Status: PLAN for a fresh implementing thread. Incorporates a red-team pass against the code, nav map,
> and perf invariants. **Several backlog items are stale-framed, moot, or partly un-fixable** — read the
> per-feature root cause before touching code; do not implement the original framing verbatim.

## 1. Read first (canonical, in this order)

1. **`docs/BRUNO_NAV_MAP.md`** — every surface, every route, the §8 mismatch table, §9 open questions, and
   §0 live sizes. Most of this backlog is mismatch/open-question items; the map is the contract.
2. **`docs/BRUNO_CODE_MAP.md`** — file geography, the `brunoRouteToShowAll` seam, the Home-vs-browse split,
   the §7 BoxSet-vs-Franchise terminology.
3. **`docs/BRUNO_PERF_INVARIANTS.md`** — INV-1..10. Each cited site is anchored `// INV-n`. Fragile
   constants live in `BrunoShelfMetrics`. **Restyle freely; keep the ten intact.**
4. **`docs/BRUNO_STALL_HANDBOOK.md`** — the felt "stall" is a tvOS held-auto-repeat *focus freeze*, not a
   render hitch. START HERE for any scroll/focus work.
5. **`docs/BRUNO_HERO_UPNAV.md`** — the un-pinned-menu-bar resolution. Required reading for B1 (which it
   makes moot).
6. **`docs/BRUNO_CERTIFICATION_PLAN.md`** — the five-check cert receipt. Per-feature "cert?" flags below
   say which items must produce one.

**Workflow (non-negotiable):**
- Work in a **worktree**; finished work lands on **`main`** via **PR — the owner merges**. **Never push
  `main` without asking.** After a PR merges, delete its worktree (with the owner's confirm).
- **`.pbxproj` is off-limits** (file-system-synchronized group). Additive, tvOS-only; Bruno UI under
  `Swiftfin tvOS/Views/BrunoHomeView/`, engine under `Shared/Objects/Bruno/`. Non-Bruno edits stay
  DEBUG-gated/inert. Never hardcode BoxSet/library IDs.

**The stall-fix prerequisite (before ANY scroll/focus work):**
- The FocusShadowPoster structural-stability fix is **`24ee9372`** ("make FocusShadowPoster structurally
  stable (INV-10)"), and it is **already on `main`**. (The red-team's `f3c58bab` is the stale
  pre-cherry-pick branch name — ignore it; `24ee9372` is the landed commit.)
- **Verify `24ee9372` on-device before C1/B2/C2 and any cell-structure change.** Re-baseline
  freeze-while-held per STALL_HANDBOOK §3c on *current main* — every freeze number in the handbook
  predates this fix and is stale. No A/B is "pending"; the fix is landed and needs a fresh on-device
  measurement, not a re-port.

---

## 2. Gating / ordering

**Gate 0 — must happen first:**
- **G0a. On-device re-baseline of `24ee9372`.** Measure freeze-while-held on Home + Movies + Decades +
  Collections on current `main`; output per-surface frozen-while-held %. **Blocks B2, C1, C2, D1 (any
  scroll/focus or cell-structure work).**
- **G0b. Owner intent capture (one batched message).** Resolve the product questions gating B3, C3, D1,
  D2, D3 in a single round-trip so implementation isn't serially blocked.

**Independent / safe now (no gate):**
- **C3-margin (renamed below to avoid confusion with the C3 "more shelves" item)** — the inter-shelf
  margin tweak. Pure spacing knob, orthogonal to INV-1. Smallest, safest; only needs a target value.

**Blocked on G0a:** C1 (Kids pill drift), C2 (Decades jank), B2 (hero steadiness).
**Blocked on G0b (owner decision):** B3 (New Releases source/sort), C3 (more-shelves scope), D2 (bruno-sig
delivery / PROJECT_TRACKER Q3), D3 (a concrete user story).
**Reframe / likely-close (do not implement as written):** B1 (moot post un-pin), D1 (documented
intentional divergence).

**Recommended sequence:** margin tweak (now) → G0a + G0b in parallel → B1/D3 verify-and-close →
C2/B2 confirm-or-drop → C1 fix → B3 → D2/D1 only with owner sign-off.

---

## 3. Per-feature entries

> Naming note: the original notes used "C1/C2/C3" loosely. Below, each item carries its original intent.

### B1 — Hero "debounce" vs tab switches + Home slide-in  ·  **MOOT — verify & close**
- **Corrected root cause:** Already architecturally dissolved. The menu bar was un-pinned (`4a721438`) and
  the hero dropped `.onMoveCommand` (`e94e07fd`); the hero is now just the first content row of each tab's
  `LazyVStack`. The original symptom (backdrop snap on tab switch) came from the *old pinned-bar* design,
  deliberately removed to fix the UP-nav focus trap (`BRUNO_HERO_UPNAV.md` §Resolution).
- **Red flags:** Framing is ~2 days stale; implementing it would require reverting the un-pin fix (major
  regression). No "Home slide-in" spec exists; all tabs are intentionally structurally identical.
- **Invariant guardrail:** INV-8 (auto-advance gated on `settle`, semantic — never on tab-switch timing),
  INV-9 (any new animation collapses under reduce-motion), INV-10 (conditional `if isTabSwitching` view
  swaps re-introduce the exact focus-stall pattern `24ee9372` fixed).
- **Recommended approach:** Do not implement as framed. On-device verify the un-pinned design meets "hero
  feels locked." If yes → close with a pointer to `BRUNO_HERO_UPNAV.md`. If a residual snap remains → fix
  architecturally (freeze hero index during tab-switch settle), never via manual debounce. No Home-specific
  animation without owner design sign-off.
- **Effort / confidence:** XL (if forced) / high that it's moot. **Cert?** No code → none; if a residual
  fix ships it touches focus → required.

### B2 — Hero index / auto-advance steadiness  ·  **likely subsumed by B1**
- **Corrected root cause:** "Debounce" is the wrong lever — the semantic gate already exists (INV-8 holds
  auto-advance until `settle`). Any misbehavior is a settle-gating/focus-structure issue, not timing.
- **Invariant guardrail:** INV-8 (keep the gate semantic), INV-10 (no conditional structure on focus).
- **Recommended approach:** Fold into B1's on-device verification (after G0a). Act only if a concrete
  settle-gating bug is observed. **Effort/confidence:** S–M / low (may not exist). **Cert?** Yes if hero
  code changes.

### B3 — "New Releases" shelf on Home after "Just Added"  ·  **needs intent (G0b)**
- **Corrected root cause:** A **naming collision**, not a missing shelf. "Just Added" (Home spine) =
  `RecentlyAddedLibrary`, `dateCreated`-desc (library state). "New Releases" (Collections) = server-curated
  favorited BoxSet, `premiereDate`-desc (release date), **also** labeled "Just Added" in
  `BrunoCategoryShelves.swift`. The request doesn't say which source/sort to surface.
- **Red flags:** No `snapshot.newReleasesBoxSets` exists; sort field ambiguous ("release date like Just
  Added"); it'd be a second entry point to data already at Collections rank #0.
- **Invariant guardrail:** INV-2 (stable domain id — use the group BoxSet id, never an index), INV-3 (pure
  over snapshot; do **not** re-shuffle the curated group by seed), INV-5 (if server `.items`, don't treat
  as live user-state).
- **Resolve first (G0b):** server group vs derived query; `premiereDate`-desc vs `dateCreated`-desc;
  distinct eyebrow label to kill the collision.
- **Recommended approach (if server group + premiereDate):** add `BrunoLibrarySnapshot.newReleasesBoxSets`
  (case-insensitive group lookup, mirrors `directorBoxSets`); add `BrunoShelf.Kind.newReleases` with a
  unique `dedupeKey`; insert one descriptor after Just Added in `BrunoHomePlan.build`; rerun
  `BrunoHomePlan+SelfCheck`; reconcile the "Just Added" label collision; update `BRUNO_NAV_MAP.md §2a`.
- **Effort / confidence:** M / high (once intent fixed). **Cert?** Yes (plan-touching: determinism + INV-2/3/5).

### C-margin — Home landscape inter-shelf margin  ·  **safe, start now**
- **Corrected root cause:** Pure UX spacing — the `LazyVStack` `spacing: 36` at `BrunoHomeView.swift:122`,
  fully orthogonal to INV-1's pinned row height (348 landscape, in `BrunoShelfMetrics`). Explicitly in the
  "safe to touch" category.
- **Invariant guardrail:** None at risk; cap-and-grow counts sections, not heights. Do not touch
  `BrunoShelfMetrics`.
- **Resolve first:** target value (24? 20? — 8/10/16/40 rhythm suggests candidates); Home-only vs all
  browse surfaces also at `spacing: 36`.
- **Recommended approach:** change the one constant to the owner's target; optionally mirror to other
  browse surfaces if in scope; visual-inspect in sim landscape. Reversible.
- **Effort / confidence:** S / high. **Cert?** Touch-only exemption (no INV sites).

### C1 — Kids pill-scroll view drift  ·  **real bug; reframed**
- **Corrected root cause:** Not "needs more debounce." The drift is an **animated `scrollTo` running
  concurrently with a grid-height change**: `onChange(focusedChip)` fires `withAnimation(.easeInOut)` to
  scroll the pills (`BrunoKidsView.swift:179–189`) while `filteredItems` re-evaluates ~500 ms later
  (`:194–196`, debounced `:231–237`) and the grid `minHeight` (`:157–160`) grows/shrinks under the in-flight
  scroll → invalid anchor. The prior "grid-height-vs-hero, not eased-scroll" diagnosis was incomplete: the
  eased scroll is the *trigger*. Commit `65d57b5f` fixed the debounce half; the scroll-timing half remains.
- **Invariant guardrail:** INV-1 (don't "fix" by pinning grid height in a way that fights the LazyVStack
  spine), INV-9 (reduce-motion path must still scroll correctly).
- **Resolve first:** does grid height actually differ between filters on the real kids library; does the
  reduce-motion (instant) path also drift (if so, the target is wrong, not the timing).
- **Recommended approach (safest first):** (a) make the scroll **instant** (drop the animation, match the
  reduce-motion branch — the "eased not snapped" comment at `:174` is likely outdated); or (b) move the
  `scrollTo` into the debounce commit task so it fires after the grid settles. Avoid (c)
  measure-and-pin-during-animation (INV-1 risk). Verify UP-from-grid still lands on the active filter; test
  sparse (TV Shows) vs dense (All).
- **Effort / confidence:** M / high. **Cert?** Yes (scroll/focus surface) — include the on-device verify.

### C2 — Decades drill-in "bouncing/snapping/thrashing"  ·  **unverified; measure before fixing**
- **Corrected root cause:** **Likely no Decades-specific symptom.** The code does an *atomic* stack swap,
  not lazy per-shelf insertion: decade fetch (paged to completion) → synchronous `yearCategories` grouping
  → atomic assign → one `LazyVStack` re-eval; all shelves height-pinned. The 500 ms debounce is a *feature*
  (coalesces scrubs), not the cause. STALL_HANDBOOK documents zero Decades-specific jank; the measured
  freeze was the shared Home/Movies focus path (now addressed by `24ee9372`).
- **Red flags:** Removing the debounce makes it worse; baseline is stale (pre-`24ee9372`).
- **Recommended approach:** **Do not write Decades-specific code yet.** After G0a, reproduce with
  `BrunoPerfLog` (STALL_HANDBOOK §3). If it's the shared focus path, `24ee9372` already covers it → close.
  Only if Decades is *measurably* jankier than other surfaces after the stall fix, analyze
  year-insertion/fetch cost.
- **Effort / confidence:** M / low (symptom may not exist). **Cert?** Only if Decades-specific code ships.

### C3 — Home needs 3–4× more loadable shelves  ·  **L; constraint is logic, not data**
- **Corrected root cause:** The real limit is **dedupe + adjacency + caps math, not the data pool.** The
  84 genres / 54 franchises are red herrings — the explore tail uses seeded *picks* and drops same-kind
  adjacents (`BrunoHomePlan.swift:486–501`) and seen `dedupeKey`s (`BrunoHomeViewModel.swift:357`). Current
  design realizes ~25–30 shelves (≈1.4–1.7× the spine), not 3–4×. Sub-genres aren't in `exploreKeys`
  (they live in `BrunoGenresView`); years are intentionally excluded from the tail.
- **Red flags:** Reaching 3–4× needs raised `tailCeiling` (~120), higher `exploreBlockCount`, and/or new
  generators. New generators that read **unsorted/shuffled** sources break INV-3 (cache hydrates wrong
  shelf after a server reorder).
- **Invariant guardrail:** INV-3 (new generators must be seeded + pure over an **ordered** source), INV-5
  (mutable source order silently corrupts the seed-keyed cache).
- **Resolve first (G0b):** baseline current realized depth; confirm the constraint (dedupe vs adjacency vs
  block-exhaustion) via instrumentation; confirm sub-genre/franchise exposure in `BrunoLibrarySnapshot`
  (may need builder-script coordination).
- **Recommended approach:** instrument tail drops → add seeded generator(s) over ORDERED sources
  (sub-genre, franchise) → rerun `selfCheckPassed()` → owner sign-off on cap raises (with a safe-ceiling
  rationale) → A/B any adjacency-rule loosening.
- **Effort / confidence:** L / high. **Cert?** Yes (plan-touching: INV-3/5 + determinism).

### D1 — Home spine tiles → branded show-all  ·  **documented-intentional; intent-first**
- **Corrected root cause:** **Intentional divergence, not a bug** (`BRUNO_NAV_MAP.md §8 #4`, open Q#4).
  Home is a *terminal, item-level browse feed*; Collections is a *category-level curation surface*. Home
  spine tiles are `.items(...)` BoxSets → `.item()` detail; Collections cards are categories →
  `brunoRouteToShowAll` → branded grid. `brunoRouteToShowAll` takes a `BrunoCollectionCategory`, **not a
  `BaseItemDto`** — "route Home tiles through it" is a signature mismatch.
- **Red flags:** Conflates "add a Show-all card" (a UI slot `PosterHStack` lacks) with "route through
  brunoRouteToShowAll." Adding the slot means forking `PosterHStack` or swapping to `BrunoShelfRow`
  (browse-surface-only) — an architecture break against the terminal-feed contract.
- **Invariant guardrail:** INV-1 (differently-styled trailing card risks the height pin), INV-10
  (non-item-keyed card recycling through the CollectionHStack-fork hosting-controller reuse = stale-state
  leak).
- **Recommended approach:** **Verify intent before any code.** Preferred: keep Home terminal; only the
  footer cards route through `brunoRouteToShowAll`; document the divergence as designed. Avoid forking
  PosterHStack or converting spine item-shelves to category-shelves (breaks the pure `.items/.query` model
  → determinism re-proof).
- **Effort / confidence:** L / high it needs intent-first. **Cert?** Yes if any routing/cell change ships.

### D2 — Decade show-all carries curation (Best-of order + "Other" subset)  ·  **partly un-fixable in-app**
- **Corrected root cause:** Two gaps: (1) Best-of significance is computed **client-side** by parsing
  `bruno-sig` tags at category-build time (`brunoSignificance ~:714`); it never persists to anything
  `ItemLibrary` can read, and **Jellyfin has no `bruno-sig` server filter** (`NAV_MAP §9.3`). (2) "Other"
  membership is a **derived predicate** (out-of-window OR yearless), modeled in no schema field. Per-year
  works only because `years:[year]` is a real server filter. So significance order and the "Other"
  boundary **cannot be carried to a paged grid** without new plumbing.
- **Red flags:** No tags field in `BrunoQuery`; static-grid fallback can't page large decade sets;
  multi-subsystem change (schema + disk-cache migration + query + routing) with no single integration point.
- **Invariant guardrail:** INV-5 (any `BrunoCollectionCategory` schema change forces a disk-cache
  migration), INV-3 (stay deterministic).
- **Resolve first (G0b / PROJECT_TRACKER Q3):** is "show-all opens the full decade unsorted" acceptable? is
  the "Other" subset intentional?
- **Recommended approach:** **Don't build client-side curation plumbing.** Preferred: deliver server-side
  **"Best of the {Decade}" BoxSets** under the Curated group (zero app code; renders like any curated
  collection — solves significance via the MovieCollection pipeline). "Other" can't be a BoxSet (it's a
  predicate); leave it teaser-only with a doc note, or accept full-decade show-all. If status-quo is fine:
  remove the misleading doc language and close as designed.
- **Effort / confidence:** L / high (and honest that the in-app path is wrong). **Cert?** Yes for any
  app-side path; server-BoxSet path = pipeline work, no app cert.

### D3 — Back button remembers the real reverse path  ·  **architectural; story-first**
- **Corrected root cause:** Not a bug — an **architectural asymmetry**. tvOS presents routes via
  `.fullScreenCover` with a fresh `NavigationCoordinator` (isolates state, avoids INV-1/5/8 re-entry
  breakage); iOS uses `path.append()`. No back-button UI exists; the Menu key already provides native back.
  Drill-ins *within* a cover retain internal history; only the bridge back to the parent is lost. Tab
  switches clear `path[]` by design (`TabCoordinator:62`).
- **Red flags:** No reproduction, no user story, no back-button to fix. Unifying to path-based tvOS nav is a
  major refactor, not a bug fix.
- **Invariant guardrail:** **HIGH** — INV-5 (cache keyed on (seed, shelf.id), assumes stateless re-entry),
  INV-8 (top-down deterministic reveal; re-entry mid-reveal breaks order), INV-1 (re-scroll on pop can
  hitch), INV-3 (`selfCheckPassed` could assert on multi-entry paths).
- **Recommended approach:** **Phase 1 clarify only (no code):** capture concrete flows; confirm it isn't
  just the native Menu-key behavior (tvOS HIG discourages custom back UI); observe current dismiss
  behavior. **Phase 2 (if approved):** a *local* `priorRoute` per view (re-route on dismiss), **not** a
  global NavigationStack unification. Re-run determinism self-check + re-measure freeze-while-held after.
  Add `NAV_MAP §9 Q#7` documenting the per-view local-back rationale.
- **Effort / confidence:** M / low (intent-bound). **Cert?** Yes if any nav code ships.

---

## 4. De-risking — top 3 things most likely to go wrong

1. **Acting on stale framing (B1, C2, D1).** Three items describe problems the codebase already dissolved
   (B1 un-pin), never exhibited (C2 Decades jank), or intentionally diverges on (D1 terminal feed).
   **Avoid:** verify-and-close before writing code; reconcile every symptom against `BRUNO_NAV_MAP.md` /
   `BRUNO_HERO_UPNAV.md` / STALL_HANDBOOK and reproduce on current `main` first. Do not revert architectural
   fixes to satisfy an old framing.
2. **Trusting stale perf baselines / re-litigating a landed stall fix.** Every freeze number in
   STALL_HANDBOOK predates `24ee9372` (on `main`). Attributing C1/C2/B2 jank to surface-specific code
   before re-baselining sends the thread fixing the wrong layer. **Avoid:** do **G0a first** — on-device
   re-baseline on current `main`, then attribute. The fix is shipped, not "pending A/B."
3. **Re-introducing the INV-10 structural-instability anti-pattern.** C1's "pin grid mid-animation," D1's
   "Show-all card in the carousel," D2's schema changes, and any B1/B2 `if isTabSwitching` swap all risk
   conditional subtree mutation on focus/state — the precise pattern that caused the held-repeat freeze and
   was reverted once. **Avoid:** keep cells structurally stable (art layer always present, work gated on
   focus, key-aware reuse); prefer the simplest non-structural fix (instant scroll, deferred scroll,
   server-side BoxSets); for any cell-structure or plan-touching change, produce a **cert** + an on-device
   freeze-while-held verification before landing.

**Cert ledger:** B3, C1, C3, D2(app-path), D3, D1(if code), B2(if code) → **cert required**. C-margin →
**touch-only exemption**. B1, C2 → **no cert** unless residual code is ultimately written.
