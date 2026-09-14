import SwiftUI
import PriceCore

/// „Preise nach Supermarkt“: jede eingeschaltete Kette mit dem günstigsten
/// Preis, den die App automatisch gefunden hat – samt Herkunft und Filiale.
///
/// Alle Preise kommen aus dem Internet: Angebote und Sortiment direkt von den
/// Ketten, die das zulassen, sonst die offene Preisdatenbank Open Prices.
/// REWE, EDEKA, PENNY, Netto und NORMA sperren automatische Abrufe; findet sich
/// dort nichts, sagt die Zeile das, statt einen Preis zu erfinden.
struct ChainPriceSection: View {

    let rows: [ProductDetailViewModel.ChainPrice]
    let onRoute: (Store) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Preise nach Supermarkt")

            if let cheapest = rows.first(where: { $0.isCurrent && $0.price != nil }) {
                cheapestCard(cheapest)
            }

            VStack(spacing: Theme.Spacing.s) {
                ForEach(rows) { row in
                    chainRow(row)
                }
            }

            Text("Automatisch aus dem Internet: Angebote von Kaufland, ALDI Nord, ALDI SÜD und "
                 + "Lidl (bei Lidl nur Getränke und Non-Food), Regalpreise aus dem ALDI-SÜD-"
                 + "Sortiment (täglich) und die offene Preisdatenbank Open Prices. Zugeordnet "
                 + "über Marke, Artikelname und Packungsgröße; einzelne Märkte können abweichen. "
                 + "REWE, EDEKA, PENNY, Netto und NORMA sperren automatische Abrufe.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Günstigster Supermarkt

    private func cheapestCard(_ row: ProductDetailViewModel.ChainPrice) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                HStack {
                    Text("Günstigster Supermarkt")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if case .marketOffer? = row.source {
                        dealBadge
                    }
                }

                if let price = row.price {
                    Text(price.roundedToCents.formatted())
                        .font(.priceDisplay(34))
                        .foregroundStyle(Theme.textPrimary)
                }

                Text(row.chainName)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)

                sourceLine(row)
                storeLine(row)

                if let store = row.nearestStore {
                    Button {
                        onRoute(store)
                    } label: {
                        Label("Route zur Filiale", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.cardTitle)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.m)
                            .background(Theme.accentFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Eine Kette

    private func chainRow(_ row: ProductDetailViewModel.ChainPrice) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.chainName)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                sourceLine(row)
                storeLine(row)
            }

            Spacer(minLength: Theme.Spacing.s)

            VStack(alignment: .trailing, spacing: 4) {
                if let price = row.price {
                    Text(price.roundedToCents.formatted())
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(row.isCurrent ? Theme.textPrimary : Theme.textSecondary)
                    if case .marketOffer? = row.source {
                        dealBadge
                    }
                    if let store = row.nearestStore {
                        Button("Route") { onRoute(store) }
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                            .buttonStyle(.plain)
                    }
                } else if let page = row.offersPage {
                    Link(destination: page) {
                        Label("Prospekt", systemImage: "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                    .accessibilityHint("Öffnet die Angebotsseite von \(row.chainName) im Browser")
                }
            }
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }

    private var dealBadge: some View {
        Label("Angebot", systemImage: "flame.fill")
            .font(.caption)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Spacing.s)
            .padding(.vertical, 2)
            .background(Theme.deal, in: Capsule())
    }

    private func sourceLine(_ row: ProductDetailViewModel.ChainPrice) -> some View {
        Text(Self.sourceText(row))
            .font(.caption)
            .foregroundStyle(Theme.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func storeLine(_ row: ProductDetailViewModel.ChainPrice) -> some View {
        if let store = row.nearestStore {
            Text(Self.storeText(row, store: store))
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Texte

    /// Woher der Preis stammt – so genau, dass man ihn nachprüfen kann.
    static func sourceText(_ row: ProductDetailViewModel.ChainPrice, now: Date = Date()) -> String {
        switch row.source {
        case .marketOffer(let offer, let viaVariety)?:
            var parts = ["Angebot laut \(host(of: offer))"]
            if let validTo = offer.validTo {
                parts.append("gültig bis \(dayFormatter.string(from: validTo))")
            } else {
                parts.append("verfügbar seit \(dayFormatter.string(from: offer.validFrom))")
            }
            if viaVariety {
                parts.append("für mehrere Sorten")
            }
            return parts.joined(separator: " · ")

        case .catalogPrice(let item, let viaVariety)?:
            var parts = ["Regalpreis laut \(host(of: item))",
                         "Stand \(dayFormatter.string(from: item.validFrom))"]
            if viaVariety {
                parts.append("für mehrere Sorten")
            }
            return parts.joined(separator: " · ")

        case .openPrices(let observation)?:
            var parts = ["Open Prices"]
            let city = observation.store?.city.flatMap { $0.isEmpty ? nil : $0 }
            if row.isRemote {
                parts.append("Preis aus \(city ?? "einer anderen Region")")
            } else if let city {
                parts.append(city)
            }
            let days = observation.ageInDays(asOf: now)
            parts.append(days <= 0 ? "heute" : (days == 1 ? "gestern" : "vor \(days) Tagen"))
            if observation.confidence(asOf: now) < .medium {
                parts.append("möglicherweise veraltet")
            }
            return parts.joined(separator: " · ")

        case nil:
            return row.hasDirectOffers
                ? "Kein passender Preis gefunden – weder im Angebot noch im Sortiment der Kette."
                : "Kein Preis gefunden – die Kette sperrt automatische Abrufe."
        }
    }

    /// Welche Filiale gemeint ist – und ob der Preis dort belegt ist.
    static func storeText(_ row: ProductDetailViewModel.ChainPrice, store: Store) -> String {
        var text = row.storeHasPrice ? "Filiale mit Beleg: " : "Nächste Filiale: "
        text += store.displayName
        if let meters = row.distanceMeters {
            text += " · " + GeoDistance.formatted(meters: meters)
        }
        if row.isRemote {
            text += " – Preis dort nicht belegt"
        }
        return text
    }

    private static func host(of offer: RetailerOffer) -> String {
        (offer.sourceURL.host ?? offer.retailerName)
            .replacingOccurrences(of: "www.", with: "")
            .replacingOccurrences(of: "filiale.", with: "")
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = RetailerOffer.calendar.timeZone
        formatter.dateFormat = "EE, dd.MM."
        return formatter
    }()
}
