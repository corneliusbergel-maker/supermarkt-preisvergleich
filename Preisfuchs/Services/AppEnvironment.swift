import Foundation
import Observation
import PriceCore
import PriceData

/// Haelt die Dienste zusammen, die die ganze App braucht.
///
/// Eine Instanz, von der Wurzelansicht nach unten gereicht. Kein globaler
/// Singleton -- so laesst sich in Vorschauen und Tests eine andere Umgebung
/// einsetzen.
@MainActor
@Observable
final class AppEnvironment {

    let settings: AppSettings
    let location: LocationService

    let products: OpenFoodFactsClient
    let prices: OpenPricesClient
    let stores: OverpassClient

    init(settings: AppSettings = AppSettings(),
         location: LocationService = LocationService(),
         products: OpenFoodFactsClient = OpenFoodFactsClient(),
         prices: OpenPricesClient = OpenPricesClient(),
         stores: OverpassClient = OverpassClient()) {
        self.settings = settings
        self.location = location
        self.products = products
        self.prices = prices
        self.stores = stores
    }

    /// Der Ort, mit dem gerechnet wird.
    ///
    /// Ein von Hand gewaehlter Ort hat Vorrang vor der Ortung: Wer ihn setzt,
    /// hat sich bewusst dafuer entschieden.
    var activeCoordinate: Coordinate? {
        settings.manualCoordinate ?? location.coordinate
    }

    /// Beschreibt fuer die Oberflaeche, worauf sich Entfernungen beziehen.
    var activeLocationDescription: String? {
        if let name = settings.manualPlaceName, settings.manualCoordinate != nil {
            return name
        }
        if location.coordinate != nil { return "Dein Standort" }
        return nil
    }

    /// Kann die App gerade Entfernungen ausweisen?
    var hasLocation: Bool { activeCoordinate != nil }
}
