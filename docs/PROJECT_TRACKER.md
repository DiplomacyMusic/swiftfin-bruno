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

_Last synced: 2026-07-01 (Fable assessment pass; corrected three claims invalidated by post-sync
reverts, see the current-state paragraph)._

## Current state

Bruno runs on a real Apple TV (ad-hoc signed; session persists). Home is a deterministic seeded spine +
explore tail; as of #37–41 it has deeper explore caps, a sub-genre + Rewatchables generator, a "New
Releases" shelf, and **Show-all on every shelf** (D1+D2). The Movies tab is the genre browse surface.
Repo is **main-only**; docs are tiered with `BRUNO_NAV_MAP` + `BRUNO_CODE_MAP` canonical.

**IA overhaul (`docs/BRUNO_IA_OVERHAUL_PLAN.md`) — most of it SHIPPED this push** (app PRs #73/#74/#75
all merged; 3 server migrations): §1 Curated-retirement migration (14 favorited groups; 5 promotes;
Recommended/show-all repoints), §2 two-row card strip (owner-placed row membership + Roger rename), §3
Studio04 pin, §4 Oscar lead-spread, §5 Household Names + John Hughes (server-side), §7 cinematic
`BrunoBrandHeroBand` drill-ins, §8 generator retarget. A same-day hotfix pass on top (all pushed straight
to `main`, no PR) then: per-card colors for the 6 promoted groups + Cities cover art; dropped the
Roger Ebert/Cities inline preview shelves (were showing box-set posters, not movies) and added guaranteed
Ebert Up+Down movie shelves to the Collections tail instead; chronological order + 2-line titles on every
stock BoxSet's own "Movies" grid; Decades preview-shelf items now route to the pill view (matching Home);
shelf preview cap 14→30; the procedural Collections tail is fully shuffled internally
(`BrunoHomePlan.collectionsTail`) and the curated-named STATIC shelves shuffle among themselves while the
browse hubs keep their slots (`BrunoCategoryShelves.shuffledCuratedOrder`); and a Romance genre-bucket fix
(stale name, drop Chicago Movies; `c7301895`). Three same-day attempts were tried and **REVERTED**, so do
not expect them in the code: themed static Seasonal covers (`3d5393f1`/`ffb86988`, reverted by
`3410f627` + `fbd91b25`); merging the static category shelves + procedural tail into ONE fully shuffled
sequence (`9cd35470`, reverted by `d1337c18`); and the Boxed Sets franchise logos
(Star Wars/Avengers/Dark Knight/Jurassic Park) — see Outstanding below. **Still open:** §6 (reactive Decades hero + double-tap pill nav — highest-risk,
not started), Asian Cinema composed shelves, Cultural Touchstones lane, Cities seed-eligibility, art for
the 3 flat promotes still on gradient (Asian Cinema/Film School/Critically Acclaimed), dead
`consolidate*`/`curatedRandomShelves` cleanup (owner call), a proper Boxed Sets franchise-art treatment
(full-bleed key-art with the logo baked in, not a floating mark), the shelfCap 14→30 on-device scroll-feel
check, and an **on-device** pass over the whole migration. See `docs/CHANGELOG.md` (2026-06-30) for what
landed.

**Top outstanding risk:** the held-scroll freeze fix (INV-10, `24ee9372`) and the Movies-hitch fork fix are
landed but **not yet re-recorded on device** — see `docs/BRUNO_PERF_PLAYBOOK.md`. Recent shipped work:
`docs/CHANGELOG.md`.

## Now / next (the active push: tvOS IA + browse polish)

