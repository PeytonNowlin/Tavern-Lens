import AppKit
import SwiftUI
import TavernEngine

extension AppDelegate {
    /// Offline visual QA with a captured AdviceView. Does not start tracking or activate a window.
    static func renderAdvisorPreview(_ arguments: [String]) {
        do {
            guard let index = arguments.firstIndex(of: "--render-advisor-preview"), arguments.count > index + 2 else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let data = try Data(contentsOf: URL(filePath: arguments[index + 1]))
            let advice = try JSONDecoder().decode(AdviceView.self, from: data)
            let content = AdvisorPanel(advice: advice, collapsed: false, name: { $0 }, scale: 1, offscreen: true, toggle: {})
                .frame(width: 250, height: 262, alignment: .bottom).environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: content)
            renderer.scale = 2
            guard let image = renderer.nsImage?.tiffRepresentation,
                  let png = NSBitmapImageRep(data: image)?.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            try png.write(to: URL(filePath: arguments[index + 2]))
            NSApp.terminate(nil)
        } catch {
            fputs("Advisor preview failed: \(error)\n", stderr)
            exit(1)
        }
    }
}
