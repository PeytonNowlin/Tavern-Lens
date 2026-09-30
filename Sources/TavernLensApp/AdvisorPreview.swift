import AppKit
import OverlayLayout
import SwiftUI
import TavernEngine

extension AppDelegate {
    /// Offline visual QA. Accepts AdviceView or an AdvisorDecision envelope; no live tracking.
    /// --scale 0.8, --comfortable, --details and --collapsed exercise supported presentations.
    static func renderAdvisorPreview(_ arguments: [String]) {
        do {
            let interactive = arguments.contains("--show-advisor-preview")
            let flag = interactive ? "--show-advisor-preview" : "--render-advisor-preview"
            guard let index = arguments.firstIndex(of: flag), arguments.count > index + (interactive ? 1 : 2) else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            let data = try Data(contentsOf: URL(filePath: arguments[index + 1]))
            let decoder = JSONDecoder()
            let envelope = try? decoder.decode(AdvisorPreviewInput.self, from: data)
            let advice = try envelope?.displayed ?? decoder.decode(AdviceView.self, from: data)
            let request = envelope?.request
            let name: (String) -> String = { request?.recruit?.definitions[$0]?.name ?? $0 }
            let presentation = AdvisorPresentation(advice: advice, request: request,
                detectedBuilds: envelope?.detectedBuilds ?? [], name: name)
            var scale: CGFloat = 1
            if let scaleIndex = arguments.firstIndex(of: "--scale"), arguments.count > scaleIndex + 1,
               let value = Double(arguments[scaleIndex + 1]), value.isFinite {
                scale = min(1.6, max(0.8, value))
            }
            let content = AdvisorPreviewContent(presentation: presentation, scale: scale,
                density: arguments.contains("--comfortable") ? .comfortable : .compact,
                detailsExpanded: arguments.contains("--details"), collapsed: arguments.contains("--collapsed"), name: name)
                .environment(\.colorScheme, .dark)
            if interactive {
                NSApp.setActivationPolicy(.regular)
                let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 450 * scale, height: 282 * scale),
                    styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
                window.title = "Advisor Preview — recorded decision"
                window.isReleasedWhenClosed = false
                window.contentView = NSHostingView(rootView: content.padding(10 * scale))
                window.center()
                window.makeKeyAndOrderFront(nil)
                NSApp.activate()
                return
            }
            // ImageRenderer omits native scroll views. A hosting view captures the same
            // details surface used by the live overlay, including its scroll content.
            let hosting = NSHostingView(rootView: content)
            hosting.frame = CGRect(origin: .zero, size: hosting.fittingSize)
            let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            hosting.layoutSubtreeIfNeeded()
            guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw CocoaError(.fileWriteUnknown)
            }
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
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

private struct AdvisorPreviewInput: Decodable {
    let displayed: AdviceView
    let request: AdvisorRequest?
    let detectedBuilds: [DetectedBuildView]?
}

private struct AdvisorPreviewContent: View {
    let presentation: AdvisorPresentation
    let scale: CGFloat
    let density: OverlayDensity
    @State var detailsExpanded: Bool
    @State var collapsed: Bool
    let name: (String) -> String

    var body: some View {
        HStack(alignment: .bottom, spacing: 8 * scale) {
            if detailsExpanded, !collapsed {
                AdvisorDetailsPanel(presentation: presentation, scale: scale, density: density, name: name)
                    .frame(width: 180 * scale, height: 250 * scale)
            }
            AdvisorPanel(presentation: presentation, collapsed: collapsed, detailsExpanded: detailsExpanded,
                scale: scale, density: density,
                toggle: { collapsed.toggle(); detailsExpanded = false },
                toggleDetails: { detailsExpanded.toggle() })
                .frame(width: 250 * scale, height: (collapsed ? 34 : 262) * scale)
        }
    }
}
