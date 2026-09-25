import Foundation
import HSData

/// Deterministic recruit effects. Exact normalized text is the compatibility check: an unrecognised
/// effect is not silently treated as a vanilla body when Blizzard changes a card.
public enum RecruitEffects {
    enum Effect {
        case none, gold(Int), buff(Int, Int, all: Bool), gems(Int), gemBonus(Int, Int)
        case deity(Int, Int), setStats(Int, Int), buffTaunt(Int, Int)
        case token(String, Int, toHand: Bool), refreshes(Int), unsupported(String)
    }

    static func captures(_ pattern: String, _ text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.length == (text as NSString).length else { return nil }
        return (1..<match.numberOfRanges).map { (text as NSString).substring(with: match.range(at: $0)) }
    }

    static func effect(_ text: String) -> Effect {
        if text == "Give your minions +1/+1. If you discard this, cast it twice." { return .buff(1, 1, all: true) }
        if let c = captures("Give your Deity \\+([0-9]+)/\\+([0-9]+)\\.", text) { return .deity(Int(c[0])!, Int(c[1])!) }
        if let c = captures("Set a minion's stats to ([0-9]+)/([0-9]+)\\.", text) { return .setStats(Int(c[0])!, Int(c[1])!) }
        if let c = captures("Give a minion \\+([0-9]+)/\\+([0-9]+) and Taunt\\.", text) { return .buffTaunt(Int(c[0])!, Int(c[1])!) }
        if let c = captures("Gain ([0-9]+) Gold\\.", text) { return .gold(Int(c[0])!) }
        if text == "Get a Tavern Coin." { return .token("BG28_810", 1, toHand: true) }
        if let c = captures("Get ([0-9]+) Tavern Coins\\.", text) { return .token("BG28_810", Int(c[0])!, toHand: true) }
        if text == "Get a Blood Gem." { return .gems(1) }
        if let c = captures("Get ([0-9]+) Blood Gems\\.", text) { return .gems(Int(c[0])!) }
        if let c = captures("Give (a minion|your minions) \\+([0-9]+)/\\+([0-9]+)\\.", text) {
            return .buff(Int(c[1])!, Int(c[2])!, all: c[0] == "your minions")
        }
        if let c = captures("Your Blood Gems give an extra \\+([0-9]+)/\\+([0-9]+) this game\\.", text) {
            return .gemBonus(Int(c[0])!, Int(c[1])!)
        }
        if let c = captures("Gain ([0-9]+) free Refreshes\\.", text) { return .refreshes(Int(c[0])!) }
        return .unsupported(text)
    }

    static func battlecry(_ card: AdvisorCard, context: RecruitContext) -> Effect {
        guard let definition = context.definitions[card.cardID] else { return .unsupported("Missing card data") }
        let text = context.text(card.cardID)
        if text.hasPrefix("Battlecry and Deathrattle: ") {
            return effect(String(text.dropFirst("Battlecry and Deathrattle: ".count)))
        }
        if text.hasPrefix("Battlecry: ") {
            let body = String(text.dropFirst("Battlecry: ".count))
            if body == "Summon a 1/1 Cat." { return .token("BG_CFM_315t", 1, toHand: false) }
            if body == "Summon a 2/2 Cat." { return .token("TB_BaconUps_093t", 1, toHand: false) }
            return effect(body)
        }
        if (definition.mechanics ?? []).contains("BATTLECRY") || text.contains("Battlecry:") {
            return .unsupported("Battlecry: \(definition.name)")
        }
        if text.lowercased().contains("choose one") || text.lowercased().contains("magnetic") {
            return .unsupported("Play effect: \(definition.name)")
        }
        return .none
    }

    static func sell(_ card: AdvisorCard, context: RecruitContext) -> Effect {
        let text = context.text(card.cardID)
        if text == "When you sell this, get a 3/3 Elemental." { return .token("BGS_115t", 1, toHand: true) }
        if text == "When you sell this, get two 3/3 Elementals." { return .token("BGS_115t", 2, toHand: true) }
        if text.lowercased().contains("when you sell") { return .unsupported("Sell effect: \(card.cardID)") }
        return .none
    }

