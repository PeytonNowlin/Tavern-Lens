import Foundation
import TavernEngine

/// The build catalog the build tests use: the Firestone comp stats and strategies HSData
/// ships, its override file, and the 36.6.1 pool from `PoolFixture`.
enum BuildFixture {
    static let overrides: BuildOverrides = BuildOverrides.current(
        at: Date(timeIntervalSince1970: 1_790_130_000), local: []
    )!

    static let catalog = BuildCatalog.compose(
        stats: FirestoneCompStats.bundled(), strategies: FirestoneStrategies.bundled(), overrides: overrides,
        pool: PoolFixture.pool
    )
}
