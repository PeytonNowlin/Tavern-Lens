import AppKit
import SwiftUI

/// The shared half of the offline QA preview renderers (`--render-*-preview`): reading
/// `flag input [output]` and `--scale`, and snapshotting a SwiftUI view to PNG. Each renderer
/// keeps only what is specific to it: what to decode and which view to draw.
enum PreviewRenderer {
    /// A preview command's own arguments, found after its flag.
    struct Arguments {
        let all: [String]
        let flag: String
        /// The file named right after the flag.
        let input: URL
        /// The PNG path after the input; nil when the command takes no output (interactive windows).
        let output: URL?

        init(_ arguments: [String], flag: String, writesOutput: Bool = true) throws {
            guard let index = arguments.firstIndex(of: flag),
                  arguments.count > index + (writesOutput ? 2 : 1) else {
                throw CocoaError(.fileReadInvalidFileName)
            }
            all = arguments
            self.flag = flag
            input = URL(filePath: arguments[index + 1])
            output = writesOutput ? URL(filePath: arguments[index + 2]) : nil
        }

        func contains(_ option: String) -> Bool { all.contains(option) }

        /// `--scale n`, clamped to the overlay's supported 0.8 to 1.6; 1 when absent or not a number.
        var scale: CGFloat {
            guard let i = all.firstIndex(of: "--scale"), all.count > i + 1,
                  let value = Double(all[i + 1]), value.isFinite else { return 1 }
            return min(1.6, max(0.8, value))
        }

        /// Writes the PNG to the output path.
        func writeOutput(_ png: Data) throws {
            guard let output else { throw CocoaError(.fileWriteUnknown) }
            try png.write(to: output)
        }
    }

    /// Runs `body`; on failure prints "<title> failed: …" and exits 1. A render that succeeds
    /// terminates the app itself.
    static func run(_ title: String, _ body: () throws -> Void) {
        do {
            try body()
        } catch {
            fail(title, error)
        }
    }

    static func fail(_ title: String, _ error: any Error) -> Never {
        fputs("\(title) failed: \(error)\n", stderr)
        exit(1)
    }

    /// Captures `content` in a hosting view, which (unlike `ImageRenderer`) includes native scroll
    /// views. Sized to `size`, or to the view's fitting size when nil.
    @MainActor
    static func hostingPNG<Content: View>(of content: Content, size: CGSize? = nil) throws -> Data {
        let hosting = NSHostingView(rootView: content)
        hosting.frame = CGRect(origin: .zero, size: size ?? hosting.fittingSize)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw CocoaError(.fileWriteUnknown)
        }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }

    /// Captures `content` with `ImageRenderer` at `scale`; for views without native scroll content.
    @MainActor
    static func imageRendererPNG<Content: View>(of content: Content, scale: CGFloat) throws -> Data {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        guard let image = renderer.nsImage?.tiffRepresentation,
              let png = NSBitmapImageRep(data: image)?.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return png
    }
}
