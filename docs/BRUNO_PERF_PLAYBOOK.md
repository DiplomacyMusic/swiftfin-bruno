# Bruno scroll/focus perf — diagnose & fix playbook

> Status: ACTIVE — the held-scroll FREEZE fix LANDED on `main` (`24ee9372`, codified as **INV-10**).
> One outstanding item: an on-device re-record to confirm the freeze is gone (sim focus is
> unrepresentative). This is the START-HERE doc for any Bruno scroll/focus perf work. It merges the
> old `BRUNO_STALL_HANDBOOK` / `BRUNO_PERF_HANDOFF` / `BRUNO_PERF_LOGGING` into one. INV-1..10 live
> separately in `docs/BRUNO_PERF_INVARIANTS.md` — referenced here, not restated.

---

## 0. The framing — it's a FREEZE, not a hitch

The felt problem — "I hold Up/Down, focus moves ~3–12 rows, then **freezes with my finger still down
and never recovers until I release and press-and-hold again**" — is the **tvOS focus engine dropping
the press-and-hold auto-repeat**, NOT a slow frame. A render hitch recovers on the next frame; this
does not recover at all while held. **Only the held direction freezes** (other directions still move),
on **both Home and Movies** (shared poster-cell path). Classify the symptom class (focus vs render)
**before** optimizing anything: *does it recover on its own (render) or only on release+re-press
(focus)?* Render cost is real but secondary — seven-plus prior threads chased it; don't repeat that.

---

## 1. Root cause + fix (LANDED)

| | |
|---|---|
| **Cause** | `FocusShadowPoster` swapped the focused cell's subtree on focus change via a `_ConditionalContent` branch (`if isFocused { content.posterShadow() } else { content }`). On the bridged self-sizing `UICollectionView` cell, toggling `isFocused` changes the focused subtree mid-focus-update → the focus engine **resets-in-place and gates off the directional auto-repeat**. It is the **shared** poster cell (every Home shelf + every non-art Movies cell); reintroduced in `fdc812fc`, two days after `86acd5f5` removed the same pattern from `BrunoFocusArtCycle`. |
| **Fix** | Keep the shadow modifier always in the tree; gate only its **opacity**. Same visual (focus-only shadow), no subtree branch. `posterShadow()` == `shadow(radius:4, y:2)`. |
| **Commit** | `24ee9372` — "make FocusShadowPoster structurally stable (INV-10)", on `main`. |
| **Anchor** | `Swiftfin tvOS/Components/PosterButton.swift:73-93` (`FocusShadowPoster`, `// INV-10`). The shadow line: `.shadow(color: Color(.sRGBLinear, white: 0, opacity: isFocused ? 0.33 : 0), radius: 4, y: 2)`. |
| **Rule** | Codified as **INV-10** (structural stability) — see `docs/BRUNO_PERF_INVARIANTS.md`. Do not restate the INV here. |
| **Non-additive note** | Edits `PosterButton.swift` (upstream-Swiftfin, a rare non-Bruno-owned edit). |
| **Outstanding** | On-device re-record of a held Up/Down scroll on Home + Movies to confirm the freeze rate dropped to ~0. Sim focus behavior is unrepresentative — this verification is still pending. |

### If the freeze survives the fix — `swift-xcode-expert` ranked fallback causes
1. **Next `LazyVStack` row not realized at repeat time** → directional search finds a zero-/unlaid-out frame → move rejected → repeat gates off. (Apple: the engine skips zero-frame items.) Fix: rely on the fixed shelf-row height (INV-1) so geometry exists before content lays out; increase realization lead; or bridge adjacent shelves with `UIFocusGuide`/`focusSection()`.
2. **`reload(using:)` on the focused row mid-repeat** (fork `UICollectionHStack.update` → `reload(using:)` runs on every `updateUIView`). Fix: only reload on a real id delta (`newIDs != currentElementIDHashes`); don't reload off-axis rows during a held move.
3. **`rootView` swap under the focused cell** (fork `HostingCollectionViewCell.setup(view:)`) mutates focused-subtree identity. Fix: don't swap `rootView` on a cell on the current focus path.
4. **`size.didSet → invalidateLayout` (async)** on the focused row → transient stale frames → rejection. Fix: elide invalidation when row geometry is unchanged (INV-1 fixed height makes most of these no-ops).
5. `preferredFocusEnvironments` churn (low; fork sets none).

