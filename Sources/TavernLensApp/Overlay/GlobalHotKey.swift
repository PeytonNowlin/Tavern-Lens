import Carbon.HIToolbox

/// A system-wide hotkey through Carbon's `RegisterEventHotKey`, which needs no
/// Accessibility or Input Monitoring permission and works while another app is frontmost.
@MainActor
final class GlobalHotKey {
    /// Shown in menus.
    let displayName: String
    private let action: @MainActor () -> Void
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let id: UInt32

    private static var nextID: UInt32 = 1

    /// `keyCode` is a virtual key code (`kVK_…`); `modifiers` are Carbon masks (`controlKey | optionKey`).
    init?(keyCode: Int, modifiers: Int, displayName: String, action: @escaping @MainActor () -> Void) {
        self.displayName = displayName
        self.action = action
        self.id = Self.nextID
        Self.nextID += 1

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var pressed = EventHotKeyID()
                GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &pressed
                )
                let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
                // Carbon delivers hotkey events on the main thread.
                return MainActor.assumeIsolated {
                    guard pressed.id == hotKey.id else { return OSStatus(eventNotHandledErr) }
                    hotKey.action()
                    return noErr
                }
            },
            1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler
        )
        guard status == noErr else { return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x544C_4E53), id: id)  // 'TLNS'
        let registered = RegisterEventHotKey(
            UInt32(keyCode), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &hotKey
        )
        guard registered == noErr else {
            if let handler { RemoveEventHandler(handler) }
            return nil
        }
    }

    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
