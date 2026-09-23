import AppKit
import OverlayLayout
import Testing

/// The once-per-game board-position check: what it captures around each anchor, and how it
/// judges where the anchors' text was found.
@Suite("Board-position check")
struct BoardCheckLayoutTests {
    @Test("Each anchor's capture holds its text with margin, stays in the window and is small",
          arguments: ReferenceFrame.all)
    func capture(frame: ReferenceFrame) {
        let l = frame.layout
        let margin = 0.025 * l.height
        for anchor in BoardAnchor.allCases {
            let capture = l.boardCheckCapture(anchor)
            #expect(CGRect(origin: .zero, size: l.size).contains(capture), "\(anchor)")
            #expect(capture.insetBy(dx: margin, dy: margin).contains(l.boardAnchor(anchor)), "\(anchor)")
            #expect(capture == capture.integral)
            #expect(capture.width * capture.height < 0.02 * l.width * l.height, "\(anchor)")
        }
        // Far apart, so together they catch a rescale as well as a move.
        let gold = l.boardAnchor(.gold), health = l.boardAnchor(.health)
        #expect(hypot(gold.midX - health.midX, gold.midY - health.midY) > 0.2 * l.height)
    }

    @Test("The check passes the predicted anchors and catches a moved or rescaled board", arguments: ReferenceFrame.all)
    func alignment(frame: ReferenceFrame) throws {
        let l = frame.layout
        let h = l.height
        let predicted = Dictionary(uniqueKeysWithValues: BoardAnchor.allCases.map { ($0, l.boardAnchor($0)) })

        let exact = try #require(l.boardAlignment(found: predicted))
        #expect(exact.isAligned && exact.offset < 1e-9 && exact.offsets.map(\.anchor) == BoardAnchor.allCases)

        // Within the measurements' noise: still aligned.
        let jittered = predicted.mapValues { $0.offsetBy(dx: 0.005 * h, dy: -0.004 * h) }
        #expect(l.boardAlignment(found: jittered)?.isAligned == true)

        // A patch that moves the board down by 0.02 h.
        let moved = try #require(l.boardAlignment(found: predicted.mapValues { $0.offsetBy(dx: 0, dy: 0.02 * h) }))
        #expect(!moved.isAligned)
        expectNear(CGFloat(moved.offset), 0.02, 1e-9, "offset")
        #expect(moved.offsets.allSatisfy { abs($0.dy - 0.02) < 1e-9 && abs($0.dx) < 1e-9 })

        // A patch that scales the board by 110% about its top centre: the anchors low on the
        // screen move by ~0.03-0.09 h.
        func scaled(_ r: CGRect) -> CGRect {
            let s: CGFloat = 1.1
            let mid = CGPoint(x: l.centreX + (r.midX - l.centreX) * s, y: r.midY * s)
            return CGRect(x: mid.x - r.width * s / 2, y: mid.y - r.height * s / 2, width: r.width * s, height: r.height * s)
        }
        #expect(l.boardAlignment(found: predicted.mapValues(scaled))?.isAligned == false)

        // One anchor moved is enough; one anchor found still gives a verdict; none gives none.
        var oneMoved = predicted
        oneMoved[.gold] = predicted[.gold]!.offsetBy(dx: 0.02 * h, dy: 0)
        #expect(l.boardAlignment(found: oneMoved)?.isAligned == false)
        #expect(l.boardAlignment(found: [.health: predicted[.health]!])?.isAligned == true)
        #expect(l.boardAlignment(found: [:]) == nil)
    }

    @Test("Anchor text: gold as n/m, health as a number")
    func matching() {
        #expect(BoardAnchor.gold.matches("3/3") && BoardAnchor.gold.matches("10 / 10") && BoardAnchor.gold.matches("0/7"))
        #expect(!BoardAnchor.gold.matches("3") && !BoardAnchor.gold.matches("3/") && !BoardAnchor.gold.matches("a/3")
                && !BoardAnchor.gold.matches("100/10"))
        #expect(BoardAnchor.health.matches("30") && BoardAnchor.health.matches("7") && BoardAnchor.health.matches(" 12 "))
        #expect(!BoardAnchor.health.matches("") && !BoardAnchor.health.matches("100") && !BoardAnchor.health.matches("3/3"))
    }
}
