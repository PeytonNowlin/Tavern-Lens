import HSLog
import SwiftUI
import TavernEngine

/// Disk-use limits: Hearthstone's log sessions, saved replays, the Power.log size
/// hint and the art cache. Changes are saved at once and apply to the next cleanup.
struct SettingsWindow: View {
    @Bindable var model: RetentionSettingsModel
    let housekeeping: HousekeepingModel

    var body: some View {
        Form {
            Section("Hearthstone logs") {
                Stepper(value: $model.settings.maxSessions, in: 1...200) {
                    LabeledContent("Sessions to keep", value: "\(model.settings.maxSessions)")
                }
                Stepper(value: gigabytes(\.maxLogBytes), in: 0.5...100, step: 0.5) {
                    LabeledContent("Size cap", value: ByteSize.format(model.settings.maxLogBytes))
                }
                Text("Old session folders are deleted, oldest first, at launch and after each game. "
                    + "The one Hearthstone is writing and any with games not yet recorded are never deleted.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper(value: megabytes(\.powerLogHintBytes), in: 100...10_000, step: 100) {
                    LabeledContent("Suggest a restart when Power.log reaches", value: ByteSize.format(model.settings.powerLogHintBytes))
                }
            }
            Section("Replays") {
                Toggle("Keep each game's log, compressed, for replay", isOn: $model.settings.keepReplays)
                Stepper(value: $model.settings.maxReplays, in: 0...1000, step: 5) {
                    LabeledContent("Games to keep", value: "\(model.settings.maxReplays)")
                }
            }
            Section("Caches") {
                Stepper(value: gigabytes(\.maxArtCacheBytes), in: 0.25...20, step: 0.25) {
                    LabeledContent("Card art cache", value: ByteSize.format(model.settings.maxArtCacheBytes))
                }
                Stepper(value: $model.settings.previousCardDataBuilds, in: 0...10) {
                    LabeledContent(
                        "Card data for earlier builds",
                        value: model.settings.previousCardDataBuilds == 1 ? "1 build" : "\(model.settings.previousCardDataBuilds) builds"
                    )
                }
            }
            Section {
                HStack {
                    Text(housekeeping.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clean Up Now") { housekeeping.run() }
                        .disabled(housekeeping.isRunning)
                    Button("Restore Defaults") { model.resetToDefaults() }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 460, idealWidth: 500, minHeight: 440)
    }

    private func gigabytes(_ keyPath: WritableKeyPath<RetentionSettings, Int64>) -> Binding<Double> {
        scaled(keyPath, unit: ByteSize.gigabyte)
    }

    private func megabytes(_ keyPath: WritableKeyPath<RetentionSettings, Int64>) -> Binding<Double> {
        scaled(keyPath, unit: ByteSize.megabyte)
    }

    private func scaled(_ keyPath: WritableKeyPath<RetentionSettings, Int64>, unit: Int64) -> Binding<Double> {
        Binding(
            get: { Double(model.settings[keyPath: keyPath]) / Double(unit) },
            set: { model.settings[keyPath: keyPath] = Int64(($0 * Double(unit)).rounded()) }
        )
    }
}
