# Enrichment → Bruno filing map (movie_features.json + GENRE_MAP.md)

> Relocated here from `PROJECT_TRACKER.md` (2026-06-28 docs streamline). Authored 2026-06-26 by
> bruno-expert. Grounds the `MovieCollection/enrich/` enrichment (sub-genres, Oscar/Ebert,
> Foreign/per-language, Vibes, discovery genres, Movie Stars, Best-of-Decade, bruno-sig) against the
> **actual** Bruno code. Source of truth for HOW the enrichment files into the app. The external
> producer is `docs/pipeline/PLAN.md` + the separate MovieCollection repo.
>
> **The one architectural fact that governs everything:** Bruno's app-side shelf engine has **no tag
> source**. `BrunoQuery` (`Shared/Objects/Bruno/BrunoQuery.swift:20-56`) maps only `genres`,
> `studioIDs`, `personIDs`, `years`, `parentID`, `minCommunityRating`, `IsUnplayed`/`IsFavorite` →
> `BrunoQueryLibrary` (`BrunoQueryLibrary.swift:46-84`). `BrunoLibrarySnapshot` carries only group
> BoxSets + genre *names* + years (`BrunoLibrarySnapshot.swift:24-37`). **There is no `tags` field on
> the query, no `Tags`/`bruno-sig` in the snapshot, and nothing in Swift reads item tags today**
> (grep: zero `bruno-sig` consumers). ⇒ Anything that is "a membership of films selected by a tag" must
> become a **server-side Jellyfin BoxSet** to render with the engine as-is. App-side dynamic rows are
> only possible from sources the engine already speaks: genre-name, parentID (a BoxSet), year,
> rating, person, studio. **This is the spine vs. tail decision for the whole enrichment.**

## Decision table — where each enrichment category files in

