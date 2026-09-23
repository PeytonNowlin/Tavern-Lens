import CoreGraphics
import ScreenCaptureKit

/// Captures one small rect of Hearthstone's window with ScreenCaptureKit: a single still
/// of that window alone (not the display, so the overlay and other windows never appear
/// in it), cropped to the rect. Call only with Screen Recording granted
/// (`ScreenRecordingPermission.isGranted`); otherwise macOS would prompt.
enum BannerCapture {
    enum Failure: Error, CustomStringConvertible {
        case noPermission
        case windowNotFound
        case outsideWindow

        var description: String {
            switch self {
            case .noPermission: "Screen Recording isn't allowed"
            case .windowNotFound: "Hearthstone's window isn't on screen"
            case .outsideWindow: "the banner isn't inside Hearthstone's window"
            }
        }
    }

    /// - Parameters:
    ///   - pid: Hearthstone's process.
    ///   - rect: what to capture, in global top-left points (CGWindowList coordinates).
    /// - Returns: the image, at the display's pixel scale.
    static func capture(pid: pid_t, rect: CGRect) async throws -> CGImage {
        guard ScreenRecordingPermission.isGranted else { throw Failure.noPermission }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        // Hearthstone's main window: its largest layer-0 window (it owns a few small helpers too).
        let window = content.windows
            .filter { $0.owningApplication?.processID == pid && $0.windowLayer == 0 && $0.frame.width >= 200 }
            .max { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        guard let window else { throw Failure.windowNotFound }
        // The source rect of a single-window capture is relative to the window's top-left.
        let local = rect.offsetBy(dx: -window.frame.minX, dy: -window.frame.minY)
        guard CGRect(origin: .zero, size: window.frame.size).contains(local) else { throw Failure.outsideWindow }

        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        configuration.sourceRect = local
        configuration.width = max(1, Int((local.width * scale).rounded()))
        configuration.height = max(1, Int((local.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.captureResolution = .best
        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
