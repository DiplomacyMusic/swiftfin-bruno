# SPEC — Romance categories for Build-Jellyfin-Collections.command

**APPLIED (2026-06-26).** Adds 4 romance sub-genre shelves driven by library metadata so they
self-populate on every run, **nested under the Genres tile** — NOT Curated. Bruno keyword-buckets
them into the "Romance" core genre, so they only need to live under Genres. (An earlier run mistakenly
nested them under Curated too; the script now un-nests them from Curated on every run — see "Grouping
choice" below.) Target file: `Build-Jellyfin-Collections.command`.

## Categories & rules

| Shelf | Rule | Notes |
|---|---|---|
| **Classic Romance** | Genre includes `Romance` AND `1 ≤ year ≤ 1979` | pure metadata |
| **RomCom All-Timers** | (Genres ⊇ `{Romance, Comedy}` AND person ∈ ROM_PEOPLE) OR title ∈ ROMCOM_TITLES | person = cast or director; requires BOTH genres so dramas don't sweep in |
| **Bromance** | title ∈ BROMANCE_TITLES **AND year ≥ 1980** | hand-picked list; pre-1980 excluded (owner) |
| **Teen Romance** | title ∈ TEEN_ROM_TITLES | hand-picked list |

ROM_PEOPLE = Julia Roberts, Meg Ryan, Tom Hanks, Sandra Bullock, Nora Ephron, Nancy Meyers
ROMCOM_TITLES = Maid in Manhattan, Sweet Home Alabama, Jerry Maguire, Dirty Dancing, Road House
BROMANCE_TITLES = Top Gun, Jerry Maguire, Say Anything…, Cocktail, Before Sunrise/Sunset/Midnight, Casablanca, Doctor Zhivago
TEEN_ROM_TITLES = Pretty in Pink, 10 Things I Hate About You, Can't Hardly Wait

## Edit 1 — extract cast (script currently reads directors only)

The data fetch (line ~87) already includes `People`, so no fetch change. Inside the
`for it in movies:` loop, right after the existing `dirs={...}` / `nm=norm(...)` line (~178-179), add:

```python
    cast = {norm(p["Name"]) for p in it.get("People", []) if p.get("Type") == "Actor"}
    dirs_n = {norm(d) for d in dirs}        # dirs is raw names; normalize for matching
```

## Edit 2 — add the title/people sets

Next to the other curated sets (after `PATRIOTIC = {...}`, ~line 169), add:

```python
ROM_PEOPLE = {norm(x) for x in ["Julia Roberts","Meg Ryan","Tom Hanks","Sandra Bullock",
 "Nora Ephron","Nancy Meyers"]}
ROMCOM_TITLES = {norm(x) for x in ["Maid in Manhattan","Sweet Home Alabama","Jerry Maguire",
 "Dirty Dancing","Road House"]}
BROMANCE_TITLES = {norm(x) for x in ["Top Gun","Jerry Maguire","Say Anything...","Cocktail",
 "Before Sunrise","Before Sunset","Before Midnight","Casablanca","Doctor Zhivago"]}
TEEN_ROM_TITLES = {norm(x) for x in ["Pretty in Pink","10 Things I Hate About You","Can't Hardly Wait"]}
```

## Edit 3 — add the 4 `add()` calls

In the curated block of the loop, after the `if nm in OSCARS:` line (~195), add:

```python
    if "Romance" in genres and 0<yr<=1979:
        add("genre","Classic Romance","3 genre 1 romance 1 classic",4,it)
    if ({"Romance","Comedy"}<=genres and (cast|dirs_n)&ROM_PEOPLE) or nm in ROMCOM_TITLES:
        add("genre","RomCom All-Timers","3 genre 1 romance 2 romcom",4,it)
    if nm in BROMANCE_TITLES and yr>=1980:   # owner: Bromance excludes movies older than 1980
        add("genre","Bromance","3 genre 1 romance 3 bromance",3,it)
    if nm in TEEN_ROM_TITLES:
        add("genre","Teen Romance","3 genre 1 romance 4 teen",2,it)
```

They nest under the **Genres** group tile (cat `"genre"`), sorted beside Romantic Comedy/Drama (keys
`3 genre 1 romance 1→4`). Posters come for free from the script's "unique member poster" pass.
`minsize` per shelf (4/4/3/2) is set so each actually creates given current counts.

## Grouping choice

Implemented as **Genres** sub-shelves (cat `"genre"`), because Bruno's Genres page keyword-buckets any
sub-collection whose name matches `romance/romantic/romcom/rom-com` into the "Romance" core genre — so
all four land in Romance with NO app change. (The original draft of this spec said Curated; that was
wrong for the Bruno IA.) Because the build only ever *adds* collections to a group tile, a stale run that
had nested these under **Curated** leaves them there — so the script now also **un-nests them from the
Curated tile** every run (`ROMANCE_SUBGENRES` removal after the group-tile pass; idempotent). A dedicated
top-level **Romance** tile would be a bigger change (add a `"romance"` entry to `CATS` + `GLABEL`); not
needed, since the keyword bucket already gives a Romance row.

## Tuning notes / gotchas

- **RomCom is broad by design.** "Any Romance-tagged [person] movie" sweeps in dramatic titles
  (e.g. Forrest Gump, Closer via Tom Hanks/Julia Roberts). To restrict to true rom-coms, change the
  people clause to require both genres: `{"Romance","Comedy"} <= genres and (cast|dirs_n) & ROM_PEOPLE`.
- **Road House ambiguity.** Title-only match also catches the **2024 remake** if it's in the library.
  If you only want the 1989 Swayze film, year-guard it (e.g. include in a `(title, year)` check)
  rather than the plain title set. (Same theoretical risk applies to the existing CLASSICS/OSCARS sets.)
- **Newly-added titles populate on the next run after they finish downloading** — e.g. Can't Hardly
  Wait (Teen) and Doctor Zhivago (Bromance) are still acquiring; they'll appear automatically once on disk.
- **Item #1 ("two-card genre shelf") is NOT specced** — no genre collection currently has 2 members
  (every 2-card collection is a TMDB movie-franchise set, e.g. Dune/Batman). It may be a Jellyfin
  home-screen genre row (Dashboard → user → Home screen layout) or a Bruno UI row, not a collection.
  Needs the shelf named before any removal can be specced.

## Apply

Make the 3 edits, save, double-click the .command (or run its python block). Coordinate with the
Jellyfin/Bruno thread first if it edits this same file or manages live collections concurrently.
