import BackgroundTasks
import Foundation
import SwiftData
import PriceCore
import PriceData

/// Prüft Preisalarme und meldet erreichte Zielpreise (#11).
///
/// Läuft ausschließlich auf dem Gerät. Es gibt keinen Server, der im
/// Hintergrund für alle Nutzer pollt – das wäre die Voraussetzung für echten
/// Push und damit für ein kostenpflichtiges Entwicklerkonto.
enum PriceAlertService {

    /// Kennung der Hintergrundaufgabe. Muss mit
    /// `BGTaskSchedulerPermittedIdentifiers` in der Info.plist übereinstimmen.
    static let taskIdentifier = "de.preisfuchs.priceCheck"

    /// Frühestens nach dieser Zeit erneut prüfen.
    ///
    /// iOS behandelt das als Wunsch, nicht als Zusage. Häufigeres Anfragen
    /// bringt nichts und belastet nur den Akku.
    static let minimumInterval: TimeInterval = 6 * 60 * 60

    /// Wie viele Alarme je Durchlauf geprüft werden.
    ///
    /// Eine Hintergrundaufgabe bekommt nur wenige Sekunden. Wer zu viel
    /// vornimmt, wird abgebrochen und erledigt gar nichts.
    static let maximumAlertsPerRun = 8

    // MARK: - Planen

    static func scheduleNextRun() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Im Simulator und bei abgeschaltetem Hintergrunddatenabgleich
            // schlägt das fehl. Das ist kein Grund, die App zu stören --
            // die Alarme werden dann beim nächsten Öffnen geprüft.
        }
    }

    /// Einstiegspunkt der Hintergrundaufgabe.
    ///
    /// Baut sich die benötigten Dienste selbst zusammen: Die API-Clients sind
    /// zustandslos, und die Einstellungen liegen in `UserDefaults`. So braucht
    /// der Hintergrundlauf keine Referenz auf die laufende Oberfläche.
    ///
    /// Als Bezugspunkt dient nur ein von Hand gewählter Ort. Eine Ortung im
    /// Hintergrund anzustoßen wäre weder zuverlässig noch angemessen –
    /// ohne Bezugspunkt entfällt schlicht der Entfernungsfilter.
    @MainActor
    static func runInBackground(container: ModelContainer) async {
        let settings = AppSettings()
        let notifications = NotificationService()
        await notifications.refreshAuthorization()

        await check(container: container,
                    prices: OpenPricesClient(),
                    notifications: notifications,
                    settings: settings,
                    coordinate: settings.manualCoordinate)

        scheduleNextRun()
    }

    // MARK: - Prüfen

    /// Prüft die fälligen Alarme.
    ///
    /// - Returns: Anzahl der ausgelösten Meldungen.
    @MainActor
    @discardableResult
    static func check(container: ModelContainer,
                      prices: OpenPricesClient,
                      notifications: NotificationService,
                      settings: AppSettings,
                      coordinate: Coordinate?) async -> Int {

        let context = ModelContext(container)

        let descriptor = FetchDescriptor<PriceAlert>(
            predicate: #Predicate { $0.isEnabled },
            sortBy: [SortDescriptor(\.lastCheckedAt, order: .forward)]
        )
        guard let alerts = try? context.fetch(descriptor), !alerts.isEmpty else { return 0 }

        let radiusKm = settings.maxDistanceMeters.map { $0 / 1000 } ?? 25
        var notified = 0

        for alert in alerts.prefix(maximumAlertsPerRun) {
            if Task.isCancelled { break }

            guard let barcode = alert.barcode, !barcode.isEmpty,
                  let threshold = alert.threshold else { continue }

            guard let observations = try? await prices.prices(
                barcode: barcode,
                near: coordinate,
                radiusKm: max(1, min(25, radiusKm)),
                limit: 25
            ) else { continue }

            alert.lastCheckedAt = Date()

            // Nur Märkte, die der Nutzer eingeschaltet hat, und -- wenn ein
            // Bezugspunkt vorliegt -- nur solche in Reichweite.
            let limit = PriceComparator.effectiveDistanceLimit(
                settings.maxDistanceMeters,
                hasReferencePoint: coordinate != nil
            )

            let candidates = observations.filter { observation in
                guard settings.includes(retailer: observation.retailer) else { return false }
                guard let limit else { return true }
                guard let coordinate, let store = observation.store,
                      let distance = GeoDistance.straightLineMeters(from: coordinate,
                                                                    to: store.coordinate)
                else { return false }
                return distance <= limit
            }

            guard let best = candidates.min(by: { $0.price.amount < $1.price.amount }),
                  best.price.currency == threshold.currency,
                  alert.shouldNotify(about: best.price) else { continue }

            await notifications.notifyPriceReached(
                productName: alert.name,
                price: best.price,
                storeName: best.store?.displayName ?? best.retailer?.name,
                freshness: best.freshnessDescription()
            )

            alert.lastNotifiedPriceText = "\(best.price.amount)"
            notified += 1
        }

        try? context.save()
        return notified
    }
}
