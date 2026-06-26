# Genre recommendation shelves — architecture spec (proposal, not yet built)

_Written 2026-06-26. This is a design to approve before any code. No implementation has been done._

## Problem

The Home **"IF YOU LIKE `<Genre>`"** shelves recommend by **raw TMDB genre**, which bypasses the owner's
curated `llm_tags` system. TMDB over-tags (Heathers→Crime, Field of Dreams→Fantasy, Contact→Mystery, True
Romance→Romance), so the recommendations are noisy and some shelves are thin/odd (e.g. a "Romance" row whose
only modern oddball was *True Romance*). The curated layer — which is the actual brand — never feeds these rows.

## Current architecture (verified in code)

- **"IF YOU LIKE" shelf** is built in `Shared/Objects/Bruno/BrunoHomePlan.swift`:
  - Spine: `seededPick(snapshot.genres, …)` → `genreQuery(genre:)` (L101-112, L323-329).
  - Explore tail: same via L273-283.
  - `genreQuery` sets `query.genres = [name]` → Jellyfin `GetItems?Genres=<name>` (a **name match against the
    raw per-item Genres field**). It does **not** touch any BoxSet.
- **Genre name universe** = `snapshot.genres`, from `GET /Genres` (TMDB names) — `BrunoLibrarySnapshot.fetchGenres`
  (L135-146).
- **Genre PILLS** (`Swiftfin tvOS/Views/BrunoHomeView/BrunoGenresView.swift`) are 5 hardcoded cores
  (`BrunoCoreGenre.all`, L34-44) that keyword-substring-match the names of `snapshot.genreBoxSets` (the 80
  children of the "Genres" group BoxSet `c37ce5607799e0c37e307c6203b32cf2`).
- **The curated BoxSets already exist** (`snapshot.genreBoxSets`), but they are **flattened**: the ~16 broad ones
  (Crime, Drama, Comedy, Action, Fantasy, Mystery, Romance, Science Fiction, Thriller, Adventure, Family,
  Animation, History, War, Music, Horror) are built from **raw TMDB genres** by `Build-Jellyfin-Collections.command`;
  the genuinely curated sub-genre/personal ones (Gangster, Noir, Heist, Cubicle, Bromance, Indie Stress, Hangout,
  Mind Blowers, Twee, Coming of Age, Sports Movies, …) are built from **`llm_tags`** by `enrich/p6_project.py`.
  The snapshot has **no flag** distinguishing them — only the name.
- **Reusable pattern already in the plan:** `parentQuery(parentID:)` + the generic `boxSetShelf(...)` helper
  (`BrunoHomePlan.swift` L387-414) already source Director / Studio / Seasonal / Curated / Decade shelves from a
  BoxSet's children. Sourcing a genre rec from a BoxSet is the same mechanism.
- **No tag query source:** `BrunoQuery` cannot filter by tag today (no `tagsAny`).

## Key correction (from red-team)

Sourcing "IF YOU LIKE / Crime" from the same-named **"Crime" BoxSet** buys **nothing** — that BoxSet is the same
raw TMDB membership, just materialized. The value is only in featuring the **curated** sub-genre/personal BoxSets.

## Options

### (a) `tagsAny` + materialize tags onto items
Add `tagsAny` to `BrunoQuery`/`BrunoQueryLibrary` (→ `GetItems?Tags=…`), and add a new pipeline phase (p8, like
`p7_brunosig`) that writes each film's `llm_tags` onto the Jellyfin item as tags. Then a shelf can query "films
tagged `gangster`".
- **Pros:** most flexible; tag-level granularity; no dependence on BoxSet upkeep.
- **Cons:** **requires a server-side data write** to every item (not app-only); new pipeline phase to build and
  maintain; another field that can drift. Higher blast radius — the kind of write the owner is rightly cautious of.

### (b) BoxSet-sourced, app-only
Re-point the "IF YOU LIKE" row at a **curated** BoxSet via the existing `boxSetShelf`/`parentQuery` pattern.
- **Pros:** **no server write**; reuses the ~80 BoxSets already built; pure app change; fully reversible.
- **Cons:** the 80 are flattened, so it needs a **curated allowlist** (or a denylist of the ~16 broad TMDB names +
  the Foreign/language ones that have their own surface); a **dedupe re-key** (`genre:<name>` → `parent:<id>`);
  determinism via `seededPick` over the allowlisted BoxSets; and **display-name/eyebrow curation** so colloquial
  names read well as a recommendation header.

### (d) Hybrid — RECOMMENDED
Keep the existing broad-genre "IF YOU LIKE" rows (now cleaner after the raw-genre fixes), and **add** a new,
separate recommendation lens sourced from the **curated** sub-genre/personal BoxSets.
- **Pros:** additive (nothing existing changes behavior), app-only, no server write, lowest risk, and it puts the
  owner's colloquial genres (Indie Stress, Hangout, Gangster, Noir…) on Home — the actual brand.
- **Cons:** two genre-rec lenses coexist (arguably a feature: "IF YOU LIKE Drama" + "IF YOU'RE INTO Indie Stress").

## Recommended design (option d), concrete

1. In `BrunoLibrarySnapshot`, expose a **curated** subset of `genreBoxSets` — everything under the "Genres" group
   **minus** a small denylist: the 16 broad TMDB names + the Foreign/language BoxSets (Foreign Film, French/Italian/
   Japanese/Korean Cinema) which belong to their own surface. (Denylist is more robust than an allowlist as new
   curated genres are added.)
2. In `BrunoHomePlan`, add one shelf (spine + explore-tail) with a distinct lens — e.g. **"IF YOU'RE INTO"** —
   built with the existing `boxSetShelf(curatedGenreBoxSets, lens: "If You're Into", kind: .genre, …)`. Dedupe key
   `parent:<id>`; determinism via the existing `seededPick`. This reuses proven code; no new query type.
3. Optional eyebrow/display-name map for a handful of colloquial BoxSet names if any read oddly as a header
   (most are fine: "Gangster", "Heist", "Coming of Age", "Sports Movies").

Effort: small-to-medium, all in `BrunoHomePlan.swift` + `BrunoLibrarySnapshot.swift`; no server changes; respects
INV-2/INV-3 (stable `parent:<id>` ids, deterministic seeded pick).

## Open questions for the owner
- Eyebrow wording for the new lens ("IF YOU'RE INTO" vs "MORE LIKE" vs keep "IF YOU LIKE").
- Which curated BoxSets are recommendation-worthy (confirm the denylist; some like "SNL Stars", "Oscar Bait" may
  be better kept off Home).
- Whether to **also** clean the broad-genre "IF YOU LIKE" rows further, or let the hybrid lens carry the curation.

## Explicitly out of scope here
No implementation until this spec is approved. No raw-`Genres` writes. No locking. No `p6`/`Build` re-runs.
