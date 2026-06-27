# Bruno tvOS — Hero focus trap: foundational knowledge + resolution record

Status: IN PROGRESS — resolution = un-pin the menu bar so it scrolls away; foundational record below.

> Sits alongside `docs/BRUNO_PERF_HANDOFF.md` and `docs/BRUNO_PERF_INVARIANTS.md`. This is the one
> document a future engineer (or the owner) reads to resolve the hero UP-nav focus trap without
> re-deriving anything — root cause, full attempt history, the invariants any fix must preserve, the
> verified design space, and the chosen resolution. The issue was attempted and **reverted twice**
> over 4 days (Jun 23–26 2026) and is logged OPEN in `docs/PROJECT_TRACKER.md`.

---

## Resolution being implemented

The owner does **not** want the menu bar pinned. They want it to **scroll up and off-screen as you
navigate down, and reappear when you scroll back to the top — like every other shelf/row in the app**,
on **every tab**. Today the bar is *pinned* (the `ZStack(.top)` "never scrolls" peer in `MainTabView`
plus the `Color.clear` barHeight inset). That pinning is exactly what makes it float and obscure
content. The entire `b891c6ee` "pin the bar" architecture was solving the wrong problem.

**Hard constraint:** the full edge-to-edge hero art MUST still reach the physical top of the screen.

**The validated structure (row form — NOT an overlay).** The bar becomes the **first row of the
scroll content** (a real focusable frame), with the hero as the **next row** whose backdrop bleeds
**up behind the bar row** via the existing `topBleed` mechanism so the art still reaches the physical
top. (An overlay-on-hero was rejected: it gives the bar zero layout height and puts two focusables —
pills + hero `Button` — in the same top region, the one geometry the tvOS focus engine resolves
badly. The BRUNO wordmark stays a non-focusable overlay; the bar becomes a focusable row.) One
focusable per vertical region → UP/DOWN are plain vertical moves.

What changes, summarized from the plan:

- **`MainTabView.swift`** — remove the pinned `BrunoMenuBar` peer (`:143-151`), the `Color.clear`
  `safeAreaInset` (`:136`), and the now-moot `onExitCommand` UP-routing (`:141`) plus the
  `focusScope`/`barFocus` plumbing. The bar lives here **once**, so this removes it from **all** tabs
  at once — the per-tab rows must land in the **same change**.
- **New shared component `BrunoScrollingMenuBar`** (wraps `BrunoMenuBar`; selection via the existing
  `TabCoordinator` env object; a "cover mode" preserving dismiss-then-select / F8 for covers).
  Injected as the **first `LazyVStack` row** of every tab root: `BrunoHomeView`,
  `BrunoCategoryShelves` (Collections + Movies/Genres), `BrunoMediaView` (TV), `BrunoKidsView`. There
  is **no single seam** to inject once (`MainTabView` mounts `tab.item.content` as opaque `AnyView`),
  so this is a real multi-view change — the bulk of the work.
- **`BrunoHeroView.swift`** — drop `.onMoveCommand` (`:77-86`) so UP/DOWN aren't swallowed (owner OK
  dropping manual L/R paging; auto-advance still rotates). **Re-derive `topBleed`** (`:104`) to drop
  the `+ BrunoMenuBar.barHeight` term now that the inset is gone (F4 coupling — else the backdrop
  over-spills).
- **`.ignoresSafeArea(.top)`** — now **REQUIRED** on hero tab roots (was forbidden) so the bar's row +
  hero bleed reach the physical top; keep title-safe insets so the bar isn't clipped under overscan.
- **Covers (`BrunoHeroMenuBar` + call sites** `BrunoMoviesView:99/109`, `BrunoGenresView:199`,
  `BrunoBoxSetShelvesView:125`**)** — un-pin too for consistency (default: yes, per "every tab"),
  rendering the same scrolling first row (cover mode), keeping the `.if(!isTabRoot)` const gate (F2).
