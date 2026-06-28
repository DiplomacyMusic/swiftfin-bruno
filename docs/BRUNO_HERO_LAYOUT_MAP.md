# Bruno tvOS — Hero / menu / shelf layout map (ground truth)

Status: written 2026-06-27 from a direct read of the code on `main`. This is a **map, not a plan** —
it describes what is actually there now, which layers are load-bearing, and what every magic number
controls. The goal: stop re-deriving (and re-breaking) this region. Touch it with this open.

Companion docs:
- `docs/BRUNO_HERO_UPNAV.md` — *why* the menu bar is a scrolling row (the focus-trap resolution).
- `docs/BRUNO_PERF_INVARIANTS.md` — the shelf perf rules (INV-1..10).
- `docs/PROJECT_TRACKER.md` — project state.

Primary files:
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoHomeView.swift` — the scroll composition + BRUNO wordmark.
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoHeroView.swift` — the hero card (heights, scrims, backdrop).
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoScrollingMenuBar.swift` + `BrunoMenuBar.swift` — the menu row.

The same structure is reused by the other hero-bleed surfaces: `BrunoKidsView`, `BrunoMediaView`,
`BrunoCategoryShelves` (all `LazyVStack(spacing: 36)`, menu row first, `BrunoHeroView(bleedsTop: true)`).

---

## 1. Vertical stack, physical top → down (Home)

Everything lives in `BrunoHomeView.content`: `ScrollView { LazyVStack(alignment: .leading, spacing: 36) }`.
Note `BrunoHomeView` applies `.ignoresSafeArea(edges: [.horizontal, .bottom])` — **top is NOT ignored**,
so scroll content begins at the tvOS top safe-area inset.

| Order | Thing | Height / position | Notes |
|---|---|---|---|
| — | top safe-area inset (`insets.top`, ~60pt) | reserved | scroll content starts below it |
| Row 1 | `BrunoScrollingMenuBar()` | `barHeight = 116` (fixed) | `.zIndex(1)` so it paints **over** the hero's upward backdrop spill |
| gap | `LazyVStack` row spacing | `36` | applies between every row |
| Row 2 | `BrunoHeroView(bleedsTop: true, extraHeight: 200)` + BRUNO wordmark overlay | `layoutHeight = 920` | `.id("bruno-top")`, `.focused($homeFocus, equals: .hero)` |
| gap | row spacing | `36` | |
| Row 3+ | `ForEach(sections)` shelves → window-grow sentinel → appendExplore sentinel → terminal footer | per shelf | `.padding(.bottom, 60)` on the stack |

The hero is the natural first-focus element (INV-7). The menu bar sits **above** it and the first shelf
**below** it; UP/DOWN move between them.

---

## 2. The hero's three height knobs (`BrunoHeroView.heroCard`)

```
let topBleed     = bleedsTop ? insets.top + BrunoMenuBar.barHeight + 36 : 0   // = insets.top + 116 + 36
let layoutHeight = (720 + extraHeight) * 0.83          // Home: 920×0.83≈764 · Kids/Movies/TV: 880×0.83≈730
let visualHeight = layoutHeight + topBleed
```

The `×0.83` runs every tab's hero **17% shorter** than its natural height so the first shelf always peeks
(and the bottom-pinned title block sits closer to the menu). It's safe for the top-bleed: `layoutHeight`
cancels in the backdrop-top math (§2 bullet on `visualHeight`), so the art still reaches the physical top.

- **`layoutHeight` (920 on Home)** — the **only** height the parent `LazyVStack` measures. It alone fixes
  the hero's bottom edge and therefore where the first shelf sits. `extraHeight` (200 on Home) grows it
  downward — it restores the space the wordmark vacated when it became an overlay, and shows more backdrop.
- **`visualHeight`** — how tall the backdrop **draws**. Lives in `.background` (never measured by the
  parent), bottom-pinned to the layout box, so its surplus over `layoutHeight` (= `topBleed`) spills
  **upward** behind the menu bar, landing the art's true top at the physical screen top.
- **`topBleed`** — the upward spill. Must equal the full distance from the hero's layout-box top to the
  physical top: `insets.top` (safe area) `+ barHeight` (the menu row) `+ 36` (the row spacing between
  them). All three terms are required; dropping any one leaves a lighter strip above the hero (the
  historic "dimmer-short-of-top" bug). The `+36` was the last missing term (fixed 2026-06-27).
- **`imageAnchor` = `.top`** — which slice of the over-tall fill survives the crop (`.top` keeps the
  source's true top so subjects sit clear of the nav).

---

## 3. The two scrims — where they live and why

There are exactly **two** gradients. They live in **different boxes on purpose**.

### 3a. Left scrim — on the BACKDROP box (`visualHeight`)
`BrunoHeroView.swift`, inside `.background { … }.overlay { … }`:
```
LinearGradient(colors: [page.opacity(0.96), page.opacity(0.1)], startPoint: .leading, endPoint: .trailing)
```
- **Purpose:** legibility for the left-aligned title/meta/buttons.
- **Why on the backdrop box:** so its top edge reaches the **physical top with the art**, covering the
  strip that bleeds up behind the menu. If you move it back into the front `layoutHeight` ZStack, its top
  edge sits **below the menu** → a bright band behind the nav with a hard horizontal seam (the exact bug
  chased for hours on 2026-06-27).

### 3b. Bottom darkening scrim — in the FRONT ZStack (`layoutHeight`) — ⚠ LOAD-BEARING
`BrunoHeroView.swift`, first child of `ZStack(alignment: .bottomLeading)`:
```
LinearGradient(colors: [page, .clear], startPoint: .bottom, endPoint: .center)
```
- **Purpose (visual):** darkens the lower half so the copy block reads; fades to clear by center so the
  top half stays as art.
- **⚠ LOAD-BEARING FOR LAYOUT — do not remove.** Empirically (clean A/B on 2026-06-27: this gradient the
  only difference between two builds), removing it pushed the first shelf **off-screen** when the hero is
  focused; restoring it put the shelf right back under the hero. A `LinearGradient` is a *greedy* layout
  view (fills its proposal), and the hero's effective height depends on it being present in the front
  ZStack — the explicit `.frame(height: layoutHeight)` does **not** fully pin it on its own here.
  **The precise mechanism is not confirmed**; the dependency is. If you ever change the front ZStack's
  children, rebuild and verify the first shelf sits directly below the hero with the hero focused.

---

## 4. The BRUNO wordmark (shared overlay, not a row)

Lives in **`BrunoHeroWordmark.swift`** and is applied on the `BrunoHeroView` of **every** hero-bleed tab
(Home / Collections / Movies / TV / Kids) via the `.brunoHeroWordmark(showBuildStamp:)` modifier — so the
brand sits identically on all of them. Only Home passes `showBuildStamp: true`.

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
`BrunoHeroWordmark` = `HStack { "BRUNO" (brunoDisplay 40, bold, tracking 6) · accent dot (12pt) [· Spacer ·
buildStamp] }`. The build stamp is a **temporary diagnostic** ("which build am I looking at"), Home-only.

The overlay is top-aligned to the hero frame, whose top is `barHeight + 36` **below** the menu bar. The
top inset lifts the wordmark back up onto the bar's centerline. The offset has three parts:

| Term | Value | What it does |
|---|---|---|
| `-(barHeight + 36)` | −152 | raise by the hero's drop below the bar (bar height + row spacing) |
| `+(barHeight - 48)/2` | +34 | re-center within the bar (`48` ≈ wordmark cap height) |
| `-10` | −10 | hand-tuned visual nudge up |
| **total** | **−128** | wordmark vertical inset |

If BRUNO sits high/low, tune the **`-10`** (more negative = higher) or the **`48`** (larger = lower).
Changing it once in `BrunoHeroWordmark.swift` moves it on every tab.
Because it is an `.overlay`, this never affects sibling layout.

---

## 5. Menu bar internals (`BrunoMenuBar` / `BrunoScrollingMenuBar`)

- `BrunoScrollingMenuBar` wraps `BrunoMenuBar`, applies `.frame(height: BrunoMenuBar.barHeight)`
  (**INV-1: fixed height, independent of focus/content**) and `.focusSection()`. It does **not** set
  `.zIndex` — the call site does (`.zIndex(1)`), so the bar paints over the hero's upward spill.
- `BrunoMenuBar.barHeight = 116`. Must stay ≥ the bar's intrinsic height (~108pt). It is read in **two**
  places that must agree: the row's own `.frame(height:)` and the hero's `topBleed`. Change it in one and
  the hero's top-bleed math drifts.
- The pills are a floating dark-glass capsule (`.black.opacity(0.4)` + `.ultraThinMaterial`), with
  `.padding(.top, 8)` / `.padding(.bottom, 14)` inside the 116 row — so the hero backdrop reads through
  the strip above and around the capsule.

---

## 6. Magic-number index

| Constant | Where | Controls | Coupled to |
|---|---|---|---|
| `720` | `BrunoHeroView` layoutHeight base | hero base height | — |
| `×0.83` | `BrunoHeroView` layoutHeight | shrinks every tab's hero 17% so shelves peek | all hero-bleed tabs |
| `extraHeight: 200` | `BrunoHomeView` hero call | grows hero down; shelf position; backdrop reveal | the wordmark being an overlay |
| `barHeight = 116` | `BrunoMenuBar` | menu row height **and** `topBleed` | both must use the same value |
| `36` | `LazyVStack(spacing:)` (all tabs) | row gaps; `topBleed`; wordmark offset | duplicated as a literal in `topBleed` + wordmark offset |
| `insets.top` | safe area | `topBleed`; title-safe insets | tvOS overscan |
| wordmark inset `−128` | `BrunoHeroWordmark.swift` (shared, all tabs) | BRUNO vertical position | `barHeight`, `36`, cap-height `48`, nudge `−10` |
| left scrim `0.96 → 0.1` | backdrop overlay | left legibility wash | — |
| bottom scrim `page → clear` (bottom→center) | front ZStack | lower legibility **+ hero height** (§3b) | load-bearing |
| `50` / `600` / `50` | hero content paddings | leading (title-safe) / trailing / bottom of copy | `50` matches wordmark leading |
| `.padding(.bottom, 60)` | `LazyVStack` | space below the last row | — |

---

## 7. If you change this region — checklist

1. **Never delete the bottom darkening scrim** (§3b) without rebuilding and confirming the first shelf
   sits directly under the focused hero. It is load-bearing for height, not just paint.
2. **Keep the left scrim on the backdrop box** (`visualHeight`), not the front box — else the seam returns.
3. **`topBleed` must stay `insets.top + barHeight + 36`** — all three terms. Verify the art reaches the
   physical top (no lighter strip above it) after any change.
4. **`barHeight` is read twice** (menu row + `topBleed`) — change both meanings together.
5. The wordmark offset is an **overlay** inset; tune it freely, it moves nothing else.
6. Heights are explicit (`720 + extraHeight`), not intrinsic — if shelves jump, suspect a *greedy view*
   added/removed from the front ZStack before suspecting the height literal.
