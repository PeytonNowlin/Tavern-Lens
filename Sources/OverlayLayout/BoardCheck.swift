import CoreGraphics

/// The once-per-game board-position check: at the first recruit phase, the screen reader
/// captures a small strip around each anchor (text Hearthstone draws on the board at a fixed
/// place) and compares where the text was found with where the layout puts it.
///
/// Two anchors far apart (the gold pill bottom right, the hero's health bottom centre) catch a
/// patch that moves or rescales the board, which the hero-pick banner alone can't show.
public struct BoardCheckMetrics: Hashable, Sendable {
    /// How much (in `h`) is captured around each anchor's text on every side, so moved text is
    /// still found (and measured).
    public var captureMargin: CGFloat = 0.03
    /// How far (in `h`) an anchor's text centre may sit from where it's predicted before the
    /// board counts as moved. The element rects are good to about ±0.004 h.
    public var alignmentTolerance: CGFloat = 0.012

    public init() {}
}

/// Text on the board at a fixed place, which the board check looks for.
public enum BoardAnchor: String, CaseIterable, Codable, Hashable, Sendable {
    /// "3/3" on the gold pill.
    case gold
    /// The local hero's health, on the portrait.
    case health

    /// Where the text is drawn.
    public var element: HSElement {
        switch self {
        case .gold: .goldPill
        case .health: .heroHealth
        }
    }

    /// Whether recognized text could be this anchor's.
    public func matches(_ text: String) -> Bool {
        let t = text.filter { !$0.isWhitespace }
        switch self {
        case .gold:
            let parts = t.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 2 && parts.allSatisfy { (1...2).contains($0.count) && $0.allSatisfy(\.isASCIIDigit) }
        case .health:
            return (1...2).contains(t.count) && t.allSatisfy(\.isASCIIDigit)
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool { ("0"..."9").contains(self) }
}

/// Where the board check found its anchors against where the layout predicts them.
public struct BoardAlignment: Hashable, Sendable, Codable {
    public struct Offset: Hashable, Sendable, Codable {
        public var anchor: BoardAnchor
        /// Found minus predicted centre, in units of `h` (positive: right, down).
        public var dx: Double
        public var dy: Double

        public init(anchor: BoardAnchor, dx: Double, dy: Double) {
            self.anchor = anchor
            self.dx = dx
            self.dy = dy
        }

        public var offset: Double { max(abs(dx), abs(dy)) }
    }

    /// The anchors found, in `BoardAnchor` order.
    public var offsets: [Offset]
    /// Every anchor found is within the tolerance: the board sits where the layout says.
    public var isAligned: Bool

    public init(offsets: [Offset], isAligned: Bool) {
        self.offsets = offsets
        self.isAligned = isAligned
    }

    /// The largest offset of any anchor found, in units of `h`.
    public var offset: Double { offsets.map(\.offset).max() ?? 0 }
}

extension OverlayLayout {
    /// Where an anchor's text is drawn.
    public func boardAnchor(_ anchor: BoardAnchor) -> CGRect { rect(anchor.element) }

    /// The strip captured for an anchor: its text with `captureMargin` on every side, kept
    /// inside the content, in whole points.
    public func boardCheckCapture(_ anchor: BoardAnchor) -> CGRect {
        let margin = constants.boardCheck.captureMargin * height
        return boardAnchor(anchor).insetBy(dx: -margin, dy: -margin).integral
            .intersection(CGRect(origin: .zero, size: size))
    }

    /// Checks the board against where its anchors' text was found (content-local points, as
    /// `boardAnchor`). Nil when none was found: no verdict.
    public func boardAlignment(found: [BoardAnchor: CGRect]) -> BoardAlignment? {
        let offsets = BoardAnchor.allCases.compactMap { anchor -> BoardAlignment.Offset? in
            guard let rect = found[anchor] else { return nil }
            let predicted = boardAnchor(anchor)
            return .init(
                anchor: anchor, dx: Double((rect.midX - predicted.midX) / height),
                dy: Double((rect.midY - predicted.midY) / height)
            )
        }
        guard !offsets.isEmpty else { return nil }
        let tolerance = Double(constants.boardCheck.alignmentTolerance)
        return BoardAlignment(offsets: offsets, isAligned: offsets.allSatisfy { $0.offset <= tolerance })
    }
}
