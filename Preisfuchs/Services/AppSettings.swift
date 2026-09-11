import Foundation
import Observation
import PriceCore

/// Einstellungen des Nutzers.
///
/// Liegen in `UserDefaults`: es sind wenige, kleine Werte ohne Beziehungen
/// untereinander. SwiftData waere dafuer schwerer als noetig -- das kommt bei
/// Favoriten, Einkaufsliste und Preisalarmen zum Einsatz.
@MainActor
@Observable
final class AppSettings {

    private let defaults: UserDefaults

    // MARK: - Berücksichtigte Händler (#29)

    /// Kennungen aus `RetailerRegistry`, nicht Anzeigenamen -- sonst wuerde
    /// der Filter an "Rewe" gegen "REWE" scheitern.
    var enabledRetailerIDs: Set<String> {
        didSet { defaults.set(Array(enabledRetailerIDs), forKey: Keys.retailers) }
    }

    /// Auswahlliste. Die Namen sind reale deutsche Ketten; die Kennung wird
    /// daraus abgeleitet, damit sie zu den Daten passt.
    static let selectableRetailers = [
        "REWE", "EDEKA", "Kaufland", "Lidl", "Aldi Süd", "Aldi Nord",
        "Penny", "Netto Marken-Discount", "Netto", "Norma", "dm", "Rossmann"
    ]

    static let selectableRetailerIDs: Set<String> = Set(
        selectableRetailers.compactMap { RetailerRegistry.identifier(forBrand: $0) }
    )

    /// Alle Märkte, die nicht in der Auswahlliste stehen: Globus, Marktkauf,
    /// tegut, Bioläden und so weiter. Standard: an.
    var includeOtherRetailers: Bool {
        didSet { defaults.set(includeOtherRetailers, forKey: Keys.otherRetailers) }
    }

    // MARK: - Umkreis (#30)

    /// `nil` bedeutet unbegrenzt.
    var maxDistanceMeters: Double? {
        didSet {
            if let maxDistanceMeters {
                defaults.set(maxDistanceMeters, forKey: Keys.maxDistance)
            } else {
                defaults.removeObject(forKey: Keys.maxDistance)
            }
        }
    }

    static let distanceOptions: [(label: String, meters: Double?)] = [
        ("1 km", 1_000), ("2 km", 2_000), ("5 km", 5_000),
        ("10 km", 10_000), ("25 km", 25_000), ("Unbegrenzt", nil)
    ]

    // MARK: - Sortierung (#31)

    var sortCriterion: PriceSortCriterion {
        didSet { defaults.set(sortCriterion.rawValue, forKey: Keys.sort) }
    }

    // MARK: - Fahrtkosten

    /// Angenommene Fahrtkosten je Kilometer, in Euro.
    ///
    /// Eine **Annahme**, kein Messwert -- deshalb einstellbar, und die
    /// Oberflaeche nennt sie beim Anzeigen eines Ergebnisses.
    var costPerKilometer: Decimal {
        didSet {
            defaults.set(NSDecimalNumber(decimal: costPerKilometer).doubleValue,
                         forKey: Keys.costPerKm)
        }
    }

    // MARK: - Manueller Ort

    /// Von Hand gewaehlter Ort. Hat Vorrang vor der Ortung.
    var manualPlaceName: String? {
        didSet { defaults.set(manualPlaceName, forKey: Keys.manualPlaceName) }
    }

    var manualLatitude: Double? {
        didSet { setOptional(manualLatitude, forKey: Keys.manualLat) }
    }

    var manualLongitude: Double? {
        didSet { setOptional(manualLongitude, forKey: Keys.manualLon) }
    }

    var manualCoordinate: Coordinate? {
        guard let manualLatitude, let manualLongitude else { return nil }
        let coordinate = Coordinate(latitude: manualLatitude, longitude: manualLongitude)
        return coordinate.isValid ? coordinate : nil
    }

    func clearManualPlace() {
        manualPlaceName = nil
        manualLatitude = nil
        manualLongitude = nil
    }

