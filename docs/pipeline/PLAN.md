# Bruno enrichment pipeline → feature store → collections + recommender

**Goal.** Turn the movie library into a single **per-film feature store** (`movie_features.json`)
that powers BOTH the Bruno browse collections AND an experimental in-house recommendation algorithm.
Enrichment logic lives here; the collection builder and the recommender are *projections* of the store.

**Why a store (not title-sets in the .command):** the owner wants to experiment with a recommender.
A recommender needs a feature matrix, not collection-membership. So every signal (colloquial genre,
significance, awards, critic verdict, watch history, embedding) lands on the film first; collections
fall out of it.

## Store schema (`movie_features.json`)
Keyed by Jellyfin item id. Columns are filled phase-by-phase (each phase idempotent):

| Column | Phase | Source |
|---|---|---|
| identity (jellyfin/tmdb/imdb id, title, year, decade) | 1 spine | Jellyfin |
| metadata (genres, director, cast[8], studio, runtime, release) | 1 spine | Jellyfin |
| ratings (community≈IMDb, critic=RT) | 1 spine | Jellyfin |
| signals (play_count, played, favorite, resume) — *watch history* | 1 spine | Jellyfin UserData |
| owner (manifest category, rewatchable, named_favorite) — *taste seed* | 1 spine | movie_manifest.json |
| tmdb (revenue, budget, votes, popularity, overview, keywords, lang, countries) | 2 tmdb | TMDB API |
| llm_tags ({superhero:0.94, spy, action_hero, alien, disaster, foreign, chicago, vibes...}) | 3 tags | LLM (Sonnet) |
| awards (oscar: {category: win/nom}) | 4 awards | compiled Academy dataset |
| ebert (verdict, stars) | 4 awards | compiled Ebert dataset |
| significance ({score, acclaim, commercial, cultural}) → `bruno-sig:NN` | 5 sig | computed |
| embedding [vector] | 6 embed | embedding API (Voyage/OpenAI — KEY NEEDED) |

## Phases
- [x] **1 spine** — `p1_spine.py` — 1133 films; 231 owner-taste films joined.
- [x] **2 tmdb** — `p2_tmdb.py` — 1133/1133, 0 errors. revenue=1077, keywords=1131, overview=1133.
- [ ] **3 tags** — LLM colloquial tagging over titles+genres+keywords+overview, with confidence.
      Decisions: Superhero = Action subgenre (pull from Sci-Fi/Fantasy, keep in Action).
      Spy = Thriller subgenre; action-spy (Bond, M:I) also in Action.
- [x] **3d QC** — title-by-title verification of 11 fuzzy shelves (noir 126→70, paranoia 99→43,
      isolation 77→45, alien 79→44+9 manual, etc.) via `p3_apply_qc.py`. Star Wars hard-added through
      `manual_tags` (gate stays strict, per owner). Rosters/verdicts in `qc/`.
- [x] **4 awards** — `data/oscars.json` (DLu/oscar_data, 12k rows) + `data/ebert.json` (Siskel-Ebert,
      8.4k films) downloaded as local DBs; joined via `p4_awards.py`. 414 films w/ Oscar noms, 737 w/ Ebert.
- [x] **5 significance** — `p5_significance.py`: per-decade Bayesian acclaim + log-revenue + cultural
      percentile → `significance{score,acclaim,commercial,cultural}`. Best-of-Decade validated vs spec
      anchors. **Zeitgeist** = LLM touchstone pass (12 agents, `zg/`) blended 62% with engagement/canon/
      Best-Picture → `zeitgeist` (absolute 0-100) for the Cultural Touchstones shelf. Cult films (Office
      Space 44→68, Heathers 24→64) correctly elevated without overtaking all-timers.
- [ ] ~~**6 embeddings**~~ — DEFERRED (owner: defer built-in rec algo for now).
- [x] **6 projection (LIVE)** — `p6_project.py` wrote **87 BoxSets** to Jellyfin: 36 Genres sub-shelves
      (sub-genres + war tree + Foreign + per-language), 13 Curated (Cultural Touchstones, Chicago, Vibes,
      6 Oscar categories, Ebert Up/Down), 3 Seasonal, **27 Movie Stars** (new tile), 8 Best-of-Decade
      (nested in each decade). Retired the 6 combos; pulled 28 Superhero films from Sci-Fi/Fantasy.
      Members ordered by weight (conf/significance/zeitgeist). 392 BoxSets total.
      App edits (worktree — need to land on main + rebuild): Movie Stars portrait rendering
      (`BrunoCategoryShelves.swift` rank/lens/artCarousel) + Superhero keyword → Action bucket
      (`BrunoGenresView.swift`).
      FOLLOW-UPS: discovery genres (biopic/sports/coming_of_age) need a tag backfill before they're shelves;
      Best-of-Decade as the significance-ordered FIRST shelf inside a decade is a deeper Swift change (now
      ships as a nested BoxSet, which renders).
- [ ] ~~**8 recommender**~~ — DEFERRED (owner: revisit later). Store is designed to support it when revived.

**Tagging method (owner): ad-hoc Sonnet sub-agent run in-thread** (not a deterministic script) —
batch the films with full context, fan out tagging agents, merge results into the store.

- [x] **3 tags** — 12 Sonnet agents tagged all 1133 films (vocab + freeform discovery). Merged via
      `p3_merge.py`; mishmash/cluster analysis via `p3_analyze.py`. Spec = `TAGGING_SPEC.md`.
      **Deliverable: `GENRE_MAP.md`** — proposed IA, hit counts, where each category lives, exclusivity
      rules, War sub-tree, 65 emergent discovery genres. AWAITING owner decisions (see map §Open decisions).

## Notes
- Watch history is currently sparse (12 plays, 0 favs) → manifest taste (Rewatchables 214, Named fav 17)
  is the cold-start personalization fuel until real history accumulates.
- "Winner/Nominated (year)" per-film second line under Oscar posters is NOT a Jellyfin collection
  capability — it ships as a Bruno app annotation fed by a per-item tag. **BUILT:** `p9_oscars.py`
  stamps `oscar:<CATEGORY>:<won|nom>:<YEAR>` (414 films; awards-edition year from `data/oscars.json`);
  the app renders *Winner (Year)* / Nominee (Year) and orders the Oscar shelves + grids reverse-chron.

- [x] **9 oscar tags (LIVE, owner-run)** — `p9_oscars.py`: per-(film,category) `oscar:` item tags for
  the app's Oscars caption + reverse-chron order. Additive/idempotent (mirrors p7); DRY-RUN default.
