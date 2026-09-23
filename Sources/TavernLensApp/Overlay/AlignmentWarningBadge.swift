import OverlayLayout
import SwiftUI

/// "⚠︎ Overlay misaligned": this game's alignment check found the hero-pick banner away from
/// where the layout puts it. Under the tribes panel; the menu has the details.
struct AlignmentWarningBadge: View {
    let text: String
    let scale: CGFloat
    let layout: OverlayLayout

    var body: some View {
        let m = layout.constants.heroPickBanner
        let rect = layout.alignmentWarning
        Text(text)
            .font(.system(size: m.warningFontSize * scale, weight: .semibold))
            .foregroundStyle(.orange)
            .lineLimit(1)
            .padding(.horizontal, layout.constants.tribesPanel.padding.width * scale)
            .frame(width: rect.width, height: rect.height, alignment: .leading)
            .background(HUDMaterial(cornerRadius: rect.height / 2))
            .overlay(Capsule().strokeBorder(.orange.opacity(0.35), lineWidth: 0.5))
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }
}
