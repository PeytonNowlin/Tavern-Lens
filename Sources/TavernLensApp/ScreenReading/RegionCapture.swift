import CoreGraphics
import OverlayLayout
import ScreenCaptureKit

/// Why a screen read got no image. The one place the find-window, layout and capture steps
/// report failure, so every reader can say why (and notice a revoked Screen Recording grant).
enum RegionCaptureFailure: Error, Equatable, CustomStringConvertible {
    case noPermission
    /// Hearthstone has no process or no window we can find.
    case windowNotFound
    /// The window is too small to lay out.
    case layoutUnavailable
    case outsideWindow
    case captureFailed(String)

    init(_ error: Error) {
        switch error as? BannerCapture.Failure {
        case .noPermission: self = .noPermission
        case .windowNotFound: self = .windowNotFound
        case .outsideWindow: self = .outsideWindow
        case nil: self = .captureFailed(String(describing: error))
        }
    }

    var description: String {
        switch self {
        case .noPermission: BannerCapture.Failure.noPermission.description
        case .windowNotFound: "Hearthstone's window wasn't found"
        case .layoutUnavailable: "Hearthstone's window is too small to read"
        case .outsideWindow: BannerCapture.Failure.outsideWindow.description
        case .captureFailed(let why): why
        }
    }
}

/// Hearthstone's window as the screen readers need it: where it is and how it's laid out.
struct HearthstoneRegionContext {
    let pid: pid_t
    let window: HearthstoneWindow
    let layout: OverlayLayout

    /// Finds the window (off the main actor) and its layout.
    static func locate(pid: pid_t?) async -> Result<HearthstoneRegionContext, RegionCaptureFailure> {
        guard let pid, let window = await HearthstoneWindowTracker.shared.locate(pid: pid) else {
            return .failure(.windowNotFound)
        }
        guard let layout = OverlayLayout(contentSize: window.contentFrame.size) else {
            return .failure(.layoutUnavailable)
        }
        return .success(HearthstoneRegionContext(pid: pid, window: window, layout: layout))
    }

    /// Captures `rect`, given in layout coordinates (relative to the window's client area).
    /// Pass `shareable` to reuse one `BannerCapture.shareableContent()` across several regions.
    func captureRegion(_ rect: CGRect, shareable: SCShareableContent? = nil) async -> Result<CGImage, RegionCaptureFailure> {
        let content = window.contentFrame
        do {
            let image = try await BannerCapture.capture(
                pid: pid, rect: rect.offsetBy(dx: content.minX, dy: content.minY), content: shareable
            )
            return .success(image)
        } catch {
            return .failure(RegionCaptureFailure(error))
        }
    }
}
