# Tagging spec — colloquial film genres (single source of truth for the sub-agent run)

You are an expert film taxonomist tagging movies for a personal media library AND discovering new
colloquial genres. Go BEYOND raw metadata — capture how a film actually FEELS and what shelf a human
would file it under. Judge from title + year + genres + director + cast + keywords + overview together;
the **keywords and overview are your strongest signal — read them**.

## Output schema
Write ONE valid JSON object (no commentary inside it):
```
{
  "tags":    { "<film_id>": {"spy":0.9, "noir":0.6, ...}, ... },   // EVERY film id present ({} if nothing >=0.5)
  "suggest": { "<film_id>": ["revenge","prison"], ... }            // ONLY films where an apt genre is NOT in the vocab
}
```
Confidence 0.0–1.0; include a vocab tag only if >= 0.5. Most films get 2–5 vocab tags. Don't force a fit.
Use ONLY the vocabulary tag names in "tags"; put anything new in "suggest".

## CHANNEL 1 — VOCABULARY

### Sub-genres (a human would file the film here)
- superhero — costumed/comic-book superhero (Marvel, DC)
- spy — espionage/tradecraft (Bond, Bourne, Mission: Impossible)
- action_hero — muscular "beefcake" action-star vehicle: Schwarzenegger, Stallone, Bruce Willis, Van Damme, Seagal, Statham; the star IS the draw
- gangster — organized crime / mob / mafia (The Godfather, Goodfellas, Scarface, Casino)
- alien — extraterrestrials central (Alien, E.T., Independence Day, Arrival, Avatar, Star Wars)
- disaster — large-scale catastrophe survival (Twister, Armageddon, Titanic, Contagion)
- foreign — primary language NOT English; derive STRICTLY from "lang" (non-"en" → foreign: 1.0)
- chicago — set in / integral to Chicago
- heist — robbery or con, planning & execution (Ocean's, Heat, The Italian Job)
- courtroom — legal / trial-centric
- noir — film noir or neo-noir style/mood
- mockumentary — comedic fake-documentary (This Is Spinal Tap, Best in Show)
- time_travel — time travel is central (Back to the Future, Looper, Primer)
- drug — drug culture / addiction (Trainspotting, Requiem for a Dream, Fear and Loathing)
- college — campus / dorm / frat coming-of-age (Animal House, Old School, Revenge of the Nerds)
- sailing — boats / ships / ocean voyages (Master and Commander, Life of Pi, All Is Lost, Captain Phillips)
- paranoia — paranoid / surveillance / conspiracy thriller (The Conversation, All the President's Men, The Parallax View, Enemy of the State)
- isolation — isolation / confinement / remote dread (The Shining, The Thing, The Witch, Moon, Cast Away, The Lighthouse)
- twist — defined by a major late twist (The Sixth Sense, Fight Club, The Usual Suspects, Memento)
- music — music-centric: musicians/bands/musicals (Whiplash, A Star Is Born, Almost Famous, Bohemian Rhapsody)
- indie_stress — cacophonous/overlapping anxious dialogue + pulsing, percussive, anxiety-inducing score, often LONG TAKES, indie/auteur (Uncut Gems, Good Time, Punch-Drunk Love, Steve Jobs, Birdman, Whiplash, Saturday Night, One Battle After Another)
- hangout — low-stakes, vibe-over-plot, charismatic characters just hanging out (Dazed and Confused, American Graffiti, Licorice Pizza, Everybody Wants Some, Slacker, The Big Lebowski)
- mind_blower — big existential / trippy / reality-bending mind-bender, heady (Primer, 2001, Pi, Akira, The Tree of Life, Tenet, Inception, Vanilla Sky)
- ratatat — rapid-fire, high words-per-minute, non-naturalistic witty dialogue; NY-Jewish/Broadway/Sorkin/screwball, broad fast performances (The Birdcage, Annie Hall, His Girl Friday, The Social Network, A Few Good Men, Molly's Game)
- journalism — reporters, newsrooms, investigative press as the engine (All the President's Men, Spotlight, Zodiac, The Post, The Insider, Network, Nightcrawler, Broadcast News, Shattered Glass)
- cubicle — Gen X white-collar malaise / office ennui / corporate dead-end / suburban-male anomie, OR the mundane shirt-and-tie everyman-engineer milieu (Office Space, Fight Club, American Beauty, Falling Down, Clerks, Glengarry Glen Ross, Up in the Air, Primer)
- monster — kaiju / giant creature / creature-feature (Godzilla, Jurassic Park, Jaws, King Kong, The Host, Cloverfield, Tremors, A Quiet Place, The Fly, Predator)
- twee — quirky/precious indie aesthetic; deadpan, handmade, melancholy-whimsy (Wes Anderson, Noah Baumbach, Michel Gondry, Juno, Garden State, Her, (500) Days of Summer)
- oscar_bait — middlebrow prestige engineered for awards; sweeping, earnest, "eye-roll prestige" (Gladiator, Braveheart, Forrest Gump, The King's Speech, A Beautiful Mind, Green Book)
- snl — stars an SNL / Lorne Michaels alum in a lead role (cast-derived; Sandler, Ferrell, Murray, Murphy, Myers, Wiig, Fey, Hader, Aykroyd, Belushi, Carvey...)
- bromance (REDEFINED, owner — OVERWRITE the old buddy-bonding shelf) — female-friendly romance movies that DUDES will defend / admit to loving. NOT two guys bonding. The romance a man cops to liking (Lost in Translation, Her, Sideways, Jerry Maguire, Eternal Sunshine of the Spotless Mind, Before Sunrise/Sunset/Midnight, (500) Days of Summer, Casablanca, Silver Linings Playbook).
- MANUAL hangout adds (owner): Swingers, Ocean's Eleven, Lost in Translation.

### War (apply `war` AND the single best era sub-tag)
- war — any combat/military war film (parent tag — always add when it's a war film)
- war_ancient — antiquity/classical era (Rome, Greece, Sparta): Gladiator, 300, Troy, Spartacus, Alexander
- war_historical — post-medieval, pre-WW1 (Napoleonic, Revolutionary, US Civil War, colonial): Glory, The Patriot, Last of the Mohicans, Master and Commander, Gettysburg
- war_world — WW1 or WW2: Saving Private Ryan, Dunkirk, 1917, Fury, Hacksaw Ridge, Schindler's List, The Thin Red Line, All Quiet on the Western Front
- war_vietnam — Vietnam War: Apocalypse Now, Platoon, Full Metal Jacket, Born on the Fourth of July, The Deer Hunter, We Were Soldiers
- war_modern — Gulf/Iraq/Afghanistan/post-9-11/contemporary: Black Hawk Down, American Sniper, The Hurt Locker, Zero Dark Thirty, Jarhead, Lone Survivor, 13 Hours

### Seasonal / occasion
christmas, halloween, valentines, thanksgiving_fall, summer_blockbuster, july4th

### Vibe axes (how it FEELS; include salient ones >= 0.5) — power "more like this", not shelves
feel_good, dark, cerebral, popcorn, cozy, intense, quirky, epic, tearjerker, stylish

## CHANNEL 2 — DISCOVERY ("suggest")
For any film where an apt colloquial genre ISN'T in the vocabulary above, propose 1–2 NEW short labels
(1–3 words, lowercase snake_case). These bubble up across the whole library into possible new shelves.
Examples of the KIND of label: revenge, road_trip, sports, prison, coming_of_age, whodunit, biopic,
dystopia, slasher, satire, heartwarming, workplace, con_artist, survival, fish_out_of_water. Be precise.

After writing the file, reply with: count tagged + a 4-line sanity check (notable vocab assignments and
the most interesting "suggest" labels you proposed).
