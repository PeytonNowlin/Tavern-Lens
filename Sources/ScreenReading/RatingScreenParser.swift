import CoreGraphics
import Foundation

/// A conservative English-client reader for the rating displayed in the Battlegrounds
/// lobby. The caller must establish the BACON scene; bare numbers are never evidence.
public enum RatingScreenParser {
    public static func rating(in lines: [RecognizedLine]) -> Int? {
        // Even uncertain Duos evidence vetoes a Solo reading; confidence filtering must
        // not remove the only indication that this belongs to a different rating history.
        guard !lines.contains(where: { $0.text.lowercased().contains("duos") }) else { return nil }
        let clear = lines.filter { $0.confidence >= 0.85 }
        var readings: [Int] = []
        for label in clear {
            let text = label.text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if let match = text.wholeMatch(of: /(?:your |current )?rating\s*:?\s+([0-9][0-9, ]*)/),
               let value = number(String(match.1)) {
                readings.append(value)
                continue
            }
            guard ["rating", "rating:", "your rating", "current rating"].contains(text),
                  label.rect.width > 0, label.rect.height > 0 else { continue }
            let nearby = clear.compactMap { line -> Int? in
                guard line != label, let value = number(line.text) else { return nil }
                let height = max(label.rect.height, line.rect.height)
                let verticallyAdjacent = abs(line.rect.midX - label.rect.midX) <= max(label.rect.width, line.rect.width) * 0.6
                    && abs(line.rect.midY - label.rect.midY) <= height * 2.8
                let onSameLine = abs(line.rect.midY - label.rect.midY) <= height * 0.5
                    && line.rect.minX >= label.rect.maxX && line.rect.minX - label.rect.maxX <= height * 2
                return verticallyAdjacent || onSameLine ? value : nil
            }
            // Ambiguous adjacent numbers (for example an animation's change and total) are not readings.
            if nearby.count == 1 { readings.append(nearby[0]) }
        }
        guard readings.count == 1 else { return nil }
        return readings[0]
    }

    private static func number(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.wholeMatch(of: /(?:[0-9]{1,5}|[0-9]{1,2}[, ][0-9]{3})/) != nil else { return nil }
        return Int(trimmed.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: " ", with: ""))
    }
}

/// Waiting for several identical observations avoids recording intermediate animated totals.
public struct StableRatingReading: Sendable {
    private var previous: Int?
    private var count = 0
    public init() {}

    public mutating func observe(_ rating: Int?) -> Int? {
        guard let rating else { previous = nil; count = 0; return nil }
        count = previous == rating ? count + 1 : 1
        previous = rating
        return count >= 3 ? rating : nil
    }
}
