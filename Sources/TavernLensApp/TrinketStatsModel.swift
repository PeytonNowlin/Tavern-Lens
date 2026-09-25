import Foundation
import TavernEngine

/// Last-good cache and a six-hour refresh. A failed fetch never replaces usable cached data.
@MainActor
final class TrinketStatsModel {
    static let shared = TrinketStatsModel()
    var onChanged: ((TrinketStats?) -> Void)?
    private var timer: Timer?
    private var loading = false
    private let cache = URL.applicationSupportDirectory.appending(path: "TavernLens/TrinketStats/past-three.json")
    private let source = URL(string: "https://static.zerotoheroes.com/api/bgs/trinket-stats/past-three/overview-from-hourly.gz.json")!

    func start() {
        guard timer == nil else { return }
        if let data = try? Data(contentsOf: cache), let stats = try? JSONDecoder().decode(TrinketStats.self, from: data) {
            onChanged?(stats)
        }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    private func refresh() {
        guard !loading else { return }
        loading = true
        Task {
            defer { loading = false }
            do {
                var request = URLRequest(url: source)
                request.timeoutInterval = 20
                request.setValue("TavernLens/0.1 (macOS)", forHTTPHeaderField: "User-Agent")
                let (data, response) = try await URLSession.shared.data(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 5_000_000,
                      let stats = try? JSONDecoder().decode(TrinketStats.self, from: data),
                      stats.usable(now: Date()) else { return }
                try FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: cache, options: .atomic)
                onChanged?(stats)
            } catch { /* The panel explicitly identifies local-only estimates if no fresh stats exist. */ }
        }
    }
}
