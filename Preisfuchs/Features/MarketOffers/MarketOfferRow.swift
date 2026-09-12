import SwiftUI
import PriceCore

/// Ein Angebot direkt von der Kette, ohne Produktbild.
///
/// Bilder aus den Prospekten zeigt die App bewusst nicht: Die Rechte daran
/// liegen bei den Ketten, und für Text und Preis reicht der Hinweis auf die
/// Quelle.
struct MarketOfferRow: View {

    let offer: RetailerOffer

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(offer.retailerName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.textSecondary)
                    if let brand = offer.brandLine {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                        Text(brand)
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                    }
                }

                Text(offer.displayName)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if let detail = detailLine {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                Text(validity)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            Spacer(minLength: Theme.Spacing.s)

            priceColumn
        }
        .padding(Theme.Spacing.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile,
                                                        style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var priceColumn: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if let price = offer.price {
                bigPrice(price)
                if let regular = offer.regularPrice {
                    oldPrice(regular)
                }
                if let percent = offer.discountPercent {
                    DealBadge(percentOff: percent)
                }
                // Der Kartenpreis steht nur daneben – nie an Stelle des
                // Preises, den jeder an der Kasse zahlt.
                if let card = offer.loyaltyPrice {
                    Text("Mit Kaufland Card \(card.roundedToCents.formatted())")
                        .font(.caption)
                        .foregroundStyle(Theme.deal)
                        .multilineTextAlignment(.trailing)
                }
            } else if let card = offer.loyaltyPrice {
                bigPrice(card)
                if let regular = offer.regularPrice {
                    oldPrice(regular)
                }
                Text("nur mit Kaufland Card")
                    .font(.caption)
                    .foregroundStyle(Theme.deal)
                if let percent = offer.loyaltyDiscountPercent {
                    DealBadge(percentOff: percent)
                }
            }

            if let deposit = offer.deposit {
                Text("zzgl. \(deposit.roundedToCents.formatted()) Pfand")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func bigPrice(_ money: Money) -> some View {
        Text(money.roundedToCents.formatted())
            .font(.system(size: 17, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(Theme.textPrimary)
    }

    private func oldPrice(_ money: Money) -> some View {
        HStack(spacing: 3) {
            if let label = offer.regularPriceLabel {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(money.roundedToCents.formatted())
                .font(.caption)
                .strikethrough()
                .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(offer.regularPriceLabel ?? "vorher") \(money.roundedToCents.formatted())")
    }

    private var detailLine: String? {
        let parts = [offer.unit, offer.basePriceText].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var validity: String {
        let formatter = Self.dayFormatter
        if offer.startsAfter(Date()) {
            return "ab \(formatter.string(from: offer.validFrom))"
        }
        guard let validTo = offer.validTo else {
            return "verfügbar seit \(formatter.string(from: offer.validFrom))"
        }
        return "gültig bis \(formatter.string(from: validTo))"
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = RetailerOffer.calendar.timeZone
        formatter.dateFormat = "EE, dd.MM."
        return formatter
    }()
}

/// Quellenhinweis unter den Angeboten der Ketten.
struct MarketOffersSourceNote: View {

    let sources: [MarketOffersStore.Source]
    let store: MarketOffersStore

    var body: some View {
        if !sources.isEmpty {
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var text: String {
        let parts = sources.map { source -> String in
            guard let fetchedAt = store.status(of: source).fetchedAt else { return source.host }
            let time = fetchedAt.formatted(.dateTime.hour().minute().locale(Locale(identifier: "de_DE")))
            return "\(source.host) (Stand \(time) Uhr)"
        }
        let list: String
        if parts.count > 1 {
            list = parts.dropLast().joined(separator: ", ") + " und " + (parts.last ?? "")
        } else {
            list = parts.first ?? ""
        }
        return "Direkt von \(list). Standardauswahl ohne gewählte Filiale – einzelne Märkte "
            + "können abweichen. Aktualisiert sich stündlich."
    }
}
