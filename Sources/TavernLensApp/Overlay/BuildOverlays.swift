import OverlayLayout
import SwiftUI
import TavernEngine

/// The build overlays of a recruit phase: shop highlights and the tips panel. None of it
/// takes the mouse.
struct BuildOverlays: View {
    let builds: BuildsView
    let shopCount: Int
    let layout: OverlayLayout
    let cards: CardDB?

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !builds.shopHighlights.isEmpty {
                ShopHighlights(highlights: builds.shopHighlights, shopCount: shopCount, layout: layout)
            }
            if !builds.detected.isEmpty {
                let rect = layout.buildTipsPanel
                BuildTipsPanel(
                    builds: builds, cards: cards, scale: layout.panelScale,
                    metrics: layout.constants.buildOverlay
                )
                .frame(width: rect.width, height: rect.height, alignment: .top)
                .offset(x: rect.minX, y: rect.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Rings on the shop cards that fit the detected builds: solid gold for a core card, a
/// thinner dashed teal for an add-on, each with a small "Core" / "Add-on" badge on the
/// card's bottom edge. Placed with `OverlayLayout.shopHighlight(_:of:)`; never takes the mouse.
struct ShopHighlights: View {
    let highlights: [ShopHighlightView]
    let shopCount: Int
    let layout: OverlayLayout

    var body: some View {
        let m = layout.constants.buildOverlay
        let h = layout.height
        ZStack(alignment: .topLeading) {
            ForEach(highlights, id: \.index) { highlight in
                let ring = layout.shopHighlight(highlight.index, of: shopCount)
                let badge = layout.shopHighlightBadge(highlight.index, of: shopCount)
                let style = BuildStyle(highlight.role)
                RoundedRectangle(cornerRadius: m.highlightCornerRadius * h, style: .continuous)
                    .strokeBorder(
                        style.color,
                        style: StrokeStyle(
                            lineWidth: m.highlightLineWidth * h * style.lineScale,
                            dash: style.dashed ? [0.012 * h, 0.006 * h] : []
                        )
                    )
                    .shadow(color: style.color.opacity(0.6), radius: 0.006 * h)
                    .frame(width: ring.width, height: ring.height)
                    .offset(x: ring.minX, y: ring.minY)
                Text(style.label)
                    .font(.system(size: badge.height * 0.62, weight: .bold))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: badge.width, height: badge.height)
                    .background(style.color, in: Capsule())
                    .offset(x: badge.minX, y: badge.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// How a highlight role looks, shared by the rings and the tips panel's legend.
struct BuildStyle {
    let color: Color
    let label: String
    let dashed: Bool
    let lineScale: CGFloat

    init(_ role: ShopCardRole) {
        switch role {
        case .core:
            color = Color(red: 1.0, green: 0.78, blue: 0.25)
            label = "Core"
            dashed = false
            lineScale = 1
        case .addon:
            color = Color(red: 0.35, green: 0.85, blue: 0.85)
            label = "Add-on"
            dashed = true
            lineScale = 0.75
        }
    }
}

/// The detected builds' tips cards, stacked: the build's name and grade, its core cards
/// (the ones the player has ticked), when to commit, and a tip. Sizes come from
/// `BuildOverlayMetrics`, which the layout tests check against the panel.
struct BuildTipsPanel: View {
    let builds: BuildsView
    let cards: CardDB?
    let scale: CGFloat
    var metrics = BuildOverlayMetrics()

    var body: some View {
        let m = metrics
        VStack(alignment: .leading, spacing: m.cardSpacing * scale) {
            ForEach(Array(builds.detected.prefix(m.cards).enumerated()), id: \.element.id) { index, build in
                if index > 0 { Divider().opacity(0.5) }
                card(build)
            }
        }
        .padding(.horizontal, m.padding.width * scale)
        .padding(.vertical, m.padding.height * scale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(HUDMaterial(cornerRadius: m.cornerRadius * scale))
        .overlay(
            RoundedRectangle(cornerRadius: m.cornerRadius * scale, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func card(_ build: DetectedBuildView) -> some View {
        let m = metrics
        let body = Font.system(size: m.bodyFontSize * scale)
        return VStack(alignment: .leading, spacing: m.partSpacing * scale) {
            HStack(spacing: 4 * scale) {
                Text(build.name)
                    .font(.system(size: m.titleFontSize * scale, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
                Text(grade(build))
                    .font(.system(size: m.bodyFontSize * scale * 0.9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            coreLine(build)
                .font(body)
                .lineLimit(m.coreLines)
            if let commit = build.tips.whenToCommit {
                Text("\(Text("Commit: ").foregroundStyle(.secondary))\(commit)")
                    .font(body)
                    .lineLimit(m.commitLines)
            } else if !build.coreMissing.isEmpty {
                Text("\(Text("Needs: ").foregroundStyle(.secondary))\(names(build.coreMissing))")
                    .font(body)
                    .lineLimit(m.commitLines)
            }
            if let tip = build.tips.tip {
                Text(tip)
                    .font(body)
                    .foregroundStyle(.secondary)
                    .lineLimit(m.tipLines)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "Core: ✓Tasty Lobster, ✓Titus, Deathstrider …": the ones the player has first, ticked.
    private func coreLine(_ build: DetectedBuildView) -> Text {
        let have = build.coreHave.map { "✓" + name($0) }
        let missing = build.coreMissing.map(name)
        let label = Text("Core: ").foregroundStyle(BuildStyle(.core).color)
        return Text("\(label)\((have + missing).joined(separator: ", "))")
    }

    /// Firestone's power level and difficulty, or that the build is our own hypothesis.
    private func grade(_ build: DetectedBuildView) -> String {
        if build.source == .overrides { return "new" }
        return [build.tips.powerLevel, build.tips.difficulty].compactMap { $0 }.joined(separator: " · ")
    }

    private func names(_ ids: [String]) -> String { ids.map(name).joined(separator: ", ") }

    private func name(_ cardID: String) -> String { cards?.name(of: cardID) ?? cardID }
}
