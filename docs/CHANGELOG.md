# Bruno — Changelog

> Newest-first milestone log of what landed on `main` (PR# / commit + one line). The
> `PROJECT_TRACKER.md` holds only **current / next** work; everything shipped is recorded here so the
> tracker can stay small. For full detail use `git log` or the merged PR list.

## 2026-06-28

- **#37–41 — deeper Home + Rewatchables/Oscars + Show-all unification** (`24b81d5d` · `58baec8f` · `436504e0` · `140937d7` · `40da403f`). C3 Phase A raised the explore-tail caps (`exploreBlockCount 3→5`, `tailCeiling 60→120`, #37); Phase B added a seeded **sub-genre** explore generator (#38). A **"New Releases"** spine shelf (movies by `premiereDate` desc, distinct from the renamed "Just Added", #39). A **Rewatchables** curation surface (`BrunoRewatchablesView`, broad-genre shelves w/ "Episode NN" captions) + **Oscars** six-BoxSet→one-tile consolidation + a Home rewatchables generator (#40). **Show-all unification (D1+D2)** (#41): every Home shelf routes a trailing "Show all" via `brunoHomeRouteToShowAll` to the same destination as its browse twin; year/decade/Eras deep-link the Decades pill.
- **Docs sync to #37–41 + hallucination fix** (PR #42). Reconciled `BRUNO_NAV_MAP`/`BRUNO_CODE_MAP`/`PROJECT_TRACKER` with the merged code; corrected the unfounded "regressions only show on a real device" claim across `CLAUDE.md`/`CERTIFICATION.md`/`BRUNO_CERTIFICATION_PLAN.md` (the real hazard is a SILENT perf/determinism regression).
- **Repo + docs consolidation; two canonical maps; certification gate** (`b7f12aff` · `33834037` · `b2155d5d` · `b5de4aaf` · `81ef04e1` · `4a983665`). Repo collapsed to **main-only** (40 worktrees / 60 local / 29 remote → `main`). `BRUNO_NAV_MAP` + `BRUNO_CODE_MAP` created; docs tiered (canonical / reference / archive); SlateRunner-style cert gate built (warn mode); `FEATURE_BACKLOG` added. Live nav counts captured (1270 movies · 44 series · 416 BoxSets).

## 2026-06-27

- **Held-scroll FREEZE fix** (`24ee9372`; handbook `4addb6f1`). `FocusShadowPoster` made structurally stable (focused-poster shadow always-present + opacity-driven, no longer `if`-inserted) so a held Up/Down auto-repeat can't re-insert a view mid-focus-move and freeze the focus engine. Codified as **INV-10**. ⚠️ On-device re-record to confirm still outstanding. Edits `Swiftfin tvOS/Components/PosterButton.swift` (rare sanctioned upstream edit).
- **Movies vertical-scroll hitch fix** (`466aeb3f` · `7985aaf0` · `60d858df`). `CollectionHStack` repointed to the `DiplomacyMusic/CollectionHStack@bruno-hosting-reuse` fork (the `UIHostingController` is kept alive across cell reuse and its `rootView` swapped, instead of minting per `cellForItemAt`); the genre cell's heavy `@StateObject`/prefetcher moved into a focus-gated `ArtCycleOverlay`; HUD instrumented on the Movies surface.

## Earlier (2026-06)

- **PR #19** (`05ae924a` · `01e05da7` · `d685b68c`) — Movies tab → genre browse surface (`BrunoMoviesView` → `BrunoGenresView`); sparse genre rows fixed (cross-category dedup removed, modern cutoff dropped on those rows); per-launch / 6h row reshuffle. Genre pills → **11 owner-curated buckets** with an explicit exact-match member map.
- **Up-nav fix** — the hero menu bar changed to an un-pinned **scrolling row** so Up reaches the tab bar without losing left/right spotlight stepping (resolved; root-cause + invariants in `BRUNO_HERO.md`).
- **Debug overlay HUD** (FPS / nav-layout / log panels, DEBUG-only) + HUD-persists-on-drill-downs + pill-select scroll framing (Decades/Kids) + Kids sparse-content focus fix.
- **Perf foundation + browse-completeness + Decades/pills pass** (`00c6d790`..`c3341149`) — lean `[.parentID]`-only poster cells + warm-snapshot reuse, page-to-completion (`BrunoItemPaging`), release-date subtitle on Decades, per-year decade shelves + Other/Undated, focus-to-select pills with "All", browse drill-in cache actor, poster disk-cache 1→10 GB.
- **Collections passes 1–4** — code-drawn category tiles, landscape Boxed Sets grid + card lockup, missing-franchise fix (fetch cap 200→1000), Decades pill selector, seeded genre-shelf shuffle, studio logos/blurbs; Hollywood-sign Studios backdrop attempted 4× and **reverted** (redesign specced in `reference/STUDIO_GRID_HANDOFF.md`).
- **Home snappiness pass** — streaming top-down paint, disk-persisted Home payload (stale-while-revalidate, `BrunoHomeCache`), Bruno-owned poster prefetch, **INV-1..9** documented; landscape shelf hard-snap fix; selector-pill highlight fix.
- **Foundation** — real-device install + session persistence on an ad-hoc-signed build; headless E2E + mock-snapshot harnesses (`bruno-verify/`); app-wide rebrand (accent `#A1CCE0`, Oswald/Inter, BRUNO wordmark); toolchain restored as-authored on Xcode 26.3.
