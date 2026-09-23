import OverlayLayout
import SwiftUI
import TavernEngine

/// The lobby's tribes in a small panel under the HUD: a lobby's worth of the most likely
/// tribes, each with a confidence dot, and the percentage while it isn't settled. Its type
/// and spacing come from `TribesPanelMetrics`, which the layout tests check against its size.
struct TribesPanel: View {
    let tribes: TribesView
    let scale: CGFloat
    var metrics = TribesPanelMetrics()

    var body: some View {
        let m = metrics
        VStack(alignment: .leading, spacing: m.titleSpacing * scale) {
            HStack(spacing: m.percentSpacing * scale) {
                Text("Tribes")
                    .font(.system(size: m.titleFontSize * scale, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                status
            }
            .lineLimit(1)
            VStack(alignment: .leading, spacing: m.rowSpacing * scale) {
                ForEach(tribes.tribes.prefix(m.rows), id: \.tribe) { tribe in
                    row(tribe)
                }
            }
        }
        .monospacedDigit()
        .padding(.horizontal, m.padding.width * scale)
        .padding(.vertical, m.padding.height * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(HUDMaterial(cornerRadius: m.cornerRadius * scale))
        .overlay(
            RoundedRectangle(cornerRadius: m.cornerRadius * scale, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .help(helpText)
    }

    @ViewBuilder private var status: some View {
        let size = metrics.titleFontSize * scale
        if tribes.screenConflict {
            Text("screen ≠ log").font(.system(size: size)).foregroundStyle(.orange)
        } else if tribes.isUncertain {
            Text("uncertain").font(.system(size: size)).foregroundStyle(.orange)
        } else if tribes.isResolved {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size))
                .foregroundStyle(.green.opacity(0.85))
        } else {
            let sure = tribes.tribes.filter { $0.confidence == .confirmed }.count
            Text("\(sure) of \(tribes.tribes.prefix(metrics.rows).count) sure")
                .font(.system(size: size))
                .foregroundStyle(.secondary)
        }
    }

    private func row(_ tribe: TribeView) -> some View {
        let m = metrics
        return HStack(spacing: m.dotSpacing * scale) {
            Image(systemName: dotSymbol(tribe.confidence))
                .font(.system(size: m.dotSize * scale, weight: .bold))
                .foregroundStyle(dotColor(tribe))
                .frame(width: m.dotSize * scale)
            Text(tribe.name)
                .font(.system(size: m.rowFontSize * scale, weight: .medium))
                .foregroundStyle(tribe.confidence == .confirmed ? .primary : .secondary)
            Spacer(minLength: m.percentSpacing * scale)
            if tribe.confidence != .confirmed {
                Text("\(tribe.percent)%")
                    .font(.system(size: m.percentFontSize * scale))
                    .foregroundStyle(.tertiary)
            }
        }
        .lineLimit(1)
    }

    private func dotSymbol(_ confidence: TribeConfidence) -> String {
        switch confidence {
        case .confirmed: "circle.fill"
        case .likely: "circle.lefthalf.filled"
        case .unlikely, .absent: "circle"
        }
    }

    private func dotColor(_ tribe: TribeView) -> Color {
        if tribe.isForced { return .purple.opacity(0.9) }
        return switch tribe.confidence {
        case .confirmed: .green.opacity(0.85)
        case .likely: .yellow.opacity(0.85)
        case .unlikely, .absent: .secondary
        }
    }

    private var helpText: String {
        var lines = [tribes.isResolved ? "The lobby's tribes" : "The lobby's tribes, inferred from what has shown up so far"]
        if tribes.tribes.contains(where: \.isForced) { lines.append("Purple: in every lobby this patch") }
        if tribes.source != .inferred { lines.append("Read from the hero-pick banner") }
        if tribes.poolIsStale { lines.append("Minion pool data is out of date") }
        return lines.joined(separator: "\n")
    }
}
