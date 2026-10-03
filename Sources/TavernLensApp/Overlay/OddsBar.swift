import SwiftUI

/// The win, tie and loss shares as one bar. Shared by the combat odds panel and the
/// next-opponent preview.
struct OddsBar: View {
    var won: Double
    var tied: Double
    var lost: Double

    var body: some View {
        GeometryReader { geometry in
            let total = max(won + tied + lost, 1)
            HStack(spacing: 0) {
                Rectangle().fill(.green.opacity(0.85)).frame(width: geometry.size.width * won / total)
                Rectangle().fill(.gray.opacity(0.6)).frame(width: geometry.size.width * tied / total)
                Rectangle().fill(.red.opacity(0.85)).frame(width: geometry.size.width * lost / total)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.1))
            .clipShape(Capsule())
        }
    }
}
