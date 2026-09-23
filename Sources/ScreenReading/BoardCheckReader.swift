import CoreGraphics
import OverlayLayout

/// Reads the board check's captures (`OverlayLayout.boardCheckCapture`): finds each anchor's
/// text and checks the layout against where it was. Like `HeroPickBannerReader`, it needs no
/// permission, so it runs on saved or drawn images in tests.
public enum BoardCheckReader {
    /// What one anchor's capture showed.
    public struct Reading: Hashable, Sendable {
        /// Every line recognized in the capture.
        public var lines: [RecognizedLine]
        /// The line taken as the anchor's text, if any.
        public var found: RecognizedLine?
    }

    /// Recognizes each anchor's capture and checks the board.
    /// - Parameter captures: per anchor, the image and what it shows (content-local points,
    ///   normally `layout.boardCheckCapture(anchor)`).
    /// - Returns: each anchor's reading, and the check (nil when no anchor was found).
    public static func read(
        _ captures: [BoardAnchor: (image: CGImage, rect: CGRect)], layout: OverlayLayout
    ) throws -> (readings: [BoardAnchor: Reading], alignment: BoardAlignment?) {
        var readings: [BoardAnchor: Reading] = [:]
        for (anchor, capture) in captures {
            let lines = try HeroPickBannerReader.recognizeLines(in: capture.image, showing: capture.rect)
            readings[anchor] = Reading(lines: lines, found: find(anchor, in: lines, layout: layout))
        }
        let found = readings.compactMapValues { $0.found?.rect }
        return (readings, layout.boardAlignment(found: found))
    }

    /// The anchor's text among recognized lines: the matching line nearest where it's predicted
    /// (the hero's armor, also a number, can be in the health's capture).
    public static func find(_ anchor: BoardAnchor, in lines: [RecognizedLine], layout: OverlayLayout) -> RecognizedLine? {
        let predicted = layout.boardAnchor(anchor)
        func distance(_ line: RecognizedLine) -> CGFloat {
            hypot(line.rect.midX - predicted.midX, line.rect.midY - predicted.midY)
        }
        return lines
            .filter { anchor.matches($0.text) && $0.confidence >= HeroPickBannerReading.minimumConfidence }
            .min { distance($0) < distance($1) }
    }
}
