import OverlayLayout
import SwiftUI
import TavernEngine

/// The advisor during recruit: the ranked list near the gold bar (collapsible from its header,
/// the only part that takes clicks) and a ring with a rank badge on each suggestion's shop card,
/// minion, hand card or tavern button. It only points; it never acts for the player.
struct AdvisorOverlays: View {
    let advice: AdviceView
    let game: GameView
    let layout: OverlayLayout
    let collapsed: Bool
    let cards: CardDB?
    let toggle: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsHighlights {
                AdvisorHighlights(suggestions: advice.advice.suggestions, game: game, layout: layout)
            }
            let rect = collapsed ? layout.advisorHeader : layout.advisorPanel
            AdvisorPanel(
                advice: advice, collapsed: collapsed, name: name, scale: layout.panelScale,
                metrics: layout.constants.advisor, toggle: toggle
            )
            .frame(width: rect.width, height: rect.height, alignment: .bottom)
            .offset(x: rect.minX, y: rect.minY)
        }
    }

    /// Only a current, confident recommendation is pointed at in place; while the state is being
    /// re-scored the old targets may have moved.
    private var showsHighlights: Bool {
        advice.advice.status == .recommendation && !advice.isUpdating && advice.failure == nil
    }

    private func name(_ cardID: String) -> String {
        cards?.name(of: cardID) ?? game.cardName(cardID) ?? cardID
    }
}

extension GameView {
    /// A card's name as the view state has it (the live engine runs without card data, so often nil).
    func cardName(_ cardID: String) -> String? {
        let all = shop.cards + (player?.board ?? []) + (player?.hand ?? [])
        return all.first { $0.cardID == cardID }?.name
    }
}

/// Rings and rank badges on the suggestions' targets, placed with `OverlayLayout.advisorRing(_:)`
/// and `advisorBadge(_:)` from the counts on screen.
struct AdvisorHighlights: View {
    let suggestions: [AdvisorSuggestion]
    let game: GameView
    let layout: OverlayLayout

    var body: some View {
        let m = layout.constants.advisor
        let h = layout.height
        ZStack(alignment: .topLeading) {
            ForEach(items, id: \.id) { item in
                let ring = layout.advisorRing(item.element)
                let badge = layout.advisorBadge(item.element)
                let color = AdvisorStyle.color(rank: item.rank)
                RoundedRectangle(cornerRadius: m.ringCornerRadius * h, style: .continuous)
                    .strokeBorder(color.opacity(item.isPrimary ? 1 : 0.7),
                                  style: StrokeStyle(lineWidth: m.ringLineWidth * h, dash: item.isPrimary ? [] : [0.01 * h, 0.005 * h]))
                    .shadow(color: color.opacity(0.5), radius: 0.005 * h)
                    .frame(width: ring.width, height: ring.height)
                    .offset(x: ring.minX, y: ring.minY)
                Text("\(item.rank)")
                    .font(.system(size: badge.height * 0.62, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: badge.width, height: badge.height)
                    .background(color, in: Circle())
                    .overlay(Circle().strokeBorder(.black.opacity(0.35), lineWidth: 0.5))
                    .offset(x: badge.minX, y: badge.minY)
            }
        }
        .allowsHitTesting(false)
    }

    private struct Item {
        var id: String
        var rank: Int
        var element: OverlayLayout.AdvisorElement
        var isPrimary: Bool
    }

    /// Each target once, with the best rank that points at it.
    private var items: [Item] {
        var seen: Set<OverlayLayout.AdvisorElement> = []
        var items: [Item] = []
        for suggestion in suggestions {
            for (index, target) in suggestion.targets.enumerated() {
                guard let element = element(target), seen.insert(element).inserted else { continue }
                items.append(Item(id: "\(suggestion.rank)-\(index)", rank: suggestion.rank, element: element, isPrimary: index == 0))
            }
        }
        return items
    }

    private func element(_ target: AdvisorTarget) -> OverlayLayout.AdvisorElement? {
        let shop = game.shop.cards.count, board = game.player?.board.count ?? 0, hand = game.player?.hand.count ?? 0
        switch (target.kind, target.index) {
        case (.shop, let i?) where i < shop: return .shop(index: i, count: shop)
        case (.board, let i?) where i < board: return .board(index: i, count: board)
        case (.hand, let i?) where i < hand: return .hand(index: i, count: hand)
        case (.levelButton, _): return .levelButton
        case (.rollButton, _): return .rollButton
        case (.freezeButton, _): return .freezeButton
        default: return nil
        }
    }
}

enum AdvisorStyle {
    static func color(rank: Int) -> Color {
        switch rank {
        case 1: Color(red: 0.35, green: 0.85, blue: 1.0)
        case 2: Color(red: 0.62, green: 0.78, blue: 1.0)
        default: Color(white: 0.82)
        }
    }

