/// Namespace for the Hearthstone enums generated from HearthstoneJSON `enums.json`
/// (`HS.CardType`, `HS.Zone`, `HS.Race`, …). The generated file lives in the build
/// directory; see Tools/HSEnumsGenerator. `GameTag` itself is in PowerParser.
public enum HS {}

/// A generated Hearthstone enum: a number with known names.
///
/// These are value types rather than Swift enums so that a number Hearthstone adds
/// after the pinned build is kept as it is instead of failing to decode.
public protocol HSEnumeration: RawRepresentable, Hashable, Sendable, Codable, CustomStringConvertible
where RawValue == Int {
    init(rawValue: Int)
    /// Each known number's canonical name (the first name when there are aliases).
    static var canonicalNames: [Int: String] { get }
    /// Every known name, aliases included, to its number.
    static var valuesByName: [String: Int] { get }
}

public extension HSEnumeration {
    /// From a name as the log prints it (`MINION`, `PLAY`); nil for a name the pinned build doesn't know.
    init?(name: some StringProtocol) {
        guard let value = Self.valuesByName[String(name)] else { return nil }
        self.init(rawValue: value)
    }

    /// The canonical name, or nil for a number the pinned build doesn't know.
    var name: String? { Self.canonicalNames[rawValue] }

    /// Whether the pinned build knows this number.
    var isKnown: Bool { name != nil }

    /// The name, or the number when the name is unknown.
    var description: String { name ?? String(rawValue) }
}
