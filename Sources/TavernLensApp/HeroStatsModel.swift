import Foundation
import Observation
import os
import TavernEngine

/// Firestone's hero stats for the hero pick (all players; past three days with fallbacks to
/// past seven and last patch): the cached copies at launch, then a fetch with ETags at launch
/// and every 6 hours. Each change goes to the live pipeline with the card data, which maps
/// skins to their base hero and names the heroes.
@MainActor
@Observable
final class HeroStatsModel {
    static let shared = HeroStatsModel()

    private(set) var stats: HeroStatsSet?
    private(set) var lastLoad: LoadedHeroStats?

    /// Told about the stats and the card data whenever either changes, on the main actor.
    @ObservationIgnored var onChanged: ((HeroStatsSet?, CardDB?) -> Void)?

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false
    @ObservationIgnored private let store = HeroStatsStore()
    @ObservationIgnored private let log = Logger(subsystem: "com.nowlinautomation.TavernLens", category: "herostats")

    var statusText: String {
        guard let stats, !stats.heroCardIDs.isEmpty else { return "Hero stats: none yet" }
        let updated = HeroStatsWindow.preference.compactMap(stats.lastUpdate(of:)).max()
        let age = updated.map { " updated \($0.formatted(.relative(presentation: .named)))" } ?? ""
        let stale = updated.map { HeroStatsSet.isStale(updatedAt: $0, now: Date()) } ?? true
        return "Hero stats: \(stats.heroCardIDs.count) heroes,\(age)\(stale ? " (stale)" : "")"
    }

    /// Call once, at launch.
    func start() {
        guard !started else { return }
        started = true
        CardDataModel.shared.loadIfNeeded()
        let store = store
        Task {
            // Draw from the cache at once; the network may be slow or down.
            let cached = await Task.detached(priority: .utility) { store.cached() }.value
            if stats == nil, !cached.files.isEmpty { publish(cached) }
            refresh()
        }
        observeCardData()
        timer = Timer.scheduledTimer(withTimeInterval: HeroStatsStore.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func observeCardData() {
        withObservationTracking {
            _ = CardDataModel.shared.loaded
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.onChanged?(self.stats, CardDataModel.shared.cards)
                self.observeCardData()
            }
        }
    }

    private func refresh() {
        let store = store
        Task {
            let loaded = await Task.detached(priority: .utility) { await store.load() }.value
            lastLoad = loaded
            for (window, origin) in loaded.origins {
                switch origin {
                case .stale(let reason), .missing(let reason):
                    log.notice("Hero stats \(window.rawValue, privacy: .public) not refreshed: \(reason, privacy: .public)")
                case .downloaded, .notModified:
                    break
                }
            }
            if loaded.stats != stats { publish(loaded.stats) }
        }
    }

    private func publish(_ newStats: HeroStatsSet) {
        stats = newStats
        onChanged?(newStats, CardDataModel.shared.cards)
    }
}
