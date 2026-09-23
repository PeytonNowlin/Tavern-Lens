import Foundation
import SwiftUI
import TavernEngine
import UniformTypeIdentifiers

/// Shows the replayed timeline of a chosen Power.log: the games found, every view
/// state the engine emitted, and the raw state of the selected entry.
struct DebugWindow: View {
    let model: DebugReplayModel
    @State private var isImporting = false
    @State private var selection: TimelineRow.ID?

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
                    .disabled(model.isReplaying)
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.log, .plainText, .data]) { outcome in
            guard case .success(let url) = outcome else { return }
            selection = nil
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            model.replay(url)
        }
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
                Text(Self.describe(game, number: index + 1))
                    .font(.callout.monospaced())
            }
        }
    }

    static func describe(_ game: BGGameRecord, number: Int) -> String {
        let end = game.end.map { "ended line \($0.line) at \($0.time)" } ?? "no end (in progress or truncated)"
        return "Game \(number): \(game.gameType), hero \(game.localHeroCardID ?? "–"), "
            + "player \(game.localPlayerID.map(String.init) ?? "–"), BG turn \(game.bgTurn), "
            + "started line \(game.start.line) at \(game.start.time), \(end)"
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
                TableColumn("Hero") { Text($0.entry.state.game?.localHeroCardID ?? "–") }
                TableColumn("Game type") { Text($0.entry.state.game?.gameType ?? "–") }
            }
            .frame(minWidth: 480)

            ScrollView {
                Text(selectedJSON)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .frame(minWidth: 220)
        }
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
