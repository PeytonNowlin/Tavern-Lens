import BGIntel
import HSData

/// The lobby's tribes as the overlay shows them: every tribe in rotation with how sure
/// the app is, most likely first.
public struct TribesView: Codable, Hashable, Sendable {
    public var tribes: [TribeView]
    /// Every tribe is confirmed or ruled out.
    public var isResolved: Bool
    /// Contradictory or weak evidence: show the tribes as uncertain.
    public var isUncertain: Bool
    public var source: TribeSource
    /// The screen reading and the log disagree.
    public var screenConflict: Bool
    /// The pool behind the inference is from stale data (older card data or meta period).
    public var poolIsStale: Bool

    public init(
        tribes: [TribeView], isResolved: Bool, isUncertain: Bool = false, source: TribeSource = .inferred,
        screenConflict: Bool = false, poolIsStale: Bool = false
    ) {
        self.tribes = tribes
        self.isResolved = isResolved
        self.isUncertain = isUncertain
        self.source = source
        self.screenConflict = screenConflict
        self.poolIsStale = poolIsStale
    }

    /// The tribes in the lobby, or most likely to be, as many as a lobby has.
    public var lobby: [TribeView] { tribes.filter { $0.confidence == .confirmed || $0.confidence == .likely } }

    // Compact JSON: the flags are written only when set.
    private enum CodingKeys: String, CodingKey {
        case tribes, isResolved, isUncertain, source, screenConflict, poolIsStale
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tribes = try c.decode([TribeView].self, forKey: .tribes)
        isResolved = try c.decode(Bool.self, forKey: .isResolved)
        isUncertain = try c.decodeIfPresent(Bool.self, forKey: .isUncertain) ?? false
        source = try c.decode(TribeSource.self, forKey: .source)
        screenConflict = try c.decodeIfPresent(Bool.self, forKey: .screenConflict) ?? false
        poolIsStale = try c.decodeIfPresent(Bool.self, forKey: .poolIsStale) ?? false
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(tribes, forKey: .tribes)
        try c.encode(isResolved, forKey: .isResolved)
        if isUncertain { try c.encode(isUncertain, forKey: .isUncertain) }
        try c.encode(source, forKey: .source)
        if screenConflict { try c.encode(screenConflict, forKey: .screenConflict) }
        if poolIsStale { try c.encode(poolIsStale, forKey: .poolIsStale) }
    }
}

/// One tribe and how sure the app is it's in the lobby.
public struct TribeView: Codable, Hashable, Sendable {
    /// The `Race` name (`MECHANICAL`).
    public var tribe: String
    /// For display (`Mech`).
    public var name: String
    /// P(in the lobby) as a whole percentage.
    public var percent: Int
    public var confidence: TribeConfidence
    /// Forced into every lobby this patch.
    public var isForced: Bool

    public init(tribe: String, name: String, percent: Int, confidence: TribeConfidence, isForced: Bool = false) {
        self.tribe = tribe
        self.name = name
        self.percent = percent
        self.confidence = confidence
        self.isForced = isForced
    }

    /// Short display names, as the game's own tribe labels.
    public static func displayName(_ tribe: HS.Race) -> String {
        switch tribe.name {
        case "MECHANICAL": "Mech"
        case let name?: name.prefix(1) + name.dropFirst().lowercased()
        case nil: "Tribe \(tribe.rawValue)"
        }
    }
}

extension TribesView {
    init(_ estimate: TribeEstimate, poolIsStale: Bool) {
        let rank: (TribeConfidence) -> Int = { [.confirmed, .likely, .unlikely, .absent].firstIndex(of: $0) ?? 4 }
        let tribes = estimate.tribes.map { tribe in
            TribeView(
                tribe: tribe.tribe.description, name: TribeView.displayName(tribe.tribe),
                percent: Int((tribe.probability * 100).rounded()), confidence: tribe.confidence,
                isForced: tribe.isForced
            )
        }
        // Stable order: forced, then by confidence, then by probability, then by name.
        let sorted = tribes.sorted {
            ($0.isForced ? 0 : 1, rank($0.confidence), -$0.percent, $0.name)
                < ($1.isForced ? 0 : 1, rank($1.confidence), -$1.percent, $1.name)
        }
        self.init(
            tribes: sorted, isResolved: estimate.isResolved, isUncertain: estimate.isUncertain, source: estimate.source,
            screenConflict: estimate.screenConflict, poolIsStale: poolIsStale
        )
    }
}