### Suspect map (shared path, file:line)
- **#1** `FocusShadowPoster` — `Swiftfin tvOS/Components/PosterButton.swift:73-93` (the landed fix).
- **#2** focused-row re-eval → `CollectionHStack.updateUIView` → `reload(using:)` (fork `UICollectionHStack.swift:~434`).
- **#3** `visibleShelfCount` grow mutating the `LazyVStack` `ForEach` (`BrunoCategoryShelves.swift:306-310`, `BrunoHomeView.swift:163-167`).
- **#4** per-row `.focusSection()` boundaries resolving `preferredFocusEnvironments` back into the current section.

---

## 2. Measurement protocol

Capture is **human-in-the-loop** — the owner drives the sim/device and records; the agent analyzes the
logs. (Self-driving the sim is unreliable: auto-login SIGTRAP when the home server is unreachable, flaky
nav.) Baseline → change ONE thing → re-measure; every change ships with a measured before/after delta.

1. Build `main` for the sim or device. In a fresh worktree, `ln -s <repo>/Carthage Carthage` first if the build complains about a missing TVVLCKit xcframework (Carthage is gitignored). Headless verify: tvOS sim, `CODE_SIGNING_ALLOWED=NO -skipMacroValidation`.
2. Settings → **Debug Overlays** → enable **FPS**, **NAV/LAYOUT**, **LOG (Event log)**, and **Perf logging → disk**. (First three = the visible HUD; the fourth writes the `.jsonl`. The FRAME panel shows `PERF ● <filename>` when logging is on.)
3. Saturate caches (scroll Movies to the bottom and back), then do the held / repeated up-scroll you want to measure. Discrete up-presses populate the same per-step `drag` log — a continuous hold isn't required, but **is** required to reproduce the freeze itself.
4. Pull the logs (see §4) → `PerfLogs/session-*.jsonl`.
5. Analyze and correlate with the recording via the shared `t`/`f` clock (§4).

**Constraints that hold:** no UX/design changes (brand shadow, focus art-cycle, reveal cadence, card
geometry); honor INV-1..10 and the F1–F9 map in `BRUNO_MOVIES_GENRE_SURFACE.md` (esp. **F5: no explicit
`init`** on `BrunoCategoryShelves`/`BrunoShelfRow`/`BrunoGenresView`).

### `/usr/bin/sample` — symbolicated CPU call tree (use this, not `xctrace`)
`xctrace export` returns **raw addresses (no symbols)** — don't waste time on it. `/usr/bin/sample`
attaches to the host sim process and emits a fully symbolicated tree with `file:line`.
```bash
PID=$(pgrep -f "Swiftfin tvOS.app/Swiftfin tvOS" | head -1)
/usr/bin/sample "$PID" 30 -file run.txt          # 30 s, 1 ms sampling
```
Analyze the **Main Thread** block: self-time per symbol (node count − sum of immediate children); treat
`mach_msg2_trap`/`kevent`/`__psynch`/`semaphore_wait` as idle, the rest busy. Attribute hot framework
leaves (CFStringHash, AttributeGraph, …) up to the nearest `Swiftfin tvOS.debug.dylib` caller to find
the responsible app code. **Caveat:** `sample` aggregates, so it under-weights brief periodic spikes (a
grow, a single focus reset) — great for steady-state cost, poor for the freeze itself. For the freeze,
use the freeze-while-held metric + focus diagnostics below.

