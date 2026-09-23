import AppKit
import Foundation
import Observation
import SwiftUI
import TavernEngine

/// The saved feedback bookmarks, for the debug window: check that one still replays to its
/// snapshot, or export it as a golden case into a checkout of the repository.
@MainActor
@Observable
final class DebugBookmarksModel {
    struct Row: Identifiable {
        var bookmark: FeedbackBookmark
        var record: GameRecord
        var id: UUID { bookmark.id }
    }

    private(set) var rows: [Row] = []
    /// Per bookmark: the outcome of the last replay or export.
    private(set) var status: [UUID: String] = [:]
    private(set) var busy: Set<UUID> = []
    private let store: GameRecordStore
    private static let exportRootKey = "bookmarkExportRoot"

    init(store: GameRecordStore = .standard) {
        self.store = store
    }

    func reload() {
        let store = store
        Task {
            let loaded = await Task.detached { store.allBookmarks() }.value
            rows = loaded.map { Row(bookmark: $0.bookmark, record: $0.record) }
        }
    }

    /// Replays the bookmark's Power.log stretch and says whether it reaches the same snapshot.
    func verify(_ row: Row) {
        let bookmark = row.bookmark
        guard let path = bookmark.powerLog else {
            status[row.id] = "No Power.log path recorded"
            return
        }
        let pool = PoolDataModel.shared.pool
        run(row) {
            let replayed = try TavernEngine.replay(bookmark, powerLog: URL(filePath: path), pool: pool)
            return replayed.timeline.last == bookmark.shown
                ? "Replays to the identical snapshot"
                : "⚠︎ Replays to a different snapshot (line \(bookmark.cut.endLine))"
        }
    }

    /// Asks for the repository root, then writes the case and its log stretch there.
    func export(_ row: Row) {
        let bookmark = row.bookmark
        guard let path = bookmark.powerLog else {
            status[row.id] = "No Power.log path recorded"
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Export Here"
        panel.message = "Choose the Tavern Lens repository root. The case goes to \(BookmarkExport.casesDirectory), "
            + "its log stretch to \(BookmarkExport.fixturesDirectory)/bookmarks (git-ignored)."
        if let saved = UserDefaults.standard.url(forKey: Self.exportRootKey) { panel.directoryURL = saved }
        guard panel.runModal() == .OK, let root = panel.url else { return }
        UserDefaults.standard.set(root, forKey: Self.exportRootKey)
        run(row) {
            let exported = try BookmarkExport.export(bookmark, powerLog: URL(filePath: path), into: root)
            return "Exported \(exported.goldenCase.name) (replay verified)"
        }
    }

    private func run(_ row: Row, _ work: @escaping @Sendable () throws -> String) {
        let id = row.id
        busy.insert(id)
        status[id] = nil
        Task {
            let outcome: String
            do {
                outcome = try await Task.detached(priority: .userInitiated) { try work() }.value
            } catch {
                outcome = "⚠︎ \(error)"
            }
            status[id] = outcome
            busy.remove(id)
        }
    }
}

/// The bookmark list shown from the debug window's toolbar.
struct DebugBookmarksView: View {
    let model: DebugBookmarksModel
    @State private var selection: UUID?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Feedback Bookmarks").font(.headline)
                Text("(\(FeedbackController.hotKeyName) during a game)").foregroundStyle(.secondary)
                Spacer()
                Button("Reload") { model.reload() }
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            if model.rows.isEmpty {
                Text("No bookmarks yet. Press \(FeedbackController.hotKeyName) during a Battlegrounds game.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Table(model.rows, selection: $selection) {
                    TableColumn("When") { Text($0.bookmark.createdAt.formatted(date: .abbreviated, time: .standard)) }
                        .width(min: 120, ideal: 160)
                    TableColumn("Game") { Text($0.bookmark.gameSeed.map(String.init) ?? "–").monospacedDigit() }
                        .width(min: 70, ideal: 90)
                    TableColumn("Turn") { Text(Self.moment($0.bookmark)) }
                        .width(min: 80, ideal: 110)
                    TableColumn("Line") { Text("\($0.bookmark.cut.endLine)").monospacedDigit() }
                        .width(min: 50, ideal: 70)
                    TableColumn("Note") { Text($0.bookmark.note.isEmpty ? "–" : $0.bookmark.note) }
                    TableColumn("") { row in
                        HStack {
                            if model.busy.contains(row.id) {
                                ProgressView().controlSize(.small)
                            } else if let status = model.status[row.id] {
                                Text(status).font(.caption).foregroundStyle(status.hasPrefix("⚠︎") ? .orange : .secondary)
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                            Button("Replay") { model.verify(row) }
                            Button("Export Golden Case…") { model.export(row) }
                        }
                        .disabled(model.busy.contains(row.id))
                    }
                    .width(min: 260, ideal: 360)
                }
            }
            if let id = selection, let row = model.rows.first(where: { $0.id == id }) {
                Divider()
                ScrollView {
                    Text(Self.details(row))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 150)
            }
        }
        .frame(minWidth: 820, minHeight: 360)
        .task { model.reload() }
    }

    static func moment(_ bookmark: FeedbackBookmark) -> String {
        if bookmark.shown.state.status == .gameOver { return "Game over" }
        guard let turn = bookmark.bgTurn else { return "–" }
        return turn == 0 ? "Hero pick" : "\(turn) \(bookmark.phase?.rawValue ?? "")"
    }

    static func details(_ row: DebugBookmarksModel.Row) -> String {
        let b = row.bookmark
        let cut = b.cut
        var lines = [
            "Session \(cut.session ?? "–"), seed \(cut.gameSeed.map(String.init) ?? "–")",
            "Power.log lines \(cut.startLine)–\(cut.endLine), bytes \(cut.startByteOffset.map(String.init) ?? "?")–"
                + "\(cut.endByteOffset.map(String.init) ?? "?"), shown at \(b.shown.position.time)",
            "Log: \(b.powerLog ?? "–")",
        ]
        if let resumed = b.resumed {
            lines.append("Resumed from sessions \(resumed.sessions.joined(separator: ", "))")
        }
        if let o = b.overlay {
            lines.append(
                "Overlay: \(o.visible ? "visible" : "not visible")\(o.hiddenByUser ? " (hidden by you)" : ""), "
                    + "panels \(o.panels.isEmpty ? "none" : o.panels.joined(separator: ", "))"
                    + (o.hoveredPlayerID.map { ", hovering P\($0)" } ?? "")
                    + (o.contentWidth.map { w in ", \(Int(w))×\(Int(o.contentHeight ?? 0))" } ?? "")
                    + (o.drewShownState ? "" : ", overlay was a frame behind")
            )
        }
        lines.append("Game outcome: \(row.record.outcome.rawValue)")
        return lines.joined(separator: "\n")
    }
}
