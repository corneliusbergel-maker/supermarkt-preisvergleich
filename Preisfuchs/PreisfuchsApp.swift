import SwiftData
import SwiftUI

@main
struct PreisfuchsApp: App {

    /// Eine Umgebung fuer die ganze App, von hier nach unten gereicht.
    @State private var appEnvironment = AppEnvironment()

    /// Favoriten, Einkaufsliste und Preisalarme liegen lokal auf dem Geraet.
    /// Es gibt keinen Server, auf den sie synchronisiert wuerden.
    ///
    /// Der Container wird ausdruecklich hier gebaut statt ueber
    /// `.modelContainer(for:)`, weil die Hintergrundaufgabe ihn ebenfalls
    /// braucht -- und die laeuft ausserhalb der Ansichtshierarchie.
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .preferredColorScheme(.dark)
        }
        .modelContainer(container)
        // Prueft Preisalarme, wenn iOS der App Rechenzeit gibt. Wann das
        // geschieht, entscheidet das System -- die App sagt das auch so.
        .backgroundTask(.appRefresh(PriceAlertService.taskIdentifier)) { [container] in
            await PriceAlertService.runInBackground(container: container)
        }
    }

    /// Faellt auf einen fluechtigen Speicher zurueck, wenn die Datenbank nicht
    /// geoeffnet werden kann.
    ///
    /// Ein Absturz waere hier die schlechtere Antwort: Suche und Preisvergleich
    /// funktionieren auch ohne gespeicherte Listen weiter.
    private static func makeContainer() -> ModelContainer {
        let schema = Schema([
            FavoriteProduct.self,
            ShoppingListEntry.self,
            PriceAlert.self
        ])

        if let container = try? ModelContainer(for: schema) {
            return container
        }

        let fallback = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        if let container = try? ModelContainer(for: schema, configurations: fallback) {
            return container
        }

        // Beide Wege fehlgeschlagen -- dann ist die Laufzeitumgebung kaputt,
        // und ein klarer Abbruch ist ehrlicher als stilles Fehlverhalten.
        fatalError("SwiftData-Container konnte nicht angelegt werden.")
    }
}

/// Plattformunterschiede an einer Stelle gebuendelt.
///
/// Die App blendet Funktionen aus, die auf der jeweiligen Plattform nicht
/// existieren, statt tote Schaltflaechen anzuzeigen.
enum Platform {

    static var isMacCatalyst: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        return false
        #endif
    }

    /// `VisionKit DataScannerViewController` gibt es auf macOS nicht.
    static var supportsBarcodeScanner: Bool { !isMacCatalyst }

    /// Auf dem Mac ist der Standort nur WLAN-basiert und deutlich ungenauer;
    /// dort ist die manuelle Ortswahl der Hauptweg.
    static var prefersManualLocation: Bool { isMacCatalyst }

    /// Die Google-Maps-App gibt es auf macOS nicht -- dort fuehrt die Route
    /// ueber die Website.
    static var hasGoogleMapsApp: Bool { !isMacCatalyst }
}