    // MARK: - Aufbau

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let stored = defaults.array(forKey: Keys.retailers) as? [String] {
            self.enabledRetailerIDs = Set(stored)
        } else {
            // Voreinstellung: alle Supermärkte und Discounter an, Drogerien aus.
            self.enabledRetailerIDs = Set(
                ["REWE", "EDEKA", "Kaufland", "Lidl", "Aldi Süd", "Aldi Nord",
                 "Penny", "Netto Marken-Discount", "Netto", "Norma"]
                    .compactMap { RetailerRegistry.identifier(forBrand: $0) }
            )
        }

        self.includeOtherRetailers = defaults.object(forKey: Keys.otherRetailers) as? Bool ?? true

        // Voreinstellung 25 km, nicht 5 km. Gemessen am 2026-09-11 hatte das
        // am besten belegte Produkt im Umkreis von 25 km um Berlin-Mitte ganze
        // sieben Preise. Mit 5 km fiel bei fast jedem Produkt alles durchs
        // Raster, und die App wirkte leer. Entfernungen werden weiterhin
        // angezeigt; enger stellen lässt es sich in den Einstellungen.
        self.maxDistanceMeters = defaults.object(forKey: Keys.maxDistance) as? Double ?? 25_000

        self.sortCriterion = (defaults.string(forKey: Keys.sort)
            .flatMap(PriceSortCriterion.init(rawValue:))) ?? .price

        let storedCost = defaults.object(forKey: Keys.costPerKm) as? Double
        self.costPerKilometer = storedCost.map { Decimal($0) } ?? Decimal(string: "0.30")!

        self.manualPlaceName = defaults.string(forKey: Keys.manualPlaceName)
        self.manualLatitude = defaults.object(forKey: Keys.manualLat) as? Double
        self.manualLongitude = defaults.object(forKey: Keys.manualLon) as? Double
    }

    // MARK: - Anwenden

    /// Wird dieser Markt berücksichtigt?
    ///
    /// Die Einzelschalter gelten nur für die Ketten der Auswahlliste; alle
    /// übrigen folgen „Andere Märkte“. Früher fiel alles außerhalb der Liste
    /// immer heraus -- Preise von Globus, Marktkauf oder tegut verschwanden
    /// ohne Hinweis, obwohl sie belegt waren.
    func includes(retailer: Retailer?) -> Bool {
        guard let retailer else { return false }
        // Filialen aus OpenStreetMap tragen eine Wikidata-Kennung, Preise aus
        // Open Prices nur den Namen. Deshalb zusaetzlich ueber den Namen pruefen.
        let candidates = [retailer.id, RetailerRegistry.identifier(forBrand: retailer.name)]
            .compactMap { $0 }
        if let listed = candidates.first(where: { Self.selectableRetailerIDs.contains($0) }) {
            return enabledRetailerIDs.contains(listed)
        }
        return includeOtherRetailers
    }

    func toggle(retailerNamed name: String) {
        guard let id = RetailerRegistry.identifier(forBrand: name) else { return }
        if enabledRetailerIDs.contains(id) {
            enabledRetailerIDs.remove(id)
        } else {
            enabledRetailerIDs.insert(id)
        }
    }

    func isEnabled(retailerNamed name: String) -> Bool {
        guard let id = RetailerRegistry.identifier(forBrand: name) else { return false }
        return enabledRetailerIDs.contains(id)
    }

    private func setOptional(_ value: Double?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    private enum Keys {
        static let retailers = "settings.enabledRetailerIDs"
        static let otherRetailers = "settings.includeOtherRetailers"
        static let maxDistance = "settings.maxDistanceMeters"
        static let sort = "settings.sortCriterion"
        static let costPerKm = "settings.costPerKilometer"
        static let manualPlaceName = "settings.manualPlaceName"
        static let manualLat = "settings.manualLatitude"
        static let manualLon = "settings.manualLongitude"
    }
}
