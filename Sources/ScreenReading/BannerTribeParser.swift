import BGIntel
import CoreGraphics
import HSData

/// One line of text recognized on the screen.
public struct RecognizedLine: Hashable, Sendable {
    public var text: String
    /// The recognizer's confidence, 0…1.
    public var confidence: Double
    /// Where it is, in Hearthstone's content-local points (top-left origin, y down).
    public var rect: CGRect

    public init(text: String, confidence: Double, rect: CGRect = .zero) {
        self.text = text
        self.confidence = confidence
        self.rect = rect
    }
}

/// Turns the hero-pick banner's text ("Aberrations, Demons, Elementals, Murlocs, Quilboar")
/// into tribes. Tolerant of small recognition errors ("Aberratlons", "Qufilboar"): each
/// word is matched to the nearest tribe name within an edit distance that grows with its
/// length, and every fix-up lowers the reading's confidence.
public enum BannerTribeParser {
    /// The banner's tribe words (English client), singular, to the `Race` name.
    static let vocabulary: [(word: String, race: String)] = [
        ("aberration", "ABERRATION"), ("beast", "BEAST"), ("demon", "DEMON"), ("dragon", "DRAGON"),
        ("elemental", "ELEMENTAL"), ("mech", "MECHANICAL"), ("mechanical", "MECHANICAL"), ("murloc", "MURLOC"),
        ("naga", "NAGA"), ("pirate", "PIRATE"), ("quilboar", "QUILBOAR"), ("undead", "UNDEAD"),
    ]

    /// Confidence lost per corrected letter.
    static let penaltyPerEdit = 0.08
    /// Confidence kept per word that isn't a tribe (the line may not be the tribe list).
    static let unknownWordFactor = 0.75

    /// The tribes the lines list, in the order they appear, or nil when none is recognized.
    /// - Parameter expectedCount: tribes per lobby; a reading with that many is complete.
    public static func tribes(in lines: [RecognizedLine], expectedCount: Int = 5) -> ScreenTribeReading? {
        var races: [HS.Race] = []
        var confidence = 1.0
        for line in lines {
            var matchedInLine = false
            for word in words(line.text) where word.count >= 3 {
                guard let (race, edits) = match(word) else {
                    confidence *= unknownWordFactor
                    continue
                }
                matchedInLine = true
                confidence -= Double(edits) * penaltyPerEdit
                if !races.contains(race) { races.append(race) }
            }
            if matchedInLine { confidence = min(confidence, line.confidence) }
        }
        guard !races.isEmpty else { return nil }
        // More tribes than a lobby has: something else was read as tribes.
        if races.count > expectedCount { confidence *= 0.5 }
        return ScreenTribeReading(
            tribes: races, isComplete: races.count == expectedCount, confidence: min(max(confidence, 0), 1)
        )
    }

    /// Whether a line is the banner's title, "Choose a Hero" (allowing a few misread letters).
    public static func isTitle(_ text: String) -> Bool {
        let letters = String(text.lowercased().filter(\.isLetter))
        return letters.count >= 8 && editDistance(letters, "chooseahero") <= 3
    }

    /// The tribe a word names and how many letters had to be corrected; nil for any other word.
    static func match(_ word: String) -> (HS.Race, edits: Int)? {
        guard word.count >= 3 else { return nil }
        let allowed = word.count >= 7 ? 2 : 1
        var best: (race: String, edits: Int)?
        for (name, race) in vocabulary {
            for form in [name, name + "s"] {
                let d = editDistance(word, form)
                if d <= allowed, d < (best?.edits ?? .max) { best = (race, d) }
            }
        }
        guard let best, let race = HS.Race(name: best.race) else { return nil }
        return (race, best.edits)
    }

    /// Lower-case words: runs of letters (commas, periods and stray marks split them).
    static func words(_ text: String) -> [String] {
        text.lowercased().split { !$0.isLetter }.map(String.init)
    }

    /// Levenshtein distance.
    static func editDistance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
