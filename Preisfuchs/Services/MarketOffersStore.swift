import Foundation
import Observation
import PriceCore
import PriceData

/// Hält die Wochenangebote, die direkt von einer Kette kommen – derzeit
/// Kaufland (siehe `KauflandOffersClient`).
///
/// Liegt in der App-Umgebung, damit Startseite und Angebotsliste dieselben
/// Daten zeigen und die große Seite nicht doppelt geladen wird.
@MainActor
@Observable
final class MarketOffersStore {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String, isRetryable: Bool)
    }

    static let retailerName = KauflandOffersClient.retailerName
    static let sourceURL = KauflandOffersClient.pageURL

    /// Nicht öfter als alle zehn Minuten neu laden – auch wenn Stundentakt
    /// und Herunterziehen kurz hintereinander kommen.
    static let minimumAge: TimeInterval = 10 * 60

    private(set) var state: State = .idle
    private(set) var offers: [RetailerOffer] = []
    private(set) var fetchedAt: Date?

    private let client: KauflandOffersClient
    private var inFlight: Task<Void, Never>?

    init(client: KauflandOffersClient) {
        self.client = client
    }

    var currentOffers: [RetailerOffer] {
        let now = Date()
        return offers.filter { $0.isValid(on: now) }
    }

    var upcomingOffers: [RetailerOffer] {
        let now = Date()
        return offers.filter { $0.startsAfter(now) }
    }

    /// Die ersten gültigen Angebote in Kauflands eigener Reihenfolge.
    ///
    /// Nicht nach größter Ersparnis: Dann standen Kochtöpfe und Wecker mit
    /// −70 % oben. Kaufland beginnt mit Obst und Gemüse – das passt zu einer
    /// Supermarkt-App.
    func topOffers(limit: Int) -> [RetailerOffer] {
        Array(currentOffers.prefix(limit))
    }

    func refresh(force: Bool = false) async {
        if let inFlight {
            await inFlight.value
            return
        }
        if !force, let fetchedAt, !offers.isEmpty,
           Date().timeIntervalSince(fetchedAt) < Self.minimumAge {
            return
        }

        // Eigene Aufgabe statt direkt im Aufrufer: Wechselt die Ansicht, wird
        // deren `.task` abgebrochen – der halb geladene Abruf soll trotzdem
        // zu Ende laufen, statt beim nächsten Mal von vorn zu beginnen.
        let task = Task { await load() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func load() async {
        if offers.isEmpty { state = .loading }
        do {
            offers = try await client.offers()
            fetchedAt = Date()
            state = .loaded
        } catch let error as DataSourceError {
            state = offers.isEmpty
                ? .failed(message: error.userMessage, isRetryable: error.offersManualRetry)
                : .loaded
        } catch {
            state = offers.isEmpty
                ? .failed(message: "Die Kaufland-Angebote konnten nicht geladen werden.", isRetryable: true)
                : .loaded
        }
    }
}
