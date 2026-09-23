import EntityStore
import PowerParser

extension GameTag {
    /// `BACON_SKIN_PARENT_ID`: on a skinned hero, the dbfId of the hero it's a skin of.
    static let baconSkinParentID = GameTag.id(2039)
    /// `BACON_LOCKED_MULLIGAN_HERO`: an offered hero the player can't pick without the Tavern Pass.
    static let baconLockedMulliganHero = GameTag.id(3877)
}

/// One hero the local player is offered at the hero pick.
public struct BGHeroOffer: Hashable, Sendable {
    public var entityID: Int
    /// The hero's card now: a reroll changes it in place (`CHANGE_ENTITY`). It may be a skin.
    public var cardID: String
    /// `BACON_SKIN_PARENT_ID`: the base hero's dbfId, when the offer is a skin.
    public var skinParentDbfID: Int?
    /// Shown but not pickable (`BACON_LOCKED_MULLIGAN_HERO`, no Tavern Pass).
    public var isLocked: Bool

    public init(entityID: Int, cardID: String, skinParentDbfID: Int? = nil, isLocked: Bool = false) {
        self.entityID = entityID
        self.cardID = cardID
        self.skinParentDbfID = skinParentDbfID
        self.isLocked = isLocked
    }
}

/// The hero pick as the player sees it: the offered heroes left to right, and the pick once made.
public struct BGHeroPick: Hashable, Sendable {
    public var offers: [BGHeroOffer]
    /// The entity of the hero picked; nil while the player is still choosing.
    public var chosenEntityID: Int?

    public var chosen: BGHeroOffer? { chosenEntityID.flatMap { id in offers.first { $0.entityID == id } } }
}

/// Follows the local player's hero pick: the `MULLIGAN` choice the server offers
/// (`GameState.DebugPrintEntityChoices`) and what was picked (`DebugPrintEntitiesChosen`).
///
/// The offer lists the heroes in their final hand order, left to right on screen (the hand's
/// `ZONE_POSITION`s are shuffled while the task list that shows the pick plays). The offered
/// heroes' cards are read from the entity store when projected, so a reroll, which changes a
/// hand hero's card in place, shows at once. Should the heroes in hand stop matching the
/// offer (a reroll that makes new entities), the heroes in hand win, by hand position.
/// A new game (`GameState` `CREATE_GAME`) clears it.
public struct BGHeroPickTracker: Sendable {
    private var choice: EntityChoice?
    private var chosenEntityID: Int?

    public init() {}

    public mutating func observe(_ event: PowerEvent) {
        switch event {
        case .newGameAnnounced:
            choice = nil
            chosenEntityID = nil
        case .entityChoices(let offered) where offered.choiceType == "MULLIGAN" && !offered.options.isEmpty:
            choice = offered
            chosenEntityID = nil
        case .entitiesChosen(let id, let chosen) where id == choice?.id:
            chosenEntityID = chosen.first?.entityID
        default:
            break
        }
    }

    /// The hero pick now, ordered as on screen; nil before the offer is on screen. The client
    /// shows the choice once the task list it names has played (`lastTaskListEnded`, from the
    /// parser, numbered from the game's start); until then the offered heroes are still being
    /// dealt and shuffled.
    public func project(_ store: EntityStore, lastTaskListEnded: Int? = nil) -> BGHeroPick? {
        guard let choice else { return nil }
        if let shownWith = choice.taskList, (lastTaskListEnded ?? Int.min) < shownWith { return nil }
        var ids = choice.options.map(\.entityID)
        let printed = Dictionary(choice.options.map { ($0.entityID, $0.cardID) }, uniquingKeysWith: { a, _ in a })
        if chosenEntityID == nil, let local = store.localPlayer {
            let inHand = store.entities(controller: local.playerID, zone: "HAND")
                .filter { $0.name(.cardType) == "HERO" && $0.cardID != BGSnapshot.placeholderHeroCardID }
            if !inHand.isEmpty, Set(inHand.map(\.id)) != Set(ids) {
                ids = inHand.sorted { ($0.int(.zonePosition) ?? 0, $0.id) < ($1.int(.zonePosition) ?? 0, $1.id) }.map(\.id)
            }
        }
        let offers = ids.map { id in
            let entity = store[id]
            let card = entity.map(\.cardID).flatMap { $0.isEmpty ? nil : $0 } ?? printed[id] ?? ""
            return BGHeroOffer(
                entityID: id, cardID: card,
                skinParentDbfID: entity?.int(.baconSkinParentID).flatMap { $0 > 0 ? $0 : nil },
                isLocked: entity?.int(.baconLockedMulliganHero) == 1
            )
        }
        return BGHeroPick(offers: offers, chosenEntityID: chosenEntityID)
    }
}
