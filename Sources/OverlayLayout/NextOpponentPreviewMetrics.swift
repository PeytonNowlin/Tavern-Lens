import CoreGraphics

/// Effective point sizes for the compact scouting panel. Text stops shrinking before the
/// panel does; the two-line header and tightly grouped board keep seven minions in its bounds.
public struct NextOpponentPreviewMetrics: Hashable, Sendable {
    public let headerFontSize: CGFloat
    public let bodyFontSize: CGFloat
    public let headerHeight: CGFloat
    public let rowHeight: CGFloat
    public let padding: CGSize
    public let rowSpacing: CGFloat
    public let cardSpacing: CGFloat

    public init(scale: CGFloat) {
        headerFontSize = max(12, 12.5 * scale)
        bodyFontSize = max(11, 10.5 * scale)
        headerHeight = max(15, 16 * scale)
        rowHeight = max(13, 14 * scale)
        padding = CGSize(width: 8 * scale, height: 4 * scale)
        rowSpacing = 2 * scale
        cardSpacing = 2 * scale
    }
}
