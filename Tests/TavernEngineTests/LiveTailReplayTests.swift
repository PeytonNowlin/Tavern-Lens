import Foundation
import HSLog
import TavernEngine
import Testing

/// A log followed live, while it's being written in arbitrary chunks, must produce
/// exactly the timeline that replaying the finished file produces.
@Suite("Live tailing matches replay", .serialized, .timeLimit(.minutes(5)))
struct LiveTailReplayTests {
    @Test("Synthetic game written in small uneven chunks")
    func synthetic() async throws {
        let text = SyntheticLog.soloGame(bgTurns: 4).lines.map { $0 + "\n" }.joined()
        try await verifyLiveMatchesReplay(Array(text.utf8), chunkSizes: [1, 7, 64, 333, 4096])
    }

    @Test(
        "Truncated capture written in large uneven chunks",
        .enabled(if: Fixtures.isAvailable(Fixtures.truncatedGame), "private fixture log not present")
    )
    func capture() async throws {
        let url = try #require(Fixtures.url(Fixtures.truncatedGame))
        let bytes = try [UInt8](Data(contentsOf: url))
        try await verifyLiveMatchesReplay(bytes, chunkSizes: [65_537, 1_000_003, 250_001])
    }

    private func verifyLiveMatchesReplay(_ bytes: [UInt8], chunkSizes: [Int]) async throws {
        // Expected: every complete line ingested in order, without end-of-input
        // handling (a live log has no end).
        var expected = TavernEngine()
        var splitter = LogLineSplitter()
        splitter.append(bytes) { expected.ingest($0) }

        let root = FileManager.default.temporaryDirectory.appending(path: "TavernLensLive-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appending(path: "Logs/Hearthstone_2026_09_22_21_08_40")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let power = session.appending(path: LogFileName.power)
        FileManager.default.createFile(atPath: power.path(percentEncoded: false), contents: nil)

        let live = LockedEngine()
        let follower = LogSessionFollower(logsDirectory: root.appending(path: "Logs")) { event in
            if case .lines(LogFileName.power, let lines) = event { live.ingest(lines) }
        }
        follower.start()
        defer { follower.stop() }

        let writer = try FileHandle(forWritingTo: power)
        var offset = 0
        var turn = 0
        while offset < bytes.count {
            let end = min(bytes.count, offset + chunkSizes[turn % chunkSizes.count])
            try writer.write(contentsOf: Data(bytes[offset..<end]))
            offset = end
            turn += 1
            if turn % 16 == 0 { try await Task.sleep(for: .milliseconds(5)) }
        }
        try writer.close()

        try await waitUntil { live.linesRead >= expected.linesRead }
        #expect(live.linesRead == expected.linesRead)
        #expect(live.timeline == expected.timeline)
        #expect(!expected.timeline.isEmpty)
    }
}

private final class LockedEngine: @unchecked Sendable {
    private let lock = NSLock()
    private var engine = TavernEngine()

    func ingest(_ lines: [String]) {
        lock.withLock { for line in lines { engine.ingest(line) } }
    }

    var linesRead: Int { lock.withLock { engine.linesRead } }
    var timeline: [TimelineEntry] { lock.withLock { engine.timeline } }
}
