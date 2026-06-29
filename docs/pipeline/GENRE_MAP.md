# Bruno genre map — proposal (where every category lives)

Built from an LLM tagging pass over all **1,133 films** (vocab tags + freeform discovery), weighed against
the **current** `Build-Jellyfin-Collections.command` structure. Counts = films with that tag at conf ≥0.5.
Nothing is written to Jellyfin yet — this is the map to approve first.

**Legend:** `(n)` = library hit count · **[NEW]** proposed · **[EXISTS]** already built · **[thin]** under ~6,
needs a seed-list pad · **EXCL** = pull out of its broad parent (mishmash cleanup).

---

## The 6 group tiles (unchanged) + what changes inside each

```
New Releases · Directors · Decades · Genres · Studios · Curated · Seasonal
                              │                          │         │
                       +Best of Decade            +Chicago,        +Valentine's,
                                                   Oscars(6),       Fall, Summer
                                                   Ebert, Vibes
```

---

## GENRES tile — core genres with nested sub-genres

Each **CORE** genre stays (broad, min 8). Sub-genres nest beneath. Exclusivity noted per the owner's rule.

### ACTION (242)
- **Superhero (28)** [NEW] **EXCL → remove from Sci-Fi (15) & Fantasy (4); keep in Action**
- **Action Hero (51)** [NEW] — Willis/Arnold/Stallone beefcake
- **Spy (54)** [NEW] — shared w/ Thriller; action-spy (Bond, M:I) stays in Action too
- **Heist (42)** [NEW] — shared w/ Crime
- **Martial Arts (~17)** [NEW, from discovery]
- **Disaster (14)** [EXISTS] — widen seed list (2012, Volcano, San Andreas, Day After Tomorrow missing on disk)

### THRILLER (280)
- **Spy (54)** · **Paranoia (99)** [NEW] · **Twist (39)** [NEW]
- **Political Thriller (17)** [NEW, cluster: political/cold_war/whistleblower]
- Erotic Thriller (4) [thin — fold or pad]

### CRIME (221)
- **Gangster (57)** [NEW] · **Heist (42)** · **Con Artist (15)** [NEW]
- **Noir (126)** [NEW] — biggest sub-genre; cross-cuts Crime/Thriller/Drama/Mystery, home base = Crime
- **Whodunit / Serial Killer (36)** [NEW, from discovery]

### SCIENCE FICTION (151)  *(Superhero removed per owner)*
- **Alien (79)** [NEW] — **ADDITIVE, do NOT pull** (75/79 are the Sci-Fi spine)
- **Time Travel (28)** [NEW] · **Dystopia (25)** [NEW] · **Space Opera (8)** [NEW]
- **Mind Blower (57)** [NEW] — also surfaced under Curated→Vibes (cross-genre)

### HORROR (64)
- **Isolation (77)** [NEW] — cross-cuts; home base Horror (The Thing/Shining/Witch)
- Slasher (7) · Folk Horror (5) · Body Horror (6) · Creature Feature (6) [all NEW, thin-ish → one "Horror Sub-genres" rollup of 24]

### COMEDY (384)
- **Satire / Parody (49)** [NEW, cluster] · **Dark Comedy** [EXISTS combo]
- **Hangout (39)** [NEW] · **College (15)** [NEW] · **Buddy (11)** [NEW]
- **Ratatat / Screwball (17)** [NEW] — your fast-talk genre
- Mockumentary (3) [too few → fold into Satire]

### DRAMA (597)
- **Coming of Age (78)** [NEW] — huge · **Biopic (81)** [NEW] — huge
- **Sports (53)** [NEW] · **Courtroom (22)** [NEW] · **Music (72)** [NEW]
- **Indie Stress (19)** [NEW] — your genre; also Curated→Vibes
- Period Drama (11) · Grief/Character (17) [thematic — optional]

### ROMANCE (241) — keep existing sub-genres
- Classic Romance · RomCom All-Timers · Bromance · Teen Romance [all EXIST]
- **Period Romance (9)** [NEW]

### WAR (72) — the new sub-genre tree you asked for
- **Ancient (4)** [NEW, thin — pad: Gladiator/300/Troy/Spartacus/Alexander/Ben-Hur]
- **Historical post-medieval→pre-WW1 (12)** [NEW] — Glory, Patriot, Last of the Mohicans, Master & Commander
- **World War I & II (38)** [NEW] — the big one
- **Vietnam (4)** [NEW, thin — pad: Apocalypse Now/Platoon/FMJ/Deer Hunter/Born on 4th]
- **Modern / post-9-11 (14)** [NEW] — Hurt Locker, American Sniper, Zero Dark Thirty