    static func needsTarget(_ effect: Effect) -> Bool {
        if case .buff(_, _, let all) = effect { return !all }
        if case .buffTaunt = effect { return true }
        if case .setStats = effect { return true }
        return false
    }

    static func isSupported(_ effect: Effect) -> Bool {
        if case .unsupported = effect { return false }
        return true
    }

    static func token(_ id: String, state: inout RecruitState, context: RecruitContext) -> AdvisorCard? {
        guard let d = context.definitions[id], let template = (state.board + state.hand + state.shop).first?.entity else { return nil }
        var e = template
        e.entityId = state.nextEntityID; state.nextEntityID -= 1; e.cardId = id
        e.attack = d.attack ?? 0; e.health = d.health ?? 0; e.maxHealth = e.health
        let mechanics = d.mechanics ?? []
        e.taunt = mechanics.contains("TAUNT"); e.divineShield = mechanics.contains("DIVINE_SHIELD")
        e.poisonous = mechanics.contains("POISONOUS"); e.venomous = mechanics.contains("VENOMOUS")
        e.reborn = mechanics.contains("REBORN"); e.stealth = mechanics.contains("STEALTH")
        e.windfury = mechanics.contains("WINDFURY"); e.locked = false
        e.enchantments = []; e.tags = [:]; e.additionalCardDbfIds = nil
        e.scriptDataNum1 = 0; e.scriptDataNum2 = 0; e.scriptDataNum3 = 0
        e.scriptDataNum4 = 0; e.scriptDataNum5 = 0; e.scriptDataNum6 = 0
        return AdvisorCard(cardID: id, kind: d.type == "MINION" ? .minion : .tavernSpell,
                           cost: d.cost, golden: d.battlegroundsNormalDbfId != nil, tier: d.techLevel, entity: e)
    }

    static func buff(_ card: inout AdvisorCard, attack: Int, health: Int) {
        card.entity.attack += attack; card.entity.health += health; card.entity.maxHealth += health
    }

    @discardableResult
    static func apply(_ effect: Effect, target: Int?, state: inout RecruitState, context: RecruitContext) -> Bool {
        switch effect {
        case .none: return true
        case .deity(let a, let h):
            guard let i = state.input.playerBoard.player.secrets.firstIndex(where: { $0.cardId == "BG_OldGod" }) else { return false }
            var secret = state.input.playerBoard.player.secrets[i]
            let attack = (secret.tags?["4914"] ?? secret.scriptDataNum2) + a
            let health = (secret.tags?["4915"] ?? secret.scriptDataNum3) + h
            secret.scriptDataNum2 = attack; secret.scriptDataNum3 = health
            var tags = secret.tags ?? [:]; tags["4914"] = attack; tags["4915"] = health; secret.tags = tags
            state.input.playerBoard.player.secrets[i] = secret
        case .setStats(let a, let h):
            guard let i = state.board.firstIndex(where: { $0.entity.entityId == target }) else { return false }
            state.board[i].entity.attack = a; state.board[i].entity.health = h; state.board[i].entity.maxHealth = h
        case .buffTaunt(let a, let h):
            guard let i = state.board.firstIndex(where: { $0.entity.entityId == target }) else { return false }
            buff(&state.board[i], attack: a, health: h); state.board[i].entity.taunt = true
        case .gold(let n): state.gold = min(100, state.gold + n)
        case .refreshes(let n): state.freeRolls += n
        case .gems(let n): return apply(.token("BG20_GEM", n, toHand: true), target: nil, state: &state, context: context)
        case .gemBonus(let a, let h):
            state.input.playerBoard.player.globalInfo["BloodGemAttackBonus", default: 0] += a
            state.input.playerBoard.player.globalInfo["BloodGemHealthBonus", default: 0] += h
        case .buff(let a, let h, let all):
            let indices = all ? Array(state.board.indices) : state.board.indices.filter { state.board[$0].entity.entityId == target }
            guard all || !indices.isEmpty else { return false }
            for i in indices { buff(&state.board[i], attack: a, health: h) }
        case .token(let id, let n, let toHand):
            guard context.definitions[id] != nil else { return false }
            for _ in 0..<min(n, 10) {
                if toHand ? state.hand.count >= AdvisorRequest.handLimit : state.board.count >= AdvisorRequest.boardLimit { continue }
                guard let card = token(id, state: &state, context: context) else { return false }
                if toHand { state.hand.append(card) } else { state.board.append(card) }
            }
        case .unsupported: return false
        }
        return true
    }

