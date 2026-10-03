import AppKit
import OverlayLayout
import SwiftUI
import TavernEngine

extension AppDelegate {
    /// Offline renderer for the exact live scouting bounds; never starts tracking.
    static func renderOpponentPreview(_ arguments: [String]) {
        PreviewRenderer.run("Opponent preview") {
            let args = try PreviewRenderer.Arguments(arguments, flag: "--render-opponent-preview")
            let input = try JSONDecoder().decode(OpponentPreviewInput.self, from: Data(contentsOf: args.input))
            let scale = args.scale
            let constants = LayoutConstants.current
            let size = CGSize(width: constants.hudSize.width * scale,
                              height: (constants.nextOpponentPreviewHeight + constants.oddsPreview.height) * scale)
            let content = NextOpponentPreview(entry: input.entry, currentTurn: input.currentTurn, cards: nil,
                                              scale: scale, odds: input.odds, oddsMetrics: constants.oddsPreview)
                .frame(width: size.width, height: size.height, alignment: .top)
                .environment(\.colorScheme, .dark)
            try args.writeOutput(PreviewRenderer.hostingPNG(of: content, size: size))
            NSApp.terminate(nil)
        }
    }
}

private struct OpponentPreviewInput: Decodable {
    let entry: LobbyEntryView
    let currentTurn: Int
    let odds: OddsPreviewView?
}
