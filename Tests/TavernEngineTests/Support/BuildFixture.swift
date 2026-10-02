import Foundation
import TavernEngine

/// The September 23 Firestone snapshot, its override file, and the 36.6.1 pool from
/// `PoolFixture`. Updating production feeds must not rewrite historical replay expectations.
enum BuildFixture {
    private static let sourceDirectory = URL(filePath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/Firestone/2026-09-23", directoryHint: .isDirectory)
    private static let stats = try! FirestoneCompStats(json: Data(contentsOf: sourceDirectory.appending(path: "firestone-comp-stats.json")))
    private static let strategies = try! FirestoneStrategies(json: Data(contentsOf: sourceDirectory.appending(path: "firestone-comp-strategies.json")))
    static let overrides: BuildOverrides = BuildOverrides.current(
        at: Date(timeIntervalSince1970: 1_790_130_000), local: []
    )!

    static let catalog = BuildCatalog.compose(
        stats: stats, strategies: strategies, overrides: overrides,
        pool: PoolFixture.pool
    )
}
