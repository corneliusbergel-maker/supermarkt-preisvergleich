import Foundation
import Observation
import UserNotifications
import PriceCore

/// Lokale Benachrichtigungen für Preisalarme (#11, #27).
///
/// **Ehrlich zur Erwartung:** Das sind *lokale* Benachrichtigungen, keine
/// Push-Nachrichten. Die App prüft die Preise selbst, wenn iOS ihr dafür
/// Rechenzeit gibt. Wann das geschieht, entscheidet das System nach Akku,
/// Netz und Nutzungsgewohnheiten – ein Alarm kann deshalb verspätet oder gar
/// nicht ausgelöst werden.
///
/// Echter Push würde über Apples APNs laufen und ein kostenpflichtiges
/// Entwicklerkonto voraussetzen. Das widerspricht der Vorgabe, dass die App
/// ohne laufende Kosten auskommt.
@MainActor
@Observable
final class NotificationService {

    enum Authorization: Equatable {
        case notDetermined
        case denied
        case authorized

        var explanation: String {
            switch self {
            case .notDetermined:
                return "Preisfuchs kann dich benachrichtigen, wenn ein Produkt deinen "
                     + "Zielpreis erreicht."
            case .denied:
                return "Benachrichtigungen sind ausgeschaltet. Preisalarme werden dann "
                     + "nur beim Öffnen der App sichtbar."
            case .authorized:
                return "Preisfuchs prüft deine Alarme im Hintergrund, sobald iOS der App "
                     + "Rechenzeit gibt. Das kann sich verzögern – eine Zustellung zu einem "
                     + "bestimmten Zeitpunkt ist damit nicht garantiert."
            }
        }
    }

    private(set) var authorization: Authorization = .notDetermined

    private let center = UNUserNotificationCenter.current()

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            authorization = .authorized
        case .denied:
            authorization = .denied
        case .notDetermined:
            authorization = .notDetermined
        @unknown default:
            authorization = .notDetermined
        }
    }

    /// Fragt die Erlaubnis an. Ohne Zustimmung wird nichts zugestellt.
    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge]))
            ?? false
        await refreshAuthorization()
        return granted
    }

    /// Meldet einen erreichten Zielpreis.
    ///
    /// Der Text nennt Betrag, Markt und Stand – damit aus der Mitteilung
    /// hervorgeht, worauf sie sich stützt.
    func notifyPriceReached(productName: String,
                            price: Money,
                            storeName: String?,
                            freshness: String) async {
        guard authorization == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "Zielpreis erreicht"

        let place = storeName.map { " bei \($0)" } ?? ""
        content.body = "\(productName) kostet \(price.roundedToCents.formatted())\(place). "
                     + "Stand: \(freshness)."
        content.sound = .default

        // Sofort zustellen; ausgelöst wird ohnehin nur, wenn die App
        // gerade laufen durfte.
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        try? await center.add(request)
    }
}
