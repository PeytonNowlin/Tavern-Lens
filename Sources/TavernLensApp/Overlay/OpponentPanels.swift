import OverlayLayout
import SwiftUI
import TavernEngine

/// The leaderboard's opponent info: the next opponent's highlight and board preview, and the
/// panel for the hovered portrait. None of it takes the mouse, so it never blocks a click.
struct OpponentOverlays: View {
    let model: OverlayModel
    let game: GameView
    let layout: OverlayLayout
    let cards: CardDB?

    var body: some View {
        let scale = layout.panelScale
        ZStack(alignment: .topLeading) {
            if let slot = model.nextOpponentSlot {
                let art = layout.leaderboardArt(slot, isNextOpponent: true).insetBy(dx: -2 * scale, dy: -2 * scale)
                NextOpponentRing(scale: scale)
                    .frame(width: art.width, height: art.height)
                    .offset(x: art.minX, y: art.minY)
            }
            if game.phase == .recruit, let next = game.nextOpponent, !next.isLocal {
                let rect = layout.nextOpponentPreview
                NextOpponentPreview(entry: next, currentTurn: game.bgTurn, cards: cards, scale: scale,
                                    odds: model.shownOddsPreview, oddsMetrics: layout.constants.oddsPreview)
                    .frame(width: rect.width, height: rect.height, alignment: .top)
                    .offset(x: rect.minX, y: rect.minY)
            }
            if let entry = model.hoveredOpponent {
                let rect = layout.opponentPanel
                OpponentPanel(
                    entry: entry, isNext: entry.playerID == game.nextOpponentPlayerID,
                    currentTurn: game.bgTurn, cards: cards, scale: scale
                )
                .frame(width: rect.width, height: rect.height, alignment: .top)
                .offset(x: rect.minX, y: rect.minY)
            }
        }
        .allowsHitTesting(false)
    }
}

/// Marks the next opponent's portrait on Hearthstone's leaderboard.
struct NextOpponentRing: View {
    let scale: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
            .strokeBorder(Palette.next, lineWidth: 2 * scale)
            .shadow(color: Palette.next.opacity(0.7), radius: 5 * scale)
    }
}

/// The hovered opponent: hero, name, tier, triples, health, and their last-seen board.
struct OpponentPanel: View {
    let entry: LobbyEntryView
    let isNext: Bool
    let currentTurn: Int
    let cards: CardDB?
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            HStack(alignment: .firstTextBaseline, spacing: 8 * scale) {
                Text(OpponentText.heroName(entry, cards: cards))
                    .font(.system(size: 15 * scale, weight: .semibold))
                if let name = entry.displayName {
                    Text(name)
                        .font(.system(size: 12 * scale))
                        .foregroundStyle(.secondary)
                }
                if isNext {
                    Tag(text: "Next opponent", color: Palette.next, scale: scale)
                }
                if entry.isDead {
                    Tag(text: entry.place.map { "Out · \(OpponentText.ordinal($0))" } ?? "Out", color: .secondary,
                        scale: scale)
                }
                Spacer(minLength: 12 * scale)
                StatLabel(symbol: "star.fill", tint: Palette.tier, text: entry.tier.map(String.init) ?? "–",
                          scale: scale)
                StatLabel(symbol: "trophy.fill", tint: Palette.triple, text: "\(entry.hero.triples)", scale: scale)
                StatLabel(symbol: "heart.fill", tint: Palette.health, text: OpponentText.health(entry), scale: scale)
            }
            .lineLimit(1)

            if let board = entry.lastSeenBoard {
                HStack(spacing: 6 * scale) {
                    Text(OpponentText.seen(board, currentTurn: currentTurn))
                        .font(.system(size: 11 * scale, weight: .medium))
                        .foregroundStyle(.secondary)
                    if let seenHero = board.heroCardID, seenHero != entry.heroCardID {
                        Text("as \(cards?.name(of: seenHero) ?? seenHero)")
                            .font(.system(size: 11 * scale))
                            .foregroundStyle(.tertiary)
                    }
                    if let likely = board.likelyBuild {
                        Text("Likely build: \(likely.name)")
                            .font(.system(size: 11 * scale, weight: .semibold))
                            .foregroundStyle(Palette.build)
                    }
                }
                if board.cards.isEmpty {
                    Placeholder(text: "Empty board", scale: scale)
                } else {
                    HStack(spacing: 6 * scale) {
                        ForEach(Array(board.cards.enumerated()), id: \.offset) { _, card in
                            MinionTile(card: card, cards: cards, scale: scale)
                        }
                    }
                }
            } else {
                Placeholder(text: "Not seen: you haven't fought them yet", scale: scale)
            }
        }
        .monospacedDigit()
        .padding(.horizontal, 12 * scale)
        .padding(.vertical, 10 * scale)
        .fixedSize()
        .panelBackground(scale: scale)
    }
}

