import BGIntel
import CoreGraphics
import Foundation
import HSData
import ImageIO
import OverlayLayout
import ScreenReading
import Testing

/// The player's own hero-pick capture (patch 36.6.1), cropped to the banner. No names, no
/// other UI: `Tests/Fixtures/Screen/hero-pick-banner-36.6.1.png`.
///
/// The source (U3 in `docs/research/overlay-coordinates.md` §8a) is a crop of the
/// 1710×1073 fullscreen frame, registered to the full-frame U4 (2000×1255 px) by
/// `U4 = 0.9599 · U3 + (18.3, 17.5)`. The fixture is U3's pixels from (770, 45), 505×260.
/// So in the fixture's pixels Hearthstone's content area is the rect below, and a layout
/// of that size says where the capture falls in it.
enum BannerFixture {
    static let url = URL(filePath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "Fixtures/Screen/hero-pick-banner-36.6.1.png")

    static let scale = 0.9599, offset = CGPoint(x: 18.3, y: 17.5), crop = CGPoint(x: 770, y: 45)
    /// Hearthstone's content area in fixture pixels.
    static let content = CGRect(
        x: -offset.x / scale - crop.x, y: -offset.y / scale - crop.y, width: 2000 / scale, height: 1255 / scale
    )
    static let layout = OverlayLayout(contentSize: content.size)!
    static let tribes: [HS.Race] = [.aberration, .demon, .elemental, .murloc, .quilboar]

    static let image: CGImage = {
        let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
        return CGImageSourceCreateImageAtIndex(source, 0, nil)!
    }()

    /// What a capture of `rect` (content-local) would return, cut from the fixture.
    static func capture(_ rect: CGRect, pixelScale: CGFloat = 1) -> CGImage {
        let inImage = rect.offsetBy(dx: content.minX, dy: content.minY).integral
        let cut = image.cropping(to: inImage)!
        guard pixelScale != 1 else { return cut }
        let size = CGSize(width: (CGFloat(cut.width) * pixelScale).rounded(), height: (CGFloat(cut.height) * pixelScale).rounded())
        let context = CGContext(
            data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.interpolationQuality = .high
        context.draw(cut, in: CGRect(origin: .zero, size: size))
        return context.makeImage()!
    }
}

@Suite("Hero-pick banner on the player's capture")
struct HeroPickBannerTests {
    @Test("The capture rect of the layout falls inside the fixture, around the title and tribes")
    func geometry() {
        let l = BannerFixture.layout
        let image = CGRect(x: 0, y: 0, width: BannerFixture.image.width, height: BannerFixture.image.height)
        let capture = l.heroPickCapture.offsetBy(dx: BannerFixture.content.minX, dy: BannerFixture.content.minY)
        #expect(image.contains(capture))
        #expect(l.heroPickCapture.contains(l.heroPickTitle))
        #expect(l.heroPickCapture.contains(l.heroPickTribes))
    }

    @Test("Vision reads the lobby's tribes, and the layout is aligned")
    func readsTribes() throws {
        let l = BannerFixture.layout
        let reading = try HeroPickBannerReader.read(
            BannerFixture.capture(l.heroPickCapture), capturedRect: l.heroPickCapture, layout: l
        )
        let tribes = try #require(reading.trustedTribes, "lines: \(reading.lines.map(\.text))")
        #expect(tribes.tribes == BannerFixture.tribes)
        #expect(tribes.isComplete)
        #expect(tribes.confidence >= 0.9)
        let alignment = try #require(reading.alignment)
        #expect(alignment.isAligned, "\(alignment)")
        #expect(alignment.offset < 0.006, "\(alignment)")
        #expect(abs(alignment.widthRatio - 1) < 0.05, "\(alignment)")
    }

    @Test("It still reads at a lower pixel scale (a small 1x window)", arguments: [0.6, 1.6])
    func pixelScale(scale: Double) throws {
        let l = BannerFixture.layout
        let image = BannerFixture.capture(l.heroPickCapture, pixelScale: scale)
        let reading = try HeroPickBannerReader.read(image, capturedRect: l.heroPickCapture, layout: l)
        #expect(reading.trustedTribes?.tribes == BannerFixture.tribes, "lines: \(reading.lines.map(\.text))")
        #expect(reading.alignment?.isAligned == true)
    }

    @Test("A banner a patch moved is still read, and the alignment check catches the move")
    func movedBanner() throws {
        let l = BannerFixture.layout
        // The game draws the banner 0.025 h further left and 0.02 h higher than the layout says:
        // the capture of the predicted rect shows what's actually at predicted + (0.025, 0.02) h.
        let shift = CGVector(dx: 0.025 * l.height, dy: 0.02 * l.height)
        let image = BannerFixture.capture(l.heroPickCapture.offsetBy(dx: shift.dx, dy: shift.dy))
        let reading = try HeroPickBannerReader.read(image, capturedRect: l.heroPickCapture, layout: l)
        #expect(reading.trustedTribes?.tribes == BannerFixture.tribes)
        let alignment = try #require(reading.alignment)
        #expect(!alignment.isAligned)
        #expect(abs(alignment.dx + 0.025) < 0.006, "\(alignment)")
        #expect(abs(alignment.dy + 0.02) < 0.006, "\(alignment)")
    }

