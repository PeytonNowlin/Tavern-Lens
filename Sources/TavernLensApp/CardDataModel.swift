import Foundation
import Observation
import TavernEngine

/// Card data for the running Hearthstone build: from the cache, or downloaded once for a new
/// build, or the newest cached build when offline. Loaded at launch, and again when Hearthstone
/// starts with a different build than the one loaded (`reloadIfBuildChanged`); the minion pool
/// and the hero stats, which observe `loaded`, follow.
@MainActor
@Observable
final class CardDataModel {
    static let shared = CardDataModel()

    private(set) var loaded: LoadedCardData?
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    var cards: CardDB? { loaded?.db }

    var statusText: String {
        if isLoading { return "Loading card data…" }
        if let errorMessage { return "No card data: \(errorMessage)" }
        guard let loaded else { return "Card data not loaded" }
        let build = loaded.db.build.map { "build \($0)" } ?? "latest build"
        let count = "\(loaded.db.count.formatted()) cards"
        switch loaded.origin {
        case .cache: return "Card data: \(build), \(count), cached"
        case .downloaded: return "Card data: \(build), \(count), downloaded"
        case .fallback(let reason):
            let wanted = loaded.requestedBuild.map { " (wanted build \($0))" } ?? ""
            return "Card data: \(build)\(wanted), \(count), stale: \(reason)"
        }
    }

    /// How many earlier builds' card data the cache keeps (the retention settings).
    @ObservationIgnored var previousBuildsKept: () -> Int = { RetentionSettings().previousCardDataBuilds }

    func loadIfNeeded() {
        guard loaded == nil, !isLoading else { return }
        load(appURL: nil)
    }

    /// Hearthstone just started (from `appURL`): if it's another build than the card data
    /// loaded, loads that build's.
    func reloadIfBuildChanged(appURL: URL?) {
        guard !isLoading else { return }
        let app = appURL ?? HearthstoneBuild.defaultAppURL
        Task {
            let running = await Task.detached(priority: .utility) { HearthstoneBuild.installed(appURL: app) }.value
            guard !isLoading, let loaded, loaded.needsReload(forRunning: running) else { return }
            load(appURL: app)
        }
    }

    private func load(appURL: URL?) {
        isLoading = true
        errorMessage = nil
        var settings = RetentionSettings()
        settings.previousCardDataBuilds = previousBuildsKept()
        let cache = settings.cardDataCache()
        Task {
            do {
                loaded = try await Task.detached(priority: .userInitiated) {
                    let build = HearthstoneBuild.installed(appURL: appURL ?? HearthstoneBuild.defaultAppURL)
                    return try await CardDataStore(cache: cache).load(build: build)
                }.value
            } catch {
                errorMessage = "\(error)"
            }
            isLoading = false
        }
    }
}