| St | Item | Where | Notes / blocker |
|----|------|-------|-----------------|
| [~] | Tab IA reorder → **Home · Movies · TV · Collections · Kids · Search · Settings** | `Shared/Coordinators/Tabs/MainTabView.swift`, `TabItem.swift` | CONTENT done (Movies = genre browse, Collections tab exists). Tab POSITION/order reorder still not done. |
| [!] | `TabItem.kids` → existing Jellyfin kids library/folder | `TabItem.swift`, `BrunoKidsView.swift` | **BLOCKED:** need exact Kids library name(s)/id(s) on the server. |
| [~] | System Top Shelf extension (dynamic previews) | `BrunoTopShelf/` | Groundwork shipped; owner must create the target + App Group + signing. See `docs/reference/TOP_SHELF_SETUP.md`. |
| [ ] | Night-mode audio control missing from tvOS Settings | `Shared/Objects/AudioNightMode.swift`, `MediaPlayerProxy+VLC.swift`, `Swiftfin tvOS/Views/SettingsView/VideoPlayerSettingsView.swift` | The `AudioNightMode` + VLC `compressor` hook work, but the picker isn't surfaced where tvOS playback settings render. Find that surface and add the picker. |
| [~] | Oscars: reverse-chron order + *Winner/Nominee (Year)* caption + per-category lead-spread | `BrunoOscarContentView`, `BrunoOscar`, `BrunoOscarAward`, `BrunoBoxSetShelvesView`, `BrunoBoxSetGridView`, `BrunoCategoryCardRow` + `Apply-Enrich-Tags.command` | App code shipped (builds). Tags are stamped LIVE — 410 Oscar films tagged on the server (unified `Apply-Enrich-Tags.command`, Ebert + Oscar, tmdb-matched, idempotent; supersedes `p9_oscars.py`); captions render now. **IA §4 lead-spread (`e2235ed3`):** after `reverseChronological`, `BrunoOscar.spreadLeads(_:category:seed:)` rotates only the top lead band (≈6) of each of the six category shelves by a per-category seeded offset so one recent award year no longer dominates the lead slot of all six (seed captured once per load like `shuffleSeed`, INV-3 safe). |
| [~] | Ebert shelves: one tile + Up⇄Down toggle grid (★ caption, score order, genre pills) | `BrunoEbertView`, `BrunoEbert`, `BrunoBoxSetShelvesView` (`consolidateEbert`), `BrunoCategoryCardRow`, `BrunoEbertContentView` + `Apply-Enrich-Tags.command` | #57 shipped (★★★½ caption, score order, custom grid + "Browse by" pills; tags STAMPED 2026-06-29). **PR #62** then merged the two "Ebert Thumbs Up/Down" entries into ONE "Ebert" tile (mirrors `consolidateOscars`) → one grid with a flip toggle (👍⇄👎) above the pills that swaps icon/label/hero-title/film-set/sort/pills (both sets pre-loaded → instant). INV-1/3/7/10 respected. **PR #63** then split the Curated display: the card row keeps the single "Ebert"/"Oscars" cards (`cardRowCategories`) but the SHELVES below show the individual film shelves again (Ebert Thumbs Up/Down + 6 Oscar categories, captioned + ordered); each Ebert shelf's Show-all opens the toggle grid pre-set to its verdict (`brunoEbert(...showingDown:)`). (#62/#63 merged). **PR #65** then put the **Ebert/Oscar shelves on Home with captions**: a `BrunoShelfCaption` on `BrunoQuery` → `.tags` in `BrunoQueryLibrary` → portrait curated shelf in `BrunoHomePlan.boxSetShelf` → `BrunoShelfView` render switch (`BrunoEbert/OscarContentView`) → `brunoHomeRouteToShowAll` toggle/Oscar grid. The existing seeded `curated` generator surfaces them on random seed/regen; caption is seeded-pure so INV-3/`selfCheck` untouched (no new generators/kinds). **Owner action:** merge #65 + rebuild; Shuffle until an Ebert/Oscar curated shelf appears, confirm caption + Show-all on-device. Hero uses `Curated02` (wider `EbertHero` asset = follow-up). |
| [ ] | On-device shelf check (focus feel, scroll-jump landing) | Home / Collections / Genres | Wants a real Apple TV pass (focus feel can't be driven headlessly in the sim). **Now also covers the whole IA migration** — the §2 two-row strip (`a6cd169b`), the §7 cinematic `BrunoBrandHeroBand` drill-ins (`ce925ac1`, lose CollectionVGrid recycling), and the §1 Curated-retirement nav (14 favorited groups). Sim focus timing differs. |
| [ ] | **IA §1 — Oscars gold-tile drill: keep 6-shelf or rebuild gold tiles?** | `BrunoCategoryShelves.swift:533` | OPEN on-device design call. The real "Oscars" favorited group's `.shelves` drill now fans out to the SIX captioned reverse-chron shelves (carrying §4 lead-spread). The old `curated-oscars` gold-tile gate (`:533`) is now **unreachable** (it gated `cardRowCategories`, never the shelves). Decide: keep the natural 6-shelf drill (current) vs. rebuild the gold tiles. |
| [ ] | **IA §1 — Asian Cinema composed shelves** | `BrunoBoxSetShelvesView` (builder) | NOT built. Asian Cinema is a flat `.grid` of 38 films today; the planned WKW/Bong + genre-filtered composed shelves (synthetic categories → `.shelves`) weren't added. |
| [ ] | **IA §1 — demote Cultural Touchstones (Decades "All"-lane prepend)** | `BrunoBoxSetShelvesView` (All branch) | NOT built. Touchstones retired with Curated (unfavorited) but the best-of-lane prepend feature wasn't added. |
| [ ] | **IA §8 — Cities seed-eligibility for Home/Collections generators** | `BrunoHomePlan.explore` / `collectionsTail` | NOT built. The per-city shelves aren't yet a `"cities"` explore source. |
| [ ] | **IA §1 — dead-code cleanup (owner call): `consolidate*` / `curatedRandomShelves` / the `"curated"` drill gates** | `BrunoBoxSetShelvesView.swift:96-169/:670-823`, `BrunoCategoryShelves.swift:231/:579` | The Curated retirement ORPHANED the drill-side cluster (`consolidateOscars/Ebert`, `cardRowCategories` consolidation branch, `curatedRandomShelves`, the `curated-oscars` gold-tile gate) — all keyed on a drill parent named "Curated", which no route produces. NOTE (corrected 2026-07-01): `BrunoHomePlan.swift:337` (`case "curated","world"`) is ALIVE — it reads `promotedCuratedBoxSets` and stays. Also dead: `BrunoStaticItemsLibrary.swift` (whole file, zero callers) + `BrunoLibrarySnapshot.curatedBoxSets`. Delete vs. re-home is an owner call; step 3 of `Documentation/fable-plans/REFACTOR_PLAN.md` has the full checklist. |
| [ ] | **IA §6 — reactive Decades hero + double-tap-down pill nav** | `BrunoBoxSetShelvesView`, `BrunoGenresView`, `BrunoKidsView` | NOT started — the highest-risk tier (backdrop-reload perf + focus-engine state machine, INV-7/10, on-device verification required). Build behind a shared-idiom refactor. See plan §6. |
| [ ] | **IA — art assets for the 3 flat promotes** (Asian Cinema / Film School / Critically Acclaimed) | `Assets.xcassets/BrunoCollections`, `BrunoCollectionArtwork` | Gradient/stand-in until bespoke art is added. |
| [ ] | Fold Studios + Rewatchables onto shared `BrunoBrandHeroBand` | `BrunoStudiosGridView`, `BrunoRewatchablesView`, `BrunoBrandHeroBand.swift` | Follow-up to §7 (`ce925ac1`): the shared band was extracted but Studios/Rewatchables still carry their own copies. Fold them on so there's truly one band (plan §7 anti-scatter). |
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
