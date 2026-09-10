import Foundation

/// Ein Angebot in der Vergleichsliste: beobachteter Preis plus alles, was
/// die App daraus abgeleitet hat.
public struct PriceOffer: Hashable, Sendable, Identifiable {

    public let observation: PriceObservation

    /// Grundpreis. `nil`, wenn die Produktmenge unbekannt ist.
    public let unitPrice: UnitPrice?

    /// Luftlinie zum Nutzer in Metern. `nil` ohne Standortfreigabe oder
    /// ohne bekannte Filialkoordinate.
    public let distanceMeters: Double?

    public init(observation: PriceObservation,
                unitPrice: UnitPrice? = nil,
                distanceMeters: Double? = nil) {
        self.observation = observation
        self.unitPrice = unitPrice
        self.distanceMeters = distanceMeters
    }

    public var id: String { observation.id }
    public var price: Money { observation.price }

    public func confidence(asOf now: Date = Date()) -> PriceConfidence {
        observation.confidence(asOf: now)
    }
}

/// Das Ergebnis eines Preisvergleichs.
///
/// Der Fall "keine Daten" ist ein eigener Zustand und kein leeres Array, das
/// die Oberflaeche versehentlich als "0 EUR" oder "kostenlos" darstellen
/// koennte.
public enum PriceComparison: Sendable {

    /// Es liegen Angebote vor, das erste ist das guenstigste.
    case offers([PriceOffer])

    /// Es gibt Preise, aber keiner erfuellt die Filter des Nutzers
    /// (Haendlerauswahl, maximale Entfernung).
    case filteredOut(totalBeforeFilter: Int)

    /// Fuer dieses Produkt existieren in Reichweite keine Preisdaten.
    case noData

    public var offers: [PriceOffer] {
        if case .offers(let list) = self { return list }
        return []
    }

    public var hasData: Bool {
        if case .offers(let list) = self { return !list.isEmpty }
        return false
    }
}

/// Sortierkriterien aus Anforderung #31.
public enum PriceSortCriterion: String, Hashable, Sendable, CaseIterable {
    case price
    case unitPrice
    case distance
    case bestValue
    case discount
    case freshness

    public var label: String {
        switch self {
        case .price: return "Guenstigster Preis"
        case .unitPrice: return "Guenstigster Grundpreis"
        case .distance: return "Entfernung"
        case .bestValue: return "Beste Kombination"
        case .discount: return "Angebote zuerst"
        case .freshness: return "Aktualitaet"
        }
    }
}

/// Vergleicht, sortiert und bewertet Angebote.
public enum PriceComparator {

    /// Baut einen Vergleich aus Rohangeboten.
    ///
    /// - Parameters:
    ///   - offers: bereits einem Produkt zugeordnete Angebote
    ///   - allowedRetailerIDs: `nil` heisst "alle" (Anforderung #29)
    ///   - maxDistanceMeters: `nil` heisst "unbegrenzt" (Anforderung #30)
    public static func compare(_ offers: [PriceOffer],
                               allowedRetailerIDs: Set<String>? = nil,
                               maxDistanceMeters: Double? = nil,
                               sortedBy criterion: PriceSortCriterion = .price,
                               costPerKilometer: Money? = nil,
                               now: Date = Date()) -> PriceComparison {

        guard !offers.isEmpty else { return .noData }

        let filtered = offers.filter { offer in
            if let allowed = allowedRetailerIDs {
                guard let retailerID = offer.observation.retailer?.id,
                      allowed.contains(retailerID) else { return false }
            }
            if let limit = maxDistanceMeters {
                // Angebote ohne bekannte Entfernung fallen bei aktivem
                // Entfernungsfilter heraus -- eine unbekannte Entfernung als
                // "innerhalb des Radius" zu werten waere geraten.
                guard let distance = offer.distanceMeters, distance <= limit else {
                    return false
                }
            }
            return true
        }

        guard !filtered.isEmpty else {
            return .filteredOut(totalBeforeFilter: offers.count)
        }

        return .offers(sort(filtered,
                            by: criterion,
                            costPerKilometer: costPerKilometer,
                            now: now))
    }

