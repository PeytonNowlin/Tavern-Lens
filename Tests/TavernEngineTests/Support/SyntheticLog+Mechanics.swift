/// Hero powers, trinkets, the Deity sigil, quests and counter enchantments for synthetic
/// logs, in the shapes the captured logs use (docs/research/simulator-input-mapping.md §4–§6).
extension SyntheticLog {
    /// A hero power in `PLAY`.
    mutating func heroPower(_ id: Int, _ cardID: String, controller: Int, extra: [String] = []) {
        card(id, cardID, controller: controller, zone: "PLAY", position: 0, type: "HERO_POWER", extra: extra)
    }

    /// A trinket in `PLAY`; `slot` is its `TAG_SCRIPT_DATA_NUM_6` (1 lesser, 2 greater).
    mutating func trinket(_ id: Int, _ cardID: String, controller: Int, slot: Int, sdn1: Int = 0, sdn2: Int = 0) {
        card(
            id, cardID, controller: controller, zone: "PLAY", position: 0, type: "BATTLEGROUND_TRINKET",
            extra: ["TAG_SCRIPT_DATA_NUM_1=\(sdn1)", "TAG_SCRIPT_DATA_NUM_2=\(sdn2)", "TAG_SCRIPT_DATA_NUM_6=\(slot)"]
        )
    }

    /// The Deity sigil `BG_OldGod` in `SECRET`, with its script data as the client prints it.
    mutating func deitySigil(_ id: Int, controller: Int, attack: Int, health: Int, deityDbfID: Int = 130_610) {
        card(
            id, "BG_OldGod", controller: controller, zone: "SECRET", position: 0, type: "SPELL",
            extra: [
                "TAG_SCRIPT_DATA_NUM_1=3", "TAG_SCRIPT_DATA_NUM_2=\(attack)", "TAG_SCRIPT_DATA_NUM_3=\(health)",
                "TAG_SCRIPT_DATA_NUM_6=\(deityDbfID)",
            ]
        )
    }

    /// An enchantment attached to a Player entity, e.g. `Bacon_TagTransferPlayerE` or `BG26_159pe`.
    mutating func playerEnchantment(_ id: Int, _ cardID: String, controller: Int, attachedTo playerEntityID: Int, extra: [String] = []) {
        card(
            id, cardID, controller: controller, zone: "PLAY", position: 0, type: "ENCHANTMENT",
            extra: ["ATTACHED=\(playerEntityID)"] + extra
        )
    }

    /// Combat setup against `opponent` up to the moment before the tag 2022 1→0 edge;
    /// `setup` adds the opponent's hero power, trinkets, sigil and transfer enchantment.
    mutating func combatSetup(bgTurn: Int, opponent: Int, name: String, heroID: Int, setup: (inout SyntheticLog) -> Void) {
        turn(bgTurn * 2)
        gameTag("2022", "1")
        slotTag("BACON_CURRENT_COMBAT_PLAYER_ID", String(opponent), name: name)
        card(heroID, "BG_HERO_\(opponent)", controller: Self.slotPlayerID, zone: "PLAY", position: 0, type: "HERO", health: 30, extra: ["PLAYER_ID=\(opponent)"])
        slotTag("HERO_ENTITY", String(heroID), name: name)
        setup(&self)
        endTaskList()
    }

    /// The tag 2022 1→0 edge: both boards are final.
    mutating func combatStarts() {
        gameTag("2022", "0")
        endTaskList()
    }
}
