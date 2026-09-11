import Foundation
import Observation

/// Merkt sich, ob die zuletzt angezeigten Daten frisch oder aus dem
/// Zwischenspeicher stammen (#32).
///
/// Der Zwischenspeicher wäre ohne diese Anzeige eine Lüge: Der Nutzer sähe
/// Preise, die aussehen wie eben geladen. Deshalb sagt die App es dazu.
@MainActor
@Observable
final class DataFreshness {

    /// Zeitpunkt des ursprünglichen Abrufs, wenn gerade Daten aus dem
    /// Zwischenspeicher gezeigt werden. `nil`, solange alles frisch ist.
    private(set) var servedFromCacheAt: Date?

    var isShowingCachedData: Bool { servedFromCacheAt != nil }

    func noteCacheHit(at date: Date) {
        servedFromCacheAt = date
    }

    func noteFreshResponse() {
        servedFromCacheAt = nil
    }

    /// Text für den Hinweis, z. B. „Offline – Daten von vor 2 Stunden".
    var bannerText: String? {
        guard let servedFromCacheAt else { return nil }

        let seconds = Date().timeIntervalSince(servedFromCacheAt)
        let age: String
        switch seconds {
        case ..<120: age = "von gerade eben"
        case ..<3600: age = "von vor \(Int(seconds / 60)) Minuten"
        case ..<7200: age = "von vor einer Stunde"
        case ..<86400: age = "von vor \(Int(seconds / 3600)) Stunden"
        case ..<172_800: age = "von gestern"
        default: age = "von vor \(Int(seconds / 86400)) Tagen"
        }
        return "Keine Verbindung – gezeigte Daten sind \(age)."
    }
}
