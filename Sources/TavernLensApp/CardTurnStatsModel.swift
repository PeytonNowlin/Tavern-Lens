import Foundation
import TavernEngine

/// Refreshes the bounded conditional cache without blocking log ingestion or the UI.
@MainActor
final class CardTurnStatsModel {
    static let shared = CardTurnStatsModel()
    var onChanged: ((CardTurnStats?, Date?) -> Void)?
    private let store = CardTurnStatsStore()
    private var timer: Timer?
    private var loading = false
    private var published: CardTurnStats?

    func start() {
        guard timer == nil else { return }
        refresh()
        // Cache hits avoid a request for six hours; missing/failed fetches retry sooner.
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        guard !loading else { return }
        loading = true
        let store = store
        Task {
            let cached = await Task.detached(priority: .utility) { store.cached() }.value
            if let cached, cached.usable(now: Date()) { publish(cached, checkedAt: Date()) }
            let loaded = await store.load(now: Date())
            loading = false
            publish(loaded.stats?.usable(now: loaded.checkedAt) == true ? loaded.stats : nil, checkedAt: loaded.checkedAt)
        }
    }

    private func publish(_ stats: CardTurnStats?, checkedAt: Date) {
        guard stats != published else { return }
        published = stats
        onChanged?(stats, stats == nil ? nil : checkedAt)
    }
}