    public static func sort(_ offers: [PriceOffer],
                            by criterion: PriceSortCriterion,
                            costPerKilometer: Money? = nil,
                            now: Date = Date()) -> [PriceOffer] {
        switch criterion {
        case .price:
            return offers.sorted { lhs, rhs in
                if lhs.price.amount != rhs.price.amount {
                    return lhs.price.amount < rhs.price.amount
                }
                return tieBreak(lhs, rhs, now: now)
            }

        case .unitPrice:
            // Angebote ohne Grundpreis wandern ans Ende statt zu verschwinden.
            return offers.sorted { lhs, rhs in
                switch (lhs.unitPrice, rhs.unitPrice) {
                case let (left?, right?):
                    if left.normalizedPerBaseUnit != right.normalizedPerBaseUnit {
                        return left.normalizedPerBaseUnit < right.normalizedPerBaseUnit
                    }
                    return tieBreak(lhs, rhs, now: now)
                case (nil, _?): return false
                case (_?, nil): return true
                default: return tieBreak(lhs, rhs, now: now)
                }
            }

        case .distance:
            return offers.sorted { lhs, rhs in
                switch (lhs.distanceMeters, rhs.distanceMeters) {
                case let (left?, right?):
                    if left != right { return left < right }
                    return tieBreak(lhs, rhs, now: now)
                case (nil, _?): return false
                case (_?, nil): return true
                default: return tieBreak(lhs, rhs, now: now)
                }
            }

        case .bestValue:
            let rate = costPerKilometer ?? defaultCostPerKilometer
            return offers.sorted { lhs, rhs in
                let left = effectiveCost(of: lhs, costPerKilometer: rate)
                let right = effectiveCost(of: rhs, costPerKilometer: rate)
                if left != right { return left < right }
                return tieBreak(lhs, rhs, now: now)
            }

        case .discount:
            return offers.sorted { lhs, rhs in
                let left = lhs.observation.isDiscounted
                let right = rhs.observation.isDiscounted
                if left != right { return left && !right }
                if lhs.price.amount != rhs.price.amount {
                    return lhs.price.amount < rhs.price.amount
                }
                return tieBreak(lhs, rhs, now: now)
            }

        case .freshness:
            return offers.sorted { lhs, rhs in
                let left = lhs.observation.ageInDays(asOf: now)
                let right = rhs.observation.ageInDays(asOf: now)
                if left != right { return left < right }
                return lhs.price.amount < rhs.price.amount
            }
        }
    }

    /// Bei Gleichstand entscheidet die verlaesslichere, dann die frischere Angabe.
    private static func tieBreak(_ lhs: PriceOffer, _ rhs: PriceOffer, now: Date) -> Bool {
        let leftConfidence = lhs.confidence(asOf: now)
        let rightConfidence = rhs.confidence(asOf: now)
        if leftConfidence != rightConfidence { return leftConfidence > rightConfidence }
        return lhs.observation.ageInDays(asOf: now) < rhs.observation.ageInDays(asOf: now)
    }
}

// MARK: - Entfernung einpreisen

public extension PriceComparator {

    /// Angenommene Fahrtkosten je Kilometer.
    ///
    /// Das ist eine **Annahme, kein Messwert**. Sie ist als Einstellung
    /// veraenderbar, und die Oberflaeche nennt sie beim Anzeigen des
    /// Ergebnisses ("bei angenommenen 0,30 EUR/km").
    static var defaultCostPerKilometer: Money {
        Money(amount: Decimal(string: "0.30")!, currency: "EUR")
    }

