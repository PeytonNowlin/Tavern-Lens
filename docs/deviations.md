# Deviations from the v1 spec

Where Tavern Lens v1 does something narrower or different from what `docs/spec/tavern-lens-v1.md`
asks for, and why. Each entry names the story or section it's about.

## The alignment check is banner-based (story 66)

The spec asks for a once-per-game check that the overlay is aligned with the game. The check uses
the hero-pick banner, and nothing else:

- The hero-pick screen reader (`HeroPickScreenReader`) captures the banner region once per game to
  read the lobby's tribes. The same Vision pass finds the banner's title, and the layout's
  `alignment(ofTitleFoundAt:)` (`OverlayLayout/HeroPickBanner.swift`) compares where it was found
  with where the layout constants put it. An offset beyond `alignmentTolerance` (0.012 of the
  frame's height) or a size off by more than `sizeTolerance` (12%) shows the overlay's alignment
  warning, which points at Show Layout Guides.
- So the check measures one element, at the hero pick. It catches a patch that moves or rescales
  the whole screen (the common case, since every overlay rect comes from the same frame
  geometry), but not one that moves a single panel, such as the shop or the leaderboard, while
  the banner stays put.

Why: the banner is the only element with fixed, readable text on every game's screen, and it is
read anyway for the tribes, so the check costs no extra capture. Checking other panels would need
a capture during recruit and a text or shape anchor per panel. The patch-day checklist still
includes a manual pass with the layout guides for that.

## The advisor's lobby term covers the baseline and the top candidates only (story 55)

Story 55 wants the advisor to weigh strength against the rest of the lobby. The lobby term is
simulated only for the board as it is (the baseline) and the best `lobbyGroups` board changes (3
live), each against every other living opponent's last-seen board. Every other suggestion has no
lobby term (nil, counted as 0). See `docs/advisor/scoring.md`, "Lobby".

Why: the lobby pass costs one evaluation per candidate per opponent. A late recruit phase has
around 30 candidates and up to 6 other opponents, so scoring all of them would be about 180
evaluations on top of the combat passes, far past the few seconds per state the live plan has.
And the lobby term rarely decides between candidates the other terms already rank low:

- the next combat, the build and the economy terms order the candidates first;
- the lobby term mostly settles close calls among the top few, which is where it's spent;
- a lower-ranked candidate would need a large lobby gain to overtake them, and the refine pass
  would already have shown it as close.

The consequence is that a board change that's only good against the rest of the lobby, and bad
against the next opponent, can't be suggested. That is the intended trade: the next combat is the
one the advice is about.

## Against an unseen next opponent, the advisor scores against a stand-in (stories 48–52)

The spec's advice is about the next combat against the next opponent's last-seen board. When the
next opponent hasn't been fought yet, the advisor scores the combat term against the most recently
seen opponent's board instead (the odds preview still shows no data). See `docs/advisor/scoring.md`,
"An unseen next opponent".

Why: matchmaking avoids recent opponents, so the next opponent is often one not fought yet. A game
with a new opponent every turn for its first seven turns (a playtest on 2026-09-23) had no advice at
all. A recent board is a fair guess at what boards look like now, so advice against it is better
than none. It is marked as a guess: at most medium confidence, reasons that name it, and a note.
