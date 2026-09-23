import BGIntel
import BGState
import EntityStore
import Foundation
import HSData
import os
import PowerParser

@_exported import struct BGIntel.ScreenTribeReading
@_exported import struct BGIntel.TribeEstimate
@_exported import enum BGIntel.TribeConfidence
@_exported import enum BGIntel.TribeSource

/// The current game's minion pool and tribe inference, fed from the engine's event loop.
///
/// It keeps the game's evidence, so the resolver can be rebuilt when the pool arrives
/// late (card data loads after the game started) or grows (a pool drift was adopted).
/// A different game starts it over; a reconnect of the same game carries on.
struct TribeTracker: Sendable {
    private static let log = Logger(subsystem: "com.nowlinautomation.TavernLens", category: "pool")

    /// The composed pool, before any game's adoptions.
    private(set) var basePool: MinionPool?
    /// This game's pool: the base plus cards the game flagged that the base lacked.
    private var pool: MinionPool?
    private var resolver: TribeResolver?
    private var collector = BGSightingCollector()
    private var evidence: [TribeEvidence] = []
    private var gameIndex: Int?
    private var gameSeed: Int?
    private var gameDate: Date?
    /// Every drift adopted, across games.
    private(set) var drift: [PoolDrift] = []

    init(pool: MinionPool?) {
        basePool = pool
        self.pool = pool
    }

    var estimate: TribeEstimate? { resolver?.estimate() }

    /// There's a pool to infer the tribes with (for the game in progress).
    var hasResolver: Bool { gameIndex != nil && resolver != nil }

    /// The lobby's tribes for the combat simulator: the confirmed and likely tribes, when
    /// they make up a whole lobby; nil otherwise (the simulator then allows every tribe).
    var simulatorLobby: Set<HS.Race>? {
        guard gameIndex != nil, let resolver, resolver.lobbyCount > 0 else { return nil }
        let estimate = resolver.estimate()
        let sure = Set(estimate.tribes.filter { $0.confidence == .confirmed || $0.confidence == .likely }.map(\.tribe))
        return sure.count == estimate.mostLikely.count ? sure : nil
    }

    mutating func usePool(_ newPool: MinionPool?) {
        basePool = newPool
        pool = newPool
        // Cards this game already showed to be in the pool stay in it.
        for adopted in drift where adopted.gameSeed == gameSeed && gameIndex != nil {
            _ = pool?.adopt(adopted.cardID, tier: adopted.tier, gameSeed: gameSeed)
        }
        rebuild()
    }

    /// After the store and the history applied the change.
    mutating func observe(
        _ change: EntityChange, in store: EntityStore, history: BGGameHistory, date: () -> Date?
    ) {
        if history.currentIndex != gameIndex {
            guard let index = history.currentIndex else {
                // Between a `CREATE_GAME` and its game entity, or not a solo BG game.
                if case .gameCreated = change { return }
                gameIndex = nil
                return
            }
            startGame(index: index, seed: history.current?.gameSeed, date: date())
        }
        guard gameIndex != nil else { return }
        collector.observe(change, in: store)
    }

    mutating func observe(_ event: PowerEvent) {
        guard gameIndex != nil else { return }
        collector.observe(event)
        // Discover options (Bob's Dark Gift, triple rewards, …) come from the lobby's pool.
        if case .entityChoices(let choice) = event, choice.choiceType == "GENERAL" {
            for option in choice.options where pool?.minion(option.cardID) != nil {
                record(.poolMinion(cardID: option.cardID, seen: .discover))
            }
        }
    }

    mutating func taskListEnded(_ store: EntityStore, at position: LogPosition) {
        guard gameIndex != nil else { return }
        for sighting in collector.taskListEnded(store, at: position) { add(sighting) }
    }

    /// The hero-pick banner read from the screen.
    mutating func add(_ reading: ScreenTribeReading) {
        guard gameIndex != nil else { return }
        record(.screen(reading))
    }

    func view(bgTurn: Int) -> TribesView? {
        guard gameIndex != nil, let resolver, resolver.lobbyCount > 0 else { return nil }
        return TribesView(resolver.estimate(bgTurn: bgTurn), poolIsStale: resolver.pool.provenance.isStale)
    }

    private mutating func startGame(index: Int, seed: Int?, date: Date?) {
        gameIndex = index
        gameSeed = seed
        gameDate = date
        collector = BGSightingCollector()
        evidence = []
        pool = basePool
        rebuild()
    }

    private mutating func add(_ sighting: BGSighting) {
        // The game says it's a pool minion and our pool doesn't have it: add it for this game.
        if sighting.poolFlag == 1, sighting.kind != .hero, pool != nil,
           let drift = pool?.adopt(sighting.cardID, tier: sighting.cardTier, gameSeed: gameSeed) {
            self.drift.append(drift)
            Self.log.notice(
                "Pool drift: \(drift.cardID, privacy: .public) (\(drift.name ?? "?", privacy: .public), tier \(drift.tier)) is flagged in the pool by the game but missing from ours; added for this game"
            )
            rebuild()
        }
        switch sighting.kind {
        case .shop:
            record(.shopDraw(cardID: sighting.cardID, tavernTier: sighting.tavernTier ?? 1))
        case .opponentBoard where sighting.poolFlag == 1:
            // Tokens and hero-power minions don't carry the flag.
            record(.poolMinion(cardID: sighting.cardID, seen: .opponentBoard))
        case .hero:
            record(.hero(cardID: sighting.cardID))
        case .opponentBoard, .poolFlagged:
            break
        }
    }

    private mutating func record(_ item: TribeEvidence) {
        evidence.append(item)
        resolver?.observe(item)
    }

    private mutating func rebuild() {
        guard let pool else {
            resolver = nil
            return
        }
        var resolver = TribeResolver(pool: pool, gameDate: gameDate)
        for item in evidence { resolver.observe(item) }
        self.resolver = resolver
    }
}
