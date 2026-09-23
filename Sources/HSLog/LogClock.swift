import Foundation

/// Gives Hearthstone's date-less timestamps a date.
///
/// Log lines carry only local time of day (`HH:MM:SS.fffffff`). The date comes from the
/// session folder's name (`Hearthstone_YYYY_MM_DD_HH_MM_SS`, the client's launch), and the
/// clock counts midnights as it reads a file in order (log-edge-cases §5):
/// - a time more than 12 hours before the previous one is the next day (midnight rollover);
/// - a smaller backward step (a clock change, DST fall-back) is clamped to the previous
///   time, so dates never go backwards.
///
/// The wall clock is never consulted, so replaying an old log dates it correctly. Keep
/// one clock per file.
public struct LogClock: Sendable {
    public let sessionStart: Date
    public let timeZone: TimeZone
    /// Midnights crossed since the session started.
    public private(set) var dayOffset = 0
    /// Seconds since midnight of the latest time observed (after clamping).
    public private(set) var secondsOfDay: Double

    private let calendar: Calendar
    private let startDay: DateComponents

    static let rolloverThreshold: Double = 12 * 3600

    public init(sessionStart: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        self.sessionStart = sessionStart
        self.timeZone = timeZone
        self.calendar = calendar
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .nanosecond], from: sessionStart)
        startDay = DateComponents(year: parts.year, month: parts.month, day: parts.day)
        let hour: Int = parts.hour ?? 0
        let minute: Int = parts.minute ?? 0
        let second: Int = parts.second ?? 0
        let nanosecond: Int = parts.nanosecond ?? 0
        secondsOfDay = Double(hour * 3600 + minute * 60 + second) + Double(nanosecond) / 1e9
    }

    /// A clock for a session folder.
    public init(session: LogSession, timeZone: TimeZone = .current) {
        self.init(sessionStart: session.started, timeZone: timeZone)
    }

    /// Advances the clock to a line's timestamp. Cheap enough for every line; returns false
    /// (and changes nothing) when the text isn't a timestamp.
    @discardableResult
    public mutating func observe(_ timestamp: some StringProtocol) -> Bool {
        guard let seconds = Self.secondsOfDay(timestamp) else { return false }
        if seconds < secondsOfDay - Self.rolloverThreshold {
            dayOffset += 1
            secondsOfDay = seconds
        } else if seconds >= secondsOfDay {
            secondsOfDay = seconds
        }
        // Otherwise a small backward step: keep the previous time.
        return true
    }

    /// The date of the latest time observed.
    public var currentDate: Date {
        date(dayOffset: dayOffset, secondsOfDay: secondsOfDay)
    }

    /// Advances to `timestamp` and returns its date; nil when it isn't a timestamp.
    public mutating func date(for timestamp: some StringProtocol) -> Date? {
        guard observe(timestamp) else { return nil }
        return currentDate
    }

    private func date(dayOffset: Int, secondsOfDay: Double) -> Date {
        let whole = Int(secondsOfDay)
        var components = startDay
        components.day = (startDay.day ?? 1) + dayOffset
        components.hour = whole / 3600
        components.minute = whole / 60 % 60
        components.second = whole % 60
        components.nanosecond = Int(((secondsOfDay - Double(whole)) * 1e9).rounded())
        return calendar.date(from: components) ?? sessionStart
    }

    /// `HH:MM:SS` with an optional fraction, as seconds since midnight.
    static func secondsOfDay(_ text: some StringProtocol) -> Double? {
        // Hours, minutes, seconds; plain variables because this runs for every line.
        var h = 0, m = 0, sec = 0
        var field = 0
        var digits = 0
        var fraction = 0.0
        var scale = 0.1
        var inFraction = false
        for byte in text.utf8 {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                let value = Int(byte - UInt8(ascii: "0"))
                if inFraction {
                    fraction += Double(value) * scale
                    scale /= 10
                } else {
                    switch field {
                    case 0: h = h * 10 + value
                    case 1: m = m * 10 + value
                    default: sec = sec * 10 + value
                    }
                    digits += 1
                    if digits > 2 { return nil }
                }
            case UInt8(ascii: ":"):
                guard !inFraction, digits > 0, field < 2 else { return nil }
                field += 1
                digits = 0
            case UInt8(ascii: "."):
                guard !inFraction, field == 2, digits > 0 else { return nil }
                inFraction = true
            default:
                return nil
            }
        }
        guard field == 2, inFraction || digits > 0, h < 24, m < 60, sec < 61 else { return nil }
        return Double(h * 3600 + m * 60 + sec) + fraction
    }
}
