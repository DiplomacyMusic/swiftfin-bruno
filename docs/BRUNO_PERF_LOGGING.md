# Bruno perf logging — guide

**DEBUG-only on-disk telemetry for diagnosing tvOS scroll/focus performance.** It writes one JSON
object per event to a `.jsonl` file, sharing the same clock as the on-screen debug HUD, so you can
correlate every event against a screen recording. Built 2026-06-27 (commits `7000d763`, `47b51f12`,
`1df5a932`). Source of truth: `Shared/Objects/Bruno/BrunoPerfLog.swift`.

> If you're a future thread picking up Bruno scroll/hitch work: **read this + `BRUNO_PERF_HANDOFF.md`
> + `BRUNO_PERF_INVARIANTS.md` first.** The HUD is great for a live glance; this file is how you get
> hard numbers to diff against a video.

---

## Quick start (simulator)

1. Run the app on the tvOS sim. In **Settings → Debug Overlays**, turn on **FPS**, **NAV/LAYOUT**,
   **LOG**, and **Perf logging → disk**. (The first three are the visible HUD; the fourth writes the
   `.jsonl`. The HUD's FRAME panel shows `PERF ● <filename>` when logging is on.)
2. Reproduce the scenario (e.g. saturate caches: scroll Movies to the bottom and back, then do the
   held / repeated up-scroll you want to measure). Optionally screen-record so you can align visuals.
3. Pull the logs to the repo:
   ```
   ./Scripts/bruno-pull-perf.command
   ```
   This resolves the booted sim's app container and copies
   `Library/Caches/BrunoPerf/*.jsonl` → `PerfLogs/` (gitignored). It prints what it copied.
4. Analyze `PerfLogs/session-*.jsonl` (jq, python, etc.) and correlate with the recording via the
   shared clock (see **Correlating with a video**).

The session file lives at
`<app container>/Library/Caches/BrunoPerf/session-<yyyyMMdd-HHmmss>.jsonl`; resolve the container
manually with `xcrun simctl get_app_container booted org.jellyfin.swiftfin data`.

---

## Line schema

Every line is one JSON object. **Always present:**

| key | meaning |
|---|---|
| `t` | exact seconds since the frame monitor started (`CACurrentMediaTime() - startTime`) — per-event precision |
| `f` | display frame index (HUD `f<n>`; updates ~4 Hz, coarser than `t`) |
| `kind` | event type (below) |

### Event kinds

| `kind` | when | payload keys |
|---|---|---|
| `session` | file header (once) | `bundleID, version, build, device, systemName, systemVersion, screenW, screenH, scale, wallClock` |
| `input` | remote press down/up | `phase` (`down`/`up`), `button` (`up`/`down`/`left`/`right`/`select`/`menu`/`playPause`/`other`), `holdMs` (on `up`) |
| `mem` | ~1 Hz | `footprintMB` (phys_footprint) |
| `fps` | ~4 Hz | `fps`, `frameMs`, `worstMs`, `hitchCount` |
| `counts` | ~1 Hz | `shelves` (mounted = `visibleShelfCount`), `cells` (live cell-content views, both surfaces) |
| `hosts` | ~1 Hz | `mints`, `reuseSwaps`, `prepareForReuse` (CollectionHStack hosting-controller reuse — from the fork's DEBUG counters) |
| `load` | content fetch/prefetch | `what` (`getitems`/`prefetch`), `phase` (`start`/`end`), `parent`, `count`, `ms` |
| `conflict` | INV-1 height drift | `site`, `measured`, `expected`, `delta` (a shelf row's measured height deviating > 1pt from the pinned `BrunoShelfMetrics` value — the "scroll/draw math conflict") |
| `nav` / `layout` / `frame` / `info` | tee of the HUD LOG lane | `text` (the same HUD line, e.g. `"drag 150ms →#0042 +40ms · 8f · f1234"`, `"shelf:Comedy Δy +26"`), `id` (HUD `#NNNN`) |

> The `nav`/`layout`/`frame` lines carry their numbers inside `text` (pre-formatted HUD strings —
> parse them). The richer kinds (`input`/`counts`/`hosts`/`load`/`conflict`/`mem`/`fps`) are
> structured fields.

---

## What each signal answers

- **`input` + `nav`(focus) → the held-scroll question.** A `down` with no matching `up` for a long
  span = the remote is being held. Count focus moves (`nav` `text: "focus → …"`) between that `down`
  and its `up`: "held 900 ms, advanced K rows." If focus moves *stop* while still held (no `up` yet),
  that's a **stall-while-held** (the regression class fixed in `86acd5f5`).
- **`frame` (`drag Nms · Mf`) → per-focus-step cost.** The headline hitch metric. Lower `ms`/`f` = smoother.
- **`hosts` → is reuse working?** After warm-up, `reuseSwaps` should climb far faster than `mints`.
  If `mints` keeps pace with scrolling, the hosting-controller reuse isn't engaging.
- **`counts` → realized-view pressure.** `shelves` (mounted) and `cells` (live content views). Spikes
  correlate with grow events / hitches.
- **`conflict` → INV-1 leaks.** Any line here means a shelf row's height is renegotiating (the
  original "math conflict"). Ideally this never fires.
- **`load` → what's loading during a hitch.** `getitems`/`prefetch` start/end, named by `parent`.
- **`mem` → leaks / pressure** over the session.
- **`fps` → settled vs scrolling** frame rate over time.

---

## Correlating with a video

The HUD's FRAME panel renders `f<n> · t <secs>` on-screen — the **same** `f`/`t` in the JSONL. So:
pick a moment in the recording, read the HUD's `t`, and find the JSONL lines around that `t`. The
`session` header's `wallClock` (ISO8601) + the recording's filename timestamp give a coarse anchor;
the on-screen `t`/`f` give the precise one. (`t` is exact per-event; `f` is ~4 Hz, so prefer `t`.)

Reading HUD numbers off video frames is lossy — that's the whole reason this log exists. Use the
`.jsonl` for hard numbers; use the video only to see *what the user saw*.

---

## Extending it

Add a signal from anywhere (DEBUG):
```swift
#if DEBUG
if BrunoPerfLog.isEnabled {
    BrunoPerfLog.event("yourKind", ["key": value])   // value: String/Int/Double/Bool
}
#endif
```
`t`/`f`/`kind` are added automatically (don't set them). Gate hot-path calls with `isEnabled` so the
payload dict isn't built when off. For ~1 Hz samplers, add to the throttled block in
`BrunoFrameMonitor.tick` next to `mem`/`counts`/`hosts`. Keep everything `#if DEBUG` and release-inert.

The fork's reuse counters live in `CollectionHStackPerfCounters` (DEBUG) in
`DiplomacyMusic/CollectionHStack@bruno-hosting-reuse` — see `BRUNO_PERF_INVARIANTS.md` INV-10 and
`[[bruno-collectionhstack-fork]]`.

---

## Gotchas

- **DEBUG only.** None of this compiles into Release. The Settings toggle only appears in DEBUG builds.
- **`GCController` is blind to the sim remote** — input capture uses a non-consuming `UIWindow.sendEvent`
  swizzle (works for sim keyboard/Remote app AND a real Siri Remote). Installed once, inert when off.
- **Caches is purgeable** — pull sessions promptly; don't expect them to survive a reboot/disk pressure.
- **No size cap / rotation** yet — a very long session grows unbounded. Pull + delete between runs.
- **Self-driving the sim is unreliable** (auto-login SIGTRAP when the home server is unreachable; flaky
  nav). Capture is a human-in-the-loop step: the owner runs + records, the agent analyzes the logs.
