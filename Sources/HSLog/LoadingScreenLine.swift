/// A scene transition from `LoadingScreen.log`.
///
/// `LoadingScreen.OnSceneLoaded() - prevMode=HUB currMode=BACON` means the client
/// is now in `BACON` (the Battlegrounds lobby); `OnScenePreUnload() - prevMode=BACON
/// nextMode=GAMEPLAY` means it's leaving for `GAMEPLAY`. Mode names are the
/// client's `SceneMgr.Mode` values, kept as text.
public enum LoadingScreenEvent: Hashable, Sendable {
    case sceneLoaded(previous: String, current: String)
    case sceneUnloading(previous: String, next: String)

    /// Parses one LoadingScreen.log line; nil for anything else.
    public init?(line: String) {
        if line.contains("LoadingScreen.OnSceneLoaded()"),
           let previous = Self.value(of: "prevMode=", in: line),
           let current = Self.value(of: "currMode=", in: line) {
            self = .sceneLoaded(previous: previous, current: current)
        } else if line.contains("LoadingScreen.OnScenePreUnload()"),
                  let previous = Self.value(of: "prevMode=", in: line),
                  let next = Self.value(of: "nextMode=", in: line) {
            self = .sceneUnloading(previous: previous, next: next)
        } else {
            return nil
        }
    }

    private static func value(of key: String, in line: String) -> String? {
        guard let range = line.range(of: key) else { return nil }
        let value = line[range.upperBound...].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
        return value.isEmpty ? nil : String(value)
    }
}
