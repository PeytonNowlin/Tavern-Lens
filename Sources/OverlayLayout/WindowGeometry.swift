import CoreGraphics

/// How Hearthstone's window is shown.
public enum WindowMode: Hashable, Sendable {
    /// Native macOS fullscreen: the window frame is the client area. On a notched Mac it
    /// is the area below the notch strip, not the whole screen.
    case fullscreen
    /// A titled window: the top `titleBarHeight` points of the frame are the title bar.
    case windowed(titleBarHeight: CGFloat)
}

/// Converting Hearthstone's window frame into the rect the overlay covers.
///
/// Window frames here are in global screen coordinates with the origin at the top-left
/// of the primary display and y pointing down, as CGWindowList and Accessibility report them.
public enum WindowGeometry {
    /// Hearthstone's client (content) area: the window frame minus the title bar when windowed.
    public static func contentFrame(windowFrame: CGRect, mode: WindowMode) -> CGRect {
        switch mode {
        case .fullscreen:
            return windowFrame
        case .windowed(let titleBar):
            let bar = min(max(titleBar, 0), windowFrame.height)
            return CGRect(
                x: windowFrame.minX, y: windowFrame.minY + bar,
                width: windowFrame.width, height: windowFrame.height - bar
            )
        }
    }

    /// Guesses the mode when Accessibility can't report `AXFullScreen`: a fullscreen window
    /// fills its screen's width and reaches its bottom, and starts at the screen's top or
    /// just below the notch strip (`screenTopInset`, the safe-area inset). All in top-left
    /// global coordinates.
    public static func inferMode(
        windowFrame: CGRect, screenFrame: CGRect, screenTopInset: CGFloat, titleBarHeight: CGFloat,
        tolerance: CGFloat = 1
    ) -> WindowMode {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= tolerance }
        let fillsWidth = near(windowFrame.minX, screenFrame.minX) && near(windowFrame.width, screenFrame.width)
        let reachesBottom = near(windowFrame.maxY, screenFrame.maxY)
        let startsAtTop = near(windowFrame.minY, screenFrame.minY)
            || near(windowFrame.minY, screenFrame.minY + screenTopInset)
        return fillsWidth && reachesBottom && startsAtTop ? .fullscreen : .windowed(titleBarHeight: titleBarHeight)
    }

    /// Converts a top-left global rect to AppKit's bottom-left global coordinates.
    /// `primaryScreenHeight` is the height of the display with the menu bar (`NSScreen.screens[0]`).
    public static func appKitRect(fromTopLeft rect: CGRect, primaryScreenHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryScreenHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Converts a point in AppKit global coordinates (such as `NSEvent.mouseLocation`) to a
    /// point local to `contentFrame` (top-left global), with y pointing down.
    public static func localPoint(
        fromAppKit point: CGPoint, contentFrame: CGRect, primaryScreenHeight: CGFloat
    ) -> CGPoint {
        CGPoint(x: point.x - contentFrame.minX, y: primaryScreenHeight - point.y - contentFrame.minY)
    }
}
