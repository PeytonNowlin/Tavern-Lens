import AppKit
import OverlayLayout
import SwiftUI
import TavernEngine

extension AppDelegate {
    /// Offline renderer for the exact live scouting bounds; never starts tracking.
    static func renderOpponentPreview(_ arguments: [String]) {
        do {
            guard let index = arguments.firstIndex(of: "--render-opponent-preview"), arguments.count > index + 2 else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let data = try Data(contentsOf: URL(filePath: arguments[index + 1]))
            let input = try JSONDecoder().decode(OpponentPreviewInput.self, from: data)
            var scale: CGFloat = 1
            if let i = arguments.firstIndex(of: "--scale"), arguments.count > i + 1,
               let value = Double(arguments[i + 1]), value.isFinite { scale = min(1.6, max(0.8, value)) }
            let constants = LayoutConstants.current
            let size = CGSize(width: constants.hudSize.width * scale,
                              height: (constants.nextOpponentPreviewHeight + constants.oddsPreview.height) * scale)
            let content = NextOpponentPreview(entry: input.entry, currentTurn: input.currentTurn, cards: nil,
                                              scale: scale, odds: input.odds, oddsMetrics: constants.oddsPreview)
                .frame(width: size.width, height: size.height, alignment: .top)
                .environment(\.colorScheme, .dark)
            let hosting = NSHostingView(rootView: content)
            hosting.frame = CGRect(origin: .zero, size: size)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { throw CocoaError(.fileWriteUnknown) }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: URL(filePath: arguments[index + 2]))
            NSApp.terminate(nil)
        } catch {
            fputs("Opponent preview failed: \(error)\n", stderr)
            exit(1)
        }
    }
}

private struct OpponentPreviewInput: Decodable {
    let entry: LobbyEntryView
    let currentTurn: Int
    let odds: OddsPreviewView?
}
