# Pipeline docs — the MovieCollection → Bruno seam

**What this folder is.** Reference *snapshots* of the design docs from **MovieCollection** — the separate,
server-side production pipeline that builds the content Bruno renders. The pipeline itself is **not** part
of this repo (it's a Python ops project with its own repo and live credentials; folding it in would break
Bruno's additive / tvOS-only / **no-secrets** guardrails). Only these clean design docs are mirrored here,
for AI-agent and contributor reference. **Authoritative source: the MovieCollection repo** — refresh these
copies from there when the pipeline's design changes. Snapshotted 2026-06-28.

## The relationship (one-directional)

```
MovieCollection (producer)                         Bruno (pure viewer)
  enrich pipeline p1..p9   ──►  Jellyfin server  ──►  renders BoxSets; reads tags for
  + Apply-*.command scripts      (BoxSets + images      captions/ordering only
  ~400 BoxSets, item tags         + item tags)          (membership must arrive as a BoxSet)
```

MovieCollection **writes** Jellyfin BoxSets, images, and item tags (`bruno-sig:NN`,
`oscar:<CAT>:<won|nom>:<YEAR>`, `ebert-stars:<n>`, `ebert-verdict:<up|down>`, `rewatchables-ep:NN`).
Bruno **reads** them. Membership is BoxSet-only: `BrunoQuery` speaks only
genre-name / parentID / year / rating / person / studio, so **every curated grouping must ship as a
Jellyfin BoxSet** under a favorited group tile. Tags are consumed app-side for captions and ordering
only (see `FILING_MAP.md`, update note). The seam is narrow and one-way: the pipeline never imports
Bruno; Bruno never writes to the server.

**Scheduling (verified 2026-07-01):** there is NO automated pipeline run. The old daily 10:00 launchd
job (`com.diplomacy.jellyfin-collections`, ran the superseded `refresh_collections.py`) was disabled
on 2026-06-28 after failing with HTTP 414; the plist is renamed `*.disabled` in
`~/Library/LaunchAgents/`. All producer runs are owner-run manually from the MovieCollection folder
(`Build-Jellyfin-Collections.command`, `Apply-Enrich-Tags.command`, `enrich/p*.py` with `LIVE=1`).

## The data contract Bruno depends on

- ~80 sub-genre BoxSets under a favorited **"Genres"** group, plus the other favorited groups. A
  "group" = a favorited BoxSet (usually with BoxSet children). Live set as of 2026-07-01: New Releases,
  Directors, Decades, Genres, Studios, Seasonal, Movie Stars, Rewatchables, Cities, Oscars, Roger
  Ebert, Asian Cinema, Film School Classics, Critically Acclaimed. **Curated was retired (unfavorited)
  2026-06-30**; its members were promoted or refiled (see `FILING_MAP.md` update note).
- Studio **Logo/Thumb** images + studio **Overviews** (from `studio_blurbs.json`, 92 studios).
- The enrich feature store as the source for curated / Oscar / Ebert / Foreign / Vibes / Movie-Stars /
  Best-of-Decade sets, and the `bruno-sig:NN` significance tags behind the Best-of-Decade shelf.

> ⚠️ **Seam fragility (operational, not a code bug):** the integration hinges on one live Jellyfin server
> (URL/token in `BRUNO_NOTES.md` §SDK — never hardcode elsewhere) and a literal lowercased match on the
> group name `"genres"`. A server move, token change, or group rename silently changes what Bruno shows,
> and Bruno has **no fallback** (no tag source). Pipeline writes should stay DRY-RUN-first.

## What's here (snapshots)

| Doc | What it specifies |
|---|---|
| `PLAN.md` | The enrich pipeline phases p1→p7 (spine → TMDB → LLM-tag → QC → awards → significance → materialize) |
| `TAGGING_SPEC.md` | The LLM sub-genre tagging pass (vocabulary, batch format) |
| `GENRE_MAP.md` | Sub-genre vs broad-genre taxonomy + near-duplicate clustering rules |
| `FILING_MAP.md` | How each pipeline output (BoxSet) files into the Bruno app surfaces. NOT a snapshot: Bruno-authored, lives only in this repo (relocated from PROJECT_TRACKER 2026-06-28) |

## Bruno-side counterparts (authoritative, in this repo)

- `docs/pipeline/FILING_MAP.md` — the "Enrichment → Bruno filing map" (how each pipeline output files into the app)
- `docs/BRUNO_MOVIES_GENRE_SURFACE.md` — how the Movies tab renders the genre BoxSets
- `docs/reference/GENRE_RECS_ARCHITECTURE.md` — the (unbuilt) "IF YOU LIKE" rec-lens design
- `docs/BRUNO_NAV_MAP.md` — where each BoxSet group surfaces in the tvOS UI
