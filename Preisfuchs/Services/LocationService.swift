import CoreLocation
import Foundation
import Observation
import PriceCore

/// Ermittelt den Standort -- ausschliesslich nach Freigabe.
///
/// Es gibt bewusst keinen Weg, hier ohne Berechtigung an eine Position zu
/// kommen. Wer nicht ortet werden will, waehlt einen Ort von Hand; die App
/// funktioniert dann vollstaendig weiter.
@MainActor
@Observable
final class LocationService {

    enum Authorization: Equatable {
        case notDetermined
        case denied
        case restricted
        case authorized

        var allowsLocating: Bool { self == .authorized }

        var explanation: String {
            switch self {
            case .notDetermined:
                return "Preisfuchs kann die Entfernung zu Märkten in deiner Nähe berechnen, "
                     + "wenn du den Standort freigibst."
            case .denied:
                return "Der Standortzugriff ist ausgeschaltet. Du kannst ihn in den "
                     + "Systemeinstellungen erlauben – oder einfach einen Ort von Hand wählen."
            case .restricted:
                return "Der Standortzugriff ist auf diesem Gerät gesperrt. "
                     + "Wähle stattdessen einen Ort von Hand."
            case .authorized:
                return "Standort wird nur zur Entfernungsberechnung genutzt und verlässt "
                     + "das Gerät nicht."
            }
        }
    }

    private(set) var authorization: Authorization = .notDetermined
    private(set) var coordinate: Coordinate?
    private(set) var isLocating = false

    /// Letzte Störung im Klartext. `nil`, solange alles glattlief.
    private(set) var lastError: String?

    private let manager = CLLocationManager()
    private let proxy = DelegateProxy()

    init() {
        proxy.onAuthorizationChange = { [weak self] status in
            Task { @MainActor in self?.handleAuthorization(status) }
        }
        proxy.onLocation = { [weak self] location in
            Task { @MainActor in self?.handle(location) }
        }
        proxy.onFailure = { [weak self] error in
            Task { @MainActor in self?.handle(error) }
        }

        manager.delegate = proxy
        // Hundert Meter genuegen fuer Entfernungen zu Filialen und schonen
        // den Akku deutlich gegenueber der Bestgenauigkeit.
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        authorization = Self.map(manager.authorizationStatus)
    }

    /// Fragt die Berechtigung an. Tut nichts, wenn bereits entschieden wurde --
    /// iOS zeigt den Dialog ohnehin nur einmal.
    func requestPermission() {
        guard authorization == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Holt **eine** Position statt fortlaufender Aktualisierung.
    ///
    /// Für Entfernungen zu Filialen reicht das, und es verbraucht deutlich
    /// weniger Energie als eine Dauerortung.
    func updateLocationOnce() {
        guard authorization.allowsLocating else { return }
        isLocating = true
        lastError = nil
        manager.requestLocation()
    }

    // MARK: - Rückmeldungen

    private func handleAuthorization(_ status: CLAuthorizationStatus) {
        authorization = Self.map(status)
        if authorization.allowsLocating {
            updateLocationOnce()
        } else {
            coordinate = nil
            isLocating = false
        }
    }

    private func handle(_ location: CLLocation) {
        isLocating = false
        let candidate = Coordinate(latitude: location.coordinate.latitude,
                                   longitude: location.coordinate.longitude)
        // Eine ungültige Position zu übernehmen wäre schlimmer als keine:
        // sie würde falsche Entfernungen erzeugen.
        guard candidate.isValid else {
            lastError = "Die ermittelte Position ist nicht plausibel."
            return
        }
        coordinate = candidate
        lastError = nil
    }

    private func handle(_ error: Error) {
        isLocating = false
        guard let clError = error as? CLError else {
            lastError = "Der Standort konnte nicht ermittelt werden."
            return
        }
        switch clError.code {
        case .denied:
            authorization = .denied
            coordinate = nil
            lastError = nil          // Der Zustand erklärt sich über `authorization`.
        case .locationUnknown:
            lastError = "Der Standort ist gerade nicht bestimmbar. "
                      + "Im Gebäude hilft oft ein Schritt ans Fenster."
        case .network:
            lastError = "Für die Ortung fehlt gerade die Netzverbindung."
        default:
            lastError = "Der Standort konnte nicht ermittelt werden."
        }
    }

    private static func map(_ status: CLAuthorizationStatus) -> Authorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        case .denied: return .denied
        case .authorizedAlways, .authorizedWhenInUse: return .authorized
        @unknown default: return .notDetermined
        }
    }
}

/// Nimmt die CoreLocation-Rückrufe entgegen und reicht sie weiter.
///
/// Ein eigener Empfänger, damit `LocationService` kein `NSObject` sein muss --
/// das verträgt sich schlecht mit `@Observable`.
private final class DelegateProxy: NSObject, CLLocationManagerDelegate {

    var onAuthorizationChange: ((CLAuthorizationStatus) -> Void)?
    var onLocation: ((CLLocation) -> Void)?
    var onFailure: ((Error) -> Void)?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        onAuthorizationChange?(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        onLocation?(latest)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        onFailure?(error)
    }
}
