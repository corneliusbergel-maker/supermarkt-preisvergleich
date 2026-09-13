import SwiftUI
import PriceCore

/// „Preise nach Supermarkt“: jede eingeschaltete Kette mit dem günstigsten
/// bekannten Preis für dieses Produkt – samt Herkunft und nächster Filiale.
///
/// Für REWE, EDEKA, PENNY, Netto und NORMA – und für Lebensmittel bei Lidl –
/// gibt es keinen erlaubten automatischen Abruf. Ihre Preise kommen von
/// Menschen, die sie bei Open Prices eintragen. Die Zeile sagt das, statt still
/// leer zu bleiben.
struct ChainPriceSection: View {

    let rows: [ProductDetailViewModel.ChainPrice]
    let canContribute: Bool
    let onRoute: (Store) -> Void
    let onContribute: () -> Void

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

            Text("Kaufland, ALDI Nord, ALDI SÜD und Lidl: Angebote direkt von der Kette – bei "
                 + "Lidl nur Getränke und Non-Food aus dem Prospekt –, über Marke, Artikelname "
                 + "und Packungsgröße zugeordnet; einzelne Märkte können abweichen. Alle anderen "
                 + "Preise haben Menschen bei Open Prices eingetragen – für REWE, EDEKA, PENNY, "
                 + "Netto, NORMA und Lebensmittel bei Lidl ist das der einzige erlaubte Weg.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if canContribute {
                Button(action: onContribute) {
                    Label("Preis aus dem Markt beitragen", systemImage: "plus.viewfinder")
                        .font(.cardBody)
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }
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
            let host = (offer.sourceURL.host ?? offer.retailerName)
                .replacingOccurrences(of: "www.", with: "")
                .replacingOccurrences(of: "filiale.", with: "")
            var parts = ["Angebot laut \(host)"]
            if let validTo = offer.validTo {
                parts.append("gültig bis \(dayFormatter.string(from: validTo))")
            } else {
                parts.append("verfügbar seit \(dayFormatter.string(from: offer.validFrom))")
            }
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
                ? "Gerade kein passendes Angebot und noch kein eingetragener Preis."
                : "Noch kein Preis bekannt – bisher hat ihn niemand eingetragen."
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

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = RetailerOffer.calendar.timeZone
        formatter.dateFormat = "EE, dd.MM."
        return formatter
    }()
}
