import SwiftUI

@main
struct PreisfuchsApp: App {

    /// Eine Umgebung fuer die ganze App, von hier nach unten gereicht.
    @State private var appEnvironment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appEnvironment)
                .preferredColorScheme(.dark)
        }
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