### Standalone cores kept as-is
Adventure (195) · Mystery (92) · Family (92) · Animation (77) · History (60) · Fantasy (97) ·
**Western (17 + neo 12 = ~29)** [EXISTS, healthy] · Music (see Drama)

> **COMBOS to retire:** "Action Sci-Fi", "Sci-Fi Adventure", "Crime Thriller" etc. become redundant once
> proper sub-genres exist. Keep "Dark Comedy" & the Romantic combos; drop the rest to cut mishmash.

---

## CURATED tile

| Shelf | Count | Status |
|---|---|---|
| Film School Classics, Critically Acclaimed, Asian Cinema, Oscar Buzz | — | [EXISTS] |
| **Chicago Movies** | 23 | [NEW] |
| **Foreign Film** | 77 | [NEW] (or promote to its own tile) |
| **Oscar Categories** → Best Picture / Directing / Acting / Cinematography / Score / Screenplay | — | [NEW] **needs Academy dataset (Phase 4)** |
| **Ebert Thumbs Up / Thumbs Down** | — | [NEW] **needs Ebert dataset (Phase 4)** |
| **Bruno Vibes** → Indie Stress (19), Hangout (39), Mind Blowers (57), Ratatat (17) | — | [NEW] your personal genres, grouped |

> The per-film "Winner/Nominated (year)" second line under Oscar posters is **not** a Jellyfin collection
> capability — it ships as a Bruno app annotation fed by a per-item tag. **BUILT** (PR for branch
> `claude/modest-goodall-5fe0fc`): producer `enrich/p9_oscars.py` stamps `oscar:<CATEGORY>:<won|nom>:<YEAR>`
> per film; the app renders *Winner (Year)* / Nominee (Year) and orders Oscar shelves reverse-chron
> (`BrunoOscarContentView`, `BrunoOscar`). Owner runs `LIVE=1 p9_oscars.py` to apply.

---

## SEASONAL tile

| Shelf | Count | Status |
|---|---|---|
| Christmas | 36 | [EXISTS] |
| Halloween | 7 + Horror | [EXISTS] |
| 4th of July | 4 + War | [EXISTS] |
| **Summer Blockbusters** | 47 | [NEW] |
| **Valentine's Day** | 4 + Romance | [NEW, thin — pad] |
| **Fall / Thanksgiving** | 3 | [NEW, thin — pad: Planes Trains, When Harry Met Sally, Dutch] |

---

## DECADES tile
- **Best of the [Decade] (1)** [NEW] — significance score (`bruno-sig`) per the spec; first shelf inside each
  decade. Pipeline = Phase 5 (revenue + acclaim + cultural percentile). App = ~30 lines.

---

## Discovery shelves worth GRADUATING (strong, cross-genre, currently homeless)
Ranked by hits — these aren't in the current build at all:
1. **Biopic (81)** · 2. **Coming of Age (78)** · 3. **Sports (53)** · 4. **Satire (49)** ·
5. **Whodunit/Serial Killer (36)** · 6. **Dystopia (33)** · 7. **Revenge/Vigilante (31)** ·
8. **Road Trip (28)** · 9. **Survival (24)**

Hold for later (thinner / fuzzier): fish_out_of_water (27, fuzzy), grief (17), con_artist (15),
political_thriller (17), prison (8), workplace (7), lgbtq (6).

---

## Mishmash cleanup rules (the "reduce genre/sub-genre mishmash" ask)
- **Superhero** → remove from **Sci-Fi & Fantasy**, keep in Action. (Cleans 15 + 4 entries.)
- **Spy** → Thriller sub-genre; action-spy (Bond, M:I) ALSO in Action.
- **Alien** → ADDITIVE (stays in Sci-Fi — it *is* 75/79 of Sci-Fi).
- **Noir, Gangster, Heist, etc.** → additive sub-genres (don't strip the parent).
- **Retire redundant COMBOS** once sub-genres exist.

## Thin shelves needing a hand-seeded pad (<6 on disk)
war_ancient (4), war_vietnam (4), valentines (4), thanksgiving_fall (3), mockumentary (3→fold),
erotic_thriller (4), folk/body/creature horror (5–6 each → consider one rollup).

---

## Open decisions for the owner
1. Which of the 9 "graduate" discovery shelves do you actually want? (I lean: all but maybe Road Trip.)
2. **Foreign Film (77):** its own top-level tile, or under Curated?
3. Retire the redundant genre COMBOS, or keep them alongside the new sub-genres?
4. Oscar + Ebert shelves need me to compile external datasets (Phase 4) — green-light?
5. Horror sub-genres: 4 separate thin shelves, or one "Horror Sub-genres" rollup (24)?
