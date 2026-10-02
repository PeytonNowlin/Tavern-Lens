import OverlayLayout
import SwiftUI
import TavernEngine

/// A single current action, plus deliberate access to its plan and evidence. Only the
/// bottom controls and the open details panel take clicks; game targets remain click-through.
struct AdvisorOverlays: View {
    let advice: AdviceView
    let game: GameView
    let layout: OverlayLayout
    let collapsed: Bool
    var detailsExpanded = false
    var request: AdvisorRequest?
    var density: OverlayDensity = .compact
    let cards: CardDB?
    let toggle: () -> Void
    var toggleDetails: () -> Void = {}

    var body: some View {
        let presentation = AdvisorPresentation(advice: advice, request: request,
            detectedBuilds: game.builds?.detected ?? [], name: name)
        ZStack(alignment: .topLeading) {
            if let primary = presentation.primary {
                AdvisorHighlights(targets: primary.targets, game: game, layout: layout)
            }
            let rect = collapsed ? layout.advisorHeader : layout.advisorPanel
            AdvisorPanel(presentation: presentation, collapsed: collapsed, detailsExpanded: detailsExpanded,
                         scale: layout.panelScale, density: density, metrics: layout.constants.advisor,
                         toggle: toggle, toggleDetails: toggleDetails)
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
            if detailsExpanded, !collapsed {
                let details = layout.advisorDetailsPanel
                AdvisorDetailsPanel(presentation: presentation, scale: layout.panelScale,
                                    density: density, name: name)
                    .id(advice.fingerprint)
                    .frame(width: details.width, height: details.height)
                    .offset(x: details.minX, y: details.minY)
            }
        }
    }

    private func name(_ cardID: String) -> String {
        cards?.name(of: cardID) ?? game.cardName(cardID) ?? cardID
    }
}

extension GameView {
    func cardName(_ cardID: String) -> String? {
        let all = shop.cards + (player?.board ?? []) + (player?.hand ?? [])
        return all.first { $0.cardID == cardID }?.name
    }
}

/// Only the first target of the current action gets a Next marker. Supporting targets
/// keep a quiet dashed outline, without implying numbered alternative ranks are plan steps.
struct AdvisorHighlights: View {
    let targets: [AdvisorTarget]
    let game: GameView
    let layout: OverlayLayout

