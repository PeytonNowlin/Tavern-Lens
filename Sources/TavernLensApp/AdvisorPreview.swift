import AppKit
import OverlayLayout
import SwiftUI
import TavernEngine

extension AppDelegate {
    /// Offline visual QA. Accepts AdviceView or an AdvisorDecision envelope; no live tracking.
    /// --scale 0.8, --comfortable, --details and --collapsed exercise supported presentations.
    static func renderAdvisorPreview(_ arguments: [String]) {
        PreviewRenderer.run("Advisor preview") {
            let interactive = arguments.contains("--show-advisor-preview")
            let args = try PreviewRenderer.Arguments(
                arguments, flag: interactive ? "--show-advisor-preview" : "--render-advisor-preview",
                writesOutput: !interactive)
            let data = try Data(contentsOf: args.input)
            let decoder = JSONDecoder()
            let envelope = try? decoder.decode(AdvisorPreviewInput.self, from: data)
            let advice = try envelope?.displayed ?? decoder.decode(AdviceView.self, from: data)
            let request = envelope?.request
            let name: (String) -> String = { request?.recruit?.definitions[$0]?.name ?? $0 }
            let presentation = AdvisorPresentation(advice: advice, request: request,
                detectedBuilds: envelope?.detectedBuilds ?? [], name: name)
            let scale = args.scale
            let content = AdvisorPreviewContent(presentation: presentation, scale: scale,
                density: args.contains("--comfortable") ? .comfortable : .compact,
                detailsExpanded: args.contains("--details"), collapsed: args.contains("--collapsed"), name: name)
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
            try args.writeOutput(PreviewRenderer.hostingPNG(of: content))
            NSApp.terminate(nil)
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
    private let constants = LayoutConstants.current

    var body: some View {
        HStack(alignment: .bottom, spacing: 8 * scale) {
            if detailsExpanded, !collapsed {
                AdvisorDetailsPanel(presentation: presentation, scale: scale, density: density, name: name)
                    // Match the live HUD-width details surface when checking text wrapping.
                    .frame(width: constants.hudSize.width * scale,
                           height: constants.buildOverlay.tipsPanelHeight * scale)
            }
            AdvisorPanel(presentation: presentation, collapsed: collapsed, detailsExpanded: detailsExpanded,
                scale: scale, density: density,
                toggle: { collapsed.toggle(); detailsExpanded = false },
                toggleDetails: { detailsExpanded.toggle() })
                .frame(width: constants.advisor.panelSize.width * scale,
                       height: (collapsed ? constants.advisor.headerHeight : constants.advisor.panelSize.height) * scale)
        }
    }
}
