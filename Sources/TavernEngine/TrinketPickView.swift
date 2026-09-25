import Foundation
import BGIntel
import EntityStore
import HSData
import PowerParser

public struct TrinketOfferRating: Codable, Hashable, Sendable {
    public var entityID: Int
    public var cardID: String
    public var name: String
    public var cost: Int?
    public var rank: Int?
    public var rating: String
    public var reason: String
    public var score: Double?
    public var affordable: Bool
    public var averagePlacement: Double?
    public var sampleSize: Int?
}

public struct TrinketPickView: Codable, Hashable, Sendable {
    public var choiceID: Int
    /// Original left-to-right offer order; rank is separate from screen position.
    public var offers: [TrinketOfferRating]
    public var note: String
}

/// GENERAL choices include discovers as well as trinkets. Require every offered card to
/// actually be a trinket, wait for its display task, and clear on chosen/new choices/games.
struct TrinketPickTracker: Sendable {
    var choice: EntityChoice?
    mutating func observe(_ event: PowerEvent) {
        switch event {
        case .newGameAnnounced: choice = nil
        case .entityChoices(let c): choice = c.choiceType == "GENERAL" ? c : nil
        case .entitiesChosen(let id, _) where choice?.id == id: choice = nil
        default: break
        }
    }

    func project(store: EntityStore, cards: CardDB, game: GameView, lastTaskListEnded: Int?, stats: TrinketStats? = nil, now: Date = Date()) -> TrinketPickView? {
        guard game.phase == .recruit, let choice, !choice.options.isEmpty,
              choice.taskList.map({ (lastTaskListEnded ?? Int.min) >= $0 }) ?? true else { return nil }
        var offers: [(Int, Card, Int?)] = []
        for option in choice.options {
            let entity = store[option.entityID]
            let id = entity?.cardID.isEmpty == false ? entity!.cardID : option.cardID
            guard let card = cards[id], card.type == "BATTLEGROUND_TRINKET" else { return nil }
            offers.append((option.entityID, card, entity?.int(GameTag.id(48)) ?? card.cost))
        }
        return TrinketRater.rate(choiceID: choice.id, offers: offers, game: game, cards: cards, stats: stats, now: now)
    }
}