    /// Preis zuzueglich der angenommenen Fahrtkosten fuer **Hin- und Rueckweg**.
    /// Ohne bekannte Entfernung bleibt es beim reinen Preis.
    static func effectiveCost(of offer: PriceOffer, costPerKilometer: Money) -> Decimal {
        guard let meters = offer.distanceMeters else { return offer.price.amount }
        let roundTripKilometers = Decimal(meters * 2 / 1000)
        return offer.price.amount + roundTripKilometers * costPerKilometer.amount
    }
}

/// Antwort auf "Lohnt sich der Umweg?" (Anforderungen #16 und #41).
public struct DetourAdvice: Sendable {

    /// Das guenstigere, aber weiter entfernte Angebot.
    public let cheaperFarther: PriceOffer

    /// Das teurere, aber naeher gelegene Angebot.
    public let pricierCloser: PriceOffer

    /// Ersparnis beim weiteren Markt.
    public let savings: Money

    /// Mehrweg (einfache Strecke) in Metern.
    public let extraDistanceMeters: Double

    /// Angenommene Fahrtkosten fuer den Mehrweg, Hin- und Rueckweg.
    public let assumedTravelCost: Money

    /// Uebersteigt die Ersparnis die angenommenen Fahrtkosten?
    public let isWorthIt: Bool

    /// Erklaerung im Klartext -- die Bewertung bleibt nachvollziehbar.
    public let explanation: String
}

public extension PriceComparator {

    /// Vergleicht das guenstigste mit dem naechstgelegenen Angebot.
    ///
    /// Gibt `nil` zurueck, wenn beides dasselbe Angebot ist oder Entfernungen
    /// fehlen -- dann gibt es schlicht nichts abzuwaegen.
    static func detourAdvice(for offers: [PriceOffer],
                             costPerKilometer: Money? = nil,
                             locale: Locale = Locale(identifier: "de_DE")) -> DetourAdvice? {

        let withDistance = offers.filter { $0.distanceMeters != nil }
        guard withDistance.count >= 2 else { return nil }

        guard let cheapest = withDistance.min(by: { $0.price.amount < $1.price.amount }),
              let nearest = withDistance.min(by: { $0.distanceMeters! < $1.distanceMeters! }),
              cheapest.id != nearest.id else { return nil }

        let savings = Money(amount: nearest.price.amount - cheapest.price.amount,
                            currency: cheapest.price.currency)
        guard savings.amount > 0 else { return nil }

        let extraMeters = cheapest.distanceMeters! - nearest.distanceMeters!
        guard extraMeters > 0 else { return nil }

        let rate = costPerKilometer ?? defaultCostPerKilometer
        let roundTripKilometers = Decimal(extraMeters * 2 / 1000)
        let travelCost = Money(amount: roundTripKilometers * rate.amount,
                               currency: rate.currency)

        let worthIt = savings.amount > travelCost.amount
        let savingsText = savings.roundedToCents.formatted(locale: locale)
        let distanceText = GeoDistance.formatted(meters: extraMeters, locale: locale)
        let costText = travelCost.roundedToCents.formatted(locale: locale)

        let explanation = worthIt
            ? "Du sparst \(savingsText) und faehrst dafuer \(distanceText) weiter. "
              + "Bei angenommenen \(rate.formatted(locale: locale))/km kostet der "
              + "Umweg hin und zurueck etwa \(costText) - er lohnt sich also."
            : "Du sparst nur \(savingsText), faehrst aber \(distanceText) weiter. "
              + "Bei angenommenen \(rate.formatted(locale: locale))/km kostet der "
              + "Umweg hin und zurueck etwa \(costText) - er lohnt sich eher nicht."

        return DetourAdvice(cheaperFarther: cheapest,
                            pricierCloser: nearest,
                            savings: savings,
                            extraDistanceMeters: extraMeters,
                            assumedTravelCost: travelCost,
                            isWorthIt: worthIt,
                            explanation: explanation)
    }
}
