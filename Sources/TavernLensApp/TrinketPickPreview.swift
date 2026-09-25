import AppKit
import SwiftUI
import TavernEngine

extension AppDelegate {
    /// Offline visual QA: --render-trinket-preview input.json output.png. Does not start tracking.
    static func renderTrinketPreview(_ arguments: [String]) {
        do {
            guard let index = arguments.firstIndex(of: "--render-trinket-preview"), arguments.count > index + 2 else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let data = try Data(contentsOf: URL(filePath: arguments[index + 1]))
            let pick = try JSONDecoder().decode(TrinketPickView.self, from: data)
            let renderer = ImageRenderer(content: TrinketPickPanel(pick: pick, scale: 1)
                .frame(width: 360).environment(\.colorScheme, .dark))
            renderer.scale = 2
            guard let image = renderer.nsImage?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: image)?.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: URL(filePath: arguments[index + 2]))
            NSApp.terminate(nil)
        } catch {
            fputs("Trinket preview failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