- **Search / Settings (stock Swiftfin; Settings is a `Form`, hero-less)** — default: give them the
  same top scrolling bar (wrap the stock view); if a `Form` can't cleanly take a scrolling row, fall
  back to a small top row. Decided in implementation; the owner's edge-to-edge concern is hero-only so
  a minor exception here is acceptable.
- **Docs/comments (now inverted)** — update F1/F4 in `BRUNO_MOVIES_GENRE_SURFACE.md`, the
  `bruno-tvos-top-bar-pattern` memory note, and the in-code "do NOT ignore `.top`" warnings
  (`BrunoHomeView:85-90`, `MainTabView:108-141`, `BrunoCategoryShelves:256-261`, `BrunoMediaView:56-60`,
  `BrunoKidsView:105-109`).

**Invariants to respect (expert-confirmed):**

- **INV-1** — the bar row must be **fixed-height** (`barHeight`); no focus-driven height change.
- **INV-7** — cold-launch focus must still land on the **hero, not a bar pill**; keep
  `prefersDefaultFocus` / first-focus on the hero (`BrunoHomeView:105-110`). Device-verify.
- **INV-10** — bar row tree constant across focus (opacity/scale only; `BrunoMenuPill` already
  complies).
- Keep `bleedsTop:true` (do NOT repeat `ceba7e18`'s `bleedsTop:false` ambient-owns-top mistake).

**Consequences (simplify the foundational record below):** UP-to-bar becomes a normal vertical focus
move — the whole #4–#9 pinned-peer bridge saga becomes moot. **Bug 2 (right-edge fall-through) becomes
moot** — no pinned pill row with a right edge by the hero. Dropping `.onMoveCommand` is the same edit
as the reverted `2182e2d6`, but for a *different* reason now (we no longer need UP-to-a-pinned-bar; we
need scroll). Still **on-device-only verifiable**.

This resolution was expert-validated by swift-xcode-expert + bruno-expert and supersedes the earlier
"pin the bar" framing. Everything below remains accurate as the *history/root-cause record*; just read
the bar's desired behavior as "scrolls away," not "pinned."

---

## Foundational knowledge (history & root cause)

> The §1–§7 record below documents the problem, root cause, the 9-commit oscillation, the invariants,
> the verified design space, and the resolution-path discussion. All claims were verified against HEAD
> (`6e39ea9a`). All SHAs are `git show`-able; all file:line references resolve at that HEAD.

### Context

On **Home**, pressing **UP** from the focused hero/spotlight banner does **not** reach the top
menu bar — you must press Menu/Back. From **Settings**, UP works. The user also reports a second,
"extremely weird" symptom: pressing **RIGHT** past the last menu pill (Settings) does not wrap to
Search or stop — it drops focus **DOWN into the hero**.

This issue has been attempted and **reverted twice** over 4 days (Jun 23–26 2026) and is logged
OPEN in `docs/PROJECT_TRACKER.md`. The goal of this work is **foundational knowledge** that ends
the oscillation: one document a future engineer (or the owner) reads to resolve it without
re-deriving anything — root cause, full attempt history, the invariants any fix must preserve, the
verified design space, and a recommended, adversarially-stress-tested resolution path.

This plan was produced by a multi-agent deep dive: git archaeology of both fix threads, a tvOS
focus-engine expert pass, **three independent adversarial verifications** (which refuted the first
recommended fix), plus a dedicated investigation of the right-edge fall-through. All claims verified
against HEAD (`6e39ea9a`).

### The core finding (one paragraph)

The hero is **one chrome-less focusable `Button`** carrying `.onMoveCommand` for left/right
spotlight paging. `.onMoveCommand` is **not** an observer — it is a **consuming sink** into UIKit's
move-command responder chain for **all four** directions. Its `default: break` marks UP/DOWN as
*handled*, so the focus engine never runs its neighbor move. UP-from-hero therefore needs **two**
independent preconditions, and only one is met today:

- **(A) Geometry** — bar + content must be non-overlapping focus peers so the engine *has* an
  up-neighbor. **Already fixed** at HEAD by `b891c6ee` (`MainTabView.brunoTabView`: `ZStack(.top)`
  with two `.focusSection()` peers under one `.focusScope` + a `Color.clear` barHeight `safeAreaInset`).
- **(B) The UP command must reach the engine** — but the hero's `.onMoveCommand` **consumes it
  first**. **Still broken.** This is the live bug.

The **right-edge fall-through is the same root in the other axis**: the menu bar has **zero
focus-trapping** (`.focusSection()` is a reachability *aid*, not a wall, and tvOS never auto-wraps
rows), and the hero's **920pt × full-width** focusable frame is a screen-spanning *magnet*. RIGHT
past Settings finds no pill → the engine widens to the global focusable set → the giant hero frame
wins. Then the `.onMoveCommand` UP-swallow blocks climbing back out → a focus **trap**.

### 1. Problem statement (precise / reproducible)

**Bug 1 — UP doesn't escape the hero.** Focus the Home hero (e.g. GoodFellas), press UP.
- Expected: the selected top-bar pill takes focus. Actual: nothing; focus stays on the hero.
- Localizing fact: Settings (no hero → no `.onMoveCommand` owner) lets UP through. The trap is
  **hero-local**, not container-global.

**Bug 2 — RIGHT past Settings falls into the hero.** With the rightmost pill (Settings) focused,
press RIGHT. Expected: wrap to Search, or stop. Actual: focus drops DOWN into the hero.

Both ship to every surface mounting `BrunoHeroView`: Home (`BrunoHomeView.swift:123`), Kids
(`BrunoKidsView.swift:127`), and the Decades/Genres covers (`BrunoCategoryShelves.swift:271`).

Bar order (verified, `MainTabView.swift:35-45`): **Search · Home · Collections · Movies · TV Shows ·
Kids · Settings** (Search & Settings are `.iconOnly`). "Rightmost" = **Settings**.

### 2. Root cause

#### 2.1 `.onMoveCommand` is a consuming responder (Bug 1, precondition B)
`BrunoHeroView.swift:70-86` — `Button { route(item) } …  .focused($isFocused) .onMoveCommand { .left→step(-1); .right→step(+1); default: break }`.
`.onMoveCommand(perform:)` bridges into UIKit's move-command chain and makes the view a **sink for
all four `MoveCommandDirection` cases**. The closure is `(MoveCommandDirection) -> Void` — **no
return, no decline, no pass-through**. `default: break` still counts as *handled*; `break` means
*you* did nothing, not that the engine regains control. So UP routes to the closure, is consumed,
and the engine never evaluates the bar neighbor. Corroborated verbatim by commit `2182e2d6`:
*"onMoveCommand is a CONSUMING responder … incl. a no-op default suppresses the focus engine's
neighbor move."* (Secondary fragility: tvOS-18 silver-remote regression FB15272007 drops the first
`onMoveCommand` press after load/direction change.)

