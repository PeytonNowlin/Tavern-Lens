import Foundation
import HSLog
import Testing
import TavernEngine

/// Replays of the captured games shared across tests: each fixture log is read and replayed once
/// per variant for the whole run, however many tests look at the result. (The logs are tens of
/// megabytes; replaying one is seconds in a debug build.)
enum FixtureReplays {
    /// How the engine was set up for the replay.
    enum Variant: Hashable, Sendable {
        /// No card data, pool, builds or session.
        case plain
        /// With `PoolFixture.pool`, for the lobby's tribes.
        case pool
        /// With `PoolFixture`'s card data and pool and `BuildFixture.catalog`.
        case builds
    }

    private struct Key: Hashable, Sendable {
        var path: String
        var variant: Variant
    }

    private static let results = Memo<Key, ReplayResult>()
    private static let lines = Memo<String, [String]>()

    /// The replay of the fixture log at `path` (relative to the fixtures directory).
    static func result(_ path: String, _ variant: Variant = .plain) throws -> ReplayResult {
        try results.value(Key(path: path, variant: variant)) {
            let url = try #require(Fixtures.url(path))
            switch variant {
            case .plain: return try TavernEngine.replay(fileAt: url)
            case .pool: return try TavernEngine.replay(fileAt: url, pool: PoolFixture.pool)
            case .builds:
                return try TavernEngine.replay(
                    fileAt: url, cards: PoolFixture.cards, pool: PoolFixture.pool, builds: BuildFixture.catalog
                )
            }
        }
    }

    /// The fixture log's lines.
    static func lines(_ path: String) throws -> [String] {
        try lines.value(path) {
            var lines: [String] = []
            try LogFileReader.forEachLine(in: #require(Fixtures.url(path))) { lines.append($0) }
            return lines
        }
    }
}

/// A value per key, computed once: a second caller for the same key waits for the first one's
/// result instead of computing it again. A failure isn't kept (the next caller tries again).
final class Memo<Key: Hashable & Sendable, Value: Sendable>: @unchecked Sendable {
    private final class Slot: @unchecked Sendable {
        let lock = NSLock()
        var value: Value?
    }

    private let lock = NSLock()
    private var slots: [Key: Slot] = [:]

    func value(_ key: Key, compute: () throws -> Value) rethrows -> Value {
        let slot = lock.withLock {
            if let slot = slots[key] { return slot }
            let slot = Slot()
            slots[key] = slot
            return slot
        }
        slot.lock.lock()
        defer { slot.lock.unlock() }
        if let value = slot.value { return value }
        let value = try compute()
        slot.value = value
        return value
    }
}