    /// Trigger coverage is conservative. Unsupported buy/play/sell/gem triggers block the affected
    /// action rather than making a false exact board. Combat-only triggers belong to the simulator.
    static func trigger(_ text: String, kind: RecruitStep.Kind) -> Effect? {
        let prefix: String
        switch kind {
        case .buy: prefix = "After you buy a minion, "
        case .play: prefix = "After you play a minion, "
        case .sell: prefix = "After you sell a minion, "
        case .spell: prefix = "After you cast a spell, "
        default: return nil
        }
        guard text.hasPrefix(prefix) else { return nil }
        let body = String(text.dropFirst(prefix.count))
        if let c = captures("gain \\+([0-9]+)/\\+([0-9]+)\\.", body) {
            return .buff(Int(c[0])!, Int(c[1])!, all: false)
        }
        return effect(body.prefix(1).uppercased() + body.dropFirst())
    }

    static func triggersSupported(_ kind: RecruitStep.Kind, state: RecruitState, context: RecruitContext) -> Bool {
        for card in state.board {
            let text = context.text(card.cardID)
            let t = text.lowercased()
            let relevant = (kind == .buy && (t.contains("after you buy") || t.contains("whenever you buy")))
                || (kind == .play && (t.contains("after you play") || t.contains("whenever you play") || t.contains("after you summon")))
                || (kind == .sell && (t.contains("after you sell") || t.contains("whenever you sell")))
                || (kind == .spell && (t.contains("after you cast") || t.contains("whenever you cast") || t.contains("after a blood gem")))
            if relevant {
                guard let effect = trigger(text, kind: kind), isSupported(effect) else { return false }
            }
        }
        return true
    }

    static func triggerEffects(_ kind: RecruitStep.Kind, before: RecruitState, state: inout RecruitState,
                               context: RecruitContext) -> Bool {
        for card in before.board where state.board.contains(where: { $0.entity.entityId == card.entity.entityId }) {
            guard let effect = trigger(context.text(card.cardID), kind: kind) else { continue }
            guard apply(effect, target: card.entity.entityId, state: &state, context: context) else { return false }
        }
        return true
    }

    static func battlecryRepeats(_ state: RecruitState, context: RecruitContext) -> Int {
        state.board.reduce(1) { repeats, card in
            switch context.text(card.cardID) {
            case "Your Battlecries trigger twice.": return max(repeats, 2)
            case "Your Battlecries trigger three times.": return max(repeats, 3)
            default: return repeats
            }
        }
    }

    static func endOfTurnRepeats(_ state: RecruitState, context: RecruitContext) -> Int {
        let extra = state.input.playerBoard.player.trinkets.filter {
            context.text($0.cardId) == "Your end of turn effects trigger an extra time."
        }.count
        return extra + state.board.reduce(1) { repeats, card in
            switch context.text(card.cardID) {
            case "Your end of turn effects trigger twice.": return max(repeats, 2)
            case "Your end of turn effects trigger three times.": return max(repeats, 3)
            default: return repeats
            }
        }
    }

