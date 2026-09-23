import Foundation
import SwiftUI
import TavernEngine
import UniformTypeIdentifiers

/// Shows the replayed timeline of a chosen Power.log: the games found, every view
/// state the engine emitted, the raw state of the selected entry, and the entities at
/// end of log with card and tag names resolved from the running build's card data.
struct DebugWindow: View {
    let model: DebugReplayModel
    private let cardData = CardDataModel.shared
    @State private var isImporting = false
    @State private var selection: TimelineRow.ID?
    @State private var detail = Detail.player
    @State private var entityFilter = ""
    @State private var showsBookmarks = false
    @State private var bookmarks = DebugBookmarksModel()

    enum Detail: String, CaseIterable, Identifiable {
        case player = "Player & shop"
        case lobby = "Lobby"
        case viewState = "View state"
        case entities = "Entities at end"
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(12)
            Divider()
            content
        }
        .frame(minWidth: 720, minHeight: 420)
        .toolbar {
            ToolbarItem {
                Button("Open Log…", systemImage: "doc.badge.plus") { isImporting = true }
                    .disabled(model.isReplaying || cardData.isLoading)
            }
            ToolbarItem {
                Button("Bookmarks", systemImage: "bookmark") { showsBookmarks = true }
                    .help("Feedback bookmarks: replay them or export them as golden cases")
            }
        }
        .sheet(isPresented: $showsBookmarks) { DebugBookmarksView(model: bookmarks) }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.log, .plainText, .data]) { outcome in
            guard case .success(let url) = outcome else { return }
            selection = nil
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            model.replay(url, cards: cardData.cards)
        }
        .task { cardData.loadIfNeeded() }
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        if let url = model.fileURL {
            Text(url.path(percentEncoded: false))
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.middle)
        } else {
            Text("Open a Power.log to replay it.")
                .font(.headline)
        }
        Text(cardData.statusText)
            .font(.caption)
            .foregroundStyle(cardData.loaded?.isExact == false || cardData.errorMessage != nil ? .orange : .secondary)
        if model.isReplaying {
            ProgressView().controlSize(.small)
        } else if let message = model.errorMessage {
            Text(message).foregroundStyle(.red)
        } else if let result = model.result {
            summary(result)
        }
    }

    private func summary(_ result: ReplayResult) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            let d = result.diagnostics
            Text(
                "\(d.linesRead.formatted()) lines · \(result.timeline.count) timeline entries"
                    + (model.elapsed.map { " · \($0.formatted(.units(allowed: [.seconds, .milliseconds])))" } ?? "")
                    + " · unparsable \(d.parse.unparsableLines), orphan tags \(d.parse.orphanTagLines),"
                    + " malformed \(d.parse.malformedPowerLines), unbound names \(d.store.unboundPlayerNames)"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            if result.games.isEmpty {
                Text("No solo Battlegrounds game found.")
            }
            ForEach(Array(result.games.enumerated()), id: \.offset) { index, game in
                Text(Self.describe(game, number: index + 1, cards: cardData.cards))
                    .font(.callout.monospaced())
            }
        }
    }

    static func describe(_ game: BGGameRecord, number: Int, cards: CardDB?) -> String {
        let end = game.end.map { "ended line \($0.line) at \($0.time)" } ?? "no end (in progress or truncated)"
        let hero = game.localHeroCardID.map { id in cards?.name(of: id).map { "\($0) (\(id))" } ?? id } ?? "–"
        return "Game \(number): \(game.gameType), hero \(hero), "
            + "player \(game.localPlayerID.map(String.init) ?? "–"), BG turn \(game.bgTurn), "
            + "started line \(game.start.line) at \(game.start.time), \(end)"
            + (game.placement.map { ", placed \($0)" + (game.placementSource == .concedeEstimate ? " (estimated)" : "") } ?? "")
    }

    // MARK: - Timeline

    private var rows: [TimelineRow] {
        (model.result?.timeline ?? []).enumerated().map { TimelineRow(id: $0.offset, entry: $0.element) }
    }

    @ViewBuilder private var content: some View {
        HSplitView {
            Table(rows, selection: $selection) {
                TableColumn("#") { Text("\($0.id)").monospacedDigit() }
                    .width(min: 30, ideal: 40, max: 60)
                TableColumn("Line") { Text("\($0.entry.position.line)").monospacedDigit() }
                    .width(min: 50, ideal: 70, max: 90)
                TableColumn("Time") { Text($0.entry.position.time).monospacedDigit() }
                    .width(min: 90, ideal: 120, max: 140)
                TableColumn("Status") { Text($0.entry.state.status.rawValue) }
                    .width(min: 60, ideal: 80, max: 100)
                TableColumn("Turn") { Text($0.entry.state.game.map { String($0.bgTurn) } ?? "–") }
                    .width(min: 30, ideal: 40, max: 60)
                TableColumn("Phase") { Text($0.entry.state.game?.phase.rawValue ?? "–") }
                    .width(min: 50, ideal: 65, max: 80)
                TableColumn("HP") { Text($0.entry.state.game?.player?.hero.map { String($0.hp) } ?? "–").monospacedDigit() }
                    .width(min: 30, ideal: 35, max: 50)
                TableColumn("Gold") { Text(Self.goldLabel($0.entry.state.game?.player?.gold)).monospacedDigit() }
                    .width(min: 40, ideal: 50, max: 70)
                TableColumn("Tier") { Text($0.entry.state.game?.player?.tier.map(String.init) ?? "–").monospacedDigit() }
                    .width(min: 25, ideal: 30, max: 40)
                // Table takes at most 10 columns; the game type is in the summary above.
                TableColumn("Hero") { Text(Self.heroLabel($0.entry.state.game)) }
            }
            .frame(minWidth: 480)

            VStack(spacing: 0) {
                Picker("Detail", selection: $detail) {
                    ForEach(Detail.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)
                switch detail {
                case .player:
                    ScrollView {
                        Text(selectedPlayerText)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                case .lobby:
                    ScrollView {
                        Text(selectedLobbyText)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                case .viewState:
                    ScrollView {
                        Text(selectedJSON)
                            .font(.body.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                case .entities:
                    entityList
                }
            }
            .frame(minWidth: 260)
        }
    }

    static func goldLabel(_ gold: GoldView?) -> String {
        guard let gold else { return "–" }
        return "\(gold.available)/\(gold.thisTurn)"
    }

    // MARK: - Player & shop

    private var selectedPlayerText: String {
        guard let selection, let row = rows.first(where: { $0.id == selection }) else {
            return "Select a timeline entry to see the player's state."
        }
        guard let game = row.entry.state.game else { return "No Battlegrounds game." }
        return Self.describe(game)
    }

    private var selectedLobbyText: String {
        guard let selection, let row = rows.first(where: { $0.id == selection }) else {
            return "Select a timeline entry to see the lobby."
        }
        guard let game = row.entry.state.game else { return "No Battlegrounds game." }
        return DebugLobbyPane.describe(game)
    }

    /// The selected state as the player would read it off the screen.
    static func describe(_ game: GameView) -> String {
        var lines = ["BG turn \(game.bgTurn), \(game.phase.rawValue)", "Hero: \(heroLabel(game))"]
        if let player = game.player {
            if let hero = player.hero {
                lines.append("HP \(hero.hp) (health \(hero.health) − damage \(hero.damage) + armor \(hero.armor)), triples \(hero.triples)")
            }
            let gold = player.gold
            lines.append(
                "Gold \(gold.available) available of \(gold.thisTurn) (used \(gold.used), temporary \(gold.temporary))"
                    + (gold.cap.map { ", cap \($0)" } ?? "")
            )
            lines.append("Tavern tier \(player.tier.map(String.init) ?? "–")")
            lines.append("")
            lines.append("Board (\(player.board.count)):")
            lines += player.board.map { "  " + describe($0) }
            lines.append("Hand (\(player.hand.count)):")
            lines += player.hand.map { "  " + describe($0) }
        }
        lines.append("Shop (\(game.shop.cards.count))\(game.shop.isFrozen ? ", frozen" : ""):")
        lines += game.shop.cards.map { "  " + describe($0) }
        return lines.joined(separator: "\n")
    }

    static func describe(_ card: CardView) -> String {
        var text = card.name ?? card.cardID
        if card.golden { text += " (golden)" }
        if let attack = card.attack, let health = card.health { text += " \(attack)/\(health)" }
        if card.kind != .minion { text += " [\(card.kind.rawValue)]" }
        if let tier = card.tier, tier > 0 { text += " T\(tier)" }
        if !card.keywords.isEmpty { text += " " + card.keywords.map(\.rawValue).joined(separator: ", ") }
        if card.name != nil { text += "  \(card.cardID)" }
        return text
    }

    static func heroLabel(_ game: GameView?) -> String {
        guard let id = game?.localHeroCardID else { return "–" }
        return game?.localHeroName.map { "\($0) (\(id))" } ?? id
    }

    // MARK: - Entities

    private var filteredEntities: [EntityRow] {
        let all = model.result?.entities ?? []
        let query = entityFilter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return all }
        return all.filter { row in
            String(row.id) == query || row.cardID.localizedCaseInsensitiveContains(query)
                || (row.cardName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    private var entityList: some View {
        VStack(spacing: 0) {
            TextField("Filter by entity ID, card ID or name", text: $entityFilter)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
            List(filteredEntities) { row in
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.entityTitle(row))
                        .font(.callout.bold())
                    Text(row.tags.map { "\($0.tag)=\($0.value)" }.joined(separator: "  "))
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    static func entityTitle(_ row: EntityRow) -> String {
        var title = "#\(row.id)"
        if let name = row.cardName { title += " \(name)" }
        if !row.cardID.isEmpty { title += " (\(row.cardID))" }
        return title
    }

    private var selectedJSON: String {
        guard let selection, let row = rows.first(where: { $0.id == selection }) else {
            return "Select a timeline entry to see its view state."
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(row.entry), let text = String(data: data, encoding: .utf8) else {
            return "Could not encode the entry."
        }
        return text
    }
}

struct TimelineRow: Identifiable {
    let id: Int
    let entry: TimelineEntry
}
