import Foundation
import Observation
import os
import TavernEngine

/// Firestone's hero stats for the hero pick (rating-matched; past three days with fallbacks to
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
    @ObservationIgnored private var expiryTimer: Timer?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var ratingHistory: RatingHistoryModel?
    @ObservationIgnored private var requestedRating: HeroStatsRating?
    @ObservationIgnored private var generation = 0
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
    func start(ratings: RatingHistoryModel? = nil) {
        guard !started else { return }
        started = true
        ratingHistory = ratings
        CardDataModel.shared.loadIfNeeded()
        refresh()
        observeCardData()
        observeRatings()
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

    private var currentRating: HeroStatsRating? {
        guard let reading = ratingHistory?.history.latest else { return nil }
        return .init(rating: reading.rating, source: reading.source == .screen ? .screen : .manual, recordedAt: reading.recordedAt)
    }

    private func observeRatings() {
        guard let ratingHistory else { return }
        withObservationTracking {
            _ = ratingHistory.history.latest
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.observeRatings()
                if self.currentRating != self.requestedRating { self.refresh() }
            }
        }
    }

    private func refresh(fetch: Bool = true) {
        generation += 1
        let requested = generation
        let rating = currentRating
        requestedRating = rating
        expiryTimer?.invalidate()
        expiryTimer = nil
        let store = store
        Task {
            // Replace a prior rating's population from local evidence before waiting on the CDN.
            let cached = await Task.detached(priority: .utility) { store.cached(rating: rating) }.value
            guard requested == generation, currentRating == rating else { return }
            // Background cache work can span a deadline or system sleep, just like a network request.
            if hasExpiredPopulation(cached, at: Date()) {
                refresh(fetch: fetch)
                return
            }
            if cached != stats, stats != nil || !cached.files.isEmpty { publish(cached) }
            else { scheduleExpiry(cached) }
            guard fetch else { return }
            let loaded = await Task.detached(priority: .utility) { await store.load(rating: rating) }.value
            guard requested == generation, currentRating == rating else { return }
            // A request spanning an expiry must not restore the old population after the deadline.
            if hasExpiredPopulation(loaded.stats, at: Date()) {
                refresh(fetch: false)
                return
            }
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
            else { scheduleExpiry(loaded.stats) }
        }
    }

    private func hasExpiredPopulation(_ stats: HeroStatsSet, at now: Date) -> Bool {
        stats.selections.values.contains {
            $0.matchedPercentile != nil && ($0.rating?.isRecent(at: now) != true || $0.table?.isFresh(at: now) != true)
        }
    }

    private func publish(_ newStats: HeroStatsSet) {
        stats = newStats
        onChanged?(newStats, CardDataModel.shared.cards)
        scheduleExpiry(newStats)
    }

    /// Expiry changes the local population immediately; the six-hour network cadence remains unchanged.
    private func scheduleExpiry(_ stats: HeroStatsSet) {
        expiryTimer?.invalidate()
        expiryTimer = nil
        let now = Date()
        var deadlines = stats.selections.values.compactMap { selection in
            selection.table?.updatedAt.addingTimeInterval(MMRPercentileTable.freshFor)
        }
        if let rating = currentRating, rating.isRecent(at: now) {
            deadlines.append(rating.recordedAt.addingTimeInterval(HeroStatsRating.recentFor))
        }
        guard let deadline = deadlines.filter({ $0 >= now }).min() else { return }
        let requested = generation
        expiryTimer = Timer.scheduledTimer(withTimeInterval: max(1, deadline.timeIntervalSince(now) + 1), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.generation == requested else { return }
                self.refresh(fetch: false)
            }
        }
    }
}
