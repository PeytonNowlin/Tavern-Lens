import AppKit
import SwiftUI
import TavernEngine

extension AppDelegate {
    /// Offline visual QA: --render-trinket-preview input.json output.png. Does not start tracking.
    static func renderTrinketPreview(_ arguments: [String]) {
        PreviewRenderer.run("Trinket preview") {
            let args = try PreviewRenderer.Arguments(arguments, flag: "--render-trinket-preview")
            let pick = try JSONDecoder().decode(TrinketPickView.self, from: Data(contentsOf: args.input))
            let content = TrinketPickPanel(pick: pick, scale: 1).frame(width: 360).environment(\.colorScheme, .dark)
            try args.writeOutput(PreviewRenderer.imageRendererPNG(of: content, scale: 2))
            NSApp.terminate(nil)
        }
    }
}
