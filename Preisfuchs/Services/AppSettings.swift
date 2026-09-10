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
            // Voreinstellung: die grossen Ketten an, Drogerien aus.
            self.enabledRetailerIDs = Set(
                ["REWE", "EDEKA", "Kaufland", "Lidl", "Aldi Süd", "Aldi Nord",
                 "Penny", "Netto Marken-Discount"]
                    .compactMap { RetailerRegistry.identifier(forBrand: $0) }
            )
        }

        self.maxDistanceMeters = defaults.object(forKey: Keys.maxDistance) as? Double ?? 5_000

        self.sortCriterion = (defaults.string(forKey: Keys.sort)
            .flatMap(PriceSortCriterion.init(rawValue:))) ?? .price

        let storedCost = defaults.object(forKey: Keys.costPerKm) as? Double
        self.costPerKilometer = storedCost.map { Decimal($0) } ?? Decimal(string: "0.30")!

        self.manualPlaceName = defaults.string(forKey: Keys.manualPlaceName)
        self.manualLatitude = defaults.object(forKey: Keys.manualLat) as? Double
        self.manualLongitude = defaults.object(forKey: Keys.manualLon) as? Double
    }

    // MARK: - Anwenden

    /// Ist diese Kette eingeschaltet?
    func includes(retailer: Retailer?) -> Bool {
        guard let retailer else { return false }
        if enabledRetailerIDs.contains(retailer.id) { return true }
        // Filialen aus OpenStreetMap tragen eine Wikidata-Kennung, Preise aus
        // Open Prices nur den Namen. Deshalb zusaetzlich ueber den Namen pruefen.
        guard let byName = RetailerRegistry.identifier(forBrand: retailer.name) else {
            return false
        }
        return enabledRetailerIDs.contains(byName)
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
        static let maxDistance = "settings.maxDistanceMeters"
        static let sort = "settings.sortCriterion"
        static let costPerKm = "settings.costPerKilometer"
        static let manualPlaceName = "settings.manualPlaceName"
        static let manualLat = "settings.manualLatitude"
        static let manualLon = "settings.manualLongitude"
    }
}
