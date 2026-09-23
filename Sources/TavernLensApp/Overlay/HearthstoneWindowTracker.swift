import AppKit
import ApplicationServices
import CoreGraphics
import OverlayLayout

/// Where Hearthstone's window is, in top-left global coordinates.
struct HearthstoneWindow: Equatable {
    enum Source: Equatable {
        /// Accessibility: the real window frame and the fullscreen flag.
        case accessibility
        /// CGWindowList bounds (no permission needed), with fullscreen inferred from the screen.
        case windowList
    }

    var windowFrame: CGRect
    var mode: WindowMode
    var source: Source

    var contentFrame: CGRect { WindowGeometry.contentFrame(windowFrame: windowFrame, mode: mode) }
    var isFullscreen: Bool { mode == .fullscreen }
}

/// Finds Hearthstone's main window: CGWindowList by PID, refined by Accessibility when granted.
///
/// CGWindowList gives bounds without any permission, but can report a stale Mission Control
/// rect for a moment, and it can't tell fullscreen apart from a window that fills the screen.
/// Accessibility reports the real frame and `AXFullScreen`, so it wins when available.
@MainActor
enum HearthstoneWindowTracker {
    static func locate(pid: pid_t) -> HearthstoneWindow? {
        let listed = windowListFrame(pid: pid)
        if AXIsProcessTrusted(), let ax = accessibilityWindow(pid: pid) {
            // AX sometimes reports a helper window; trust it only if it's the size of the main one.
            if listed == nil || ax.frame.width * ax.frame.height >= 0.5 * (listed!.width * listed!.height) {
                let mode: WindowMode = ax.fullscreen ? .fullscreen : .windowed(titleBarHeight: titleBarHeight)
                return HearthstoneWindow(windowFrame: ax.frame, mode: mode, source: .accessibility)
            }
        }
        guard let listed else { return nil }
        return HearthstoneWindow(windowFrame: listed, mode: inferMode(listed), source: .windowList)
    }

    /// The standard title-bar height (the frame of a titled window minus its content).
    static let titleBarHeight: CGFloat = {
        let content = NSRect(x: 0, y: 0, width: 800, height: 600)
        return NSWindow.frameRect(forContentRect: content, styleMask: [.titled]).height - content.height
    }()

    /// The largest on-screen layer-0 window of the process. Hearthstone also owns a few
    /// thin or off-screen helper windows at layer 0.
    private static func windowListFrame(pid: pid_t) -> CGRect? {
        guard let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]]
        else { return nil }
        var best: CGRect?
        for window in info {
            guard (window[kCGWindowOwnerPID as String] as? pid_t) == pid,
                  (window[kCGWindowLayer as String] as? Int) == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary),
                  bounds.width >= 200, bounds.height >= 200
            else { continue }
            if best == nil || bounds.width * bounds.height > best!.width * best!.height {
                best = bounds
            }
        }
        return best
    }

    private static func accessibilityWindow(pid: pid_t) -> (frame: CGRect, fullscreen: Bool)? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        let window = element(app, kAXFocusedWindowAttribute) ?? element(app, kAXMainWindowAttribute)
            ?? firstWindow(app)
        guard let window else { return nil }
        guard let origin = value(window, kAXPositionAttribute, type: .cgPoint, as: CGPoint.self),
              let size = value(window, kAXSizeAttribute, type: .cgSize, as: CGSize.self)
        else { return nil }
        var fullscreen: CFTypeRef?
        AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &fullscreen)
        return (CGRect(origin: origin, size: size), (fullscreen as? Bool) ?? false)
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXUIElementGetTypeID()
        else { return nil }
        return (ref as! AXUIElement)
    }

    private static func firstWindow(_ app: AXUIElement) -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &ref) == .success,
              let windows = ref as? [AXUIElement]
        else { return nil }
        return windows.first
    }

    private static func value<T>(_ element: AXUIElement, _ attribute: String, type: AXValueType, as _: T.Type) -> T? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &ref) == .success,
              let ref, CFGetTypeID(ref) == AXValueGetTypeID()
        else { return nil }
        let axValue = ref as! AXValue
        return withUnsafeTemporaryAllocation(of: T.self, capacity: 1) { buffer -> T? in
            guard AXValueGetValue(axValue, type, buffer.baseAddress!) else { return nil }
            return buffer.baseAddress!.move()
        }
    }

    /// Without AX: fullscreen when the window fills the width and bottom of the screen it's on,
    /// starting at the top or just below the notch.
    private static func inferMode(_ frame: CGRect) -> WindowMode {
        guard let primaryHeight = NSScreen.screens.first?.frame.maxY else {
            return .windowed(titleBarHeight: titleBarHeight)
        }
        let screens = NSScreen.screens.map { screen in
            (frame: WindowGeometry.appKitRect(fromTopLeft: screen.frame, primaryScreenHeight: primaryHeight),
             topInset: screen.safeAreaInsets.top)
        }
        // appKitRect is its own inverse, so the same call converts AppKit screen frames to top-left.
        let screen = screens.max { $0.frame.intersection(frame).area < $1.frame.intersection(frame).area }
        guard let screen, !screen.frame.intersection(frame).isNull else {
            return .windowed(titleBarHeight: titleBarHeight)
        }
        return WindowGeometry.inferMode(
            windowFrame: frame, screenFrame: screen.frame, screenTopInset: screen.topInset,
            titleBarHeight: titleBarHeight
        )
    }
}

private extension CGRect {
    var area: CGFloat { isNull ? 0 : width * height }
}
