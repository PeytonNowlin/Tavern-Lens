import Foundation
import Observation
import TavernEngine

@MainActor
@Observable
final class RatingHistoryModel {
    private(set) var history = RatingHistory()
    private(set) var errorMessage: String?
    private var activeOperations = 0
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let store: RatingHistoryStore

    init(store: RatingHistoryStore = .standard) { self.store = store }

    var entries: [RatingReading] { history.readings }
    var isBusy: Bool { activeOperations > 0 }

    func refresh() async {
        _ = await update { [store] in try await store.load() }
    }

    /// true includes an accepted stable duplicate; false means nothing was saved.
    @discardableResult
    func record(_ rating: Int, source: RatingReading.Source, gameSeed: Int? = nil, at: Date = Date()) async -> Bool {
        await update { [store] in
            let reading = try RatingReading(recordedAt: at, rating: rating, source: source, gameSeed: gameSeed)
            return try await store.record(reading)
        }
    }

    @discardableResult
    func correct(id: UUID, rating: Int) async -> Bool {
        await update { [store] in try await store.correct(id: id, rating: rating) }
    }

    private func update(_ operation: @Sendable () async throws -> RatingHistory) async -> Bool {
        generation += 1
        let requested = generation
        activeOperations += 1
        defer { activeOperations -= 1 }
        do {
            let loaded = try await operation()
            // A slower earlier refresh must not replace a newer result or its error.
            if requested == generation {
                history = loaded
                errorMessage = nil
            }
            return true
        } catch {
            if requested == generation { errorMessage = error.localizedDescription }
            return false
        }
    }
}
