import Foundation
import TavernEngine

/// The minion pool the tribe tests use: a BG-only trim of the real build 251952
/// `cards.json` (committed), with the meta-period snapshot and override file HSData ships.
enum PoolFixture {
    static let cardsURL = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/HearthstoneJSON/cards.251952.bg.json")

    static let cards: CardDB = try! CardDB(build: 251_952, json: Data(contentsOf: cardsURL))

    static let overrides: PoolOverrides = PoolOverrides.current(
        at: Date(timeIntervalSince1970: 1_790_130_000), local: []
    )!

    /// The 36.6.1 pool: card data, HSReplay's meta period and our override file.
    static let pool = MinionPool.compose(cards: cards, metaPeriod: MetaPeriod.bundled(), overrides: overrides)

    /// What HDT and HSTracker ship: card data plus HSReplay, without our override file's
    /// per-card fixes (it keeps the tribe settings).
    static var poolWithoutOurCardFixes: MinionPool {
        var partial = overrides
        partial.minionPool = [:]
        return MinionPool.compose(cards: cards, metaPeriod: MetaPeriod.bundled(), overrides: partial)
    }

    static func tribeNames(_ names: String...) -> [String] { names.sorted() }
}

extension TribesView {
    /// The confirmed tribes' `Race` names, sorted.
    var confirmedNames: [String] { tribes.filter { $0.confidence == .confirmed }.map(\.tribe).sorted() }
}
