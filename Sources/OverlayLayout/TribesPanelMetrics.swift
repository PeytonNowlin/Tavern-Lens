import CoreGraphics

/// The lobby-tribes panel's type sizes and spacing, in reference points (multiplied by
/// `panelScale`).
///
/// A title row ("Tribes" and a status), then one row per tribe of the lobby: a confidence
/// dot, the tribe's name and, while it isn't confirmed, its percentage. Kept with the
/// layout so the panel's size can be checked against its widest content without drawing it.
public struct TribesPanelMetrics: Hashable, Sendable {
    public var titleFontSize: CGFloat = 10
    public var rowFontSize: CGFloat = 11
    public var percentFontSize: CGFloat = 10
    public var dotSize: CGFloat = 7
    /// Between the dot and the name.
    public var dotSpacing: CGFloat = 5
    /// Between the name and the percentage, at least.
    public var percentSpacing: CGFloat = 6
    public var rowSpacing: CGFloat = 2
    /// Between the title row and the first tribe.
    public var titleSpacing: CGFloat = 4
    /// Tribe rows shown: a lobby's worth.
    public var rows = 5
    public var padding = CGSize(width: 9, height: 6)
    public var cornerRadius: CGFloat = 10
    /// The panel's height (its width is the HUD's); `rows` rows must fit it (checked in the layout tests).
    public var height: CGFloat = 112

    public init() {}
}
