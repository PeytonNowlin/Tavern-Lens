import Foundation

/// Public aggregate statistics, fetched independently of the MIT combat simulator. These
/// describe observed placements, not a causal win-rate benefit for the current board.
public struct TrinketStats: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public struct MMRPlacement: Codable, Hashable, Sendable {
            /// Provider percentile bucket (100, 50, 25, 10 or 1), rather than a rating.
            public var mmr: Int
            public var dataPoints: Int
            public var placement: Double
        }
        public struct MMRPickRate: Codable, Hashable, Sendable {
            public var mmr: Int
            public var dataPoints: Int?
            public var pickRate: Double
        }
        public var trinketCardId: String
        public var dataPoints: Int
        public var averagePlacement: Double
        public var pickRate: Double?
        public var pickRateAtMmr: [MMRPickRate]?
        public var averagePlacementAtMmr: [MMRPlacement]?

        private enum CodingKeys: String, CodingKey {
            case trinketCardId, dataPoints, averagePlacement, pickRate, pickRateAtMmr, averagePlacementAtMmr
        }

        public init(from decoder: any Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            trinketCardId = try c.decode(String.self, forKey: .trinketCardId)
            dataPoints = try c.decode(Int.self, forKey: .dataPoints)
            averagePlacement = try c.decode(Double.self, forKey: .averagePlacement)
            pickRate = (try? c.decodeIfPresent(Double.self, forKey: .pickRate)).flatMap {
                $0.isFinite && (0...1).contains($0) ? $0 : nil
            }
            pickRateAtMmr = (try? c.decodeIfPresent([Lenient<MMRPickRate>].self, forKey: .pickRateAtMmr))?
                .compactMap(\.value).filter { $0.pickRate.isFinite && (0...1).contains($0.pickRate) }
            averagePlacementAtMmr = (try? c.decodeIfPresent([Lenient<MMRPlacement>].self, forKey: .averagePlacementAtMmr))?
                .compactMap(\.value)
        }

        /// Retained marginal evidence, never interpreted as trinket-pair synergy.
        public func placement(atMMRPercentile mmr: Int, minimumGames: Int = 200) -> MMRPlacement? {
            let rows = averagePlacementAtMmr?.filter { $0.mmr == mmr } ?? []
            guard [100, 50, 25, 10, 1].contains(mmr), rows.count == 1,
                  let row = rows.first, row.dataPoints >= max(1, minimumGames),
                  row.placement.isFinite, (1...8).contains(row.placement) else { return nil }
            return row
        }
    }
    public var trinketStats: [Entry]
    public var lastUpdateDate: String
    public var dataPoints: Int
    public var timePeriod: String

    public var updatedAt: Date? {
        let format = ISO8601DateFormatter()
        format.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return format.date(from: lastUpdateDate) ?? ISO8601DateFormatter().date(from: lastUpdateDate)
    }

    public func usable(now: Date) -> Bool {
        guard timePeriod == "past-three", dataPoints > 0, !trinketStats.isEmpty, let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) >= -3600 && now.timeIntervalSince(updatedAt) < 48 * 3600
    }

    public func entry(_ id: String, now: Date) -> Entry? {
        guard usable(now: now) else { return nil }
        return trinketStats.first {
            $0.trinketCardId == id && $0.dataPoints >= 200 && $0.averagePlacement.isFinite
                && (1...8).contains($0.averagePlacement)
        }
    }
}