### The FREEZE-WHILE-HELD metric (the key diagnostic — the regression target)
For each `input` `up` with `holdMs`, the held span is `[up.t − holdMs/1000, up.t]`. Count `frame`(drag)
events inside it; the **tail-gap** = `up.t − last_step.t`. A span with tail-gap > ~0.6 s =
**frozen-while-held** (held, but focus stopped advancing). Report the % of held spans (>0.6 s) that are
frozen. **Pre-fix baseline: 56% Movies / 25% Home** (worst single case: Home held 7001 ms, 12 steps,
then frozen 4.7 s). Goal: drive toward 0. (~30 lines of Python over the JSONL; re-derive from the §4
schema.)

### Focus-engine diagnostics (names the rejection cause instead of inferring it)
Add (DEBUG, tvOS, near launch) to capture *why* the move was rejected at the freeze instant:
```swift
#if DEBUG
NotificationCenter.default.addObserver(forName: UIFocusSystem.movementDidFailNotification,
                                        object: nil, queue: .main) { note in
    let ctx = note.userInfo?[UIFocusSystem.focusUpdateContextUserInfoKey] as? UIFocusUpdateContext
    print("FOCUS-FAIL heading=\(String(describing: ctx?.focusHeading)) from=\(String(describing: ctx?.previouslyFocusedItem))")
    if let f = UIScreen.main.focusSystem?.focusedItem { print(UIFocusDebugger.checkFocusability(for: f)) }
}
#endif
```
At the moment it's frozen, from lldb:
```
(lldb) e -l swift -- import UIKit
(lldb) po UIFocusDebugger.status()
(lldb) po UIFocusDebugger.checkFocusability(for: UIScreen.main.focusSystem!.focusedItem!)
(lldb) po UIFocusDebugger.simulateFocusUpdateRequest(from: UIScreen.main.focusSystem!.focusedItem!)
```
Plus the engine's own log:
`xcrun simctl spawn booted log stream --predicate 'category CONTAINS[c] "focus"' --style compact`.
**Interpretation:** "no focusable item found in heading" → fallback cause #1 (zero-frame/unrealized next
row); candidate exists but focusability fails / identity just changed → cause #2/#3 (reload or
rootView-swap under focus).

---

## 3. RULED OUT / declined — do NOT re-chase (each measured or grounded)

| lever | verdict |
|---|---|
| `UIHostingController` minting / the `bruno-hosting-reuse` fork reuse | `UIHostingController.init` was **5 samples** in a 15 s scroll. Irrelevant to render cost and to the freeze. |
| "Heavy `BrunoLabelArtCard`" cell | Scrolled genre cells are `PosterButton`; `BrunoLabelArtCard` is the tile-picker, **0 samples** in the scroll. |
| The shelf-window grow (`visibleShelfCount += 4`) | Does NOT correlate with the freeze (every frozen span had `grow_near=False`). Real but minor render batch, separate from the freeze. |
| The focus art-cycle (`BrunoFocusArtCycle`) | Already structurally stable in `86acd5f5`; the freeze also hits Home, which has no art-cycle. |
| `posterStyle(.portrait)` as a cell cost | Adds **no** shadow/corner on tvOS — not a cost. |
| Brand shadow on browse | Declined on UX/brand grounds (and moot — no tvOS shadow on the genre cell). |
| `.hoverEffect` removal | Deferred on unverified focus-appearance risk. |
| Item-level pop-in | Declined UX change. |
| `drawingGroup()` on cells | Functional — breaks focus. |
| `dataPrefix` tuning | Measured-ineffective (already `== cards.count`). |

If a **profile** later proves one of the *unmeasured* declined UX levers is the dominant cost, bring the
data to the owner — don't unilaterally reattempt, don't treat them as eternally sacred.

**Stop condition:** if, after the above, the per-row `drag` floor persists and the call tree attributes
it to irreducible per-content SwiftUI graph building, **stop and surface to the owner** that the only
remaining fix is the `bebdfe30` UIKit-drawn-cell rewrite (multi-week, highest risk).

---

## 4. Telemetry — `BrunoPerfLog` on-disk JSONL (DEBUG only)

Writes one JSON object per event to a `.jsonl`, sharing the on-screen HUD's clock so every event aligns
to a screen recording. Source of truth: `Shared/Objects/Bruno/BrunoPerfLog.swift` (commits `7000d763`,
`47b51f12`, `1df5a932`).