    /// Triple combines current buffs and removes all three copies. The golden stays in hand;
    /// discovering is a terminal information boundary, not a fabricated reward.
    static func triples(state: inout RecruitState, context: RecruitContext) -> Bool {
        let all = state.board + state.hand
        let groups = Dictionary(grouping: all.filter { $0.isMinion && !$0.golden }, by: \.cardID)
        for id in groups.keys.sorted() {
            guard let copies = groups[id], copies.count >= 3 else { continue }
            guard let normal = context.definitions[id], let golden = context.golden(id) else { return false }
            let consumed = Array(copies.prefix(3)); let ids = Set(consumed.map { $0.entity.entityId })
            var combined = consumed[0]
            combined.cardID = golden.id; combined.entity.cardId = golden.id; combined.golden = true
            combined.entity.attack = (golden.attack ?? 0) + consumed.reduce(0) { $0 + $1.entity.attack - (normal.attack ?? 0) }
            combined.entity.health = (golden.health ?? 1) + consumed.reduce(0) { $0 + $1.entity.health - (normal.health ?? 1) }
            combined.entity.maxHealth = combined.entity.health
            combined.entity.enchantments = consumed.flatMap { $0.entity.enchantments }
            combined.entity.divineShield = consumed.contains { $0.entity.divineShield }
            combined.entity.taunt = consumed.contains { $0.entity.taunt }
            combined.entity.reborn = consumed.contains { $0.entity.reborn }
            combined.entity.windfury = consumed.contains { $0.entity.windfury }
            combined.entity.venomous = consumed.contains { $0.entity.venomous }
            combined.entity.poisonous = consumed.contains { $0.entity.poisonous }
            combined.entity.stealth = consumed.contains { $0.entity.stealth }
            state.board.removeAll { ids.contains($0.entity.entityId) }; state.hand.removeAll { ids.contains($0.entity.entityId) }
            guard state.hand.count < AdvisorRequest.handLimit else { return false }
            state.hand.append(combined)
            state.pendingDiscover += 1
            state.limitations.append("Triple reward is unknown; choose it and replan")
        }
        return true
    }

    /// Apply supported end-of-turn buffs, including known multipliers, in board order before combat. Unknown end-of-turn
    /// effects are recorded and exclude this board from exact combat claims.
    public static func combatProjection(_ state: RecruitState, context: RecruitContext) -> RecruitState {
        var result = state
        var consumedFromShop = false
        for card in state.board {
            let text = context.text(card.cardID)
            if text.hasPrefix("At the end of your turn, ") {
                for _ in 0..<endOfTurnRepeats(state, context: context) {
                    let body = String(text.dropFirst("At the end of your turn, ".count))
                    var effect = effect(body.prefix(1).uppercased() + body.dropFirst())
                    if body == "consume the highest-Health minion in the Tavern to gain its stats."
                        || body == "consume the highest-Health minion in the Tavern to gain double its stats." {
                        if consumedFromShop {
                            result.limitations.append("Multiple Tavern consumes need unknown shop replacements")
                            continue
                        }
                        let shop = result.shop.filter(\.isMinion)
                        let high = shop.map { $0.entity.health }.max()
                        let targets = shop.filter { $0.entity.health == high }
                        if targets.isEmpty { effect = .none }
                        else if targets.count == 1, let target = targets.first,
                                let i = result.board.firstIndex(where: { $0.entity.entityId == card.entity.entityId }) {
                            let repeats = body.contains("double") ? 2 : 1
                            buff(&result.board[i], attack: target.entity.attack * repeats, health: target.entity.health * repeats)
                            // The consumed shop replacement is random. A second consume needs a new observation.
                            consumedFromShop = true
                            effect = .none
                        }
                    }
                    if let c = captures("give your other minions \\+([0-9]+)/\\+([0-9]+)\\.", body) {
                        for i in result.board.indices where result.board[i].entity.entityId != card.entity.entityId {
                            buff(&result.board[i], attack: Int(c[0])!, health: Int(c[1])!)
                        }
                        effect = .none
                    }
                    if !apply(effect, target: nil, state: &result, context: context) {
                        result.limitations.append("End-of-turn effect not resolved: \(context.definitions[card.cardID]?.name ?? card.cardID)")
                    }
                }
            }
        }
        for trinket in state.input.playerBoard.player.trinkets {
            let text = context.text(trinket.cardId)
            if trinket.cardId == "BG36_MagicItem_302" || trinket.cardId == "BG36_MagicItem_302t",
               text.hasPrefix("At the end of your turn, give your minions +") {
                for _ in 0..<endOfTurnRepeats(state, context: context) {
                    _ = apply(.buff(trinket.scriptDataNum1, trinket.scriptDataNum2, all: true),
                              target: nil, state: &result, context: context)
                }
            }
        }
        result.limitations += RecruitMechanics.limitations(state, context: context, projectionOnly: true)
        if !state.input.playerBoard.player.questEntities.isEmpty
            || !state.input.playerBoard.player.questRewards.isEmpty {
            result.limitations.append("Recruit effects of quests are not resolved")
        }
        return result
    }
}
