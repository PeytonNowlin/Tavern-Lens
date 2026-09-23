import Observation
import OverlayLayout
import SwiftUI
import TavernEngine

/// What the overlay draws. Owned by `OverlayController`, which keeps it in step with
/// Hearthstone's window and the live view state.
@MainActor
@Observable
final class OverlayModel {
    var layout: OverlayLayout?
    var view: ViewState = .noGame
    var showsLayoutGuides = false
    @ObservationIgnored var hide: () -> Void = {}

    /// The status HUD shows during a solo Battlegrounds game and on its game-over screen.
    var game: GameView? {
        switch view.status {
        case .inGame, .gameOver: view.game
        case .noGame: nil
        }
    }

    /// Where the cursor makes the panel take clicks, in content-local top-left points.
    var interactiveRegions: [CGRect] {
        guard let layout, game != nil else { return [] }
        return [layout.hud]
    }
}

struct OverlayRootView: View {
    let model: OverlayModel

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if let layout = model.layout {
                if model.showsLayoutGuides {
                    LayoutGuides(layout: layout)
                }
                if let game = model.game {
                    StatusHUD(game: game, isOver: model.view.status == .gameOver, scale: layout.panelScale,
                              hide: model.hide)
                        .frame(width: layout.hud.width, height: layout.hud.height)
                        .offset(x: layout.hud.minX, y: layout.hud.minY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .environment(\.colorScheme, .dark)
    }
}

/// Turn, phase, tavern tier and gold, in a small dark translucent panel.
struct StatusHUD: View {
    let game: GameView
    let isOver: Bool
    let scale: CGFloat
    let hide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5 * scale) {
            HStack(spacing: 6 * scale) {
                Text(turnText)
                    .font(.system(size: 13 * scale, weight: .semibold))
                if let phaseText {
                    Text(phaseText)
                        .font(.system(size: 9.5 * scale, weight: .semibold))
                        .foregroundStyle(phaseColor)
                        .padding(.horizontal, 5 * scale)
                        .padding(.vertical, 1.5 * scale)
                        .background(phaseColor.opacity(0.18), in: Capsule())
                }
            }
            .lineLimit(1)
            HStack(spacing: 12 * scale) {
                Label {
                    Text(tierText)
                } icon: {
                    Image(systemName: "star.fill").foregroundStyle(.yellow.opacity(0.85))
                }
                .help("Tavern tier")
                Label {
                    Text(goldText)
                } icon: {
                    Image(systemName: "circle.circle.fill").foregroundStyle(.orange.opacity(0.9))
                }
                .help("Gold")
                Spacer(minLength: 0)
                Button(action: hide) {
                    Image(systemName: "eye.slash")
                        .font(.system(size: 10 * scale, weight: .medium))
                        .foregroundStyle(.secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Hide the overlay (⌃⌥H)")
            }
            .labelStyle(CompactLabelStyle(spacing: 4 * scale, iconSize: 10 * scale))
            .font(.system(size: 12.5 * scale, weight: .medium))
        }
        .monospacedDigit()
        .foregroundStyle(.primary)
        .padding(.horizontal, 10 * scale)
        .padding(.vertical, 7 * scale)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(HUDMaterial(cornerRadius: 10 * scale))
        .overlay(
            RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var turnText: String { game.bgTurn > 0 ? "Turn \(game.bgTurn)" : "Hero pick" }

    /// Nil at the hero pick, which the turn text already says.
    private var phaseText: String? {
        if isOver { return "Game over" }
        return switch game.phase {
        case .heroPick: nil
        case .recruit: "Recruit"
        case .combat: "Combat"
        }
    }

    private var phaseColor: Color {
        if isOver { return .secondary }
        return switch game.phase {
        case .heroPick: .purple
        case .recruit: .green
        case .combat: .red
        }
    }

    private var tierText: String { game.player?.tier.map(String.init) ?? "–" }

    private var goldText: String {
        guard let gold = game.player?.gold, game.bgTurn > 0 else { return "–" }
        return "\(gold.available)/\(gold.thisTurn)"
    }
}

private struct CompactLabelStyle: LabelStyle {
    var spacing: CGFloat
    var iconSize: CGFloat
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: spacing) {
            configuration.icon.font(.system(size: iconSize))
            configuration.title
        }
    }
}

/// Outlines every rect the layout knows, for checking alignment against the game.
struct LayoutGuides: View {
    let layout: OverlayLayout

    var body: some View {
        Canvas { context, _ in
            func stroke(_ rect: CGRect, _ color: Color, dash: Bool = false) {
                context.stroke(Path(roundedRect: rect, cornerRadius: 2), with: .color(color),
                               style: StrokeStyle(lineWidth: 1, dash: dash ? [4, 3] : []))
            }
            stroke(layout.boardRegion, .white.opacity(0.35), dash: true)
            for i in 0..<layout.constants.leaderboardSlots { stroke(layout.leaderboardSlot(i), .cyan) }
            for k in 0..<7 {
                stroke(layout.boardSlot(.top, index: k, of: 7), .orange)
                stroke(layout.boardSlot(.player, index: k, of: 7), .green)
            }
            for element in HSElement.allCases { stroke(layout.rect(element), .pink) }
            for i in 0..<10 { stroke(layout.goldCoin(i), .yellow) }
            stroke(layout.hud, .white)
        }
        .allowsHitTesting(false)
    }
}
