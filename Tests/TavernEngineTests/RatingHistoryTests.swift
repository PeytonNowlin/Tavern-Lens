import Foundation
import Testing
import TavernEngine

@Suite("Rating history")
struct RatingHistoryTests {
    private func reading(_ rating: Int, time: TimeInterval, source: RatingReading.Source = .screen,
                         seed: Int? = nil, id: UUID = UUID()) throws -> RatingReading {
        try RatingReading(id: id, recordedAt: Date(timeIntervalSince1970: time), rating: rating,
                          source: source, gameSeed: seed)
    }

    @Test("Ratings validate their value and timestamp, including decoded readings")
    func validation() throws {
        #expect(throws: RatingHistoryError.invalidRating) { try reading(-1, time: 0) }
        #expect(throws: RatingHistoryError.invalidDate) { try reading(4000, time: .infinity) }
        #expect(try reading(0, time: 0).rating == 0)
        let invalid = Data("""
            {"id":"00000000-0000-0000-0000-000000000001","recordedAt":0,"rating":-1,"source":"screen"}
            """.utf8)
        #expect(throws: RatingHistoryError.invalidRating) { try JSONDecoder().decode(RatingReading.self, from: invalid) }
    }

    @Test("Readings stay chronological and compute rating changes, never placements")
    func ordering() throws {
        var history = RatingHistory()
        try history.record(reading(4100, time: 30, seed: 3))
        try history.record(reading(4000, time: 10, seed: 1))
        try history.record(reading(4200, time: 20, seed: 2))
        #expect(history.readings.map(\.rating) == [4000, 4200, 4100])
        #expect(history.latest?.rating == 4100)
        #expect(history.latestChange == -100)
        #expect(history.highest == 4200)
        #expect(RatingHistory().latestChange == nil)
    }

    @Test("Stable sightings dedupe but zero-change games and changed sources remain")
    func duplicates() throws {
        var history = RatingHistory()
        #expect(try history.record(reading(4000, time: 10)))
        #expect(try !history.record(reading(4000, time: 11)))
        #expect(try history.record(reading(4000, time: 20, seed: 1)))
        #expect(try !history.record(reading(4000, time: 21, seed: 1)))
        #expect(try history.record(reading(4000, time: 30, seed: 2)))
        #expect(history.latestChange == 0)
        #expect(try history.record(reading(4000, time: 31, source: .manual, seed: 2)))
        #expect(try history.record(reading(4100, time: 40, seed: 3)))
        #expect(try history.record(reading(4000, time: 50, seed: 4)))
        #expect(history.readings.map(\.rating) == [4000, 4000, 4000, 4000, 4100, 4000])
        let first = try #require(history.readings.first)
        #expect(throws: RatingHistoryError.duplicateID) { try history.record(first) }
        #expect(throws: RatingHistoryError.duplicateID) { try RatingHistory(readings: [first, first]) }
    }

    @Test("A correction preserves identity, date and game while marking the source as entered")
    func correction() throws {
        let first = try reading(4000, time: 10, seed: 1)
        let second = try reading(4200, time: 20, seed: 2)
        var history = try RatingHistory(readings: [second, first])
        try history.correct(id: second.id, rating: 4000)
        #expect(history.readings.count == 2)
        #expect(history.latest?.id == second.id)
        #expect(history.latest?.recordedAt == second.recordedAt)
        #expect(history.latest?.gameSeed == second.gameSeed)
        #expect(history.latest?.source == .manual)
        #expect(history.latestChange == 0)
        let before = history
        #expect(throws: RatingHistoryError.invalidRating) { try history.correct(id: second.id, rating: -2) }
        #expect(history == before)
        #expect(throws: RatingHistoryError.missingReading) { try history.correct(id: UUID(), rating: 4300) }
    }

