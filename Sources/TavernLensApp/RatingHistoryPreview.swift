import AppKit
import SwiftUI
import TavernEngine

extension AppDelegate {
    /// An isolated history fixture for visual QA; does not read or write the live store.
    static func renderRatingPreview(_ arguments: [String]) {
        let args: PreviewRenderer.Arguments
        do { args = try PreviewRenderer.Arguments(arguments, flag: "--render-rating-preview") }
        catch { PreviewRenderer.fail("Rating preview", error) }
        let model = RatingHistoryModel(store: RatingHistoryStore(url: args.input))
        Task { @MainActor in
            await model.refresh()
            PreviewRenderer.run("Rating preview") {
                let content = RatingHistoryWindow(model: model,
                    readingStatus: "MMR is read between games when the rating is visible in the Battlegrounds lobby.")
                    .environment(\.colorScheme, .dark)
                try args.writeOutput(PreviewRenderer.hostingPNG(of: content, size: CGSize(width: 800, height: 670)))
                NSApp.terminate(nil)
            }
        }
    }
}
