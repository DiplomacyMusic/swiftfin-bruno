# Bruno tvOS — Hero reference (layout + up-nav focus model)

> Status: ACTIVE — hero layout numbers + up-nav focus model.

The one doc to open before touching the hero / menu / shelf region. A **map, not a plan** — it
describes `main` as it is now, which layers are load-bearing, and what every magic number controls.
Two concerns: **Layout** (fragile constants) and the **Up-nav focus model** (root cause + invariants
any edit must preserve). The up-nav focus trap is **RESOLVED** (menu bar is now an un-pinned scrolling
row); not an open saga, do not re-derive it.

**Primary files:**
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeView.swift` — scroll composition + BRUNO wordmark.
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoHeroView.swift` — hero card (heights, scrims, backdrop).
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoScrollingMenuBar.swift` + `BrunoMenuBar.swift` — the menu row.
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoHeroWordmark.swift` — the shared BRUNO wordmark overlay.

The same structure is reused by the other hero-bleed surfaces — `BrunoKidsView`, `BrunoMediaView`,
`BrunoCategoryShelves` (all `LazyVStack(spacing: 36)`, menu row first, `BrunoHeroView(bleedsTop: true)`).

Companion docs: `docs/BRUNO_PERF_INVARIANTS.md` (shelf perf rules INV-1..10) · `docs/PROJECT_TRACKER.md`.

---

## Layout

### Vertical stack, physical top → down (Home)

Everything lives in `BrunoHomeView.content`: `ScrollView { LazyVStack(alignment: .leading, spacing: 36) }`.
`BrunoHomeView` applies `.ignoresSafeArea(edges: [.horizontal, .bottom])` — **top is NOT ignored**,
so scroll content begins at the tvOS top safe-area inset.

| Order | Thing | Height / position | Notes |
|---|---|---|---|
| — | top safe-area inset (`insets.top`, ~60pt) | reserved | scroll content starts below it |
| Row 1 | `BrunoScrollingMenuBar()` | `barHeight = 116` (fixed) | `.zIndex(1)` so it paints **over** the hero's upward backdrop spill |
| gap | `LazyVStack` row spacing | `36` | applies between every row |
| Row 2 | `BrunoHeroView(bleedsTop: true, extraHeight: 160)` + BRUNO wordmark overlay | `layoutHeight ≈ 730` | `.id("bruno-top")`, `.focused($homeFocus, equals: .hero)` |
| gap | row spacing | `36` | |
| Row 3+ | `ForEach(sections)` shelves → window-grow sentinel → appendExplore sentinel → terminal footer | per shelf | `.padding(.bottom, 60)` on the stack |

The hero is the natural first-focus element (INV-7). The menu bar sits **above** it and the first
shelf **below** it; UP/DOWN move between them (now plain vertical scroll moves — see Up-nav model).

### The hero's three height knobs (`BrunoHeroView.heroCard`)

```
let topBleed     = bleedsTop ? insets.top + BrunoMenuBar.barHeight + 36 : 0   // = insets.top + 116 + 36
let layoutHeight = (720 + extraHeight) * 0.83          // all tabs: extraHeight 160 → 880×0.83 ≈ 730
let visualHeight = layoutHeight + topBleed
```

The `×0.83` runs every tab's hero **17% shorter** than its natural height so the first shelf always
peeks (and the bottom-pinned title block sits closer to the menu). Safe for the top-bleed:
`layoutHeight` cancels in the backdrop-top math, so the art still reaches the physical top.

- **`layoutHeight`** — the **only** height the parent `LazyVStack` measures; alone fixes the hero's
  bottom edge and where the first shelf sits. `extraHeight` grows it downward (restoring the space the
  wordmark vacated as an overlay, showing more backdrop).
- **`visualHeight`** — how tall the backdrop **draws**. Lives in `.background` (never measured by the
  parent), bottom-pinned to the layout box, so its surplus over `layoutHeight` (= `topBleed`) spills
  **upward** behind the menu bar, landing the art's true top at the physical screen top.
- **`topBleed`** — the upward spill; must equal the full distance from the hero's layout-box top to
  the physical top: `insets.top` (safe area) `+ barHeight` (menu row) `+ 36` (row spacing between
  them). All three terms required; dropping any one leaves a lighter strip above the hero (the
  historic "dimmer-short-of-top" bug). The `+36` was the last missing term (fixed 2026-06-27).