| Enrichment category | Jellyfin BoxSet vs app-side | Surface(s) in Bruno | Code / script touch-point |
|---|---|---|---|
| **Sub-genre shelves** (superhero, noir, gangster, spy, alien, isolation, paranoia, war sub-tree…) | **BoxSet** (build script writes them as sub-collections under the **Genres** group, exactly like today's romance sub-genres) | Genre main screen (auto, as new shelf rows) + Home explore tail (auto, via the `genre`/`curated`/`subgenre` generators that walk group children) | Script: `Build-Jellyfin-Collections.command` (add to the `add("genre",…)` pattern, lines ~258-300). **App: zero changes** — `BrunoBoxSetShelvesView` + `BrunoGenresView` already render every Genres-group child as a shelf. |
| **Two-tier model** (CORE = pills; sub/vibes/discovery = weighted rows) | both — CORE pills are app-side, weighted rows are BoxSets | Genre screen: CORE = `BrunoCoreGenre.all` pills; sub-genres = the shelf stack beneath, **weighted** by `childCount` | CORE pills: `BrunoGenresView.swift` (`BrunoCoreGenre.all`). Weighting: `BrunoCategoryShelves.weightedPreview` already ranks shelves/cells by `childCount^0.6`. See Q1 below. |
| **Oscar category collections** (Best Picture/Directing/Acting/Cinematography/Score/Screenplay) | **BoxSet** under **Curated** (consolidated into one synthetic "Oscars" tile app-side, #40) **+ per-item `oscar:<cat>:<won|nom>:<year>` tags** (`enrich/p9_oscars.py`, owner-run LIVE) | Curated drill-in shelves + Home `curated` generator | Script: Phase 4 `oscars.json` join → Phase 9 tag stamp (`p9_oscars.py`). App: Oscars consolidation (`BrunoCategoryCardRow.swift:72`) + reverse-chron order & *Winner/Nominee (Year)* caption (`BrunoOscarContentView`, `BrunoOscar`) in the Oscars drill-in shelves + their `brunoBoxSetGrid` "Show all". |
| **Ebert Thumbs Up/Down** | **BoxSet** under **Curated** | Curated + Home tail | Script only (Phase 4 `ebert.json`). App: zero. |
| **Foreign Film + per-language** (Korean/Japanese/French…) | **BoxSet** (Foreign under Curated *or* a new top-level group; per-language as sub-collections) | Curated/Genre drill-in + Home. If promoted to its own top-level group tile → also a Collections-hub tile, auto-ranked. | Script writes collections. App: **only** if a NEW top-level group → add it to `BrunoCollectionCategory.rank` (`BrunoCategoryShelves.swift:99`) + an artwork case. Under Curated → zero app changes. |
| **Bruno Vibes** (indie_stress, hangout, mind_blower, ratatat) | **BoxSet** — one "Bruno Vibes" sub-group under **Curated** holding 4 collections | Curated drill-in + Home tail | Script only. App: zero. |
| **Personal genres** (cubicle, journalism, twee, oscar_bait, monster, snl, bromance…) | **BoxSet** under **Genres** (weighted rows, NOT pills — owner's two-tier rule) | Genre screen shelves + Home tail | Script only. App: zero. |
| **~65 discovery genres** (biopic, coming_of_age, sports…) | **BoxSet** under **Genres**, only the graduated ones | Genre screen shelves (weighted, sink low) + Home tail | Script only. App: zero. Owner picks which graduate (GENRE_MAP §Open decisions). |
| **Movie Stars master tile** (24 actors) | **BoxSet group** — a favorited group "Movie Stars" whose children are per-actor sub-collations, **structurally identical to Directors** | Collections hub tile + a "Browse by Stars" portrait shelf on Home (clone of "Browse by Director") | Script: clone the `director` CATS block keyed on `Type=="Actor"` cast. App: small — clone the auteurs shelf + a `movieStarBoxSets` snapshot accessor. See Q2 below. |
| **Best of [decade]** top row | app-side ranked row — but needs a **rank source** | First shelf inside a Decade drill-in + a promoted Home shelf | Needs bruno-sig (see Q3). Touch-point: `BrunoBoxSetShelvesView.loadYearShelves` / the decade overview. |
| **"[Year] in focus" Home shelf** | app-side — **already exists** | Home spine | `BrunoHomePlan.yearShelf`; 3 promoted years in the spine (`build`). Ranking by bruno-sig is the only enhancement. |
| **bruno-sig (significance)** | **server-side item field** (Tag or a custom field), consumed app-side | drives Best-of-Decade ordering + a "Cultural Touchstones" shelf | **Requires NEW plumbing** — the engine has no tag/sig source today. See Q3. The lowest-friction path is a **server BoxSet** ("Cultural Touchstones" / "Best of the 2000s") rather than an item-tag the app must learn to read. |
| **Cultural Touchstones** shelf | **BoxSet** under Curated (membership = top-bruno-sig films) | Curated + Home tail | Script computes membership from bruno-sig; writes a collection. App: zero. |

## Build-script-side (Jellyfin collections) vs app-side (Swift)

- **Build-script-side (the bulk — ~90% of this enrichment):** every membership-defined set becomes a
  Jellyfin BoxSet under one of the group tiles. The script already does exactly this pattern
  (`add(cat, clean, …)` → `/Collections?name=…&ids=…` → nest under the group tile via `add_items`).
  Sub-genres, Oscar, Ebert, Foreign, Vibes, discovery, personal genres, Cultural Touchstones, and the
  per-actor Movie Stars collections are **all script work**. **The app renders them with ZERO changes**
  because `BrunoCategoryShelves` / `BrunoBoxSetShelvesView` / `BrunoGenresView` walk group children
  generically and the Home explore generators (`genre`, `subgenre`, `curated`, `studio`, `decade`,
  `seasonal`, `rewatchables`) seed off the snapshot's group lists.
- **App-side (small, surgical):** (1) Movie Stars group tile + "Browse by Stars" shelf (clone of
  Directors/auteurs). (2) Best-of-Decade row + bruno-sig consumption *if* sig ships as an item field
  rather than a BoxSet. (3) Adding a NEW top-level group (Foreign, Oscars) to `rank` + artwork *if*
  promoted out of Curated. (4) Optionally widening `BrunoCoreGenre.all` keyword buckets so new
  sub-genres land in the right CORE pill. Nothing here touches a perf invariant if done right (below).

## Open enrichment items (deferred)

| St | Item | Where | Notes |
|----|------|-------|-------|
| [ ] | **Sub-genre / Oscar / Ebert / Foreign / Vibes / discovery collections** | `Build-Jellyfin-Collections.command` (owner-run) | Pure script work; app renders them free. Gated on GENRE_MAP §Open-decisions + Phase 4/5 datasets. |
| [ ] | **Movie Stars master tile** (clone of Directors) | Script: per-actor collections under a new "Movie Stars" group · App: `movieStarBoxSets` snapshot accessor + "Browse by Stars" shelf in `BrunoHomePlan` + Collections rank/artwork | Cleanly cloneable — see Q2. Both halves needed; ship together. |
| [ ] | **Best-of-[decade] top row + "[year] in focus" ranking** | App: `BrunoBoxSetShelvesView` (decade) + `BrunoHomePlan.yearShelf` · plumbing for bruno-sig | Blocked on the bruno-sig delivery decision (Q3). Year-in-focus row already exists; only ranking is new. |
| [ ] | **bruno-sig delivery decision** | owner + script vs app | **DECISION NEEDED:** ship sig as a server BoxSet ("Best of the 2000s", zero app work) OR as an item field the app must learn to read (new `BrunoQuery`/snapshot plumbing). Recommend BoxSet first. |
| [ ] | **New top-level group(s)?** (Foreign / Oscars / Movie Stars promoted) | `BrunoCollectionCategory.rank` + `BrunoCollectionArtwork` | Only if promoted out of Curated; else zero app work. |

## Perf-invariant flags (`docs/BRUNO_PERF_INVARIANTS.md`)

- **No conflict for the BoxSet-only work.** Adding more group children = more shelves; the shelf
  scaffold is already height-pinned (INV-1), id-stable (INV-2 — ids derive from `boxSet.id`), and
  cap-and-grown. Genre-screen and Home shelf counts grow, but each shelf is a fixed-height, lazily-mounted
  row — no invariant breaks.
- **Watch the Home explore tail (INV-3).** The tail generators pick a *random* group child per slot
  (`BrunoHomePlan.boxSetShelf`). Dozens of new sub-genre collections = a much larger random pool, which
  is fine and stays deterministic. **Do NOT** introduce nondeterministic selection (e.g. "show the
  highest-sig collection") into `build`/`appendExplore` without seeding it — that would break "same seed
  ⇒ same Home" and trip `BrunoHomePlan.selfCheckPassed()`.
- **Best-of-Decade ordering must be a pure function of (sig, snapshot)** to keep INV-3. If sig arrives
  as item data, sort by it deterministically (sig, then a stable tiebreaker) — never by a live/random
  server sort.
- **Movie Stars shelf is INV-safe** — it's the auteurs shelf shape (portrait `.items`, fixed height,
  stable id), already proven by Directors.
- **A bigger genre/curated child set does not change prefetch width (INV-4)** or the seed-keyed cache
  (INV-5) — those are per-cell/per-shelf-id and indifferent to how many shelves exist.

## Answers to the four questions

1. **Weighted/ranked rows on Home + Genre screen?** Yes — but the SOURCE is **collections (BoxSets),
   not tags**. `weightedPreview` already weights by `childCount`. Tag-driven rows are **not** possible
   without new plumbing; file tag-memberships as BoxSets.
2. **Directors tile cloneable for Movie Stars?** Yes, cleanly. It's a favorited group of sub-BoxSets
   (script) + a `directorBoxSets` snapshot accessor + an `appendItemsShelf` portrait row + a Collections
   rank/lens entry. Clone each. Lowest-risk app change in this whole plan.
3. **Best-of-Decade + year-in-focus wiring?** Year-in-focus already ships (`yearShelf`). Best-of-Decade
   = prepend a ranked row to the decade drill-in. Both need a rank signal. **Reconcile with bruno-sig by
   shipping sig as a server BoxSet first** ("Best of the 2000s") so the app renders it with zero new
   plumbing; defer the item-field path.
4. **Script-side vs app-side?** ~90% script (every membership set → BoxSet under a group tile, rendered
   free). App-side is only: Movie Stars tile+shelf, Best-of-Decade ordering, and any newly-promoted
   top-level group's rank/artwork.
