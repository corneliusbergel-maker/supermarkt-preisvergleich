import SwiftUI
import PriceCore

/// Ein Angebot in der Deals-Liste der Startseite (#28).
struct DealRow: View {

    let deal: DealsViewModel.Deal

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.xs) {
                    if deal.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.accent)
                            .accessibilityLabel("Favorit")
                    }
                    Text(deal.product?.name ?? "Unbekanntes Produkt")
                        .font(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }

                HStack(spacing: Theme.Spacing.s) {
                    Text(deal.priced.observation.store?.displayName
                         ?? deal.priced.observation.retailer?.name
                         ?? "Unbekannter Markt")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)

                    if let meters = deal.distanceMeters {
                        Text("· \(GeoDistance.formatted(meters: meters))")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Text(deal.priced.observation.freshnessDescription())
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: Theme.Spacing.s)

            VStack(alignment: .trailing, spacing: 3) {
                Text(deal.price.roundedToCents.formatted())
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)

                // Ein Prozentwert steht nur da, wenn der Ursprungspreis
                // bekannt ist. Sonst nur die Tatsache "Angebot".
                if let percent = deal.priced.discountPercent {
                    DealBadge(percentOff: percent)
                } else {
                    Label("Angebot", systemImage: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.deal)
                }

                if let unitPrice = deal.unitPrice {
                    Text(unitPrice.formatted())
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile,
                                                        style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        )
    }

    private var thumbnail: some View {
        AsyncImage(url: deal.product?.imageURL) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFit()
            default:
                Image(systemName: "tag")
                    .font(.system(size: 18, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 48, height: 48)
        .background(Theme.surfaceRaised,
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
