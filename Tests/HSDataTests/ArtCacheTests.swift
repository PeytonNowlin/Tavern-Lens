import Darwin
import Foundation
import HSData
import Testing

/// The art cache on a temporary directory: an LRU bounded by its size cap.
@Suite("Art cache")
struct ArtCacheTests {
    final class Folder {
        let url = FileManager.default.temporaryDirectory.appending(path: "TavernLensArt-\(UUID().uuidString)", directoryHint: .isDirectory)
        init() throws { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: url) }

        /// A file of `bytes`, last used `age` seconds ago.
        func file(_ name: String, bytes: Int, age: TimeInterval) throws {
            let file = url.appending(path: name)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 7, count: bytes).write(to: file)
            let used = Date().addingTimeInterval(-age).timeIntervalSince1970
            var times = [timeval(tv_sec: Int(used), tv_usec: 0), timeval(tv_sec: Int(used), tv_usec: 0)]
            #expect(utimes(file.path(percentEncoded: false), &times) == 0)
        }

        var names: [String] {
            let enumerator = FileManager.default.enumerator(atPath: url.path(percentEncoded: false))
            return (enumerator?.allObjects as? [String] ?? []).filter { !$0.hasSuffix("/") && $0.contains(".") }.sorted()
        }
    }

    @Test("Over the cap, the least recently used files go first")
    func lru() throws {
        let folder = try Folder()
        try folder.file("a.png", bytes: 400, age: 400)
        try folder.file("builds/1/b.png", bytes: 400, age: 300)
        try folder.file("c.png", bytes: 400, age: 200)
        try folder.file("d.png", bytes: 400, age: 100)
        let cache = ArtCache(directory: folder.url)

        let result = cache.prune(maxBytes: 1000)
        #expect(result.filesDeleted == 2)
        #expect(result.bytesFreed == 800)
        #expect(result.bytesRemaining == 800)
        #expect(folder.names == ["c.png", "d.png"])
    }

    @Test("A touched file counts as just used")
    func touch() throws {
        let folder = try Folder()
        try folder.file("old.png", bytes: 500, age: 1000)
        try folder.file("newer.png", bytes: 500, age: 10)
        let cache = ArtCache(directory: folder.url)
        cache.touch(folder.url.appending(path: "old.png"))
        cache.prune(maxBytes: 600)
        #expect(folder.names == ["old.png"])
    }

    @Test("Under the cap, or with no cache folder, nothing happens")
    func underCap() throws {
        let folder = try Folder()
        try folder.file("a.png", bytes: 400, age: 10)
        #expect(ArtCache(directory: folder.url).prune(maxBytes: 400).filesDeleted == 0)
        #expect(folder.names == ["a.png"])
        let missing = ArtCache(directory: folder.url.appending(path: "missing"))
        #expect(missing.prune(maxBytes: 0) == ArtCache.PruneResult())
    }
}
