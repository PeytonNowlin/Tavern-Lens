import Foundation

/// Locates the private fixture logs (git-ignored, never committed).
///
/// `TAVERN_FIXTURES_DIR` wins when set. Otherwise the nearest `fixtures/private-logs`
/// directory above this source file is used, which also finds the main checkout's
/// fixtures from a git worktree nested inside it. Tests that need a fixture are
/// disabled (reported as skipped) when it's absent.
enum Fixtures {
    static let fullGame = "Hearthstone_2026_09_22_21_08_40/Power.log"
    static let truncatedGame = "Hearthstone_2026_09_22_20_33_28/Power.log"
    /// Hearthstone was closed mid-game at BG turn 3; no later session resumes it.
    static let abandonedGame = "Hearthstone_2026_09_22_21_59_59/Power.log"

    static let directory: URL? = {
        if let override = ProcessInfo.processInfo.environment["TAVERN_FIXTURES_DIR"], !override.isEmpty {
            return URL(filePath: override, directoryHint: .isDirectory)
        }
        var dir = URL(filePath: #filePath).deletingLastPathComponent()
        while dir.pathComponents.count > 1 {
            let candidate = dir.appending(path: "fixtures/private-logs", directoryHint: .isDirectory)
            if FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }()

    static func url(_ relativePath: String) -> URL? {
        guard let directory else { return nil }
        let url = directory.appending(path: relativePath)
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
    }

    static func isAvailable(_ relativePath: String) -> Bool {
        url(relativePath) != nil
    }
}
