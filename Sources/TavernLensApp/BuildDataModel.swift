import Foundation
import Observation
import os
import TavernEngine

/// The live build catalog: Firestone's comp stats and curated strategies (fetched at launch
/// and every 6 hours with ETags, cached, with a bundled fallback) and our override file,
/// filtered by the live minion pool. Recomposed whenever the pool or the data changes.
@MainActor
@Observable
final class BuildDataModel {
    static let shared = BuildDataModel()

    private(set) var catalog: BuildCatalog?
    private(set) var data: LoadedBuildData?

    /// Told about every new catalog, on the main actor.
    @ObservationIgnored var onCatalogChanged: ((BuildCatalog?) -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false
    /// Bumped by each compose, so an older one finishing last doesn't overwrite a newer catalog.
    @ObservationIgnored private var composeGeneration = 0
    @ObservationIgnored private let log = Logger(subsystem: "com.nowlinautomation.TavernLens", category: "builds")

    var statusText: String {
        guard let catalog else { return "Builds: waiting for the minion pool" }
        let stats: String = switch data?.statsOrigin {
        case .downloaded?, .cache?: "Firestone \(catalog.provenance.statsTimePeriod ?? "")"
        case .stale?: "Firestone (stale)"
        case .bundled?: "Firestone (bundled copy)"
        case nil: "no Firestone data"
        }
        let patch = catalog.provenance.overridesPatch.map { ", overrides \($0)" } ?? ""
        return "Builds: \(catalog.builds.count), \(stats)\(patch)"
    }

    /// Call once, at launch (after `PoolDataModel.shared.start()`).
    func start() {
        guard !started else { return }
        started = true
        observePool()
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: BuildDataStore.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func observePool() {
        withObservationTracking {
            _ = PoolDataModel.shared.pool
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.compose()
                self?.observePool()
            }
        }
    }

    private func refresh() {
        Task {
            let loaded = await Task.detached(priority: .utility) { await BuildDataStore().load() }.value
            for (file, origin) in [("comp stats", loaded.statsOrigin), ("strategies", loaded.strategiesOrigin)] {
                switch origin {
                case .stale(let reason)?:
                    log.notice("Build \(file, privacy: .public) fetch failed, using the cached copy: \(reason, privacy: .public)")
                case .bundled(let reason)?:
                    log.notice("Build \(file, privacy: .public) fetch failed, using the bundled copy: \(reason, privacy: .public)")
                default:
                    break
                }
            }
            guard loaded != data else { return }
            data = loaded
            compose()
        }
    }

    private func compose() {
        guard let pool = PoolDataModel.shared.pool, let data else { return }
        let overrides = BuildOverrides.current()
        let provenance = data.provenance(overridesPatch: overrides?.patch)
        composeGeneration += 1
        let generation = composeGeneration
        Task {
            let catalog = await Task.detached(priority: .userInitiated) {
                BuildCatalog.compose(
                    stats: data.stats, strategies: data.strategies, overrides: overrides, pool: pool, provenance: provenance
                )
            }.value
            guard generation == composeGeneration else { return }
            for dropped in catalog.dropped {
                log.info("Build \(dropped.id, privacy: .public) left out: \(dropped.reason, privacy: .public)")
            }
            self.catalog = catalog
            onCatalogChanged?(catalog)
        }
    }
}
