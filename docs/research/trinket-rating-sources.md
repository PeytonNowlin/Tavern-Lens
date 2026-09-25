# Trinket rating sources

Checked 2026-09-24. The app combines a modest population prior with local board-fit estimates;
these are not causal win probabilities or an optimal recruit policy.

- **Firestone public aggregates:**
  [upstream service](https://github.com/Zero-to-Heroes/firestone/blob/master/libs/battlegrounds/services/src/lib/services/bgs-trinkets.service.ts)
  identifies `https://static.zerotoheroes.com/api/bgs/trinket-stats/past-three/overview-from-hourly.gz.json`.
  A live read returned 262 entries, 488,721 data points, `lastUpdateDate` 2026-09-25T00:10:27.592Z.
  Entries contain card ID, samples, average placement and MMR breakdowns. The adapter uses all-rank
  samples, requires >=200 per entry, valid placements 1–8 and an update <48 hours old. Data is fetched
  at launch/every six hours, cached locally, and attributed in the panel. No dataset is committed.
  Public access is distinct from an open-source license: the main Firestone repository does not
  declare a root code license; no application implementation or strategy prose was copied.
- **Existing MIT simulator:** npm metadata for
  [`@firestone-hs/simulate-bgs-battle@1.1.755`](https://www.npmjs.com/package/@firestone-hs/simulate-bgs-battle/v/1.1.755)
  declares MIT. Already pinned in this app. Keep using it for combat with trinkets/Deity/enchantments
  intact; it does not replace recruit-phase modelling. No dependency bump was needed.
- **[HearthstoneJSON](https://hearthstonejson.com/):** existing build-specific game card definitions,
  now also carried for equipped trinkets and Dark Gift enchantments. Preserve exact build matching.
- **[HS BG Cards API](https://hsbg.cards/api-docs):** free card metadata, most endpoints without keys;
  useful cross-check, but documented endpoints do not supply placement/pick statistics.
- **[Amalgadon API](https://www.amalgadon.com/blog/developer-api):** unauthenticated `/api/cards` provides
  BG metadata; lookup/board encoding need free keys. No documented trinket-placement feed.

Known limits: the feed has a time window, not a client-build identifier. A 48-hour freshness check
cannot guarantee patch purity. Ratings remain low confidence, show actual samples/average placement,
join only offered card IDs, and fall back to local estimates with unknown effects explicitly unrated.
Specific board-fit handlers cover the eight choices in the regression match; other choices use the
population baseline when fresh, with an explicit unmodelled-interaction reason. Do not describe this
as complete trinket effect coverage. The provider is queried anonymously; no match/player data is sent.