- **`imageAnchor` = `.top`** — which slice of the over-tall fill survives the crop (`.top` keeps the
  source's true top so subjects sit clear of the nav).

### The two scrims — where they live and why

Exactly **two** gradients. They live in **different boxes on purpose.**

**3a. Left scrim — on the BACKDROP box (`visualHeight`).** `BrunoHeroView.swift`, inside
`.background { … }.overlay { … }`:
```
LinearGradient(colors: [page.opacity(0.96), page.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
```
- Purpose: legibility for the left-aligned title/meta/buttons.
- Why on the backdrop box: so its top edge reaches the **physical top with the art**, covering the
  strip that bleeds up behind the menu. Move it into the front `layoutHeight` ZStack and its top edge
  sits **below the menu** → a bright band behind the nav with a hard horizontal seam.

**3b. Bottom darkening scrim — in the FRONT ZStack (`layoutHeight`) — ⚠ LOAD-BEARING.**
`BrunoHeroView.swift`, first child of `ZStack(alignment: .bottomLeading)`:
```
LinearGradient(colors: [page, .clear], startPoint: .bottom, endPoint: .center)
```
- Purpose (visual): darkens the lower half so the copy block reads; fades to clear by center so the
  top half stays as art.
- **⚠ LOAD-BEARING FOR LAYOUT — do not remove.** Empirically (clean A/B on 2026-06-27), removing it
  pushed the first shelf **off-screen** when the hero is focused; restoring it put the shelf right
  back under the hero. A `LinearGradient` is a *greedy* layout view (fills its proposal), and the
  hero's effective height depends on it being present in the front ZStack — the explicit
  `.frame(height: layoutHeight)` does **not** fully pin it on its own here. The precise mechanism is
  unconfirmed; the dependency is real. If you change the front ZStack's children, rebuild and verify
  the first shelf sits directly below the hero with the hero focused.

### The BRUNO wordmark (shared overlay, not a row)

Lives in `BrunoHeroWordmark.swift`, applied on the `BrunoHeroView` of **every** hero-bleed tab
(Home / Collections / Movies / TV / Kids) via `.brunoHeroWordmark(showBuildStamp:)` — so the brand
sits identically on all of them. Only Home passes `showBuildStamp: true` (a temporary diagnostic).

```
func brunoHeroWordmark(showBuildStamp: Bool = false) -> some View {
    overlay(alignment: .top) {
        BrunoHeroWordmark(showBuildStamp: showBuildStamp)
            .padding(.horizontal, 50)
            .padding(.top, -(BrunoMenuBar.barHeight + 36) + (BrunoMenuBar.barHeight - 48) / 2 - 10)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
```
`BrunoHeroWordmark` = `HStack { "BRUNO" (brunoDisplay 40, bold, tracking 6) · accent dot (12pt)
[· Spacer · buildStamp] }`. The overlay is top-aligned to the hero frame, whose top is `barHeight + 36`
**below** the menu bar; the top inset lifts the wordmark back up onto the bar's centerline:

| Term | Value | What it does |
|---|---|---|
| `-(barHeight + 36)` | −152 | raise by the hero's drop below the bar (bar height + row spacing) |
| `+(barHeight - 48)/2` | +34 | re-center within the bar (`48` ≈ wordmark cap height) |
| `-10` | −10 | hand-tuned visual nudge up |
| **total** | **−128** | wordmark vertical inset |

If BRUNO sits high/low, tune the **`-10`** (more negative = higher) or the **`48`** (larger = lower).
It's an `.overlay`, so it never affects sibling layout; one edit moves it on every tab.

### Menu bar internals (`BrunoMenuBar` / `BrunoScrollingMenuBar`)

- `BrunoScrollingMenuBar` wraps `BrunoMenuBar`, applies `.frame(height: BrunoMenuBar.barHeight)`
  (**INV-1: fixed height, independent of focus/content**) and `.focusSection()`. It does **not** set
  `.zIndex` — the call site does (`.zIndex(1)`), so the bar paints over the hero's upward spill.
- `BrunoMenuBar.barHeight = 116`. Must stay ≥ the bar's intrinsic height (~108pt). Read in **two**
  places that must agree: the row's own `.frame(height:)` and the hero's `topBleed`. Change it in one
  and the hero's top-bleed math drifts.
- Pills are a floating dark-glass capsule (`.black.opacity(0.4)` + `.ultraThinMaterial`), with
  `.padding(.top, 8)` / `.padding(.bottom, 14)` inside the 116 row — so the hero backdrop reads
  through the strip above and around the capsule.

### Magic-number index

| Constant | Where | Controls | Coupled to |
|---|---|---|---|
| `720` | `BrunoHeroView` layoutHeight base | hero base height | — |
| `×0.83` | `BrunoHeroView` layoutHeight | shrinks every tab's hero 17% so shelves peek | all hero-bleed tabs |
| `extraHeight: 160` | every tab's hero call | grows hero down; shelf position; backdrop reveal | all tabs use 160 → equal hero height |
| `barHeight = 116` | `BrunoMenuBar` | menu row height **and** `topBleed` | both must use the same value |
| `36` | `LazyVStack(spacing:)` (all tabs) | row gaps; `topBleed`; wordmark offset | duplicated as a literal in `topBleed` + wordmark offset |
| `insets.top` | safe area | `topBleed`; title-safe insets | tvOS overscan |
| wordmark inset `−128` | `BrunoHeroWordmark.swift` (shared) | BRUNO vertical position | `barHeight`, `36`, cap-height `48`, nudge `−10` |
| left scrim `0.96 → 0.1` | backdrop overlay | left legibility wash | — |
| bottom scrim `page → clear` (bottom→center) | front ZStack | lower legibility **+ hero height** (3b) | load-bearing |
| `50` / `600` / `50` | hero content paddings | leading (title-safe) / trailing / bottom of copy | `50` matches wordmark leading |
| `.padding(.bottom, 60)` | `LazyVStack` | space below the last row | — |

### If you change this region — checklist

1. **Never delete the bottom darkening scrim** (3b) without rebuilding and confirming the first shelf
   sits directly under the focused hero. Load-bearing for height, not just paint.
2. **Keep the left scrim on the backdrop box** (`visualHeight`), not the front box — else the seam returns.
3. **`topBleed` must stay `insets.top + barHeight + 36`** — all three terms. Verify the art reaches
   the physical top (no lighter strip above it) after any change.
4. **`barHeight` is read twice** (menu row + `topBleed`) — change both meanings together.
5. The wordmark offset is an **overlay** inset; tune it freely, it moves nothing else.
6. Heights are explicit (`720 + extraHeight`), not intrinsic — if shelves jump, suspect a *greedy view*
   added/removed from the front ZStack before suspecting the height literal.

---

## Up-nav focus model

> **Status: RESOLVED** (pending only an on-device confirm). The menu bar is now an **un-pinned
> scrolling row**; UP from the hero reaches the bar as a normal vertical move. Per
> `docs/FEATURE_BACKLOG.md` B1 this is **MOOT — verify & close**; do not re-open it as a saga.

### Root cause (the durable finding)

The hero was **one chrome-less focusable `Button`** carrying `.onMoveCommand` for left/right spotlight
paging. `.onMoveCommand(perform:)` is **not** an observer — it is a **consuming sink** into UIKit's
move-command responder chain for **all four** directions (closure is `(MoveCommandDirection) -> Void`:
no return, no decline; a `default: break` still counts as *handled*). So UP was consumed and the focus
engine never evaluated the bar neighbor → UP could not escape the hero. (The right-edge fall-through
was the same root in the other axis: a pinned pill row with no focus wall plus a screen-spanning hero
frame that won the geometric search.)

### Resolution (what landed)

The menu bar is **no longer pinned**. It is now the **first scrolling row** of each tab's
`LazyVStack` (`BrunoScrollingMenuBar`), so it scrolls up and off-screen on DOWN and reappears at the
top — like every other row. The old pinned `ZStack(.top)` peer + `Color.clear` barHeight inset were
removed, and the hero dropped `.onMoveCommand`. With one focusable per vertical region, **UP/DOWN are
plain vertical moves** and the trap is architecturally dissolved.

- Menu bar un-pinned: `4a721438`. Hero `.onMoveCommand` dropped: `e94e07fd`.
- The hero's backdrop still reaches the physical top via the existing `topBleed` bleed (see Layout).
- Manual click L/R hero paging was intentionally dropped with this resolution; auto-advance still
  rotates.

### Invariants any edit must preserve

An edit to this region must keep **left/right spotlight stepping working AND let Up escape upward** —
both, simultaneously (every past attempt broke one to fix the other). Concretely:

- **INV-1** — the bar row stays **fixed-height** (`barHeight`); no focus-driven height change.
- **INV-7** — cold-launch focus lands on the **hero, not a bar pill**; keep first-focus /
  `.focused($homeFocus, equals: .hero)` on the hero wrapper (`BrunoHomeView`). Device-verify.
- **INV-10** — the bar row tree stays constant across focus (opacity/scale only); no conditional view
  insertion on focus (re-introduces the focus-stall freeze).
- Keep `bleedsTop: true` so the hero art reaches the physical top.
- Keep **exactly one unambiguous hero focusable** — the `homeFocus/.hero` anchor drives cold-launch
  and Back-to-Top; splitting or duplicating it strands those.
- Do **not** re-pin the bar or re-add `.onMoveCommand` to the hero — that reverts the resolution.

### On-device confirm (the only remaining step)

Verify on a **real Apple TV + Siri Remote** (sim focus is unreliable): on DOWN the bar scrolls fully
off and on UP fully back; DOWN reaches the first shelf; cold-launch hands focus to the hero, not a
pill (INV-7); hero art still reaches the physical top (no light strip / no over-spill crop) after the
`topBleed` math; tab-switching works from the scrolling bar; held-scroll doesn't stall crossing the
bar row (INV-10).
