import Foundation

/// The on-disk card art cache, bounded as an LRU: when it's over its cap, the files
/// used longest ago go first.
///
/// "Used" is the later of a file's last access and last modification, so a reader
/// that marks a hit with `touch(_:)` keeps the file alive even where the volume
/// doesn't record access times.
public struct ArtCache: Sendable {
    public static let defaultLimit: Int64 = 1_000_000_000

    public let directory: URL

    public init(directory: URL = ArtCache.defaultDirectory) {
        self.directory = directory
    }

    /// `~/Library/Application Support/TavernLens/Art`.
    public static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "TavernLens/Art", directoryHint: .isDirectory)
    }

    public struct PruneResult: Hashable, Sendable {
        public var filesDeleted = 0
        public var bytesFreed: Int64 = 0
        public var bytesRemaining: Int64 = 0

        public init() {}
    }

    /// Marks a cached file as just used.
    public func touch(_ url: URL) {
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path(percentEncoded: false))
    }

    /// Deletes the least recently used files until the cache is at most `maxBytes`.
    @discardableResult
    public func prune(maxBytes: Int64) -> PruneResult {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentAccessDateKey, .contentModificationDateKey]
        var files: [(url: URL, size: Int64, used: Date)] = []
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
                let used = max(values.contentAccessDate ?? .distantPast, values.contentModificationDate ?? .distantPast)
                files.append((url, Int64(values.fileSize ?? 0), used))
            }
        }
        var result = PruneResult()
        var total = files.reduce(0) { $0 + $1.size }
        for file in files.sorted(by: { ($0.used, $0.url.path) < ($1.used, $1.url.path) }) where total > max(0, maxBytes) {
            guard (try? FileManager.default.removeItem(at: file.url)) != nil else { continue }
            total -= file.size
            result.filesDeleted += 1
            result.bytesFreed += file.size
        }
        result.bytesRemaining = total
        return result
    }
}
