import Foundation

/// Observed final placements associated with a card on an exact turn. The comparison
/// does not establish the causal value of purchasing it in the current recruit state.
public struct CardTurnStats: Codable, Hashable, Sendable {
    public static let liveURL = URL(string:
        "https://static.zerotoheroes.com/api/bgs/card-stats/mmr-25/last-patch/overview-from-hourly.gz.json")!
    public static let maximumSourceAge: TimeInterval = 48 * 3600

    public struct TurnStat: Codable, Hashable, Sendable {
        /// Some published rows contain null or omit the turn; they cannot be exact-turn evidence.
        public var turn: Int?
        public var totalPlayed: Int
        public var totalOther: Int
        /// The feed emits null comparator means when no comparison population was observed.
        public var averagePlacement: Double?
        public var averagePlacementOther: Double?

        public init(turn: Int?, totalPlayed: Int, totalOther: Int, averagePlacement: Double?, averagePlacementOther: Double?) {
            self.turn = turn
            self.totalPlayed = totalPlayed
            self.totalOther = totalOther
            self.averagePlacement = averagePlacement
            self.averagePlacementOther = averagePlacementOther
        }
    }

    public struct CardStat: Codable, Hashable, Sendable {
        public var cardId: String
        public var totalPlayed: Int
        public var averagePlacement: Double
        public var averagePlacementOther: Double
        public var turnStats: [TurnStat]

        public init(cardId: String, totalPlayed: Int, averagePlacement: Double, averagePlacementOther: Double, turnStats: [TurnStat]) {
            self.cardId = cardId
            self.totalPlayed = totalPlayed
            self.averagePlacement = averagePlacement
            self.averagePlacementOther = averagePlacementOther
            self.turnStats = turnStats
        }
    }

    /// Validated evidence for one card and turn, with both observed populations.
    public struct Entry: Codable, Hashable, Sendable {
        public let cardID: String
        public let turn: Int
        public let totalPlayed: Int
        public let totalOther: Int
        public let averagePlacement: Double
        public let averagePlacementOther: Double
        /// Average placement with the card minus the comparator; negative is better.
        public var impact: Double { averagePlacement - averagePlacementOther }
    }

    public var lastUpdateDate: String
    public var dataPoints: Int
    public var timePeriod: String
    public var cardStats: [CardStat]
    /// Endpoint metadata, not a claim that the provider supplied these fields in its JSON.
    public var mmrPercentile: Int
    public var sourceURL: String

    public var updatedAt: Date? { FirestoneDate.parse(lastUpdateDate) }

    public init(
        lastUpdateDate: String, dataPoints: Int, timePeriod: String, cardStats: [CardStat],
        mmrPercentile: Int = 25, sourceURL: String = CardTurnStats.liveURL.absoluteString
    ) {
        self.lastUpdateDate = lastUpdateDate
        self.dataPoints = dataPoints
        self.timePeriod = timePeriod
        self.cardStats = cardStats
        self.mmrPercentile = mmrPercentile
        self.sourceURL = sourceURL
    }

    public init(json: Data) throws { self = try JSONDecoder().decode(Self.self, from: json) }

    private enum CodingKeys: String, CodingKey {
        case lastUpdateDate, dataPoints, timePeriod, cardStats, mmrPercentile, sourceURL
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        lastUpdateDate = try container.decode(String.self, forKey: .lastUpdateDate)
        dataPoints = try container.decode(Int.self, forKey: .dataPoints)
        timePeriod = try container.decode(String.self, forKey: .timePeriod)
        cardStats = try container.decode([CardStat].self, forKey: .cardStats)
        mmrPercentile = try container.decodeIfPresent(Int.self, forKey: .mmrPercentile) ?? 25
        sourceURL = try container.decodeIfPresent(String.self, forKey: .sourceURL) ?? Self.liveURL.absoluteString
    }

    public func usable(now: Date) -> Bool {
        guard timePeriod == "last-patch", mmrPercentile == 25, sourceURL == Self.liveURL.absoluteString,
              dataPoints > 0, !cardStats.isEmpty, let updatedAt else { return false }
        let age = now.timeIntervalSince(updatedAt)
        return age >= 0 && age <= Self.maximumSourceAge
    }

    public func entry(cardID: String, turn: Int, now: Date, minimumPopulation: Int = 200) -> Entry? {
        guard usable(now: now), turn > 0 else { return nil }
        let matches = cardStats.filter { $0.cardId == cardID }
            .flatMap(\.turnStats).filter { $0.turn == turn }
        // Repeated rows are ambiguous; choosing one or summing populations could inflate evidence.
        guard matches.count == 1, let row = matches.first,
              row.totalPlayed >= max(1, minimumPopulation), row.totalOther >= max(1, minimumPopulation),
              let averagePlacement = row.averagePlacement, let averagePlacementOther = row.averagePlacementOther,
              averagePlacement.isFinite, averagePlacementOther.isFinite,
              (1...8).contains(averagePlacement), (1...8).contains(averagePlacementOther) else { return nil }
        return Entry(cardID: cardID, turn: turn, totalPlayed: row.totalPlayed, totalOther: row.totalOther,
            averagePlacement: averagePlacement, averagePlacementOther: averagePlacementOther)
    }

    /// A small, deterministic source snapshot suitable for archiving in an advisor request.
    /// Unavailable, ambiguous and invalid rows are excluded without borrowing another turn.
    public func subset(cardIDs: Set<String>, turn: Int, now: Date, minimumPopulation: Int = 200) -> Self {
        var result = self
        result.cardStats = cardIDs.sorted().compactMap { id in
            guard entry(cardID: id, turn: turn, now: now, minimumPopulation: minimumPopulation) != nil,
                  var card = cardStats.first(where: { $0.cardId == id && $0.turnStats.contains { $0.turn == turn } })
            else { return nil }
            card.turnStats = card.turnStats.filter { $0.turn == turn }
            return card
        }
        return result
    }
}
