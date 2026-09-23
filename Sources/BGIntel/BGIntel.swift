// BGIntel: Battlegrounds intelligence built on BGState snapshots and HSData.
//
// - TribeResolver.swift: the lobby's tribes from shop draws, opponent boards, heroes and
//   (from #14) the hero-pick banner read from the screen
// - BuildDetector.swift: the builds a board leans into (with turn-to-turn hysteresis), an
//   opponent's likely build, and the shop highlighter
// - Advisor/: the advisor's recruit-phase request, candidate actions (buy, play, sell, swap,
//   cast, move, level, roll, freeze) with their hypothetical boards, and the ranking of their
//   simulated odds into suggestions with reasons and confidence (scoring runs in TavernEngine)
//
// Planned (see docs/spec/tavern-lens-v1.md): build detector, shop highlighter, hero-pick
// stats, simulator adapter and advisor.
