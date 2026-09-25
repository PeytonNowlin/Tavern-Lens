import SwiftUI
import TavernEngine

struct TrinketPickPanel: View {
    let pick: TrinketPickView
    let scale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 8 * scale) {
            Text("Choose a Trinket").font(.system(size: 15 * scale, weight: .bold))
            ForEach(Array(pick.offers.enumerated()), id: \.element.entityID) { index, offer in
                VStack(alignment: .leading, spacing: 2 * scale) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(index + 1). \(offer.name)").fontWeight(.semibold)
                        Spacer(minLength: 4)
                        Text(offer.rank.map { "#\($0) · \(offer.rating)" } ?? offer.rating)
                            .foregroundStyle(offer.rank == 1 ? Color.green : Color.secondary)
                    }
                    if let placement = offer.averagePlacement, let count = offer.sampleSize {
                        Text(String(format: "Avg. place %.2f · %d games", placement, count))
                            .font(.system(size: 10 * scale)).foregroundStyle(.secondary)
                    }
                    Text("\(offer.cost.map { "\($0) Gold · " } ?? "")\(offer.reason)")
                        .font(.system(size: 11 * scale)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.system(size: 12 * scale))
            }
            Text(pick.note).font(.system(size: 10 * scale)).foregroundStyle(.secondary)
        }
        .padding(12 * scale)
        .background(.black.opacity(0.9), in: RoundedRectangle(cornerRadius: 10 * scale))
        .overlay(RoundedRectangle(cornerRadius: 10 * scale).stroke(.white.opacity(0.2)))
    }
}
