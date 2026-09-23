import OverlayLayout
import SwiftUI
import TavernEngine

extension OverlayModel {
    /// The hero pick while the player is choosing: the plates show until the pick is confirmed.
    var heroPick: HeroPickView? {
        guard view.status == .inGame, let game = view.game, game.phase == .heroPick,
              let pick = game.heroPick, pick.chosenCardID == nil, !pick.offers.isEmpty
        else { return nil }
        return pick
    }

    /// The plate at a content-local point, or nil when the plates aren't up.
    func heroPickPlate(at point: CGPoint) -> Int? {
        guard let layout, let pick = heroPick else { return nil }
        return layout.heroPickPlate(at: point, count: pick.offers.count)
    }
}

/// A stats plate over each offered hero, and the hovered hero's placement chart.
struct HeroPickOverlays: View {
    let pick: HeroPickView
    let layout: OverlayLayout
    let hovered: Int?
    let cards: CardDB?

    var body: some View {
        let count = pick.offers.count
        ZStack(alignment: .topLeading) {
            ForEach(Array(pick.offers.enumerated()), id: \.offset) { index, offer in
                let plate = layout.heroPickPlate(index, of: count)
                HeroPickPlate(offer: offer, isStale: pick.isStale, scale: layout.referenceScale, metrics: layout.constants.heroPick)
                    .frame(width: plate.width, height: plate.height)
                    .offset(x: plate.minX, y: plate.minY)
            }
            if let hovered, pick.offers.indices.contains(hovered), let stats = pick.offers[hovered].stats {
                let chart = layout.heroPickChart(hovered, of: count)
                PlacementChart(
                    offer: pick.offers[hovered], stats: stats, pick: pick, name: name(pick.offers[hovered]),
                    scale: layout.referenceScale, metrics: layout.constants.heroPick
                )
                .frame(width: chart.width, height: chart.height)
                .offset(x: chart.minX, y: chart.minY)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func name(_ offer: HeroOfferView) -> String {
        offer.name ?? cards?.name(of: offer.cardID) ?? cards?.name(of: offer.baseCardID) ?? offer.baseCardID
    }
}

/// Tier letter, average placement (tribe-adjusted), then top-4 % and win %.
struct HeroPickPlate: View {
    let offer: HeroOfferView
    let isStale: Bool
    let scale: CGFloat
    var metrics = HeroPickMetrics()

    var body: some View {
        let m = metrics
        VStack(alignment: .leading, spacing: m.rowSpacing * scale) {
            if let stats = offer.stats {
                HStack(spacing: m.itemSpacing * scale) {
                    Text(stats.tier.rawValue)
                        .font(.system(size: m.tierFontSize * scale, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.85))
                        .frame(width: m.tierBadgeSize * scale, height: m.tierBadgeSize * scale)
                        .background(Self.tierColor(stats.tier), in: RoundedRectangle(cornerRadius: 4 * scale, style: .continuous))
                    Text(stats.averagePlacement.formatted(.number.precision(.fractionLength(2))))
                        .font(.system(size: m.averageFontSize * scale, weight: .bold))
                    Text("avg place")
                        .font(.system(size: m.captionFontSize * scale))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    marks
                }
                Text("Top 4 \(Self.percent(stats.top4Percent))  ·  Win \(Self.percent(stats.winPercent))")
                    .font(.system(size: m.detailFontSize * scale, weight: .medium))
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: m.itemSpacing * scale) {
                    Text("No stats for this hero")
                        .font(.system(size: m.detailFontSize * scale, weight: .medium))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    marks
                }
                .frame(maxHeight: .infinity)
            }
        }
        .lineLimit(1)
        .monospacedDigit()
        .padding(.horizontal, m.padding.width * scale)
        .padding(.vertical, m.padding.height * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(HUDMaterial(cornerRadius: m.cornerRadius * scale))
        .overlay(
            RoundedRectangle(cornerRadius: m.cornerRadius * scale, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
        .opacity(offer.isLocked ? 0.6 : 1)
    }

    @ViewBuilder private var marks: some View {
        let size = metrics.captionFontSize * scale
        if isStale {
            Image(systemName: "clock.badge.exclamationmark")
                .font(.system(size: size))
                .foregroundStyle(.orange)
                .help("These stats are more than a day old")
        }
        if offer.isLocked {
            Image(systemName: "lock.fill")
                .font(.system(size: size))
                .foregroundStyle(.secondary)
        }
    }

    static func percent(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(1))))%"
    }

    static func tierColor(_ tier: HeroTier) -> Color {
        switch tier {
        case .S: Color(red: 1.00, green: 0.50, blue: 0.50)
        case .A: Color(red: 1.00, green: 0.75, blue: 0.50)
        case .B: Color(red: 1.00, green: 0.87, blue: 0.50)
        case .C: Color(red: 0.75, green: 0.95, blue: 0.55)
        case .D: Color(red: 0.55, green: 0.85, blue: 0.95)
        case .E: Color(red: 0.70, green: 0.70, blue: 0.80)
        }
    }
}

/// The hovered hero's placement distribution, 1st to 8th, with what the numbers rest on.
struct PlacementChart: View {
    let offer: HeroOfferView
    let stats: HeroPickStatsView
    let pick: HeroPickView
    let name: String
    let scale: CGFloat
    var metrics = HeroPickMetrics()

    var body: some View {
        let m = metrics
        let s = scale
        let top = max(stats.placements.max() ?? 0, 1)
        VStack(alignment: .leading, spacing: 4 * s) {
            Text(name)
                .font(.system(size: m.chartTitleFontSize * s, weight: .semibold))
            Text(caption)
                .font(.system(size: m.chartFontSize * s))
                .foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 3 * s) {
                ForEach(Array(stats.placements.enumerated()), id: \.offset) { index, share in
                    VStack(spacing: 2 * s) {
                        Text(share.formatted(.number.precision(.fractionLength(0))))
                            .font(.system(size: (m.chartFontSize - 1) * s))
                            .foregroundStyle(.secondary)
                        RoundedRectangle(cornerRadius: 2 * s, style: .continuous)
                            .fill(index < 4 ? Color.green.opacity(0.75) : Color.red.opacity(0.55))
                            .frame(height: max(1, CGFloat(share / top) * 70 * s))
                        Text("\(index + 1)")
                            .font(.system(size: m.chartFontSize * s, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .lineLimit(1)
        .monospacedDigit()
        .padding(.horizontal, m.padding.width * s)
        .padding(.vertical, m.padding.height * s)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HUDMaterial(cornerRadius: m.cornerRadius * s))
        .overlay(
            RoundedRectangle(cornerRadius: m.cornerRadius * s, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        )
    }

    /// Games, window and the tribe adjustment, e.g. "1,464 games · 3 days · tribes −0.18".
    private var caption: String {
        let window = switch stats.window {
        case .pastThree: "3 days"
        case .pastSeven: "7 days"
        case .lastPatch: "last patch"
        }
        var parts = ["\(stats.dataPoints.formatted()) games", window]
        if pick.tribeAdjustment != .none, stats.tribeModifier != 0 {
            let sign = stats.tribeModifier > 0 ? "+" : "−"
            let value = abs(stats.tribeModifier).formatted(.number.precision(.fractionLength(2)))
            parts.append("tribes \(sign)\(value)\(pick.tribeAdjustment == .estimated ? "?" : "")")
        }
        if pick.isStale { parts.append("stale") }
        return parts.joined(separator: " · ")
    }
}
