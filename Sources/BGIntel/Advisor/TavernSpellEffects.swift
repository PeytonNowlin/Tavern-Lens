/// What a tavern spell does to the coming combat's board, for the spells whose effect is a plain,
/// certain stat change (the advisor scores those by simulating the changed board). Spells that
/// discover, generate, steal, transform, give gold or act at random aren't modelled, so the advisor
/// doesn't suggest them.
///
/// Hand-maintained from the card text of patch 36.6.1 (build 251952); the card text isn't
/// available at runtime (the live engine runs without card data). Add an entry when a new spell
/// with a certain stat effect shows up.
public enum TavernSpellEffect: Codable, Hashable, Sendable {
    /// One chosen minion gets +attack/+health; `taunt` adds or toggles Taunt.
    case buffTarget(attack: Int, health: Int, taunt: TauntChange)
    /// Set one chosen minion's stats.
    case setTargetStats(attack: Int, health: Int)
    /// Every friendly minion.
    case buffAll(attack: Int, health: Int)
    /// The left-most friendly minion.
    case buffLeftmost(attack: Int, health: Int)
    /// The local Deity (the Deity secret's stats, tags 4914/4915).
    case buffDeity(attack: Int, health: Int)

    public enum TauntChange: String, Codable, Hashable, Sendable {
        case none, add
        /// Tricky Trousers: gives Taunt, or removes it when the minion has it.
        case toggle
    }

    public var needsTarget: Bool {
        switch self {
        case .buffTarget, .setTargetStats: true
        default: false
        }
    }

    /// The effects of a spell card, one per Choose One option; nil when the spell isn't modelled.
    public static func options(of cardID: String) -> [TavernSpellEffect]? { table[cardID] }

    static let table: [String: [TavernSpellEffect]] = [
        // Shiny Ring: Give your minions +1/+1.
        "BG28_168": [.buffAll(attack: 1, health: 1)],
        // Fortify: Give a minion +3 Health and Taunt.
        "BG28_503": [.buffTarget(attack: 0, health: 3, taunt: .add)],
        // Tricky Trousers: Give a minion +1/+2 and Taunt. If it already has Taunt, remove it.
        "BG28_520": [.buffTarget(attack: 1, health: 2, taunt: .toggle)],
        // Defender's Rites: Give a minion +7/+7 and Taunt.
        "BG28_825": [.buffTarget(attack: 7, health: 7, taunt: .add)],
        // Perfect Vision: Set a minion's stats to 20/20.
        "BG28_838": [.setTargetStats(attack: 20, health: 20)],
        // Tavern Dish Banana: Give a minion +2/+2.
        "BG28_897": [.buffTarget(attack: 2, health: 2, taunt: .none)],
        // Alliance Flag: Choose One - Give a minion +3/+1; or +1/+3.
        "BG31_880": [.buffTarget(attack: 3, health: 1, taunt: .none), .buffTarget(attack: 1, health: 3, taunt: .none)],
        // Time Management: Choose One - Give your minions +2/+2; or (next turn, not modelled).
        "BG31_881": [.buffAll(attack: 2, health: 2)],
        // Selfish Bounty: Give your left-most minion +6/+6.
        "BG33_813": [.buffLeftmost(attack: 6, health: 6)],
        // Sludge Corrosion: Give your minions +1/+1 (twice if discarded; casting it is once).
        "BG36_301t": [.buffAll(attack: 1, health: 1)],
        // Energizing Chamber: Give your Deity +7/+7.
        "BG36_371": [.buffDeity(attack: 7, health: 7)],
        // Winner's Bread: Give a minion +2/+3 (and more next turn if you win, not modelled).
        "BG36_883": [.buffTarget(attack: 2, health: 3, taunt: .none)],
    ]

    /// Applies the effect to a local side's minions (left to right) and Deity.
    func apply(to minions: inout [BattleEntity], secrets: inout [BattleSecret], target: Int?) {
        func buff(_ index: Int, _ attack: Int, _ health: Int) {
            guard minions.indices.contains(index) else { return }
            minions[index].attack += attack
            minions[index].health += health
            minions[index].maxHealth += health
        }
        switch self {
        case .buffTarget(let attack, let health, let taunt):
            guard let target, minions.indices.contains(target) else { return }
            buff(target, attack, health)
            switch taunt {
            case .none: break
            case .add: minions[target].taunt = true
            case .toggle: minions[target].taunt.toggle()
            }
        case .setTargetStats(let attack, let health):
            guard let target, minions.indices.contains(target) else { return }
            minions[target].attack = attack
            minions[target].health = health
            minions[target].maxHealth = health
        case .buffAll(let attack, let health):
            for index in minions.indices { buff(index, attack, health) }
        case .buffLeftmost(let attack, let health):
            buff(0, attack, health)
        case .buffDeity(let attack, let health):
            for index in secrets.indices {
                guard var tags = secrets[index].tags, let a = tags["4914"], let h = tags["4915"] else { continue }
                tags["4914"] = a + attack
                tags["4915"] = h + health
                secrets[index].tags = tags
            }
        }
    }
}
