import Foundation
import HSLog

/// A throwaway directory tree shaped like a Hearthstone install plus its
/// Preferences folder. Never touches the real `/Applications/Hearthstone`.
final class TemporaryInstall {
    let root: URL
    let locations: HearthstoneLocations

    init(installed: Bool = true) throws {
        root = FileManager.default.temporaryDirectory
            .appending(path: "TavernLensTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        locations = HearthstoneLocations(
            installDirectory: root.appending(path: "Applications/Hearthstone", directoryHint: .isDirectory),
            logConfigFile: root.appending(path: "Library/Preferences/Blizzard/Hearthstone/log.config")
        )
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if installed {
            try FileManager.default.createDirectory(at: locations.installDirectory, withIntermediateDirectories: true)
        }
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    /// Creates `Logs/<name>/` and returns it.
    @discardableResult
    func makeSession(_ name: String) throws -> URL {
        let url = locations.logsDirectory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func read(_ url: URL) -> String? {
        FileManager.default.contents(atPath: url.path(percentEncoded: false)).map { String(decoding: $0, as: UTF8.self) }
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    /// Appends raw bytes, as the client does while it logs.
    func append(_ bytes: some Sequence<UInt8>, to url: URL) throws {
        if !exists(url) {
            FileManager.default.createFile(atPath: url.path(percentEncoded: false), contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(bytes))
    }

    func append(_ text: String, to url: URL) throws {
        try append(Array(text.utf8), to: url)
    }
}

/// Collects a follower's events from its queue for assertions.
final class EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [LogSessionFollower.Event] = []

    func record(_ event: LogSessionFollower.Event) {
        lock.withLock { events.append(event) }
    }

    var sessions: [String] {
        lock.withLock {
            events.compactMap { if case .sessionStarted(let session) = $0 { session.name } else { nil } }
        }
    }

    /// Lines of one file, in order, from the most recent session only.
    func lines(of file: String) -> [String] {
        lock.withLock {
            var result: [String] = []
            for event in events {
                switch event {
                case .sessionStarted: result = []
                case .lines(let name, let lines) where name == file: result += lines
                case .lines: break
                }
            }
            return result
        }
    }

    /// Polls until `condition` holds or `timeout` passes; returns whether it held.
    func wait(timeout: Duration = .seconds(1), until condition: (EventRecorder) -> Bool) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if condition(self) { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition(self)
    }
}
