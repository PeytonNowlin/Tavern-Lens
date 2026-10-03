import Foundation

/// The QA and diagnostic command-line modes `TavernLens` runs instead of starting tracking.
/// `AppDelegate.applicationDidFinishLaunching` asks for the first one present and handles it.
enum DebugCommand {
    case ratingPreview, opponentPreview, advisorPreview, settingsPreview, trinketPreview, simulatorBenchmark

    /// The mode `arguments` selects, in precedence order; nil for a normal launch.
    init?(_ arguments: [String]) {
        let table: [(DebugCommand, [String])] = [
            (.ratingPreview, ["--render-rating-preview"]),
            (.opponentPreview, ["--render-opponent-preview"]),
            (.advisorPreview, ["--render-advisor-preview", "--show-advisor-preview"]),
            (.settingsPreview, ["--show-settings-preview"]),
            (.trinketPreview, ["--render-trinket-preview"]),
            (.simulatorBenchmark, ["--simulator-benchmark"]),
        ]
        guard let match = table.first(where: { _, flags in flags.contains(where: arguments.contains) }) else { return nil }
        self = match.0
    }
}
