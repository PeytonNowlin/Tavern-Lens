import SwiftUI

/// The menu's screen-reading items: the permission (explained before macOS asks), the
/// on/off switch, the last reading and this game's alignment warning.
struct ScreenReadingMenuSection: View {
    @Bindable var reader: HeroPickScreenReader

    var body: some View {
        Group {
            if reader.permissionGranted {
                Toggle("Read Tribes from the Hero Pick", isOn: $reader.isEnabled)
                if reader.isEnabled, let status = reader.statusText {
                    Text(status)
                }
            } else {
                Button("Allow Screen Recording for Exact Tribes…") {
                    reader.requestPermission()
                }
            }
            if let warning = reader.alignmentWarning {
                Text("⚠︎ \(warning)")
            }
        }
        // It can be granted or revoked in System Settings at any time.
        .onAppear { reader.refreshPermission() }
    }
}