    @Test("Only the title in view: no tribes, nothing trusted")
    func titleOnly() throws {
        let l = BannerFixture.layout
        let title = l.heroPickTitle.insetBy(dx: -0.01 * l.height, dy: -0.006 * l.height)
        let reading = try HeroPickBannerReader.read(BannerFixture.capture(title), capturedRect: title, layout: l)
        #expect(reading.title != nil)
        #expect(reading.trustedTribes == nil)
    }

    /// Capture itself isn't exercised here (it needs Screen Recording and the real screen);
    /// the app logs each capture's time. This measures recognition, the bulk of the work.
    @Test("Recognition is fast enough to run during the hero pick")
    func latency() throws {
        let l = BannerFixture.layout
        let image = BannerFixture.capture(l.heroPickCapture, pixelScale: 1.6)
        let clock = ContinuousClock()
        var times: [Duration] = []
        for _ in 0..<6 {
            let start = clock.now
            _ = try HeroPickBannerReader.read(image, capturedRect: l.heroPickCapture, layout: l)
            times.append(clock.now - start)
        }
        let first = times[0], warm = times.dropFirst().sorted()[2]
        print("Banner OCR (\(image.width)×\(image.height) px): first \(first), warm median \(warm)")
        // The first call loads Vision's models (about 0.25–0.35 s alone, several seconds while the
        // rest of the suite runs in parallel), once per app launch. Warm calls are about 30 ms alone;
        // the bound is loose for a loaded machine.
        #expect(warm < .milliseconds(500))
    }
}

@Suite("Banner text to tribes")
struct BannerTribeParserTests {
    static func lines(_ texts: String..., confidence: Double = 1) -> [RecognizedLine] {
        texts.map { RecognizedLine(text: $0, confidence: confidence) }
    }

    @Test("The banner's three lines give the lobby, in order, complete and sure")
    func exact() throws {
        let reading = try #require(BannerTribeParser.tribes(in: Self.lines(
            "Aberrations, Demons,", "Elementals, Murlocs,", "Quilboar"
        )))
        #expect(reading.tribes == BannerFixture.tribes)
        #expect(reading.isComplete)
        #expect(reading.confidence == 1)
    }

    @Test("Misread letters are corrected, at some cost in confidence")
    func misread() throws {
        // Vision's fast mode on the fixture.
        let reading = try #require(BannerTribeParser.tribes(in: Self.lines(
            "Aberratlons. Demons.", "Elementats. Murlocs.", "Qufilboar"
        )))
        #expect(reading.tribes == BannerFixture.tribes)
        #expect(reading.isComplete)
        #expect(reading.confidence < 1 && reading.confidence >= HeroPickBannerReading.minimumConfidence)
    }

    @Test("Every tribe name, singular or plural, including Mechs")
    func vocabulary() throws {
        let reading = try #require(BannerTribeParser.tribes(
            in: Self.lines("Beasts, Dragons, Mechs,", "Pirates, Undead, Naga"), expectedCount: 6
        ))
        #expect(reading.tribes == [.beast, .dragon, .mechanical, .pirate, .undead, .naga])
        #expect(reading.isComplete)
    }

    @Test("A partial list is incomplete; a line's low confidence caps the reading")
    func partial() throws {
        let reading = try #require(BannerTribeParser.tribes(in: Self.lines("Aberrations, Demons,", confidence: 0.4)))
        #expect(reading.tribes == [.aberration, .demon])
        #expect(!reading.isComplete)
        #expect(reading.confidence <= 0.4)
    }

    @Test("Text that isn't a tribe list gives nothing, or a reading too weak to trust")
    func noise() {
        #expect(BannerTribeParser.tribes(in: Self.lines("Choose a Hero", "Confirm")) == nil)
        #expect(BannerTribeParser.tribes(in: Self.lines("")) == nil)
        let mixed = BannerTribeParser.tribes(in: Self.lines("Demons wreck the tavern tonight, friend"))
        #expect(mixed.map { $0.confidence < HeroPickBannerReading.minimumConfidence } ?? true)
    }

    @Test("The title is recognized with a few misread letters, and nothing else is")
    func title() {
        #expect(BannerTribeParser.isTitle("Choose a Hero"))
        #expect(BannerTribeParser.isTitle("\"Choose a Hero '"))
        #expect(BannerTribeParser.isTitle("Choase a Her0"))
        #expect(!BannerTribeParser.isTitle("Aberrations, Demons,"))
        #expect(!BannerTribeParser.isTitle("Confirm"))
    }

    @Test("Only a complete, confident reading is trusted")
    func trust() {
        func reading(_ tribes: ScreenTribeReading?) -> HeroPickBannerReading {
            HeroPickBannerReading(lines: [], title: nil, tribes: tribes, alignment: nil)
        }
        #expect(reading(ScreenTribeReading(tribes: BannerFixture.tribes, confidence: 0.9)).trustedTribes != nil)
        #expect(reading(ScreenTribeReading(tribes: BannerFixture.tribes, confidence: 0.5)).trustedTribes == nil)
        #expect(reading(ScreenTribeReading(tribes: [.demon], isComplete: false)).trustedTribes == nil)
        #expect(reading(nil).trustedTribes == nil)
    }
}
