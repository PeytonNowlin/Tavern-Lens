import BGIntel
import CoreGraphics
import OverlayLayout
import Vision

/// What the hero-pick banner said, and where it was.
public struct HeroPickBannerReading: Hashable, Sendable {
    /// Every line recognized in the capture.
    public var lines: [RecognizedLine]
    /// "Choose a Hero", if found.
    public var title: RecognizedLine?
    /// The tribes listed under the title, however sure.
    public var tribes: ScreenTribeReading?
    /// Where the title was found against the layout; nil when it wasn't found.
    public var alignment: BannerAlignment?

    public init(
        lines: [RecognizedLine], title: RecognizedLine?, tribes: ScreenTribeReading?, alignment: BannerAlignment?
    ) {
        self.lines = lines
        self.title = title
        self.tribes = tribes
        self.alignment = alignment
    }

    /// The lowest confidence a reading is trusted at.
    public static let minimumConfidence = 0.6

    /// The tribes when the reading can be trusted: every tribe of the lobby, read clearly.
    /// Anything less is left to the log's inference.
    public var trustedTribes: ScreenTribeReading? {
        guard let tribes, tribes.isComplete, tribes.confidence >= Self.minimumConfidence else { return nil }
        return tribes
    }
}

/// Reads the hero-pick banner from a capture of `OverlayLayout.heroPickCapture`: Vision
/// text recognition, then the tribe parser and the alignment check. It needs no
/// permission (the capture is someone else's job), so it runs on saved images in tests.
public enum HeroPickBannerReader {
    /// Recognizes and interprets the banner.
    /// - Parameters:
    ///   - image: the capture, at any pixel scale.
    ///   - capturedRect: what the image shows, in content-local points (normally `layout.heroPickCapture`).
    ///   - expectedTribes: tribes per lobby.
    public static func read(
        _ image: CGImage, capturedRect: CGRect, layout: OverlayLayout, expectedTribes: Int = 5
    ) throws -> HeroPickBannerReading {
        let lines = try recognizeLines(in: image, showing: capturedRect)
        return interpret(lines, layout: layout, expectedTribes: expectedTribes)
    }

    /// Vision's lines, placed in content-local points.
    public static func recognizeLines(in image: CGImage, showing rect: CGRect) throws -> [RecognizedLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // The banner's words aren't a sentence; the parser corrects them against the tribe names.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            // Vision's box is normalized with a bottom-left origin.
            let box = observation.boundingBox
            let placed = CGRect(
                x: rect.minX + box.minX * rect.width, y: rect.minY + (1 - box.maxY) * rect.height,
                width: box.width * rect.width, height: box.height * rect.height
            )
            return RecognizedLine(text: candidate.string, confidence: Double(candidate.confidence), rect: placed)
        }
    }

    /// The title, the tribes under it and the alignment check, from recognized lines.
    public static func interpret(
        _ lines: [RecognizedLine], layout: OverlayLayout, expectedTribes: Int = 5
    ) -> HeroPickBannerReading {
        let title = lines.filter { BannerTribeParser.isTitle($0.text) }.max { $0.confidence < $1.confidence }
        let tribeLines: [RecognizedLine]
        if let title {
            // The list starts under the title and is centred on it.
            tribeLines = lines.filter { $0 != title && $0.rect.midY > title.rect.maxY - title.rect.height * 0.25 }
        } else {
            // No title (another language, or a partial capture): lines where the list should be.
            let area = layout.heroPickTribes.insetBy(dx: -0.03 * layout.height, dy: -0.03 * layout.height)
            tribeLines = lines.filter { area.contains(CGPoint(x: $0.rect.midX, y: $0.rect.midY)) }
        }
        let ordered = tribeLines.sorted { ($0.rect.minY, $0.rect.minX) < ($1.rect.minY, $1.rect.minX) }
        return HeroPickBannerReading(
            lines: lines, title: title,
            tribes: BannerTribeParser.tribes(in: ordered, expectedCount: expectedTribes),
            alignment: title.map { layout.alignment(ofTitleFoundAt: $0.rect) }
        )
    }
}
