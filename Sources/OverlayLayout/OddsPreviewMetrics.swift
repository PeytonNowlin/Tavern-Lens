import CoreGraphics

/// The odds section at the foot of the next-opponent preview, in reference points (multiplied
/// by `panelScale`).
///
/// Rows: win / tie / loss labels above their percentages, a bar, then the damage or lethal
/// warning. Kept with the layout so the section's size can be checked against its widest
/// content without drawing it.
public struct OddsPreviewMetrics: Hashable, Sendable {
    public var percentFontSize: CGFloat = 10
    public var footnoteFontSize: CGFloat = 9
    public var barHeight: CGFloat = 3
    /// Between the win, tie and loss values.
    public var columnSpacing: CGFloat = 3
    public var rowSpacing: CGFloat = 2
    /// The section's height, added under the preview's board list (its width is the preview's);
    /// its rows must fit it (checked in the layout tests).
    public var height: CGFloat = 58

    public init() {}

    /// These are effective point sizes, not reference sizes to multiply again.
    public func percentSize(at scale: CGFloat) -> CGFloat { max(11, percentFontSize * scale) }
    public func footnoteSize(at scale: CGFloat) -> CGFloat { max(11, footnoteFontSize * scale) }
    public func lineHeight(at scale: CGFloat) -> CGFloat { max(13, 13 * scale) }
}
