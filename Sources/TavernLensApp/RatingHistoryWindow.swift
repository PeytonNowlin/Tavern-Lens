import Charts
import SwiftUI
import TavernEngine

struct RatingHistoryWindow: View {
    let model: RatingHistoryModel
    var readingStatus: String = ""
    var requestScreenReadingPermission: (() -> Void)?
    @State private var showsEditor = false
    @State private var editingReading: RatingReading?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Rating history").font(.title2.bold())
                    Text("Your Battlegrounds rating over time.").foregroundStyle(.secondary)
                    if !readingStatus.isEmpty {
                        Text(readingStatus).font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if model.isBusy { ProgressView().controlSize(.small) }
                Button {
                    editingReading = nil
                    showsEditor = true
                } label: {
                    Label("Record rating…", systemImage: "plus")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.white.opacity(model.isBusy ? 0.65 : 1))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(model.isBusy ? Color.gray.opacity(0.45) : Color(red: 0.08, green: 0.39, blue: 0.78),
                                    in: RoundedRectangle(cornerRadius: 6))
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .disabled(model.isBusy)
            }

            if let error = model.errorMessage {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .textSelection(.enabled)
            }

            if let requestScreenReadingPermission {
                Button("Allow automatic MMR reading…", action: requestScreenReadingPermission)
                    .buttonStyle(.borderless)
            }

            if model.entries.isEmpty {
                ContentUnavailableView(model.errorMessage == nil ? "No rating readings yet" : "Rating history unavailable",
                    systemImage: "chart.xyaxis.line",
                    description: Text(model.errorMessage == nil
                        ? "Record the rating shown in Battlegrounds to start your history."
                        : "Refresh to try reading the saved history again."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                summary
                Chart(model.entries) { reading in
                    LineMark(x: .value("Date", reading.recordedAt), y: .value("Rating", reading.rating))
                        .foregroundStyle(.blue)
                    PointMark(x: .value("Date", reading.recordedAt), y: .value("Rating", reading.rating))
                        .foregroundStyle(.blue)
                        .symbol(by: .value("Source", reading.source.label))
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .chartXAxisLabel("Recorded date")
                .chartYAxisLabel("Rating")
                .frame(height: 230)
                .accessibilityLabel("Battlegrounds rating history")

                Table(Array(model.entries.reversed())) {
                    TableColumn("Recorded") { reading in
                        Text(reading.recordedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                    TableColumn("Rating") { reading in Text(reading.rating.formatted()).monospacedDigit() }
                        .width(min: 70, ideal: 90, max: 120)
                    TableColumn("Source") { reading in Text(reading.source.label) }
                        .width(min: 70, ideal: 90, max: 120)
                    TableColumn("") { reading in
                        Button("Correct…") {
                            editingReading = reading
                            showsEditor = true
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isBusy)
                    }
                    .width(80)
                }
                .frame(minHeight: 150)
                Text("Entered readings and corrections are labeled Entered. Screen readings come from the visible rating.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(minWidth: 720, minHeight: 620)
        .toolbar {
            ToolbarItem {
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .disabled(model.isBusy)
            }
        }
        .task { await model.refresh() }
        .sheet(isPresented: $showsEditor) { RatingHistoryEditor(model: model, reading: editingReading) }
    }

    private var summary: some View {
        HStack(alignment: .top, spacing: 36) {
            statistic("Latest rating", value: model.history.latest?.rating.formatted() ?? "–")
            statistic("Last change", value: model.history.latestChange.map { $0 > 0 ? "+\($0.formatted())" : $0.formatted() } ?? "–")
            statistic("Highest recorded", value: model.history.highest?.formatted() ?? "–")
            Spacer()
        }
    }

    private func statistic(_ label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit()
        }
    }
}

private struct RatingHistoryEditor: View {
    let model: RatingHistoryModel
    let reading: RatingReading?
    @State private var ratingText: String
    @State private var date = Date()
    @Environment(\.dismiss) private var dismiss

    init(model: RatingHistoryModel, reading: RatingReading?) {
        self.model = model
        self.reading = reading
        _ratingText = State(initialValue: reading.map { String($0.rating) } ?? "")
    }

    private var rating: Int? {
        let text = ratingText.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: "")
        guard let value = Int(text), value >= 0 else { return nil }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(reading == nil ? "Record rating" : "Correct rating").font(.title2.bold())
            TextField("Rating shown in Battlegrounds", text: $ratingText)
                .textFieldStyle(.roundedBorder)
            if let reading {
                Text("Reading from \(reading.recordedAt.formatted(date: .abbreviated, time: .shortened))")
                    .foregroundStyle(.secondary)
            } else {
                DatePicker("Recorded", selection: $date, displayedComponents: [.date, .hourAndMinute])
            }
            Text("This reading will be labeled Entered.").font(.caption).foregroundStyle(.secondary)
            if !ratingText.isEmpty, rating == nil {
                Text("Enter a whole-number rating of 0 or greater.").foregroundStyle(.red)
            }
            if let error = model.errorMessage { Text(error).foregroundStyle(.orange) }
            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                Spacer()
                Button(reading == nil ? "Record" : "Save correction") {
                    guard let rating else { return }
                    Task {
                        let saved: Bool
                        if let reading { saved = await model.correct(id: reading.id, rating: rating) }
                        else { saved = await model.record(rating, source: .manual, at: date) }
                        if saved { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(rating == nil || model.isBusy)
            }
        }
        .padding(24)
        .frame(width: 380)
    }
}
