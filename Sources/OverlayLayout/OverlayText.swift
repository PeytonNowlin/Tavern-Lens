/// The overlay's presentation text and the decisions behind it, kept out of the views so they
/// can be tested. Everything takes plain values: the views pass in what they read from the
/// engine's view types.
public enum OverlayText {
    /// "74%", "<1%" for a small non-zero chance, ">99%" for a near-certain one.
    public static func percent(_ value: Double) -> String {
        if value > 0, value < 1 { return "<1%" }
        if value < 100, value > 99 { return ">99%" }
        return "\(Int(value.rounded()))%"
    }

    /// "8.8 (7–13)", or "–" when no simulation ended that way.
    public static func damage(average: Double?, range: ClosedRange<Int>?, any: Bool) -> String {
        guard any, let average else { return "–" }
        let mean = String(format: "%.1f", average)
        guard let range else { return mean }
        return range.lowerBound == range.upperBound
            ? "\(mean) (\(range.lowerBound))" : "\(mean) (\(range.lowerBound)–\(range.upperBound))"
    }

    /// How many simulations have run ("850", "2.5k"), with "…" while more are coming. Without a
    /// result yet it is "…", or empty when the calculation failed.
    public static func progress(simulations: Int?, isFinal: Bool, isUpdating: Bool = false, failed: Bool = false) -> String {
        guard let simulations else { return failed ? "" : "…" }
        let count = simulations >= 1000 ? String(format: "%.1fk", Double(simulations) / 1000) : String(simulations)
        return isFinal && !isUpdating ? count : "\(count)…"
    }

    /// The combat odds panel's footer warning, most urgent first.
    public enum CombatWarning: Equatable, Sendable {
        case unavailable
        /// The chance this combat eliminates the local player.
        case lethalRisk(String)
        /// The chance this combat eliminates the opponent.
        case lethalChance(String)
    }

    public static func combatWarning(failed: Bool, lethalRisk: Double?, lethalChance: Double?) -> CombatWarning? {
        if failed { return .unavailable }
        if let lethalRisk { return .lethalRisk("Lethal \(percent(lethalRisk))") }
        if let lethalChance { return .lethalChance("Lethal \(percent(lethalChance))") }
        return nil
    }

    // MARK: Next-opponent odds preview

    /// What the preview's odds section has to go on.
    public struct PreviewInput: Equatable, Sendable {
        /// Whether the opponent's board has been seen (the preview knows before the first request).
        public var seen: Bool
        /// Nil before the first request reaches the preview.
        public var request: Request?

        public struct Request: Equatable, Sendable {
            public var hasData: Bool
            public var bgTurn: Int
            public var opponentSeenTurn: Int?
            public var failure: String?
            public var isUpdating: Bool
            public var hasResult: Bool

            public init(hasData: Bool, bgTurn: Int, opponentSeenTurn: Int?, failure: String?, isUpdating: Bool,
                        hasResult: Bool) {
                self.hasData = hasData
                self.bgTurn = bgTurn
                self.opponentSeenTurn = opponentSeenTurn
                self.failure = failure
                self.isUpdating = isUpdating
                self.hasResult = hasResult
            }
        }

        public init(seen: Bool, request: Request?) {
            self.seen = seen
            self.request = request
        }
    }

    public enum PreviewState: Equatable, Sendable {
        /// A message in place of the odds.
        case status(title: String, detail: String, isWarning: Bool, help: String?)
        /// The odds are ready to show.
        case odds
    }

    /// The preview's odds section: why there are no odds, or that there are. Unseen and stale
    /// boards explain themselves; a changed board shows an explicit updating state.
    public static func previewState(_ input: PreviewInput, staleBoardTurns: Int) -> PreviewState {
        let request = input.request
        if !input.seen || request?.hasData == false {
            return .status(title: "No odds", detail: "Not fought yet", isWarning: false, help: nil)
        }
        if let request, let seenTurn = request.opponentSeenTurn, request.bgTurn - seenTurn >= staleBoardTurns {
            return .status(title: "Board too old", detail: "No odds shown", isWarning: true, help: nil)
        }
        if let failure = request?.failure {
            return .status(title: "Odds unavailable", detail: "Calculation failed", isWarning: true, help: failure)
        }
        if request?.isUpdating == true || request?.hasResult != true {
            return .status(title: "Updating…", detail: request?.isUpdating == true ? "Board changed" : "Calculating…",
                           isWarning: false, help: nil)
        }
        return .odds
    }

    /// The line under the preview's bar: the lethal warning, else the likelier damage.
    public enum PreviewFootnote: Equatable, Sendable {
        case lethal(String)
        case take(String)
        case deal(String)
    }

    public static func previewFootnote(won: Double, lost: Double, averageDamageWon: Double, averageDamageLost: Double,
                                       lethalRisk: Double?) -> PreviewFootnote? {
        if let lethalRisk { return .lethal("Lethal \(percent(lethalRisk))") }
        if lost >= won, lost > 0 { return .take("Take \(String(format: "%.1f", averageDamageLost))") }
        if won > 0 { return .deal("Deal \(String(format: "%.1f", averageDamageWon))") }
        return nil
    }

    // MARK: Opponent panels

    /// "Seen turn 7 (last turn)".
    public static func seen(bgTurn: Int, currentTurn: Int) -> String {
        let ago = currentTurn - bgTurn
        let when = switch ago {
        case ...0: "this turn"
        case 1: "last turn"
        default: "\(ago) turns ago"
        }
        return "Seen turn \(bgTurn) (\(when))"
    }

    /// "Unseen", "This turn" or "3t old", for the next-opponent preview's header.
    public static func previewAge(seenTurn: Int?, currentTurn: Int) -> String {
        guard let seenTurn else { return "Unseen" }
        let age = max(0, currentTurn - seenTurn)
        return age == 0 ? "This turn" : "\(age)t old"
    }

    public static func ordinal(_ n: Int) -> String {
        let suffix = switch (n % 10, n % 100) {
        case (_, 11...13): "th"
        case (1, _): "st"
        case (2, _): "nd"
        case (3, _): "rd"
        default: "th"
        }
        return "\(n)\(suffix)"
    }

    /// A hero's health: "0" once dead.
    public static func health(hp: Int, isDead: Bool) -> String { isDead ? "0" : "\(hp)" }

    /// "4/5", or empty for a card without stats.
    public static func stats(attack: Int?, health: Int?) -> String {
        guard let attack, let health else { return "" }
        return "\(attack)/\(health)"
    }
}
