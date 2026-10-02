import AppKit
import SwiftUI
import TavernEngine

extension AppDelegate {
    /// An isolated history fixture for visual QA; does not read or write the live store.
    static func renderRatingPreview(_ arguments: [String]) {
        guard let index = arguments.firstIndex(of: "--render-rating-preview"), arguments.count > index + 2 else {
            exit(1)
        }
        let model = RatingHistoryModel(store: RatingHistoryStore(url: URL(filePath: arguments[index + 1])))
        Task { @MainActor in
            await model.refresh()
            let content = RatingHistoryWindow(model: model,
                readingStatus: "MMR is read between games when the rating is visible in the Battlegrounds lobby.")
                .environment(\.colorScheme, .dark)
            let hosting = NSHostingView(rootView: content)
            hosting.frame = CGRect(x: 0, y: 0, width: 800, height: 670)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { exit(1) }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { exit(1) }
            do { try png.write(to: URL(filePath: arguments[index + 2])) }
            catch { fputs("Rating preview failed: \(error)\n", stderr); exit(1) }
            NSApp.terminate(nil)
        }
    }
}
