import Foundation

/// Eine Handelsmarke, z. B. REWE oder Lidl.
///
/// `id` ist die Wikidata-ID aus OpenStreetMap (`brand:wikidata`), weil die
/// Schreibweise in den Rohdaten schwankt -- dort kommt "Rewe" **und** "REWE"
/// vor. Ueber die Wikidata-ID sind beide dieselbe Kette.
public struct Retailer: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public struct Coordinate: Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// Plausibilitaetspruefung -- verhindert, dass fehlerhafte Datensaetze
    /// als gueltige Orte in die Entfernungsberechnung geraten.
    public var isValid: Bool {
        latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
            && !(latitude == 0 && longitude == 0)
    }
}

/// Eine konkrete Filiale.
public struct Store: Hashable, Sendable, Identifiable {

    /// Stabile Kennung aus OpenStreetMap, z. B. "node/58489979".
    public let id: String

    public let retailer: Retailer
    public let coordinate: Coordinate

    /// Anzeigename, falls er von der Kette abweicht.
    public let name: String?

    public let street: String?
    public let houseNumber: String?
    public let postalCode: String?
    public let city: String?

    /// Rohwert des OSM-Tags `opening_hours`. Bewusst unveraendert
    /// aufbewahrt -- die Syntax ist komplex, und eine halbgare Auswertung
    /// waere eine erfundene Aussage ueber Oeffnungszeiten.
    public let openingHoursRaw: String?

    public let websiteURL: URL?

    public init(id: String,
                retailer: Retailer,
                coordinate: Coordinate,
                name: String? = nil,
                street: String? = nil,
                houseNumber: String? = nil,
                postalCode: String? = nil,
                city: String? = nil,
                openingHoursRaw: String? = nil,
                websiteURL: URL? = nil) {
        self.id = id
        self.retailer = retailer
        self.coordinate = coordinate
        self.name = name
        self.street = street
        self.houseNumber = houseNumber
        self.postalCode = postalCode
        self.city = city
        self.openingHoursRaw = openingHoursRaw
        self.websiteURL = websiteURL
    }

    public var displayName: String { name ?? retailer.name }

    /// Einzeilige Adresse. Gibt `nil` zurueck, wenn nichts Verwertbares da ist
    /// -- statt einer halben Adresse, die nach einem Datenfehler aussieht.
    public var formattedAddress: String? {
        let line1 = [street, houseNumber].compactMap { $0 }.joined(separator: " ")
        let line2 = [postalCode, city].compactMap { $0 }.joined(separator: " ")
        let parts = [line1, line2].filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

/// Wie verlaesslich ist ein Preis?
///
/// Wird ausschliesslich aus vorhandenen Metadaten abgeleitet -- Alter, Beleg
/// und Qualitaet der Produktzuordnung. Nichts daran wird geschaetzt.
public enum PriceConfidence: Int, Hashable, Sendable, Comparable, CaseIterable {

    /// Kein Preis vorhanden.
    case none = 0

    /// Vorhanden, aber alt. In der UI als moeglicherweise veraltet markiert.
    case low = 1

    /// Aktuell genug fuer eine Orientierung.
    case medium = 2

    /// Frisch, belegt und eindeutig zugeordnet.
    case high = 3

    public static func < (lhs: PriceConfidence, rhs: PriceConfidence) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Text fuer die Oberflaeche.
    public var label: String {
        switch self {
        case .none: return "Keine Preisdaten"
        case .low: return "Moeglicherweise veraltet"
        case .medium: return "Aktuell"
        case .high: return "Bestaetigt"
        }
    }
}

/// Ein beobachteter Preis aus einer Datenquelle.
///
/// Jeder Preis traegt seine Herkunft mit sich. Ohne `observedOn` und `source`
/// darf er in der App nicht angezeigt werden.
public struct PriceObservation: Hashable, Sendable, Identifiable {

    public let id: String

    /// Verweis auf das Produkt (`Product.id`).
    public let productID: String

    public let price: Money

    /// Tag der Beobachtung. Open Prices liefert Tagesgenauigkeit.
    public let observedOn: Date

    /// Filiale, sofern bekannt.
    public let store: Store?

    /// Kette, auch wenn die Filiale unbekannt ist.
    public let retailer: Retailer?

    /// Von der Quelle als Aktionspreis markiert.
    public let isDiscounted: Bool

    /// Es existiert ein Beleg (Preisschild- oder Kassenbonfoto).
    public let hasProof: Bool

    /// War die Produktzuordnung eindeutig (Barcode) oder nur wahrscheinlich?
    public let isExactProductMatch: Bool

    /// Name der Quelle, z. B. "Open Prices". Wird in der UI genannt.
    public let source: String

    public init(id: String,
                productID: String,
                price: Money,
                observedOn: Date,
                store: Store? = nil,
                retailer: Retailer? = nil,
                isDiscounted: Bool = false,
                hasProof: Bool = false,
                isExactProductMatch: Bool = true,
                source: String) {
        self.id = id
        self.productID = productID
        self.price = price
        self.observedOn = observedOn
        self.store = store
        self.retailer = retailer
        self.isDiscounted = isDiscounted
        self.hasProof = hasProof
        self.isExactProductMatch = isExactProductMatch
        self.source = source
    }

    /// Alter in vollen Tagen.
    public func ageInDays(asOf now: Date = Date()) -> Int {
        let calendar = Calendar(identifier: .gregorian)
        let from = calendar.startOfDay(for: observedOn)
        let to = calendar.startOfDay(for: now)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Ableitung der Verlaesslichkeit.
    ///
    /// Schwellen:
    /// - **hoch**: hoechstens 7 Tage alt, mit Beleg, eindeutig zugeordnet
    /// - **mittel**: hoechstens 30 Tage alt
    /// - **niedrig**: aelter als 30 Tage
    ///
    /// Ein Preis mit unsicherer Produktzuordnung erreicht nie "hoch" -- sonst
    /// wuerde die App eine Genauigkeit behaupten, die sie nicht hat.
    public func confidence(asOf now: Date = Date()) -> PriceConfidence {
        let age = ageInDays(asOf: now)

        // Ein Datum in der Zukunft ist ein Datenfehler, kein frischer Preis.
        guard age >= 0 else { return .low }

        if age <= 7 && hasProof && isExactProductMatch { return .high }
        if age <= 30 { return .medium }
        return .low
    }

    /// Text wie "heute", "gestern", "vor 5 Tagen" fuer die Oberflaeche.
    public func freshnessDescription(asOf now: Date = Date()) -> String {
        let age = ageInDays(asOf: now)
        switch age {
        case ..<0: return "Datum ungueltig"
        case 0: return "heute"
        case 1: return "gestern"
        case 2...30: return "vor \(age) Tagen"
        case 31...60: return "vor etwa einem Monat"
        default: return "vor \(age / 30) Monaten"
        }
    }
}
