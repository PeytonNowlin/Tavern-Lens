import Foundation
import Observation
import os
import TavernEngine

/// The live minion pool: the running build's card data, HSReplay's live meta period
/// (fetched at launch and every 6 hours, cached, with a bundled fallback) and our override
/// file, composed whenever one of them changes. The live pipeline and the debug replay use it.
@MainActor
@Observable
final class PoolDataModel {
    static let shared = PoolDataModel()

    private(set) var pool: MinionPool?
    private(set) var metaPeriod: LoadedMetaPeriod?
    private(set) var overrides: PoolOverrides?

    /// Told about every new pool, on the main actor.
    @ObservationIgnored var onPoolChanged: ((MinionPool?) -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false
    /// The first meta-period load has finished (it falls back to the bundled copy at worst),
    /// so a pool composed now isn't missing HSReplay's layer.
    @ObservationIgnored private var metaPeriodTried = false
    /// Bumped by each compose, so an older one finishing last doesn't overwrite a newer pool.
    @ObservationIgnored private var composeGeneration = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.nowlinautomation.TavernLens", category: "pool")

    var statusText: String {
        guard let pool else { return "Minion pool: waiting for card data" }
        let period: String = switch metaPeriod?.origin {
        case .downloaded?, .cache?: metaPeriod.map { "\($0.period.name)" } ?? "no meta period"
        case .stale?: "\(metaPeriod?.period.name ?? "?") (stale)"
        case .bundled?: "\(metaPeriod?.period.name ?? "?") (bundled copy)"
        case nil: "no meta period"
        }
        let patch = overrides.map { ", overrides \($0.patch)" } ?? ""
        return "Minion pool: \(pool.minions.count) minions, \(period)\(patch)"
    }

    /// Call once, at launch.
    func start() {
        guard !started else { return }
        started = true
        CardDataModel.shared.loadIfNeeded()
        observeCardData()
        refreshMetaPeriod()
        timer = Timer.scheduledTimer(withTimeInterval: MetaPeriodStore.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshMetaPeriod() }
        }
    }

    private func observeCardData() {
        withObservationTracking {
            _ = CardDataModel.shared.loaded
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.compose()
                self?.observeCardData()
            }
        }
        compose()
    }

    private func refreshMetaPeriod() {
        Task {
            let loaded = await Task.detached(priority: .utility) { await MetaPeriodStore().load() }.value
            if let loaded, case .stale(let reason) = loaded.origin {
                log.notice("Meta period fetch failed, using the cached copy: \(reason, privacy: .public)")
            } else if let loaded, case .bundled(let reason) = loaded.origin {
                log.notice("Meta period fetch failed, using the bundled copy: \(reason, privacy: .public)")
            }
            let first = !metaPeriodTried
            metaPeriodTried = true
            guard first || loaded != metaPeriod else { return }
            metaPeriod = loaded
            compose()
        }
    }

    private func compose() {
        guard let cards = CardDataModel.shared.loaded, metaPeriodTried else { return }
        let overrides = PoolOverrides.current()
        self.overrides = overrides
        let meta = metaPeriod
        let provenance = MinionPool.Provenance(
            cardBuild: cards.db.build, cardDataIsExact: cards.isExact, metaPeriodName: meta?.period.name,
            metaPeriodIsStale: meta?.isStale ?? true, overridesPatch: overrides?.patch
        )
        composeGeneration += 1
        let generation = composeGeneration
        Task {
            let pool = await Task.detached(priority: .userInitiated) {
                MinionPool.compose(cards: cards.db, metaPeriod: meta?.period, overrides: overrides, provenance: provenance)
            }.value
            guard generation == composeGeneration else { return }
            self.pool = pool
            onPoolChanged?(pool)
        }
    }
}
