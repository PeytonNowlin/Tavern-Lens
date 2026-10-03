/// Whether this game's board check may start: it runs once per game, at the first recruit
/// phase, and only while the screen reader is on with Screen Recording granted.
///
/// Stopping it (the reader turned off) must leave it startable, or turning the reader back
/// on during recruit would never restart the check.
public struct BoardCheckGate: Equatable, Sendable {
    public private(set) var isStarted = false

    public init() {}

    /// True, and now started, if the check may start.
    public mutating func begin(isEnabled: Bool, permissionGranted: Bool) -> Bool {
        guard !isStarted, isEnabled, permissionGranted else { return false }
        isStarted = true
        return true
    }

    /// The check was stopped without the game ending.
    public mutating func stop() { isStarted = false }

    /// A new game: it gets its own check.
    public mutating func reset() { isStarted = false }
}