#### 2.2 Necessary-but-not-sufficient pair — and the decisive timeline insight
`b891c6ee` fixed **(A)** geometry; the hero still owns `.onMoveCommand`, so **(B)** is violated.
**Geometry alone cannot fix UP-from-hero** — both halves must hold. This is why every container-only
attempt (#4–#9 below) failed to resolve the hero case.

**THE KEY FINDING: (A) and (B) have never been simultaneously true in the entire history.** When
`onMoveCommand` was removed to satisfy (B) — `2182e2d6`, **Jun 25 20:44** — the repo had: the **stock
`TabView`** (the focusable custom `BrunoMenuBar` didn't exist until `22ee33ec`, Jun 26 11:25; revert
note: *"the system bar had no focus binding, so UP did nothing there"*), **no peer-section geometry**
(precondition A, `b891c6ee`, didn't land until Jun 26 17:12), and **no cover bar bridge**
(`BrunoHeroMenuBar`, Jun 26 12:43). So UP was freed with **nothing to reach** → "didn't fix" →
reverted ~3h later (`92a2e11e`). Every piece of UP-escape infrastructure landed *afterward*, always
paired with `onMoveCommand` restored. **This is why the bug survived every attempt, and why dropping
`onMoveCommand` now is a fundamentally different proposition than it was on Jun 25** — at HEAD, (A) +
the focusable bar + the cover bridge all exist; only (B) is missing.

#### 2.3 Bug 2 — the right-edge fall-through
`BrunoMenuBar` (`BrunoMenuBar.swift:40-67`) is a bare focusable `HStack` of pills — **no
`.focusSection()` on the bar itself** (the only one is one level up in `MainTabView`), no
`UIFocusGuide`, no wrap logic. tvOS focus-engine facts: `.focusSection()` does **not** trap focus at
edges (it aids reachability), tvOS does **not** auto-wrap rows, and directional search is
**geometric** — when no in-section candidate exists in the press direction, it falls through to the
**global** focusable set and scores by direction + frame overlap + distance. The hero's focusable
frame is **`maxWidth:.infinity` × 920pt** (`720 + extraHeight:200`, `BrunoHeroView.swift:115-137`),
starting just under the bar — it overlaps the RIGHT-projected region from the centered Settings pill
and **wins**. No wrap (no mechanism), no stop (a candidate exists). Coupled with §2.1, you fall in
from the side and can't climb out → trap.

### 3. Timeline of attempted fixes (the oscillation)

Thread **H** = hero `.onMoveCommand`; Thread **C** = container/bar bridge. Pattern: *fix UP by
touching the hero → break L/R; restore L/R → break UP; fix container geometry → never un-sinks UP.*

| # | SHA | Date | Thread | Tried | Outcome |
|---|-----|------|--------|-------|---------|
| 1 | `b064f714` | 06-23 | H | Introduced hero `.onMoveCommand` (L/R), `default: break` | L/R works; **sinks UP/DOWN** → trap. Original sin. |
| 2 | `2182e2d6` | 06-25 20:44 | H | **Removed** `.onMoveCommand` to free UP | Killed L/R paging; **never device-verified**; premise wrong on covers (bar not in cover focus tree). |
| 3 | `92a2e11e` | 06-25 23:53 | H | **Reverted #2** (restored handler) | L/R back; **UP re-broken**. = hero state at HEAD today. |
| 4 | `22ee33ec` | 06-26 11:25 | C | Custom bar as **VStack** peer | UP works geometrically, but **opaque band** kills full-bleed hero. |
| 5 | `57aa061d` | 06-26 11:57 | C | `safeAreaInset{bar}` | Hero bleeds, but inset content **isn't a focus peer** → UP can't enter; bar **drifts** with scroll. |
| 6 | `5840d968` | 06-26 12:43 | C | `BrunoHeroMenuBar` for covers + `BrunoTabBridge` | Covers get a bar; becomes the cover template. |
| 7 | `b891c6ee` | 06-26 17:12 | **C — the (A) fix** | `ZStack(.top)` peers + `Color.clear` barHeight inset; `+barHeight` hero `topBleed` | **Real geometry fix.** UP-to-bar geometry restored, no drift, hero bleeds. Hero still sinks UP (B). |
| 8 | `ceba7e18` | 06-26 18:09 | C | `View.brunoBelowMenuBar()` = `.padding(.top,barHeight).focusSection()` on scroll content | **Reverted 16 min later.** Killed L/R; never device-verified; risks INV reset-in-place stall. |
| 9 | `4a4f12f3` | 06-26 18:25 | C | **Reverted #8** | **Current container HEAD.** Memory: *"do NOT reintroduce brunoBelowMenuBar."* |

Net: #1–#3 oscillated UP↔L/R on the hero; #4–#9 fixed container geometry (A) but never the hero's
sink (B). The threads never converged because **the remaining fix must land in the hero (B)** — and
(A) is already done.

### 4. Invariants any fix must preserve (each broke in a prior attempt)

**Must achieve:** UP escapes hero → bar (Home) / cover bar or pop (covers); DOWN escapes → first
shelf (Home) / chip row (Kids); Select still opens detail (`BrunoHeroView.swift:71`).

**Must preserve:**
1. **L/R spotlight paging on the hero** — `step(by:)` `withAnimation(.easeInOut(0.45))`, modulo-wrap.
   The exact feel `92a2e11e`/`4a4f12f3` were created to protect. **Must keep CLICK paging, not just swipe.**
2. **Auto-advance pause-while-focused** — gated on the Button's `@FocusState isFocused`
   (`BrunoHeroView.swift:87-92`, `:59/:76`); same Bool drives Play-pill brightening. A focus-perturbing
   sibling makes auto-advance not pause + pill not brighten.
3. **Back-to-Top `homeFocus/.hero` anchor** — `.focused($homeFocus, equals: .hero)` is on the
   **wrapper** (`BrunoHomeView.swift:146`), not the inner Button; drives cold-launch (`:109`) + Back-to-Top
   (`:193`, `BrunoCategoryShelves.swift:323`). Needs **exactly one unambiguous hero focusable**.
4. **Bar bridge for BOTH root and cover** — root `MainTabView.swift:117-154`; cover
   `BrunoHeroMenuBar.swift:42-74` (*"Menu dismisses"* `:23,47`).
5. **Perf invariants** — no conditional view insertion on focus (INV reset-in-place stall,
   `BRUNO_PERF_INVARIANTS.md:170-172`) — part of why `ceba7e18` failed.
6. **Kids-cover DOWN must not auto-commit** — chip row is `selectsOnFocus:true` + `defaultFocus`
   (`BrunoKidsView.swift:186,198`). Today DOWN is *consumed*; freeing it commits a filter on focus-land.
7. **Accessibility** — dots are `.accessibilityHidden(true)` (`:~204`); `reduceMotion` disables
   auto-advance (`:90`), so manual paging is the *only* spotlight control for those users. VoiceOver
   consumes swipes before app recognizers (argues against a swipe-only input).

### 5. Design space (verified; myths flagged)

- **(a) Remove `.onMoveCommand`; L/R via transparent `UIViewRepresentable` + `UISwipeGestureRecognizer`.**
  Keeps L/R (swipe only), frees UP/DOWN. **Refuted by all 3 adversarial passes as the *base*:** swipe ≠
  click (drops click paging, invariant #1), axis arbitration can eat diagonal-up swipes, VoiceOver
  shadows swipes, and placement/focusability are unstated conditionals (FM1–FM5). Good as an *additive*
  layer, not the base.
- **(b) `UIView.pressesBegan(_:with:)` override — handle `.leftArrow/.rightArrow`, call `super` for
  `.upArrow/.downArrow/.select`.** Keeps L/R **including click**, frees UP/DOWN via **affirmative
  super-forward**. **This is the project tracker's own specified fix.** Risk: medium; `pressesBegan` can
  fire after focus moves → may need a `GCController.microGamepad.dpad` supplement; device-only to settle.
- **(c) Keep `.onMoveCommand` + `UIFocusGuide`/`preferredFocusEnvironments`/imperative `@FocusState`.**
  **MYTH** — the guide never runs because the command is already consumed; `preferredFocusEnvironments`
  governs focus *reset*, not traversal. Don't.
- **(d) Paging via focusable dots / separate control.** Frees UP/DOWN but **abandons the product model**
  (single chrome-less hero; passive dots) and the "page while the hero holds focus" feel. Fails invariant #1.
- **(e) SwiftUI-native reshuffles (outer focusSection, sibling, conditional/parent onMoveCommand).**
  **MYTHS, disproven by #4–#9** — `.onMoveCommand` consumes wherever it lives; no SwiftUI "handle L/R but
  decline UP/DOWN" API exists.

**Bug 2 (right-edge) levers:** (1) **focus guide / aligned sentinel at the bar's trailing edge** that
absorbs (or wraps to Search) horizontal moves — surgical, no harm to hero L/R or UP-to-bar
[**recommended**]; (2) shrink the hero's *focusable* frame so it isn't a magnet — but risks UP if the
hero frame stops overlapping the bar capsule; (3) decompose the hero — fights L/R. **`preferredFocusEnvironments`
as a directional blocker is a myth** (it only sets focus on entry).

### 6. Recommended resolution path

**Primary: option (b)** — the `pressesBegan` super-forward override — restores L/R (click + swipe)
and frees UP/DOWN, satisfying precondition (B); `b891c6ee` already satisfies (A). Layer (a)'s swipe
recognizer *on top* only if analog-swipe feel is wanted (sharing one non-focusable, non-hit-stealing
representable). **For Bug 2, add a trailing-edge focus guide on the bar** so RIGHT-past-Settings
absorbs/wraps instead of falling into the hero. The two fixes are independent and complementary.

**Hard mitigations (from the adversarial passes — bake into implementation):** representable must be
**`canBecomeFocused = false`** and non-hit-test-stealing; **keep `.focused($homeFocus,equals:.hero)` on
the existing wrapper** (don't fold the Button's tap into the representable → would strand Back-to-Top);
verify `isFocused` still reads true (auto-advance pause); decide Kids-DOWN auto-commit (gate via the
existing `didEnterChipRow`); decide cover UP = reach-bar-vs-pop.

> Note: this §6 path documents the **option (b) / keep-paging** resolution that the deep dive
> recommended. The owner subsequently chose the **un-pin-the-bar** resolution captured in
> "Resolution being implemented" above, which makes UP-to-bar a normal vertical move and drops manual
> L/R paging. Both are recorded; the un-pin path is the one being implemented.

### 7. Open questions (device / product)

- **Q1** Cover UP: reach the cover's re-created bar, or **pop** the cover? (tracker leans "Menu dismisses").
- **Q2** Kids DOWN: instant filter-commit on focus-land, or land-on-"All"-without-commit?
- **Q3** Hero paging: swipe-only acceptable, or must click L/R keep working? (decides if (a) alone is viable).
- **Q4** Does `pressesBegan` reliably beat the engine for L/R, or need the `GCController` dpad supplement?
- **Q5** Confirm FB15272007 first-press-drop doesn't manifest in the chosen path.

---

## Verification checklist

Behavior must be confirmed on a **real Apple TV + silver Siri Remote** (sim focus is unreliable; this
issue was reverted twice for landing blind — do NOT land on `main` until all pass):

1. UP from Home hero → selected menu-bar pill (or, under the un-pin resolution, the bar scrolls fully
   off on DOWN and fully back on UP).
2. DOWN → first shelf.
3. Hero still auto-rotates (~8s) when unfocused.
4. *(Path B / keep-paging only)* L/R click **and** swipe → spotlight steps.
5. Auto-advance pauses while hero focused + Play pill bright; resumes when focus leaves.
6. Back-to-Top → focus returns to hero.
7. Cold-launch → focus hands to hero, **not** a bar pill (INV-7).
8. Select opens detail.
9. Cover hero UP → decided behavior (Q1); Menu dismisses.
10. Kids hero DOWN → chip-row per Q2 (no surprise commit).
11. Settings UP still reaches the bar (unbroken).
12. *(Un-pin resolution)* hero art still reaches the physical top with no light strip / no over-spill
    crop after the `topBleed` change; tab-switching works from the scrolling bar (+ dismiss-then-select
    on covers); held-scroll doesn't stall crossing the bar row (INV-10).

**Doc acceptance:** every file:line resolves at HEAD; every timeline SHA is `git show`-able.
