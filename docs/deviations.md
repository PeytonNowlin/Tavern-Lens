# Deviations from the v1 spec

Where Tavern Lens v1 does something narrower or different from what `docs/spec/tavern-lens-v1.md`
asks for, and why. Each entry names the story or section it's about.

## Policy 11 source and effect limits

The card-by-turn feed is an undocumented, unversioned public aggregate. The app
pins its source window and percentile, validates freshness and the active pool,
and archives exact accepted rows. It cannot prove which client build produced
the aggregate or remove purchase-selection and survivorship bias. Influence
remains small and positive; observed current-state effects and combat checks
remain the stronger evidence. No improvement in placement or MMR is established.

Lionfish support covers verified deterministic attack chains only. Missing
generated-card definitions and unmodelled friendly attack/death effects remain
visible gaps. Population hero warband averages lack per-turn samples and tail
distributions, so they are retained rather than used as lethal-risk forecasts.

Outgoing selection packets contain only actions actually logged by the client.
They do not recover unlogged UI gestures or prove the player followed advice.
Action records use bounded local storage without uploading game logs.

## Archived advisor version 1: against an unseen next opponent or an old board, the advisor scores against a stand-in (stories 48–52)

The live version-2 planner replaces this policy with strategic plans and multiple combat scenarios;
see [scoring](advisor/scoring.md). This entry describes archived version-1 bookmark replay.

The spec's advice is about the next combat against the next opponent's last-seen board. When the
next opponent hasn't been fought yet, or their board is 3 or more turns old, the advisor scores the
combat term against the most recently seen opponent's board instead (the odds preview still shows
the next opponent's own board, or no data). See `docs/advisor/scoring.md`, "An unseen next
opponent, or an old board".

Why: matchmaking avoids recent opponents, so the next opponent is often one not fought yet. A game
with a new opponent every turn for its first seven turns (a playtest on 2026-09-23) had no advice at
all. A recent board is a fair guess at what boards look like now, so advice against it is better
than none. It is marked as a guess: at most medium confidence, reasons that name it, and a note.
Likewise a board 3-5 turns old: in a later playtest the advisor gave a 100% win against such boards
on three turns that were lost, the last one lethally; against the freshest board it gave 0-1%.