/// Explainable board-fit estimates. These are neither population win rates nor an optimal
/// policy. Unrecognised effects stay unrated instead of receiving an invented average score.
public enum TrinketRater {
    public static func rate(choiceID: Int, offers: [(Int, Card, Int?)], game: GameView, cards: CardDB, stats: TrinketStats? = nil, now: Date = Date()) -> TrinketPickView {
        let board = game.player?.board ?? []
        let texts = board.map { RecruitContext.plain(cards[$0.cardID]?.text ?? "").lowercased() }
        let discarders = texts.filter { $0.contains("activate (") && $0.contains("discard a card") }.count
        let endOfTurns = texts.filter { $0.contains("at the end of your turn") }.count
        let gold = game.player?.gold.available ?? 0
        let hp = game.player?.hero?.hp ?? 30
        let horizon = hp <= 10 ? 1.0 : hp <= 20 ? 2.0 : 3.0
        let stand = game.player?.mechanics?.trinkets.contains { $0.cardID == "BG30_MagicItem_888" } ?? false
        var ratings = offers.map { entity, card, cost -> TrinketOfferRating in
            let text = RecruitContext.plain(card.text ?? "")
            var value: Double?, reason = "Effect not rated yet; compare its text before choosing"
            if text == "Get a Sludge Corrosion. After you discard a card, get a Sludge Corrosion." {
                value = Double(board.count) * (1 + Double(discarders) * horizon)
                reason = discarders > 0 ? "\(discarders) discard minion(s) supply repeated board buffs" : "Immediate board buff; no discard engine yet"
            } else if text == "Your end of turn effects trigger an extra time." {
                value = Double(endOfTurns) * 4 * horizon
                reason = endOfTurns > 0 ? "Repeats \(endOfTurns) existing end-of-turn effect(s)" : "No end-of-turn engine on your board"
            } else if text.hasPrefix("At the end of your turn, give your minions +"),
                      let regex = try? NSRegularExpression(pattern: "give your minions \\+([0-9]+)/\\+([0-9]+)"),
                      let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) {
                let ns = text as NSString
                let a = Double(ns.substring(with: match.range(at: 1))) ?? 0
                let h = Double(ns.substring(with: match.range(at: 2))) ?? 0
                value = (a + h) * Double(board.count) * 0.5 * horizon
                reason = "Buffs all \(board.count) minions every turn"
            } else if text == "When you buy a Greater Trinket, this transforms into a copy of it." {
                value = hp > 20 ? 9 : 2
                reason = hp > 20 ? "Invests in a second Greater Trinket; no immediate board strength" : "Delayed payoff is risky at your current health"
            } else if text == "Get three random Tier 4 minions." {
                value = 9; reason = "Three immediate minion options; outcomes are random"
            } else if text == "Discover a Tier 4 minion of your most common type with a Dark Gift." {
                value = 8; reason = "A tailored Tier 4 minion plus a Dark Gift; choices are unknown"
            } else if text == "Get 2 random Tavern spells. When you play one, discard the other. At the start of your turn, repeat this." {
                value = 2 * horizon + Double(discarders)
                reason = "Recurring spell supply; only one of each pair can be played"
            } else if text == "Your Tavern spells give an extra +1/+1. After you cast a spell on a minion, improve for this turn only." {
                let held = game.player?.hand.filter { cards[$0.cardID]?.type == "BATTLEGROUND_SPELL" || cards[$0.cardID]?.type == "SPELL" }.count ?? 0
                value = Double(held + discarders) * horizon * 2
                reason = held + discarders > 0 ? "Supports your spell supply; needs targeted buff spells to ramp" : "Little spell supply visible on your board"
            }
            if let current = value {
                value = current * (stand && card.id != "BG30_MagicItem_888" ? 2 : 1) - Double(cost ?? 0) * 1.5
                if stand && card.id != "BG30_MagicItem_888" { reason += "; Souvenir Stand copies it" }
            }
            let hasBoardModel = value != nil
            let meta = stats?.entry(card.id, now: now)
            if let meta {
                // A modest population prior; board-specific engine payoff can outweigh it.
                let prior = max(-8, min(8, (4.5 - meta.averagePlacement) * 8))
                if let local = value { value = local + prior }
                else {
                    value = 8 + prior - Double(cost ?? 0) * 1.5
                    reason = "Population baseline only; board interaction not modelled"
                }
            }
            let affordable = cost.map { $0 <= gold } ?? false
            let rating = !affordable ? "Unavailable" : value.map { hasBoardModel ? ($0 >= 16 ? "Strong fit" : $0 >= 6 ? "Good fit" : "Weak fit") : "Meta baseline" } ?? "Unrated"
            return TrinketOfferRating(entityID: entity, cardID: card.id, name: card.name, cost: cost,
                rank: nil, rating: rating, reason: reason, score: value, affordable: affordable, averagePlacement: meta?.averagePlacement, sampleSize: meta?.dataPoints)
        }
        let order = ratings.indices.filter { ratings[$0].score != nil && ratings[$0].affordable }.sorted {
            ratings[$0].score == ratings[$1].score ? $0 < $1 : ratings[$0].score! > ratings[$1].score!
        }
        for (i, index) in order.enumerated() { ratings[index].rank = i + 1 }
        return TrinketPickView(choiceID: choiceID, offers: ratings,
            note: (stats?.usable(now: now) == true ? "Firestone · past 3 days · all ranks + board fit" : "Local board-fit estimates · no fresh population data") + " · low confidence" + (ratings.contains { $0.score == nil } ? " · some choices unrated" : ""))
    }
}