    static func color(_ confidence: AdvisorConfidence) -> Color {
        switch confidence {
        case .high: .green
        case .medium: .yellow
        case .low: .secondary
        }
    }

    static func label(_ confidence: AdvisorConfidence) -> String {
        switch confidence {
        case .high: "High"
        case .medium: "Med"
        case .low: "Low"
        }
    }
}

/// The ranked list: up to three rows (rank, action, one-line reason, confidence) above a header
/// strip with the status and the collapse toggle. Sizes from `AdvisorMetrics`.
struct AdvisorPanel: View {
    let advice: AdviceView
    let collapsed: Bool
    let name: (String) -> String
    let scale: CGFloat
    var metrics = AdvisorMetrics()
    let toggle: () -> Void

    var body: some View {
        let m = metrics, s = scale
        VStack(alignment: .leading, spacing: m.rowSpacing * s) {
            if !collapsed {
                ForEach(advice.advice.suggestions, id: \.rank) { suggestion in
                    row(suggestion)
                }
                if let note = advice.advice.note, advice.advice.status != .noData {
                    Text(note)
                        .font(.system(size: m.reasonFontSize * s))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Divider().opacity(0.5)
            }
            header
        }
        .padding(.horizontal, m.padding.width * s)
        .padding(.vertical, m.padding.height * s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HUDMaterial(cornerRadius: m.cornerRadius * s))
        .overlay(
            RoundedRectangle(cornerRadius: m.cornerRadius * s, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .opacity(advice.isUpdating ? 0.6 : 1)
        .animation(.easeOut(duration: 0.15), value: advice.isUpdating)
        .frame(maxHeight: .infinity, alignment: .bottom)
    }

    private var header: some View {
        let m = metrics, s = scale
        return Button(action: toggle) {
            HStack(spacing: m.badgeSpacing * s) {
                Image(systemName: "lightbulb")
                    .foregroundStyle(.yellow.opacity(0.85))
                Text(headerText)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Image(systemName: collapsed ? "chevron.up" : "chevron.down")
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: m.headerFontSize * s, weight: .semibold))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(collapsed ? "Show the advisor's suggestions" : "Hide the advisor's suggestions")
    }

    private var headerText: String {
        if advice.failure != nil { return "Advisor unavailable" }
        switch advice.advice.status {
        case .thinking: return "Advisor: thinking…"
        case .noData: return "Advisor: no data yet"
        case .noStrongRecommendation: return "No strong recommendation"
        case .recommendation:
            guard let top = advice.advice.suggestions.first else { return "Advisor" }
            return collapsed ? "1. \(top.action.title(name: name))" : "Advisor"
        }
    }

    private func row(_ suggestion: AdvisorSuggestion) -> some View {
        let m = metrics, s = scale
        return HStack(alignment: .top, spacing: m.badgeSpacing * s) {
            Text("\(suggestion.rank)")
                .font(.system(size: m.rankFontSize * s, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(.black.opacity(0.85))
                .frame(width: m.rankDiameter * s, height: m.rankDiameter * s)
                .background(AdvisorStyle.color(rank: suggestion.rank), in: Circle())
            VStack(alignment: .leading, spacing: m.lineSpacing * s) {
                HStack(spacing: 3 * s) {
                    Text(suggestion.action.title(name: name))
                        .font(.system(size: m.titleFontSize * s, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 0)
                    Text(AdvisorStyle.label(suggestion.confidence))
                        .font(.system(size: m.reasonFontSize * s, weight: .semibold))
                        .fixedSize()
                        .layoutPriority(1)
                        .foregroundStyle(AdvisorStyle.color(suggestion.confidence))
                        .help("Confidence: \(suggestion.confidence.rawValue)")
                }
                Text(suggestion.reason)
                    .font(.system(size: m.reasonFontSize * s))
                    .foregroundStyle(.secondary)
                    .lineLimit(m.reasonLines)
                    .truncationMode(.tail)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .monospacedDigit()
        .help(suggestion.reason)
    }
}
