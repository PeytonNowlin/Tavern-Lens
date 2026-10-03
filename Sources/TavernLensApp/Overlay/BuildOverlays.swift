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
    var showsTips = true
    var density: OverlayDensity = .compact

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !builds.shopHighlights.isEmpty {
                ShopHighlights(highlights: builds.shopHighlights, shopCount: shopCount, layout: layout)
            }
            if showsTips, !builds.detected.isEmpty {
                let rect = layout.buildTipsPanel
                BuildTipsPanel(
                    builds: builds, cards: cards, scale: layout.panelScale,
                    metrics: layout.constants.buildOverlay, density: density
                )
                .frame(width: rect.width, height: rect.height, alignment: .top)
                .offset(x: rect.minX, y: rect.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Quiet compatibility rings on shop cards: gold for a core card, dashed lavender for
/// an add-on, each with a "Core fit" / "Fits" badge on the card's bottom edge.
/// Placed with `OverlayLayout.shopHighlight(_:of:)`; never takes the mouse.
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
                let badgeWidth = max(m.badgeMinSize.width, badge.width)
                let badgeHeight = max(m.badgeMinSize.height, badge.height)
                RoundedRectangle(cornerRadius: m.highlightCornerRadius * h, style: .continuous)
                    .strokeBorder(
                        style.color.opacity(m.highlightOpacity),
                        style: StrokeStyle(
                            lineWidth: m.highlightLineWidth * h * style.lineScale * m.highlightLineShare,
                            dash: style.dashed ? m.highlightDash.map { $0 * h } : []
                        )
                    )
                    .frame(width: ring.width, height: ring.height)
                    .offset(x: ring.minX, y: ring.minY)
                Text(style.label)
                    .font(.system(size: max(m.badgeMinFontSize, badge.height * m.badgeFontShare), weight: .semibold))
                    .foregroundStyle(style.color)
                    .frame(width: badgeWidth, height: badgeHeight)
                    .background(.black.opacity(0.9), in: Capsule())
                    .offset(x: badge.midX - badgeWidth / 2, y: badge.midY - badgeHeight / 2)
            }
        }
        .allowsHitTesting(false)
    }
}

/// How a compatibility highlight's role looks.
struct BuildStyle {
    let color: Color
    let label: String
    let dashed: Bool
    let lineScale: CGFloat

    init(_ role: ShopCardRole) {
        switch role {
        case .core:
            color = Color(OverlayPalette.buildCore)
            label = "Core fit"
            dashed = false
            lineScale = 1
        case .addon:
            color = Color(OverlayPalette.buildAddon)
            label = "Fits"
            dashed = true
            lineScale = 0.75
        }
    }
}

/// A brief description of the player's existing pieces. Full guidance lives in advisor
/// details; this fixed space prioritizes readable text over the number of builds shown.
struct BuildTipsPanel: View {
    let builds: BuildsView
    let cards: CardDB?
    let scale: CGFloat
    var metrics = BuildOverlayMetrics()
    var density: OverlayDensity = .compact

    private var type: BuildTipsTypography { BuildTipsTypography(panelScale: scale) }

    var body: some View {
        ViewThatFits(in: .vertical) {
            if density == .comfortable {
                summary(limit: 2)
            }
            summary(limit: 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func summary(limit: Int) -> some View {
        let m = metrics
        return VStack(alignment: .leading, spacing: m.cardSpacing * scale) {
            HStack(spacing: 4) {
                Text("Current fit")
                    .font(.system(size: type.headerFontSize, weight: .semibold))
                if builds.catalogIsStale {
                    Text("· cached")
                        .font(.system(size: type.headerFontSize))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
            ForEach(Array(builds.detected.prefix(limit).enumerated()), id: \.element.id) { index, build in
                if index > 0 { Divider().opacity(0.5) }
                card(build)
            }
        }
        .padding(.horizontal, m.padding.width * scale)
        .padding(.vertical, m.padding.height * scale)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .hudPanel(cornerRadius: m.cornerRadius * scale)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func card(_ build: DetectedBuildView) -> some View {
        let m = metrics
        return VStack(alignment: .leading, spacing: m.partSpacing * scale) {
            Text(build.name)
                .font(.system(size: type.nameFontSize, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.tail)
            if build.source == .overrides {
                Text("Experimental fit")
                    .font(.system(size: type.bodyFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            coreRow("Owned", ids: build.coreHave, empty: "No core cards")
            coreRow("Missing", ids: build.coreMissing, empty: "Core complete")
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func coreRow(_ label: String, ids: [String], empty: String) -> some View {
        let text = ids.isEmpty ? empty : ids.map(name).joined(separator: ", ")
        return Text("\(Text(label + ": ").foregroundStyle(.secondary))\(text)")
            .font(.system(size: type.bodyFontSize))
            .lineLimit(1)
            .truncationMode(.tail)
    }

    private func name(_ cardID: String) -> String { cards?.name(of: cardID) ?? cardID }
}
