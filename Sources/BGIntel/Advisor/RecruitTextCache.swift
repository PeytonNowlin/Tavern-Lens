import Foundation

/// Immutable parsing results shared across bounded searches. NSCache is thread-safe; duplicate
/// cache misses compute the same value. Eviction changes cost, never planning semantics.
final class RecruitTextCache: @unchecked Sendable {
    static let shared = RecruitTextCache()
    private let expressions = NSCache<NSString, NSRegularExpression>()
    private let normalized = NSCache<NSString, NSString>()
    private init() { expressions.countLimit = 128; normalized.countLimit = 2048 }

    func expression(_ pattern: String) -> NSRegularExpression? {
        if let existing = expressions.object(forKey: pattern as NSString) { return existing }
        guard let result = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        expressions.setObject(result, forKey: pattern as NSString)
        return result
    }

    func plain(_ text: String) -> String {
        if let existing = normalized.object(forKey: text as NSString) { return existing as String }
        let result = text.replacingOccurrences(of: "<[^>]+>|\\[x\\]", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.setObject(result as NSString, forKey: text as NSString)
        return result
    }
}
