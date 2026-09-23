import CoreGraphics

/// The odds section at the foot of the next-opponent preview, in reference points (multiplied
/// by `panelScale`).
///
/// Rows: win / tie / loss percentages on one line, a bar of the three, then a footnote (the
/// damage taken or dealt, a lethal warning, the simulations so far, or "no data"). Kept with the
/// layout so the section's size can be checked against its widest content without drawing it.
public struct OddsPreviewMetrics: Hashable, Sendable {
    public var percentFontSize: CGFloat = 10
    public var footnoteFontSize: CGFloat = 9
    public var barHeight: CGFloat = 3
    /// Between the win, tie and loss values.
    public var columnSpacing: CGFloat = 3
    public var rowSpacing: CGFloat = 3
    /// The section's height, added under the preview's board list (its width is the preview's);
    /// its rows must fit it (checked in the layout tests).
    public var height: CGFloat = 44

    public init() {}
}
