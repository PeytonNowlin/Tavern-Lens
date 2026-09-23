/// Cards, zones and player tags for synthetic logs, in the shapes the captured logs use.
extension SyntheticLog {
    /// `FULL_ENTITY - Updating` with the usual tags plus `extra` (`"TAUNT=1"`, `"PREMIUM=1"`, …).
    mutating func card(
        _ id: Int, _ cardID: String, controller: Int, zone: String, position: Int,
        type: String = "MINION", atk: Int = 0, health: Int = 0, extra: [String] = []
    ) {
        power("FULL_ENTITY - Updating [entityName=Some Card id=\(id) zone=\(zone) zonePos=\(position) cardId= player=\(controller)] CardID=\(cardID)")
        var tags = [
            "CONTROLLER=\(controller)", "CARDTYPE=\(type)", "ATK=\(atk)", "HEALTH=\(health)",
            "ZONE=\(zone)", "ZONE_POSITION=\(position)",
        ]
        tags += extra
        for tag in tags {
            let parts = tag.split(separator: "=", maxSplits: 1)
            power("tag=\(parts[0]) value=\(parts[1])", indent: 8)
        }
    }

    /// A shop minion or tavern spell under the bartender slot.
    mutating func shopCard(_ id: Int, _ cardID: String, position: Int, type: String = "MINION", atk: Int = 0, health: Int = 0, extra: [String] = []) {
        card(id, cardID, controller: Self.slotPlayerID, zone: "PLAY", position: position, type: type, atk: atk, health: health, extra: extra)
    }

    /// `TAG_CHANGE` on an entity in bracket form (the bracket's zone is deliberately stale).
    mutating func tag(_ id: Int, _ tag: String, _ value: String, suffix: String = " ") {
        power("TAG_CHANGE Entity=[entityName=Some Card id=\(id) zone=PLAY zonePos=1 cardId= player=\(Self.slotPlayerID)] tag=\(tag) value=\(value)\(suffix)")
    }

    /// `TAG_CHANGE` on the local Player entity, by BattleTag.
    mutating func localTag(_ tag: String, _ value: String) {
        power("TAG_CHANGE Entity=\(Self.localName) tag=\(tag) value=\(value) ")
    }

    /// `TAG_CHANGE` on the bartender slot, by one of its changing names.
    mutating func slotTag(_ tag: String, _ value: String, name: String = "Bartender Bob") {
        power("TAG_CHANGE Entity=\(name) tag=\(tag) value=\(value) ")
    }

    /// `TAG_CHANGE` on the game entity.
    mutating func gameTag(_ tag: String, _ value: String) {
        power("TAG_CHANGE Entity=GameEntity tag=\(tag) value=\(value) ")
    }
}
