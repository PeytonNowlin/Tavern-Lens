# Tavern Lens

A macOS companion for Hearthstone Battlegrounds that reads the game log and advises the player during the recruit phase.

## Language

### Recruit advisor

**Recruit plan**:
A bounded sequence of recruit-phase actions (buy, play, sell, cast, activate, level, refresh, freeze, move) the advisor evaluates from the observed state.
_Avoid_: Line, move list

**Policy version**:
The numbered advisor behaviour a recruit plan was evaluated under. An archived request replays under its own policy version.
_Avoid_: Evaluation version (in prose), advisor version

**Card effect**:
Everything the advisor knows about one card beyond the generic text grammar: which exact definition it accepts, the policy version it entered at, and how it changes a recruit plan.
_Avoid_: Card handler, card rule

**Card-effect table**:
The set of all card effects, each owning distinct card IDs.
_Avoid_: Registry, card database

**Generic text grammar**:
The advisor's recognition of common effect wording (for example "Give a minion +N/+N.") on any card that has no card effect of its own.
_Avoid_: Fallback parser

**Limitation**:
A reason a recruit plan, or the projection after it, cannot be claimed exactly, such as an unmodelled trinket or an unknown random reward.
_Avoid_: Warning, caveat