/// One minion of a last-seen board: tier, combat keywords, name, attack and health.
struct MinionTile: View {
    let card: CardView
    let cards: CardDB?
    let scale: CGFloat

    var body: some View {
        VStack(spacing: 3 * scale) {
            HStack(spacing: 2 * scale) {
                if let tier = card.tier {
                    Text("\(tier)")
                        .font(.system(size: 9.5 * scale, weight: .bold))
                        .foregroundStyle(Palette.tier)
                }
                Spacer(minLength: 0)
                ForEach(KeywordBadge.shown(card.keywords), id: \.self) { keyword in
                    Image(systemName: KeywordBadge.symbol(keyword))
                        .font(.system(size: 8.5 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            Text(OpponentText.cardName(card, cards: cards))
                .font(.system(size: 10.5 * scale, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(card.attack.map(String.init) ?? "–").foregroundStyle(Palette.attack)
                Spacer(minLength: 0)
                Text(card.health.map(String.init) ?? "–").foregroundStyle(Palette.health)
            }
            .font(.system(size: 15 * scale, weight: .bold))
        }
        .padding(.horizontal, 6 * scale)
        .padding(.vertical, 5 * scale)
        .frame(width: 92 * scale, height: 88 * scale)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 7 * scale, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7 * scale, style: .continuous)
                .strokeBorder(card.golden ? Palette.golden : .white.opacity(0.1), lineWidth: card.golden ? 1.5 : 0.5)
        )
    }
}

/// The next opponent, compact: hero, tier, health, their last-seen board as a list, and the live
/// odds of the board as it is now against it.
struct NextOpponentPreview: View {
    let entry: LobbyEntryView
    let currentTurn: Int
    let cards: CardDB?
    let scale: CGFloat
    /// The recruit-phase odds preview for this opponent; nil until the first request reaches it.
    var odds: OddsPreviewView?
    var oddsMetrics = OddsPreviewMetrics()

    var body: some View {
        VStack(alignment: .leading, spacing: 4 * scale) {
            Text("Next opponent")
                .font(.system(size: 9.5 * scale, weight: .semibold))
                .foregroundStyle(Palette.next)
            Text(OpponentText.heroName(entry, cards: cards))
                .font(.system(size: 12.5 * scale, weight: .semibold))
            HStack(spacing: 8 * scale) {
                StatLabel(symbol: "star.fill", tint: Palette.tier, text: entry.tier.map(String.init) ?? "–",
                          scale: scale * 0.85)
                StatLabel(symbol: "heart.fill", tint: Palette.health, text: OpponentText.health(entry),
                          scale: scale * 0.85)
                if entry.hero.triples > 0 {
                    StatLabel(symbol: "trophy.fill", tint: Palette.triple, text: "\(entry.hero.triples)",
                              scale: scale * 0.85)
                }
            }
            Divider().opacity(0.5)
            if let board = entry.lastSeenBoard {
                Text(OpponentText.seen(board, currentTurn: currentTurn))
                    .font(.system(size: 9.5 * scale))
                    .foregroundStyle(.secondary)
                if let likely = board.likelyBuild {
                    Text(likely.name)
                        .font(.system(size: 9.5 * scale, weight: .semibold))
                        .foregroundStyle(Palette.build)
                }
                if board.cards.isEmpty {
                    Text("Empty board").font(.system(size: 10.5 * scale)).foregroundStyle(.secondary)
                }
                ForEach(Array(board.cards.enumerated()), id: \.offset) { _, card in
                    HStack(spacing: 4 * scale) {
                        Text(OpponentText.cardName(card, cards: cards))
                            .foregroundStyle(card.golden ? Palette.golden : .primary)
                            .truncationMode(.tail)
                        Spacer(minLength: 2 * scale)
                        Text(OpponentText.stats(card)).foregroundStyle(.secondary)
                    }
                    .font(.system(size: 10.5 * scale))
                }
            } else {
                Text("Not seen yet")
                    .font(.system(size: 10.5 * scale, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Divider().opacity(0.5)
            PreviewOdds(odds: odds, seen: entry.lastSeenBoard != nil, scale: scale, metrics: oddsMetrics)
        }
        .lineLimit(1)
        .monospacedDigit()
        .padding(.horizontal, 9 * scale)
        .padding(.vertical, 7 * scale)
        .frame(maxWidth: .infinity, alignment: .leading)
        .panelBackground(scale: scale)
    }
}

// MARK: - Pieces

/// Colour only where it carries meaning: the next fight, stats in Hearthstone's own colours, golden.
private enum Palette {
    static let next = Color.orange
    static let tier = Color.yellow.opacity(0.85)
    static let triple = Color(red: 0.95, green: 0.78, blue: 0.35)
    static let golden = Color(red: 1.0, green: 0.8, blue: 0.3)
    static let attack = Color(red: 1.0, green: 0.85, blue: 0.45)
    static let health = Color(red: 1.0, green: 0.45, blue: 0.42)
    static let build = Color(red: 0.35, green: 0.85, blue: 0.85)
}

private struct StatLabel: View {
    let symbol: String
    let tint: Color
    let text: String
    let scale: CGFloat

    var body: some View {
        HStack(spacing: 3 * scale) {
            Image(systemName: symbol)
                .font(.system(size: 10 * scale))
                .foregroundStyle(tint)
            Text(text).font(.system(size: 13 * scale, weight: .semibold))
        }
    }
}

private struct Tag: View {
    let text: String
    let color: Color
    let scale: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 9.5 * scale, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5 * scale)
            .padding(.vertical, 1.5 * scale)
            .background(color.opacity(0.18), in: Capsule())
    }
}

private struct Placeholder: View {
    let text: String
    let scale: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: 12 * scale, weight: .medium))
            .foregroundStyle(.secondary)
            .frame(minWidth: 320 * scale, alignment: .leading)
            .padding(.vertical, 4 * scale)
    }
}

private enum KeywordBadge {
    /// The keywords that change a combat, in a fixed order.
    static let combat: [BGKeyword] = [.taunt, .divineShield, .reborn, .poisonous, .venomous, .windfury,
                                      .megaWindfury, .stealth]

