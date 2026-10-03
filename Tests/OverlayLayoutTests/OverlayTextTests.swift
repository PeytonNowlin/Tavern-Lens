import Testing
@testable import OverlayLayout

/// The overlay's presentation text and the decisions behind it.
@Suite("Overlay text")
struct OverlayTextTests {
    @Test("Percent rounds, and keeps the extremes honest")
    func percent() {
        #expect(OverlayText.percent(74.4) == "74%")
        #expect(OverlayText.percent(0) == "0%")
        #expect(OverlayText.percent(0.3) == "<1%")
        #expect(OverlayText.percent(99.4) == ">99%")
        #expect(OverlayText.percent(100) == "100%")
    }

    @Test("Damage shows the mean with its range, or a dash when nothing ended that way")
    func damage() {
        #expect(OverlayText.damage(average: 8.84, range: 7...13, any: true) == "8.8 (7–13)")
        #expect(OverlayText.damage(average: 5, range: 5...5, any: true) == "5.0 (5)")
        #expect(OverlayText.damage(average: 5, range: nil, any: true) == "5.0")
        #expect(OverlayText.damage(average: 5, range: 1...2, any: false) == "–")
        #expect(OverlayText.damage(average: nil, range: nil, any: true) == "–")
    }

    @Test("Progress counts simulations, with an ellipsis until final or while updating")
    func progress() {
        #expect(OverlayText.progress(simulations: nil, isFinal: false) == "…")
        #expect(OverlayText.progress(simulations: nil, isFinal: false, failed: true) == "")
        #expect(OverlayText.progress(simulations: 850, isFinal: false) == "850…")
        #expect(OverlayText.progress(simulations: 850, isFinal: true) == "850")
        #expect(OverlayText.progress(simulations: 2500, isFinal: true) == "2.5k")
        #expect(OverlayText.progress(simulations: 2500, isFinal: true, isUpdating: true) == "2.5k…")
    }

    @Test("The combat warning puts failure first, then the risk to you, then the chance to win outright")
    func combatWarning() {
        #expect(OverlayText.combatWarning(failed: true, lethalRisk: 5, lethalChance: 5) == .unavailable)
        #expect(OverlayText.combatWarning(failed: false, lethalRisk: 4, lethalChance: 9) == .lethalRisk("Lethal 4%"))
        #expect(OverlayText.combatWarning(failed: false, lethalRisk: nil, lethalChance: 0.2) == .lethalChance("Lethal <1%"))
        #expect(OverlayText.combatWarning(failed: false, lethalRisk: nil, lethalChance: nil) == nil)
    }

    private func request(
        hasData: Bool = true, bgTurn: Int = 8, seenTurn: Int? = 7, failure: String? = nil,
        isUpdating: Bool = false, hasResult: Bool = true
    ) -> OverlayText.PreviewInput.Request {
        .init(hasData: hasData, bgTurn: bgTurn, opponentSeenTurn: seenTurn, failure: failure,
              isUpdating: isUpdating, hasResult: hasResult)
    }

    private func state(seen: Bool = true, _ request: OverlayText.PreviewInput.Request?) -> OverlayText.PreviewState {
        OverlayText.previewState(.init(seen: seen, request: request), staleBoardTurns: 3)
    }

    @Test("The preview explains why there are no odds, in priority order")
    func previewState() {
        #expect(state(seen: false, request()) == .status(title: "No odds", detail: "Not fought yet", isWarning: false, help: nil))
        #expect(state(request(hasData: false)) == .status(title: "No odds", detail: "Not fought yet", isWarning: false, help: nil))
        // Stale beats a failure; the boundary turn counts as stale.
        #expect(state(request(bgTurn: 10, seenTurn: 7, failure: "x"))
                == .status(title: "Board too old", detail: "No odds shown", isWarning: true, help: nil))
        #expect(state(request(bgTurn: 9, seenTurn: 7, hasResult: true)) == .odds)
        #expect(state(request(failure: "boom"))
                == .status(title: "Odds unavailable", detail: "Calculation failed", isWarning: true, help: "boom"))
        #expect(state(request(isUpdating: true))
                == .status(title: "Updating…", detail: "Board changed", isWarning: false, help: nil))
        #expect(state(request(hasResult: false))
                == .status(title: "Updating…", detail: "Calculating…", isWarning: false, help: nil))
        // Before the first request reaches the preview, a seen board is "calculating".
        #expect(state(nil) == .status(title: "Updating…", detail: "Calculating…", isWarning: false, help: nil))
        #expect(state(request()) == .odds)
        #expect(state(request(seenTurn: nil, hasResult: true)) == .odds)
    }

    @Test("The footnote prefers lethal, then the likelier damage")
    func previewFootnote() {
        func note(won: Double, lost: Double, risk: Double? = nil) -> OverlayText.PreviewFootnote? {
            OverlayText.previewFootnote(won: won, lost: lost, averageDamageWon: 6.25, averageDamageLost: 3.04, lethalRisk: risk)
        }
        #expect(note(won: 90, lost: 10, risk: 2) == .lethal("Lethal 2%"))
        #expect(note(won: 40, lost: 60) == .take("Take 3.0"))
        #expect(note(won: 50, lost: 50) == .take("Take 3.0"))
        #expect(note(won: 70, lost: 30) == .deal("Deal 6.2"))
        #expect(note(won: 0, lost: 0) == nil)
    }

    @Test("Opponent text")
    func opponentText() {
        #expect(OverlayText.seen(bgTurn: 7, currentTurn: 7) == "Seen turn 7 (this turn)")
        #expect(OverlayText.seen(bgTurn: 7, currentTurn: 8) == "Seen turn 7 (last turn)")
        #expect(OverlayText.seen(bgTurn: 4, currentTurn: 8) == "Seen turn 4 (4 turns ago)")
        #expect(OverlayText.previewAge(seenTurn: nil, currentTurn: 8) == "Unseen")
        #expect(OverlayText.previewAge(seenTurn: 8, currentTurn: 8) == "This turn")
        #expect(OverlayText.previewAge(seenTurn: 5, currentTurn: 8) == "3t old")
        #expect([1, 2, 3, 4, 8, 11, 12, 13, 21, 22].map(OverlayText.ordinal)
                == ["1st", "2nd", "3rd", "4th", "8th", "11th", "12th", "13th", "21st", "22nd"])
        #expect(OverlayText.health(hp: -3, isDead: true) == "0")
        #expect(OverlayText.health(hp: 27, isDead: false) == "27")
        #expect(OverlayText.stats(attack: 4, health: 5) == "4/5")
        #expect(OverlayText.stats(attack: nil, health: 5) == "")
    }

    @Test("The panel outline is one opacity")
    func chrome() {
        #expect(PanelChromeMetrics().strokeOpacity == 0.12)
    }
}
