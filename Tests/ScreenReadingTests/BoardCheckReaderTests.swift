import AppKit
import CoreGraphics
import OverlayLayout
import ScreenReading
import Testing

/// The board check's reader on drawn frames: each anchor's text drawn where the layout puts it
/// (or moved), captured as the app would and read with Vision. It checks the reading and the
/// geometry, not the measured constants (those need a capture of a real recruit phase).
@Suite("Board-position check reader")
struct BoardCheckReaderTests {
    static let layout = OverlayLayout(contentSize: CGSize(width: 1710, height: 1073))!

    /// A dark 1710×1073 frame with `texts` drawn centred on the given content-local points.
    static func frame(_ texts: [(String, CGPoint, CGFloat)]) -> CGImage {
        let size = layout.size
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.12, green: 0.1, blue: 0.14, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        // Draw in a flipped context so points are top-left, y down, like the layout's.
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
        for (text, centre, fontSize) in texts {
            let string = NSAttributedString(string: text, attributes: [
                .font: NSFont.boldSystemFont(ofSize: fontSize), .foregroundColor: NSColor.white,
            ])
            let box = string.size()
            string.draw(at: CGPoint(x: centre.x - box.width / 2, y: centre.y - box.height / 2))
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()!
    }

    /// What the app would capture of `frame` for each anchor.
    static func captures(of frame: CGImage) -> [BoardAnchor: (image: CGImage, rect: CGRect)] {
        Dictionary(uniqueKeysWithValues: BoardAnchor.allCases.map { anchor in
            let rect = layout.boardCheckCapture(anchor)
            return (anchor, (frame.cropping(to: rect)!, rect))
        })
    }

    static func centre(_ anchor: BoardAnchor, shift: CGVector = .zero) -> CGPoint {
        let r = layout.boardAnchor(anchor)
        return CGPoint(x: r.midX + shift.dx * layout.height, y: r.midY + shift.dy * layout.height)
    }

    /// Glyph size about that of the game's text at this height.
    static let fontSize: CGFloat = 0.03 * 1073

    @Test("Text where the layout puts it reads as aligned, both anchors found")
    func aligned() throws {
        let image = Self.frame([
            ("3/3", Self.centre(.gold), Self.fontSize), ("30", Self.centre(.health), Self.fontSize),
            // The armor, also a number, just above the health: not taken for it.
            ("5", CGPoint(x: Self.layout.rect(.heroArmor).midX, y: Self.layout.rect(.heroArmor).midY), Self.fontSize),
        ])
        let result = try BoardCheckReader.read(Self.captures(of: image), layout: Self.layout)
        #expect(result.readings[.gold]?.found?.text.filter { !$0.isWhitespace } == "3/3")
        #expect(result.readings[.health]?.found?.text == "30")
        let alignment = try #require(result.alignment)
        #expect(alignment.offsets.map(\.anchor) == [.gold, .health])
        #expect(alignment.isAligned, "offsets \(alignment.offsets)")
    }

    @Test("A board a patch moved reads as misaligned, by about how far it moved")
    func moved() throws {
        let shift = CGVector(dx: 0.02, dy: 0.015)
        let image = Self.frame([
            ("7/7", Self.centre(.gold, shift: shift), Self.fontSize), ("24", Self.centre(.health, shift: shift), Self.fontSize),
        ])
        let alignment = try #require(try BoardCheckReader.read(Self.captures(of: image), layout: Self.layout).alignment)
        #expect(!alignment.isAligned)
        for offset in alignment.offsets {
            #expect(abs(offset.dx - 0.02) < 0.006 && abs(offset.dy - 0.015) < 0.006, "\(offset)")
        }
    }

    @Test("Nothing readable gives no verdict")
    func nothing() throws {
        let result = try BoardCheckReader.read(Self.captures(of: Self.frame([])), layout: Self.layout)
        #expect(result.alignment == nil)
    }
}
