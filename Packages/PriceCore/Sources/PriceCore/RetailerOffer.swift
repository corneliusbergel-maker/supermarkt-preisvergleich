import Foundation

/// Ein Angebot, wie es eine Kette selbst veröffentlicht – etwa aus ihrem
/// Wochenprospekt.
///
/// Anders als `PriceObservation` hängt es an keinem Barcode: Die Ketten nennen
/// nur einen Titel („Südafrik. Mandarinen“). Es wird deshalb nie mit Produkten
/// aus Open Food Facts zusammengeführt – eine Zuordnung über den Namen wäre
/// geraten, und ein falsch zugeordneter Preis ist schlimmer als keiner.
public struct RetailerOffer: Hashable, Sendable, Identifiable {

    public let id: String

    /// Anzeigename der Kette, z. B. „ALDI SÜD“.
    public let retailerName: String

    /// Bei Markenartikeln oft die Marke („MONTORSI“), sonst der Artikel.
    public let title: String

    /// Bei Markenartikeln der Artikel („Pancetta Coppata“).
    public let subtitle: String?

    /// Kurzbeschreibung der Kette, etwa die Sorten.
    public let details: String?

    /// Aktionspreis ohne Kundenkarte. `nil` bei Angeboten nur für Karteninhaber.
    public let price: Money?

    /// Preis mit Kundenkarte (etwa Kaufland Card), soweit angegeben.
    public let loyaltyPrice: Money?

    /// Vergleichspreis, soweit die Kette ihn nennt.
    public let regularPrice: Money?

    /// Wie die Kette den Vergleichspreis nennt, etwa „UVP“. `nil` heißt:
    /// der Preis vor der Aktion.
    public let regularPriceLabel: String?

    /// Ersparnis in Prozent ohne und mit Kundenkarte, wie die Kette sie angibt.
    public let discountPercent: Int?
    public let loyaltyDiscountPercent: Int?

    /// Verkaufseinheit, z. B. „je 750-g-Netz“.
    public let unit: String?

    /// Grundpreis als Text, z. B. „1 kg = 2,66 €“.
    public let basePriceText: String?

    /// Pfand, das zum Preis hinzukommt.
    public let deposit: Money?

    /// Erster Gültigkeitstag.
    public let validFrom: Date

    /// Letzter Gültigkeitstag, einschließlich. `nil`, wenn die Kette keinen
    /// nennt – ALDI SÜD etwa schreibt nur „verfügbar seit“. Ein Enddatum
    /// dazuzudenken wäre erfunden.
    public let validTo: Date?

    /// Seite, von der das Angebot stammt.
    public let sourceURL: URL

    public init(id: String,
                retailerName: String,
                title: String,
                subtitle: String? = nil,
                details: String? = nil,
                price: Money?,
                loyaltyPrice: Money? = nil,
                regularPrice: Money? = nil,
                regularPriceLabel: String? = nil,
                discountPercent: Int? = nil,
                loyaltyDiscountPercent: Int? = nil,
                unit: String? = nil,
                basePriceText: String? = nil,
                deposit: Money? = nil,
                validFrom: Date,
                validTo: Date?,
                sourceURL: URL) {
        self.id = id
        self.retailerName = retailerName
        self.title = title
        self.subtitle = subtitle
        self.details = details
        self.price = price
        self.loyaltyPrice = loyaltyPrice
        self.regularPrice = regularPrice
        self.regularPriceLabel = regularPriceLabel
        self.discountPercent = discountPercent
        self.loyaltyDiscountPercent = loyaltyDiscountPercent
        self.unit = unit
        self.basePriceText = basePriceText
        self.deposit = deposit
        self.validFrom = validFrom
        self.validTo = validTo
        self.sourceURL = sourceURL
    }

    /// Name für Listen: der Artikel, nicht die Marke.
    public var displayName: String { subtitle ?? title }

    /// Die Marke, wenn der Titel eine ist.
    public var brandLine: String? { subtitle == nil ? nil : title }

    /// Gibt es den Preis nur mit Kundenkarte?
    public var requiresLoyaltyCard: Bool { price == nil && loyaltyPrice != nil }

    /// Größte angegebene Ersparnis, für die Sortierung.
    public var bestDiscountPercent: Int {
        max(discountPercent ?? 0, loyaltyDiscountPercent ?? 0)
    }

    // MARK: - Gültigkeit

    /// Kalender für Gültigkeitstage. Prospekte gelten nach deutscher Zeit,
    /// nicht nach der Zeitzone, in der das Gerät gerade steht.
    public static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        return calendar
    }()

    /// Gilt das Angebot zu diesem Zeitpunkt? Erster und letzter Tag zählen mit;
    /// ohne Enddatum gilt es ab dem ersten Tag.
    public func isValid(on date: Date) -> Bool {
        let calendar = Self.calendar
        guard date >= calendar.startOfDay(for: validFrom) else { return false }
        guard let validTo else { return true }
        guard let end = calendar.date(byAdding: .day, value: 1,
                                      to: calendar.startOfDay(for: validTo)) else { return false }
        return date < end
    }

    /// Beginnt das Angebot erst nach dem Tag dieses Zeitpunkts?
    public func startsAfter(_ date: Date) -> Bool {
        Self.calendar.startOfDay(for: validFrom) > Self.calendar.startOfDay(for: date)
    }

    /// Tag im Format `yyyy-MM-dd`, gelesen als deutscher Kalendertag.
    public static func day(from text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
              calendar.component(.day, from: date) == parts[2] else { return nil }
        return date
    }
}