### Pull command
The session file lives at `<app container>/Library/Caches/BrunoPerf/session-<yyyyMMdd-HHmmss>.jsonl`.
**The bundle id is `com.diplomacymusic.bruno`** — NOT `org.jellyfin.swiftfin`.
`Scripts/bruno-pull-perf.command` historically hard-coded the wrong id and silently found nothing —
verify the id, or pull manually:
```bash
SIM=$(xcrun simctl list devices booted | grep -oE '[0-9A-F-]{36}' | head -1)
C=$(xcrun simctl get_app_container "$SIM" com.diplomacymusic.bruno data)
cp -p "$C/Library/Caches/BrunoPerf/"*.jsonl ./PerfLogs/   # PerfLogs/ is gitignored
```

### Line schema
Every line is one JSON object. **Always present:** `t` (exact seconds since the frame monitor started,
`CACurrentMediaTime() − startTime`, per-event precision), `f` (display frame index, ~4 Hz, coarser),
`kind`.

| `kind` | when | payload keys |
|---|---|---|
| `session` | file header (once) | `bundleID, version, build, device, systemName, systemVersion, screenW, screenH, scale, wallClock` |
| `input` | remote press down/up | `phase` (`down`/`up`), `button` (`up`/`down`/`left`/`right`/`select`/`menu`/`playPause`/`other`), `holdMs` (on `up`) |
| `mem` | ~1 Hz | `footprintMB` (phys_footprint) |
| `fps` | ~4 Hz | `fps`, `frameMs`, `worstMs`, `hitchCount` |
| `counts` | ~1 Hz | `shelves` (mounted = `visibleShelfCount`), `cells` (live cell-content views, both surfaces) |
| `hosts` | ~1 Hz | `mints`, `reuseSwaps`, `prepareForReuse` (fork hosting-controller reuse DEBUG counters) |
| `load` | content fetch/prefetch | `what` (`getitems`/`prefetch`), `phase` (`start`/`end`), `parent`, `count`, `ms` |
| `conflict` | INV-1 height drift | `site`, `measured`, `expected`, `delta` (row height deviating > 1pt from the pinned `BrunoShelfMetrics` value) |
| `nav` / `layout` / `frame` / `info` | tee of the HUD LOG lane | `text` (the HUD line, e.g. `"drag 150ms →#0042 +40ms · 8f · f1234"`, `"shelf:Comedy Δy +26"`), `id` (HUD `#NNNN`) |

The `nav`/`layout`/`frame` lines carry numbers inside `text` (pre-formatted HUD strings — parse them);
the richer kinds are structured fields.

### What each signal answers
- **`input` + `nav`(focus) → the held-scroll question.** A `down` with no matching `up` for a long span = held remote. Count focus moves between that `down` and its `up`. If moves *stop* while still held → **stall-while-held** (the regression class fixed by `24ee9372`).
- **`frame` (`drag Nms · Mf`) → per-focus-step cost.** The headline hitch metric; lower `ms`/`f` = smoother.
- **`hosts` → is reuse working?** After warm-up, `reuseSwaps` should climb far faster than `mints`.
- **`counts` → realized-view pressure.** Spikes correlate with grow events / hitches.
- **`conflict` → INV-1 leaks.** Any line = a row's height renegotiating; ideally never fires.
- **`load` → what's loading during a hitch.** `mem` → leaks/pressure. `fps` → settled vs scrolling.

