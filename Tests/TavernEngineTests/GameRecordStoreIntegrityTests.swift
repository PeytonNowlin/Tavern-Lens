import Foundation
import Testing
import TavernEngine

/// A record that can't be read is never silently replaced: its bookmarks live only there.
@Suite("Game record store integrity")
struct GameRecordStoreIntegrityTests {
    static func record() throws -> GameRecord {
        var engine = TavernEngine(session: try GameRecordTests.session("Hearthstone_2026_09_22_21_08_40"), timeZone: .gmt)
        for line in GameRecordTests.afterFirstCombat().lines { engine.ingest(line) }
        engine.finish()
        return try #require(engine.takeUnsavedRecords().last)
    }

    @Test("A corrupt existing record is moved aside, not overwritten")
    func corruptIsKept() throws {
        let directory = BookmarkTests.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameRecordStore(directory: directory)
        let record = try Self.record()
        try store.save(record)
        let file = store.url(for: record)
        let garbage = Data("{\"format\":1,\"bookmarks\":[".utf8)
        try garbage.write(to: file)

        try store.save(record)

        let aside = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.contains(".corrupt-") }
        #expect(aside.count == 1)
        #expect(try Data(contentsOf: directory.appending(path: aside[0])) == garbage)
        #expect(store.load(seed: try #require(record.gameSeed)) != nil)
        #expect(store.all().count == 1, "the quarantined file is not listed as a record")
    }

    @Test("A record of an unsupported format is rejected on load and never overwritten")
    func mismatchedFormatRejected() throws {
        let directory = BookmarkTests.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GameRecordStore(directory: directory)
        var record = try Self.record()
        try store.save(record)
        let file = store.url(for: record)
        record.format = GameRecord.currentFormat + 1
        try JSONEncoder().encode(["format": record.format]).write(to: file)
        let before = try Data(contentsOf: file)

        #expect(throws: GameRecordError.unsupportedFormat(record.format)) { try store.decodeRecord(at: file) }
        #expect(store.load(seed: try #require(record.gameSeed)) == nil)
        #expect(store.all().isEmpty)
        var fresh = record
        fresh.format = GameRecord.currentFormat
        #expect(throws: GameRecordError.unsupportedFormat(record.format)) { try store.save(fresh) }
        #expect(try Data(contentsOf: file) == before)
    }
}
