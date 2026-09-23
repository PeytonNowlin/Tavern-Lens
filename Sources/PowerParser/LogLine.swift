/// One line of a Hearthstone log: `<Level> <HH:MM:SS.fffffff> <Method>() - <payload>`.
///
/// The method may contain spaces and brackets
/// (`PowerSpellController [taskListId=N].InitPowerSpell()`), so it runs up to the
/// first `() - `. Timestamps carry no date and every line of a task list shares
/// one, so they are for display and pacing only, never for ordering.
public struct LogLine: Sendable, Equatable {
    public var level: Character
    public var timestamp: Substring
    public var method: Substring
    public var payload: Substring

    public init?(_ text: String) {
        self.init(Substring(text))
    }

    public init?(_ text: Substring) {
        // Scans UTF-8 bytes: every delimiter is ASCII, and this runs for every line of the log.
        let bytes = text.utf8
        var i = bytes.startIndex
        guard i != bytes.endIndex else { return nil }
        let levelByte = bytes[i]
        guard levelByte == UInt8(ascii: "D") || levelByte == UInt8(ascii: "W") || levelByte == UInt8(ascii: "E") else {
            return nil
        }
        i = bytes.index(after: i)
        guard i != bytes.endIndex, bytes[i] == UInt8(ascii: " ") else { return nil }
        let timeStart = bytes.index(after: i)
        guard let timeEnd = bytes[timeStart...].firstIndex(of: UInt8(ascii: " ")), timeEnd != timeStart else {
            return nil
        }
        let methodStart = bytes.index(after: timeEnd)
        guard let separator = text.utf8FirstRange(of: "() - ", from: methodStart), separator.lowerBound != methodStart else {
            return nil
        }
        level = Character(Unicode.Scalar(levelByte))
        timestamp = text[timeStart..<timeEnd]
        method = text[methodStart..<separator.lowerBound]
        payload = text[separator.upperBound...]
    }
}

/// Where something happened in a log: the 1-based line number and that line's timestamp.
public struct LogPosition: Hashable, Sendable, Codable {
    public var line: Int
    public var time: String

    public init(line: Int, time: String) {
        self.line = line
        self.time = time
    }
}
