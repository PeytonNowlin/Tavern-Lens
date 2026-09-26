import Foundation

/// Scope and freshness belong to the evidence, independently of when we fetched its file.
public struct BuildEvidence: Codable, Hashable, Sendable {
    public var provider: String
    public var url: String
    public var capturedAt: String?
    public var sourceUpdated: String?
    public var tierUpdated: String?
    public var mode: String
    public var metric: String
    public var sampleSize: Int?
    public var sampledBoards: Int?
    public var window: String?
    public var mmr: String?
    public var access: String

    /// Editorial tier updates are independent from guide edits and capture time.
    public func tierIsCurrent(at now: Date) -> Bool {
        guard let stamp = tierUpdated, let date = FirestoneDate.parse(stamp) else { return false }
        return date <= now && now.timeIntervalSince(date) <= 14 * 86400
    }

    public init(provider: String, url: String, capturedAt: String? = nil, sourceUpdated: String? = nil,
                tierUpdated: String? = nil, mode: String = "solo", metric: String = "curated guide",
                sampleSize: Int? = nil, sampledBoards: Int? = nil, window: String? = nil,
                mmr: String? = nil, access: String = "public snapshot") {
        self.provider = provider; self.url = url; self.capturedAt = capturedAt
        self.sourceUpdated = sourceUpdated; self.tierUpdated = tierUpdated; self.mode = mode
        self.metric = metric; self.sampleSize = sampleSize; self.sampledBoards = sampledBoards
        self.window = window; self.mmr = mmr; self.access = access
    }
}

/// All requirements must be supplied before committing. Cards within one requirement are
/// alternatives. An empty list denotes a resource condition the advisor cannot verify yet.
public struct BuildRequirement: Codable, Hashable, Sendable {
    public var role: String
    public var anyOf: [String]
    public init(role: String, anyOf: [String]) { self.role = role; self.anyOf = anyOf }
}
