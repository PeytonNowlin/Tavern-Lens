import Foundation

/// Public aggregate statistics, fetched independently of the MIT combat simulator. These
/// describe observed placements, not a causal win-rate benefit for the current board.
public struct TrinketStats: Codable, Hashable, Sendable {
    public struct Entry: Codable, Hashable, Sendable {
        public var trinketCardId: String
        public var dataPoints: Int
        public var averagePlacement: Double
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
