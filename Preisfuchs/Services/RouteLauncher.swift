import Foundation
import MapKit
import PriceCore
#if canImport(UIKit)
import UIKit
#endif

/// Übergibt eine Route an eine Karten-App (#15).
///
/// Die App entwickelt selbst keine Navigation. Sie öffnet die vorhandene
/// Karten-App und gibt das Ziel weiter – als **Koordinate der Filiale**, nicht
/// als Stadt oder Marke.
///
/// Für Google Maps wird nur ein URL-Schema verwendet. Kein SDK, kein
/// API-Schlüssel, keine Kosten.
enum RouteLauncher {

    enum Mode: String, CaseIterable, Identifiable {
        case driving
        case walking
        case transit

        var id: String { rawValue }

        var label: String {
            switch self {
            case .driving: return "Auto"
            case .walking: return "Zu Fuß"
            case .transit: return "Öffentlich"
            }
        }

        var symbol: String {
            switch self {
            case .driving: return "car.fill"
            case .walking: return "figure.walk"
            case .transit: return "tram.fill"
            }
        }

        var appleMapsDirections: String {
            switch self {
            case .driving: return MKLaunchOptionsDirectionsModeDriving
            case .walking: return MKLaunchOptionsDirectionsModeWalking
            case .transit: return MKLaunchOptionsDirectionsModeTransit
            }
        }

        var googleMapsDirections: String {
            switch self {
            case .driving: return "driving"
            case .walking: return "walking"
            case .transit: return "transit"
            }
        }
    }

    /// Öffnet Apple Karten mit der Filiale als Ziel.
    static func openAppleMaps(store: Store, mode: Mode) {
        let coordinate = CLLocationCoordinate2D(latitude: store.coordinate.latitude,
                                                longitude: store.coordinate.longitude)
        let placemark = MKPlacemark(coordinate: coordinate)
        let item = MKMapItem(placemark: placemark)
        item.name = store.displayName
        item.openInMaps(launchOptions: [
            MKLaunchOptionsDirectionsModeKey: mode.appleMapsDirections
        ])
    }

    /// Ist die Google-Maps-App installiert?
    ///
    /// Auf dem Mac gibt es sie nicht – dort führt der Weg über den Browser.
    /// Die Abfrage setzt `LSApplicationQueriesSchemes` in der Info.plist voraus.
    static var isGoogleMapsAppAvailable: Bool {
        #if canImport(UIKit)
        guard Platform.hasGoogleMapsApp,
              let url = URL(string: "comgooglemaps://") else { return false }
        return UIApplication.shared.canOpenURL(url)
        #else
        return false
        #endif
    }

    /// Öffnet Google Maps – die App, wenn vorhanden, sonst die Website.
    ///
    /// Gibt `false` zurück, wenn sich gar nichts öffnen ließ, damit die
    /// Oberfläche das sagen kann, statt es stillschweigend zu verschlucken.
    @discardableResult
    static func openGoogleMaps(store: Store, mode: Mode) -> Bool {
        #if canImport(UIKit)
        let latitude = store.coordinate.latitude
        let longitude = store.coordinate.longitude

        if isGoogleMapsAppAvailable,
           let appURL = URL(string: "comgooglemaps://?daddr=\(latitude),\(longitude)"
                            + "&directionsmode=\(mode.googleMapsDirections)") {
            UIApplication.shared.open(appURL)
            return true
        }

        guard let webURL = URL(string: "https://www.google.com/maps/dir/?api=1"
                               + "&destination=\(latitude),\(longitude)"
                               + "&travelmode=\(mode.googleMapsDirections)") else {
            return false
        }
        UIApplication.shared.open(webURL)
        return true
        #else
        return false
        #endif
    }
}