### Correlating with a video
The HUD's FRAME panel renders `f<n> · t <secs>` on-screen — the **same** `f`/`t` in the JSONL. Read the
HUD's `t` at a moment in the recording, find the JSONL lines around that `t`. The `session` header's
`wallClock` (ISO8601) + the recording filename give a coarse anchor; `t` is the precise one (prefer `t`,
it's exact per-event; `f` is ~4 Hz).

### Extending it (DEBUG)
```swift
#if DEBUG
if BrunoPerfLog.isEnabled {
    BrunoPerfLog.event("yourKind", ["key": value])   // value: String/Int/Double/Bool
}
#endif
```
`t`/`f`/`kind` are auto-added (don't set them). Gate hot-path calls with `isEnabled`. For ~1 Hz
samplers, add to the throttled block in `BrunoFrameMonitor.tick` next to `mem`/`counts`/`hosts`. Keep
everything `#if DEBUG` and release-inert.

### Gotchas
- **DEBUG only** — none of this compiles into Release; the Settings toggle only appears in DEBUG.
- **`GCController` is blind to the sim remote** — input capture uses a non-consuming `UIWindow.sendEvent` swizzle (works for sim keyboard/Remote app AND a real Siri Remote).
- **`Caches/` is purgeable** — pull sessions promptly; don't expect them to survive a reboot/disk pressure.
- **No size cap / rotation** — a long session grows unbounded. Pull + delete between runs.

---

## 5. Modifying the CollectionHStack fork

The cell-reuse package is forked: **`DiplomacyMusic/CollectionHStack@bruno-hosting-reuse`**, pinned at
revision `f6b6a3e2` in `Swiftfin.xcodeproj/.../swiftpm/Package.resolved`. The patch keeps each cell's
`UIHostingController` alive across reuse and swaps `rootView` instead of re-minting per `cellForItemAt`.

The SPM checkout under
`~/Library/Developer/Xcode/DerivedData/Swiftfin-*/SourcePackages/checkouts/CollectionHStack` is
**read-only** — editing it there won't stick. To change the fork:
1. Clone the repo, edit on the `bruno-hosting-reuse` branch, commit, and push.
2. Bump the `revision` for `collectionhstack` in `Package.resolved` to the new commit.
3. In Xcode: **File → Packages → Reset Package Caches** (then resolve) so it picks up the new revision.
4. Rebuild and re-measure (§2).

Key fork files: `HostingCollectionViewCell.swift` (rootView-swap reuse + DEBUG `CollectionHStackPerfCounters`),
`UICollectionHStack.swift` (`update`/`reload`, `singleItemSize` memo, `canFocusItemAt:false`, `size.didSet` invalidate).

---

## 6. Key files

- `Swiftfin tvOS/Components/PosterButton.swift` — `FocusShadowPoster` (the fix, `:73-93`), the shared poster cell.
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoCategoryShelves.swift` — Movies scroll container, grow, `shelfItems`/`weightedPreview`.
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfRow.swift` / `BrunoShelfView.swift` — the rows (each a `CollectionHStack`), INV-1 pin.
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoFocusArtCycle.swift` — genre cell art cycle (INV-10).
- `Swiftfin tvOS/Views/BrunoHomeView/BrunoShelfMetrics.swift` — the only place to touch heights/widths.
- `Shared/Objects/Bruno/BrunoPerfLog.swift` + `BrunoDebugCore.swift` + `BrunoInputMonitor.swift` — telemetry.
- `Shared/Services/SwiftfinDefaults.swift` — Fix #1 history (`static let` keys; the same computed-`static var` anti-pattern remains on OTHER keys — convert any that show up hot).
- Fork: `DiplomacyMusic/CollectionHStack@bruno-hosting-reuse` — see §5.

## 7. Related docs & agents

- `docs/BRUNO_PERF_INVARIANTS.md` — INV-1..10 (esp. **INV-1** fixed height, **INV-10** structural stability). Authoritative; this playbook references it, never duplicates it.
- `docs/BRUNO_MOVIES_GENRE_SURFACE.md` — the F1–F9 map (esp. F5: no explicit `init`).
- `docs/BRUNO_HERO.md` — the menu-bar un-pin + hero UP-nav focus restructure (changed vertical focus traversal).
- `docs/reference/swift-reference.md` — Apple/Swift citations the focus diagnostics rely on.
- Agents (consult at the *start* of a hypothesis, in parallel, with the precise measured symptom + what's ruled out): **`swift-xcode-expert`** (focus engine / Swift / SwiftUI / Instruments, citing Apple docs) and **`bruno-expert`** (codebase map, INV compliance, prior-attempt history, tracker).