    static func shown(_ keywords: [BGKeyword]) -> [BGKeyword] { combat.filter(keywords.contains) }

    static func symbol(_ keyword: BGKeyword) -> String {
        switch keyword {
        case .taunt: "shield.fill"
        case .divineShield: "sun.max.fill"
        case .reborn: "arrow.counterclockwise"
        case .poisonous, .venomous: "drop.fill"
        case .windfury, .megaWindfury: "wind"
        case .stealth: "eye.slash.fill"
        default: "circle.fill"
        }
    }
}

enum OpponentText {
    static func heroName(_ entry: LobbyEntryView, cards: CardDB?) -> String {
        entry.heroName ?? cards?.name(of: entry.heroCardID) ?? entry.heroCardID
    }

    /// The live engine may run without card data, so fall back to the app's card DB.
    static func cardName(_ card: CardView, cards: CardDB?) -> String {
        card.name ?? cards?.name(of: card.cardID) ?? card.cardID
    }

    static func health(_ entry: LobbyEntryView) -> String {
        entry.isDead ? "0" : "\(entry.hero.hp)"
    }

    static func stats(_ card: CardView) -> String {
        guard let attack = card.attack, let health = card.health else { return "" }
        return "\(attack)/\(health)"
    }

    static func seen(_ board: LastSeenBoardView, currentTurn: Int) -> String {
        let ago = currentTurn - board.bgTurn
        let when = switch ago {
        case ...0: "this turn"
        case 1: "last turn"
        default: "\(ago) turns ago"
        }
        return "Seen turn \(board.bgTurn) (\(when))"
    }

    static func ordinal(_ n: Int) -> String {
        let suffix = switch (n % 10, n % 100) {
        case (_, 11...13): "th"
        case (1, _): "st"
        case (2, _): "nd"
        case (3, _): "rd"
        default: "th"
        }
        return "\(n)\(suffix)"
    }
}

private extension View {
    /// The overlay's dark translucent panel look, shared with the status HUD.
    func panelBackground(scale: CGFloat) -> some View {
        background(HUDMaterial(cornerRadius: 10 * scale))
            .overlay(
                RoundedRectangle(cornerRadius: 10 * scale, style: .continuous)
                    .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
            )
    }
}