    @Test("Equal manual readings and corrections preserve every saved identity and timestamp")
    func preservesExplicitHistory() throws {
        let first = try reading(6000, time: 10, source: .manual)
        let second = try reading(6100, time: 20, source: .manual)
        let third = try reading(6000, time: 30, source: .manual)
        let fourth = try reading(6000, time: 40, source: .manual)
        var history = RatingHistory()
        for item in [first, second, third, fourth] { #expect(try history.record(item)) }
        try history.correct(id: second.id, rating: 6000)
        #expect(history.readings.map(\.id) == [first, second, third, fourth].map(\.id))
        #expect(history.readings.map(\.recordedAt) == [first, second, third, fourth].map(\.recordedAt))
        #expect(history.readings.map(\.rating) == [6000, 6000, 6000, 6000])
    }

    @Test("A backdated duplicate screen sighting cannot replace an existing observation")
    func backdatedScreenDuplicate() throws {
        let original = try reading(6000, time: 20, seed: 1)
        var history = try RatingHistory(readings: [original])
        #expect(try !history.record(reading(6000, time: 10, seed: 1)))
        #expect(history.readings == [original])
        let entered = try reading(6000, time: 5, source: .manual, seed: 1)
        #expect(try history.record(entered))
        #expect(history.readings == [entered, original])
    }

    @Test("The byte store round trips sources and timestamps without rewriting stable readings")
    func roundTrip() async throws {
        let bytes = RatingBytes()
        let store = RatingHistoryStore(persistence: bytes)
        #expect(try await store.load() == RatingHistory())
        let first = try reading(4000, time: 1_700_000_000.125, source: .manual)
        _ = try await store.record(first)
        let second = try reading(4010, time: 1_700_000_100.25, seed: 22)
        let saved = try await store.record(second)
        let loaded = try await RatingHistoryStore(persistence: bytes).load()
        #expect(loaded == saved)
        #expect(loaded.readings == [first, second])
        #expect(bytes.writes == 2)
        _ = try await store.record(reading(4010, time: 1_700_000_200, seed: 22))
        #expect(bytes.writes == 2)
        #expect(try await store.load() == saved)
    }

    @Test("Malformed, future-format and unreadable history cannot be silently overwritten")
    func protectsExistingData() async throws {
        let existing = [Data("not JSON".utf8), Data("{\"format\":999,\"readings\":[]}".utf8)]
        for data in existing {
            let bytes = RatingBytes(data)
            let store = RatingHistoryStore(persistence: bytes)
            await #expect(throws: RatingHistoryError.self) { try await store.load() }
            await #expect(throws: RatingHistoryError.self) { try await store.record(reading(4100, time: 20)) }
            #expect(bytes.data == data)
            #expect(bytes.writes == 0)
        }
        let bytes = RatingBytes(Data("keep".utf8), failRead: true)
        await #expect(throws: RatingHistoryError.self) {
            try await RatingHistoryStore(persistence: bytes).record(reading(4100, time: 20))
        }
        #expect(bytes.data == Data("keep".utf8))
        #expect(bytes.writes == 0)
    }

    @Test("Concurrent observations serialize their read-modify-write operations")
    func concurrentRecords() async throws {
        let bytes = RatingBytes()
        let store = RatingHistoryStore(persistence: bytes)
        let earlier = try reading(4000, time: 10, seed: 1)
        let later = try reading(4100, time: 20, seed: 2)
        async let first = store.record(earlier)
        async let second = store.record(later)
        _ = try await (first, second)
        #expect(try await store.load().readings == [earlier, later])
        #expect(bytes.writes == 2)
    }

    @Test("Failed appends and corrections preserve the previously saved history")
    func saveFailure() async throws {
        let bytes = RatingBytes()
        let store = RatingHistoryStore(persistence: bytes)
        let first = try reading(4000, time: 10, seed: 1)
        let original = try await store.record(first)
        let originalData = bytes.data
        bytes.failWrite = true
        await #expect(throws: RatingHistoryError.self) { try await store.record(reading(4100, time: 20, seed: 2)) }
        await #expect(throws: RatingHistoryError.self) { try await store.correct(id: first.id, rating: 4500) }
        #expect(bytes.data == originalData)
        #expect(try await store.load() == original)
        #expect(bytes.writes == 1)
    }
}

/// In-memory persistence only: these tests never open the app's store or another filesystem path.
private final class RatingBytes: RatingHistoryPersistence, @unchecked Sendable {
    private enum Failure: Error { case read, write }
    private let lock = NSLock()
    private var stored: Data?
    private var writeCount = 0
    private var shouldFailWrite = false
    private let failRead: Bool

    init(_ data: Data? = nil, failRead: Bool = false) { stored = data; self.failRead = failRead }

    var data: Data? { lock.withLock { stored } }
    var writes: Int { lock.withLock { writeCount } }
    var failWrite: Bool {
        get { lock.withLock { shouldFailWrite } }
        set { lock.withLock { shouldFailWrite = newValue } }
    }

    func read() throws -> Data? {
        try lock.withLock {
            if failRead { throw Failure.read }
            return stored
        }
    }

    func write(_ data: Data) throws {
        try lock.withLock {
            if shouldFailWrite { throw Failure.write }
            stored = data
            writeCount += 1
        }
    }
}
