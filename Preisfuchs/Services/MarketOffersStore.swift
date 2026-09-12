import Foundation
import Observation
import PriceCore
import PriceData

/// Hält die Angebote, die direkt von den Ketten kommen: Kaufland, ALDI Nord
/// und ALDI SÜD.
///
/// Liegt in der App-Umgebung, damit Startseite und Angebotsliste dieselben
/// Daten zeigen und keine Seite doppelt geladen wird. Jede Kette hat ihren
/// eigenen Stand – fällt eine aus, bleiben die anderen sichtbar.
@MainActor
@Observable
final class MarketOffersStore {

    enum State: Equatable {
        case idle
        case loading
        case loaded
        case failed(message: String, isRetryable: Bool)
    }

    struct Source: Identifiable, Sendable {
        /// Name wie in der Auswahlliste der Einstellungen.
        let settingsName: String
        let displayName: String
        let host: String
        let pageURL: URL
        /// Frühestens nach dieser Zeit erneut laden.
        let minimumAge: TimeInterval
        let load: @Sendable () async throws -> [RetailerOffer]

        var id: String { settingsName }
    }

    struct Status {
        var state: State = .idle
        var offers: [RetailerOffer] = []
        var fetchedAt: Date?
    }

    let sources: [Source]
    private(set) var statuses: [String: Status] = [:]
    private var inFlight: [String: Task<Void, Never>] = [:]

    init(sources: [Source]) {
        self.sources = sources
    }

    static func standard(transport: HTTPTransport) -> MarketOffersStore {
        let kaufland = KauflandOffersClient(transport: transport)
        let aldiNord = AldiNordOffersClient(transport: transport)
        let aldiSued = AldiSuedOffersClient(transport: transport)

        return MarketOffersStore(sources: [
            Source(settingsName: "Kaufland",
                   displayName: KauflandOffersClient.retailerName,
                   host: "kaufland.de",
                   pageURL: KauflandOffersClient.pageURL,
                   minimumAge: 10 * 60,
                   load: { try await kaufland.offers() }),
            Source(settingsName: "Aldi Nord",
                   displayName: AldiNordOffersClient.retailerName,
                   host: "aldi-nord.de",
                   pageURL: AldiNordOffersClient.pageURL,
                   minimumAge: 10 * 60,
                   load: { try await aldiNord.offers() }),
            // Bis zu rund 20 Seitenabrufe je Durchlauf – deshalb höchstens
            // einmal im Stundentakt, nie zwischendurch.
            Source(settingsName: "Aldi Süd",
                   displayName: AldiSuedOffersClient.retailerName,
                   host: "aldi-sued.de",
                   pageURL: AldiSuedOffersClient.pageURL,
                   minimumAge: 59 * 60,
                   load: { try await aldiSued.offers() })
        ])
    }

    // MARK: - Lesen

    func enabledSources(_ settings: AppSettings) -> [Source] {
        sources.filter { settings.isEnabled(retailerNamed: $0.settingsName) }
    }

    func status(of source: Source) -> Status {
        statuses[source.id] ?? Status()
    }

    func currentOffers(from sources: [Source], now: Date = Date()) -> [RetailerOffer] {
        sources.flatMap { status(of: $0).offers.filter { $0.isValid(on: now) } }
    }

    func upcomingOffers(from sources: [Source], now: Date = Date()) -> [RetailerOffer] {
        sources.flatMap { status(of: $0).offers.filter { $0.startsAfter(now) } }
    }

    /// Zusammengefasster Zustand, wenn keine Kette etwas zu zeigen hat.
    func combinedState(of sources: [Source]) -> State {
        let states = sources.map { status(of: $0).state }
        if states.contains(where: { $0 == .idle || $0 == .loading }) { return .loading }
        if !states.contains(.loaded),
           let failure = states.first(where: { if case .failed = $0 { return true } else { return false } }) {
            return failure
        }
        return .loaded
    }

    // MARK: - Laden

    func refresh(_ sources: [Source], force: Bool = false) async {
        let tasks = sources.compactMap { startRefresh($0, force: force) }
        for task in tasks {
            await task.value
        }
    }

    /// Eigene Aufgabe je Kette: Wird die aufrufende Ansicht verlassen, läuft
    /// der Abruf trotzdem zu Ende, statt beim nächsten Mal von vorn zu beginnen.
    private func startRefresh(_ source: Source, force: Bool) -> Task<Void, Never>? {
        if let running = inFlight[source.id] { return running }

        let current = status(of: source)
        if !force, let fetchedAt = current.fetchedAt, !current.offers.isEmpty,
           Date().timeIntervalSince(fetchedAt) < source.minimumAge {
            return nil
        }

        let task = Task { await self.load(source) }
        inFlight[source.id] = task
        return task
    }

    private func load(_ source: Source) async {
        var current = status(of: source)
        if current.offers.isEmpty {
            current.state = .loading
            statuses[source.id] = current
        }

        do {
            let offers = try await source.load()
            statuses[source.id] = Status(state: .loaded, offers: offers, fetchedAt: Date())
        } catch {
            var failed = status(of: source)
            if failed.offers.isEmpty {
                if let error = error as? DataSourceError {
                    failed.state = .failed(message: error.userMessage, isRetryable: error.offersManualRetry)
                } else {
                    failed.state = .failed(message: "Die Angebote von \(source.displayName) konnten "
                                           + "nicht geladen werden.", isRetryable: true)
                }
            } else {
                failed.state = .loaded
            }
            statuses[source.id] = failed
        }

        inFlight[source.id] = nil
    }
}
