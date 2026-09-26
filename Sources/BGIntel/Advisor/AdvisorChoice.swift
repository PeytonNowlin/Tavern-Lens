/// A currently visible seasonal choice evaluated against the same observed board/resources.
/// Kept apart from recruit actions: choosing reveals new information and ends this plan.
public struct AdvisorChoice: Codable, Hashable, Sendable {
    public var entityID: Int
    public var cardID: String
    public var name: String
    public var cost: Int?
    public var reason: String
    public var confidence: AdvisorConfidence
    public init(entityID: Int, cardID: String, name: String, cost: Int?, reason: String, confidence: AdvisorConfidence) {
        self.entityID = entityID; self.cardID = cardID; self.name = name; self.cost = cost
        self.reason = reason; self.confidence = confidence
    }
}