    var body: some View {
        let m = layout.constants.advisor, h = layout.height
        ZStack(alignment: .topLeading) {
            ForEach(Array(elements.enumerated()), id: \.offset) { index, element in
                let ring = layout.advisorRing(element)
                RoundedRectangle(cornerRadius: m.ringCornerRadius * h, style: .continuous)
                    .strokeBorder(AdvisorStyle.accent.opacity(index == 0 ? 1 : 0.55),
                        style: StrokeStyle(lineWidth: m.ringLineWidth * h,
                                           dash: index == 0 ? [] : [0.01 * h, 0.005 * h]))
                    .frame(width: ring.width, height: ring.height)
                    .offset(x: ring.minX, y: ring.minY)
                if index == 0 {
                    let badge = layout.advisorNextBadge(element)
                    Text("Next")
                        .font(.system(size: max(12, badge.height * 0.48), weight: .semibold))
                        .foregroundStyle(.black.opacity(0.9))
                        .frame(width: badge.width, height: badge.height)
                        .background(AdvisorStyle.accent, in: Capsule())
                        .offset(x: badge.minX, y: badge.minY)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private var elements: [OverlayLayout.AdvisorElement] {
        var seen: Set<OverlayLayout.AdvisorElement> = []
        return targets.compactMap(element).filter { seen.insert($0).inserted }
    }

    private func element(_ target: AdvisorTarget) -> OverlayLayout.AdvisorElement? {
        let shop = game.shop.cards.count, board = game.player?.board.count ?? 0, hand = game.player?.hand.count ?? 0
        switch (target.kind, target.index) {
        case (.shop, let i?) where i >= 0 && i < shop: return .shop(index: i, count: shop)
        case (.board, let i?) where i >= 0 && i < board: return .board(index: i, count: board)
        case (.hand, let i?) where i >= 0 && i < hand: return .hand(index: i, count: hand)
        case (.levelButton, _): return .levelButton
        case (.rollButton, _): return .rollButton
        case (.freezeButton, _): return .freezeButton
        default: return nil
        }
    }
}

enum AdvisorStyle {
    static let accent = Color(red: 0.55, green: 0.84, blue: 0.92)

    static func color(_ confidence: AdvisorConfidence) -> Color {
        switch confidence {
        case .high: .green
        case .medium: Color(red: 0.88, green: 0.75, blue: 0.48)
        case .low: .secondary
        }
    }

    static func label(_ confidence: AdvisorConfidence) -> String {
        switch confidence {
        case .high: "High confidence"
        case .medium: "Medium confidence"
        case .low: "Low confidence"
        }
    }
}

struct AdvisorPanel: View {
    let presentation: AdvisorPresentation
    let collapsed: Bool
    var detailsExpanded = false
    let scale: CGFloat
    var density: OverlayDensity = .compact
    var metrics = AdvisorMetrics()
    let toggle: () -> Void
    var toggleDetails: () -> Void = {}

    private var type: AdvisorTypography { AdvisorTypography(density: density, panelScale: scale) }

    var body: some View {
        VStack(spacing: 0) {
            if !collapsed {
                ViewThatFits(in: .vertical) {
                    summary(showsContext: true, reasonLines: type.reasonLines)
                    summary(showsContext: false, reasonLines: 1)
                    summary(showsContext: false, reasonLines: 0)
                }
                .padding(.horizontal, metrics.padding.width * scale)
                .padding(.vertical, 8 * scale)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)
                Divider().overlay(.white.opacity(0.08))
            }
            controls.frame(height: metrics.headerHeight * scale)
        }
        .modifier(AdvisorSurface(radius: metrics.cornerRadius * scale))
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private func summary(showsContext: Bool, reasonLines: Int) -> some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            HStack {
                Text(presentation.primary == nil ? "ADVISOR" : "NEXT ACTION")
                    .tracking(0.9)
                    .foregroundStyle(AdvisorStyle.accent)
                Spacer(minLength: 0)
                if presentation.state == .thinking || presentation.state == .updating {
                    Image(systemName: "ellipsis")
                }
            }
            .font(.system(size: type.labelFontSize, weight: .medium))
            Text(presentation.title)
                .font(.system(size: type.titleFontSize, weight: .semibold))
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(2)
            if let confidence = presentation.primary?.confidence ?? presentation.choice?.confidence {
                HStack(spacing: 4) {
                    Text(AdvisorStyle.label(confidence))
                        .foregroundStyle(AdvisorStyle.color(confidence))
                    if let limitations = presentation.primary?.limitations, !limitations.isEmpty {
                        Text("· \(limitations.count) \(limitations.count == 1 ? "limit" : "limits")")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.system(size: type.labelFontSize))
                .fixedSize(horizontal: false, vertical: true)
            }
            if reasonLines > 0 || presentation.primary == nil {
                Text(presentation.summaryReason)
                    .font(.system(size: type.bodyFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(presentation.primary == nil ? 4 : reasonLines)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if presentation.primary != nil, let caution = presentation.caveat {
                Text(caution)
                    .font(.system(size: type.labelFontSize))
                    .foregroundStyle(Color(red: 0.88, green: 0.75, blue: 0.48))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }
            if showsContext {
                if let direction = presentation.direction {
                    Divider()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(direction.committed ? "Building toward" : "Suggested direction")
                            .foregroundStyle(.secondary)
                        Text(direction.name).fontWeight(.medium)
                    }
                    .font(.system(size: type.labelFontSize))
                    .lineLimit(type.contextLines)
                } else if let fit = presentation.currentFits.first {
                    Text("Current fit: \(fit.name)")
                        .font(.system(size: type.labelFontSize))
                        .foregroundStyle(.secondary)
                        .lineLimit(type.contextLines)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private var controls: some View {
        if collapsed {
            Button(action: toggle) {
                HStack(spacing: 6) {
                    Image(systemName: "lightbulb")
                        .foregroundStyle(AdvisorStyle.accent)
                    Text(presentation.title).lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up")
                }
                .padding(.horizontal, metrics.padding.width * scale)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .font(.system(size: type.headerFontSize, weight: .medium))
            .accessibilityLabel("Expand advisor: \(presentation.title)")
        } else {
            HStack(spacing: 0) {
                Button(action: toggleDetails) {
                    HStack(spacing: 6) {
                        Image(systemName: detailsExpanded ? "text.alignleft" : "info.circle")
                        Text(detailsExpanded ? "Hide details" : "Why & plan")
                        Spacer(minLength: 0)
                        Image(systemName: detailsExpanded ? "chevron.down" : "chevron.up")
                    }
                    .foregroundStyle(detailsExpanded ? AdvisorStyle.accent : .primary)
                    .padding(.horizontal, metrics.padding.width * scale)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel(detailsExpanded ? "Hide advisor details" : "Show advisor explanation and plan")
                Button(action: toggle) {
                    Image(systemName: "minus")
                        .frame(width: metrics.headerHeight * scale, height: metrics.headerHeight * scale)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Collapse advisor")
                .help("Collapse advisor")
            }
            .buttonStyle(.plain)
            .font(.system(size: type.headerFontSize, weight: .medium))
        }
    }
}

struct AdvisorSurface: ViewModifier {
    let radius: CGFloat
    func body(content: Content) -> some View {
        content
            .foregroundStyle(.primary)
            .background(Color(red: 0.10, green: 0.12, blue: 0.13),
                        in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5))
            .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}
