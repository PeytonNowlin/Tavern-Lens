import AppKit
import OverlayLayout
import SwiftUI

/// The transparent panel laid over Hearthstone's client area.
///
/// Borderless and non-activating, so clicking it never takes focus from Hearthstone; one level
/// above normal windows, so it sits just over the game but under menus and Notification Center;
/// on every Space and allowed next to fullscreen apps. It's click-through unless the cursor is
/// over one of its interactive regions (see `OverlayController`).
final class OverlayPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.normalWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Takes the first click even though the panel is never key, so buttons work in one click.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A native behind-window blur for the overlay's panels: dark HUD material, rounded.
extension View {
    /// The dark translucent panel look every overlay panel shares: the HUD material with a
    /// hairline outline. `border` and `borderWidth` override the outline for a panel that flags
    /// something (the combat odds panel's lethal risk).
    func hudPanel(cornerRadius: CGFloat, border: Color? = nil, borderWidth: CGFloat? = nil) -> some View {
        let chrome = LayoutConstants.current.panelChrome
        return background(HUDMaterial(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(border ?? .white.opacity(chrome.strokeOpacity), lineWidth: borderWidth ?? chrome.strokeWidth)
            )
    }
}

extension Color {
    init(_ rgb: RGB) { self.init(red: rgb.red, green: rgb.green, blue: rgb.blue) }
}

struct HUDMaterial: NSViewRepresentable {
    var cornerRadius: CGFloat

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.maskImage = Self.mask(cornerRadius: cornerRadius)
    }

    /// A resizable rounded-rect mask; `layer.cornerRadius` doesn't clip a behind-window blur.
    private static func mask(cornerRadius r: CGFloat) -> NSImage {
        let edge = 2 * r + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: r, yRadius: r).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: r, left: r, bottom: r, right: r)
        image.resizingMode = .stretch
        return image
    }
}
