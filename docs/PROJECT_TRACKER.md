# Bruno — Project Tracker

> Canonical status board for the Bruno tvOS fork. The **bruno-expert** agent owns this file. When you
> finish a unit of work, update the matching row here in the same change — and add a one-liner to
> `docs/CHANGELOG.md`. Keep this file SMALL: current + next only. Shipped history lives in the changelog.
>
> Inputs that feed this tracker (read them, don't duplicate them):
> - Product contract: `prototype/design_handoff_bruno/PRODUCT_SPEC.md` + `README.md` (the mockup)
> - Surfaces / shelves / show-all routing: `docs/BRUNO_NAV_MAP.md`
> - Architecture / code geography / doc map: `docs/BRUNO_CODE_MAP.md`
> - Verified architecture / signatures: `BRUNO_NOTES.md`
> - Perf invariants (read before shelf UX): `docs/BRUNO_PERF_INVARIANTS.md`
> - Shipped history: `docs/CHANGELOG.md` · Next-thread plan: `docs/FEATURE_BACKLOG.md`
> - Enrichment producer→app seam: `docs/pipeline/FILING_MAP.md`
> - Build & run on device: `docs/DEPLOYMENT_HANDOFF.md`
>
> Status legend: `[ ]` not started · `[~]` in progress · `[x]` done · `[!]` blocked

_Last synced: 2026-06-29._

## Current state

Bruno runs on a real Apple TV (ad-hoc signed; session persists). Home is a deterministic seeded spine +
explore tail; as of #37–41 it has deeper explore caps, a sub-genre + Rewatchables generator, a "New
Releases" shelf, and **Show-all on every shelf** (D1+D2). The Movies tab is the genre browse surface.
Repo is **main-only**; docs are tiered with `BRUNO_NAV_MAP` + `BRUNO_CODE_MAP` canonical. **Top outstanding
risk:** the held-scroll freeze fix (INV-10, `24ee9372`) and the Movies-hitch fork fix are landed but
**not yet re-recorded on device** — see `docs/BRUNO_PERF_PLAYBOOK.md`. Recent shipped work: `docs/CHANGELOG.md`.

## Now / next (the active push: tvOS IA + browse polish)

| St | Item | Where | Notes / blocker |
|----|------|-------|-----------------|
| [~] | Tab IA reorder → **Home · Movies · TV · Collections · Kids · Search · Settings** | `Shared/Coordinators/Tabs/MainTabView.swift`, `TabItem.swift` | CONTENT done (Movies = genre browse, Collections tab exists). Tab POSITION/order reorder still not done. |
| [!] | `TabItem.kids` → existing Jellyfin kids library/folder | `TabItem.swift`, `BrunoKidsView.swift` | **BLOCKED:** need exact Kids library name(s)/id(s) on the server. |
| [~] | System Top Shelf extension (dynamic previews) | `BrunoTopShelf/` | Groundwork shipped; owner must create the target + App Group + signing. See `docs/reference/TOP_SHELF_SETUP.md`. |
| [ ] | Night-mode audio control missing from tvOS Settings | `Shared/Objects/AudioNightMode.swift`, `MediaPlayerProxy+VLC.swift`, `Swiftfin tvOS/Views/SettingsView/VideoPlayerSettingsView.swift` | The `AudioNightMode` + VLC `compressor` hook work, but the picker isn't surfaced where tvOS playback settings render. Find that surface and add the picker. |
| [~] | Oscars: reverse-chron order + *Winner/Nominee (Year)* caption | `BrunoOscarContentView`, `BrunoOscar`, `BrunoBoxSetShelvesView`, `BrunoBoxSetGridView`, `BrunoCategoryCardRow` + `enrich/build_oscar_tags.py` + `Apply-Enrich-Tags.command` | App code shipped (builds). Tags now stamped by the **unified** `Apply-Enrich-Tags.command` (Ebert + Oscar, tmdb-matched, idempotent) — supersedes `p9_oscars.py`. **Owner action:** `./Apply-Enrich-Tags.command apply` to stamp; captions blank until then. preview verified 413 Oscar films. |
| [~] | Ebert shelves: one tile + Up⇄Down toggle grid (★ caption, score order, genre pills) | `BrunoEbertView`, `BrunoEbert`, `BrunoBoxSetShelvesView` (`consolidateEbert`), `BrunoCategoryCardRow`, `BrunoEbertContentView` + `Apply-Enrich-Tags.command` | #57 shipped (★★★½ caption, score order, custom grid + "Browse by" pills; tags STAMPED 2026-06-29). **PR #62** then merged the two "Ebert Thumbs Up/Down" entries into ONE "Ebert" tile (mirrors `consolidateOscars`) → one grid with a flip toggle (👍⇄👎) above the pills that swaps icon/label/hero-title/film-set/sort/pills (both sets pre-loaded → instant). INV-1/3/7/10 respected. **PR #63** then split the Curated display: the card row keeps the single "Ebert"/"Oscars" cards (`cardRowCategories`) but the SHELVES below show the individual film shelves again (Ebert Thumbs Up/Down + 6 Oscar categories, captioned + ordered); each Ebert shelf's Show-all opens the toggle grid pre-set to its verdict (`brunoEbert(...showingDown:)`). **Owner action:** merge #62 + #63 + rebuild; focus traversal on-device check. **Next (PR — not started):** Ebert Up/Down + Oscar category shelves on **Home** with captions — needs caption threading in `BrunoShelfView` + `.tags` in `BrunoQueryLibrary` + seeded generators (determinism-sensitive). Hero uses `Curated02` (wider `EbertHero` asset = follow-up). |
| [ ] | On-device shelf check (focus feel, scroll-jump landing) | Home / Collections / Genres | Wants a real Apple TV pass (focus feel can't be driven headlessly in the sim). |
| [ ] | Collection "card-deck" card | `BrunoBoxSetGridView` / `BrunoBoxSetCardLabel` | Deferred from the Collections pass: cover + 2 titles peeking behind, total width = one landscape card. |
| [ ] | Server curation: orphan director collections | Jellyfin server (owner) | A standalone director collection neither nested under Directors nor name-identical leaks into Boxed Sets. Durable fix is server-side: nest under **Directors**. |
| [ ] | Genre BoxSet membership cleanup + 100% coverage audit | enrich pipeline + live server (owner) | Follow-up from PR #19 (rows now show full membership). Named removals + audit every movie into ≥1 genre BoxSet. |
| [ ] | Browse → Home realignment redesign | Collections / Genres / Decades | Browse drifts from Home (no persistent hero banner, repeated group-name eyebrows, flat vs elevated posters). Make consistent on color/type/spacing; keep `.posterShadow()` (brand). Brief authored 2026-06-23. |

**Movies/genre audit (PR #19 §8, `docs/BRUNO_MOVIES_GENRE_SURFACE.md`):** G1/G3/G4/G5/G2/G7 done;
deferred — G6 (no poster prefetcher on this surface), G8 (long `Show all · <genre>` label truncation),
G10 (dead decades-only machinery on this VM).

## Backlog / deferred (from PRODUCT_SPEC §8 + perf pass)

Need owner decision or on-device measurement — NOT done:

- [ ] **Per-generator query-limit cut** (`BrunoQuery` 60→20 for spine `.query` shelves) — changes the *visible* per-shelf set, so it's a content change needing owner sign-off, not a silent perf tweak.
- [ ] **Reuse `BrunoPosterPrefetcher` on browse rows** — additive, but needs on-device (real Apple TV, Release) hitch measurement; interacts with the artCarousel cards' own focus-fetch.
- [ ] **Static-collection-grid completeness** — `fetchChildren` `limit=200` feeds Directors/Studios grids; sub-group list `limit=100`. LATENT at current scale; open: cap-at-shelf vs lazy-fetch-at-destination.
- [ ] **On-device perf re-record** — confirm the held-scroll freeze fix (INV-10) + Movies-hitch fork fix on a real Apple TV (Release). The single most important open verification.
- [ ] **Home cold-load latency — FORESEEN (PR #46).** *If a "slow / laggy Home load" report comes in, START HERE — this is the known first suspect.* #46 folded the all-box-sets fetch (~416 BoxSets, `BrunoLibrarySnapshot.fetchAllBoxSets`) into the shared Home snapshot load and persists the franchise set in the cached payload, so Home load now pays a fetch + a larger disk read/write the Collections tab used to own alone. Needs a measured fetch/payload-size delta before deciding a fix (lazy-fetch franchises at the Collections drill vs. trim the persisted set) — not a revert.
- [x] **Hero left/right spotlight** — DONE (2026-06-28, PR pending): restored via focusable page-indicator dots (a `.focusSection()` move-to-select pager), **not** the `pressesBegan` UIViewRepresentable originally sketched — LEFT/RIGHT pages the multi-item spotlight while UP/DOWN escape, no `.onMoveCommand`. Same change rests launch/Back-to-Top focus on the menu bar. Device-verify the focus feel. See `docs/BRUNO_HERO.md`.
- [ ] Direct hero-play (build `MediaPlayerItemProvider` → `.videoPlayer`; today routes to stock detail → Play).
- [ ] Localize Bruno UI strings via `L10n` (prototype is English-only).
- [ ] Licensed Knockout font (Oswald is the brand stand-in).
- [ ] Formal XCTest target (today: `bruno-verify/` RNG checks + DEBUG self-check only).
- [ ] Open design questions from PRODUCT_SPEC §7 (Continue vs Up-Next merge, watched-dimming, studio card treatment).

## Spine vs tail (the product contract, condensed)

Home is a **stable spine** (Continue Watching → Up Next → Just Added → New Releases → A Year in Film #1 →
Spotlight/Director → Genre → Classic Romance → Series → A Year #2 → Studio → Eras → Browse-by-Director →
A Year #3 → Collections) plus a **dynamic tail** of up to 5 initial seeded "explore" shelves (+2 per scroll
page; `exploreBlockCount = 5` blocks, `tailCeiling = 120`, per-shelf cap 18). `seed = dayStamp()`,
**Shuffle** re-rolls. `build(seed:snapshot:now:)` is pure given `(seed, snapshot, now)`. Every shelf also
carries a trailing "Show all" → its browse twin (#41). Full taxonomy + generators: `PRODUCT_SPEC.md` §3–4.

## Guardrails (do not regress)

- **Additive, tvOS-only.** Bruno UI lives in `Swiftfin tvOS/Views/BrunoHomeView/` and `Shared/Objects/Bruno/`.
  iOS stays stock Swiftfin + rebrand. Don't touch player/nav/detail engine source.
- New files in the file-system-synchronized tvOS group → **no `.pbxproj` edits**. Non-Bruno edits stay
  DEBUG-gated and inert-by-default (see `SwiftfinApp.swift`). Sanctioned upstream exceptions are listed in
  `BRUNO_CODE_MAP.md` §2 (the `TabItem`/`MainTabView` seams; `PosterButton.swift` for the freeze fix).
- Never hardcode BoxSet/library IDs — discover groups dynamically (favorited BoxSets of BoxSets).
- **Before UX-polishing Home/browse shelves, read `docs/BRUNO_PERF_INVARIANTS.md`** (INV-1..10). The
  Home perf rests on non-obvious invariants (fixed row height, stable shelf ids, prefetch width ==
  cell width, seed-keyed/source-restricted cache, structurally-stable focus poster); `// INV-n` anchors
  mark each site. Restyle freely — just keep those ten intact.
  - **Owner-override exception:** `BrunoStudiosGridView` *intentionally* breaks **INV-6** (scroll-coupled
    blur over a `LazyVGrid`) for the demanded "image descends into the grid" effect. **Do NOT** revert it
    to a sibling layer — the tuning lever is the hero header height/blur, not the structure.
- No secrets in the repo. Live creds live only in gitignored `bruno_jellyfin.env`.
- **Work in a worktree → open a PR; the owner merges.** Don't push `main` directly (the owner builds
  `main` in Xcode; keeping edits in the worktree keeps the desktop app's file links resolving). PRs are
  a fork of `jellyfin/Swiftfin`, so pass `--repo DiplomacyMusic/swiftfin-bruno --base main`.
- **Worktree/DerivedData disk reclaim:** `Scripts/cleanup-worktrees.sh` (dry-run by default; `--apply`
  to delete) removes merged+clean worktrees and orphaned Xcode DerivedData; a daily launchd job
  (`Scripts/com.bruno.cleanup-worktrees.plist`) automates it. See `CLAUDE.md` → Maintenance.
