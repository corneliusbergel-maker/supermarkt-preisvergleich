import Foundation
import Observation
import PriceCore
import PriceData

/// Lädt Filialen in der Umgebung (#13).
@MainActor
@Observable
final class StoresViewModel {

    enum State {
        case idle
        case needsLocation
        case loading
        case stores([Entry])
        case empty
        case failed(message: String, isRetryable: Bool)
    }

    /// Eine Filiale mit ihrer Entfernung zum Bezugspunkt.
    struct Entry: Identifiable, Hashable {
        let store: Store
        let distanceMeters: Double?
        var id: String { store.id }
    }

    private(set) var state: State = .idle

    /// Radius der letzten Abfrage, in Kilometern.
    private(set) var radiusKm: Double = 5

    func load(using environment: AppEnvironment, radiusKm: Double? = nil) async {
        guard let coordinate = environment.activeCoordinate else {
            state = .needsLocation
            return
        }

        if let radiusKm { self.radiusKm = radiusKm }
        state = .loading

        do {
            let found = try await environment.stores.stores(near: coordinate,
                                                            radiusKm: self.radiusKm)
            guard !Task.isCancelled else { return }

            let settings = environment.settings
            let entries = found
                .filter { settings.includes(retailer: $0.retailer) && Self.isChainStore($0) }
                .map { store in
                    Entry(store: store,
                          distanceMeters: GeoDistance.straightLineMeters(from: coordinate,
                                                                         to: store.coordinate))
                }
                .sorted { lhs, rhs in
                    // Filialen ohne Entfernung ans Ende -- sie sind hier die
                    // Ausnahme, weil Overpass immer Koordinaten liefert.
                    switch (lhs.distanceMeters, rhs.distanceMeters) {
                    case let (left?, right?): return left < right
                    case (nil, _?): return false
                    case (_?, nil): return true
                    default: return lhs.store.displayName < rhs.store.displayName
                    }
                }

            state = entries.isEmpty ? .empty : .stores(entries)

        } catch let error as DataSourceError {
            guard !Task.isCancelled, error != .cancelled else { return }
            state = .failed(message: error.userMessage, isRetryable: error.offersManualRetry)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(message: "Die Filialen konnten nicht geladen werden.",
                            isRetryable: true)
        }
    }

    /// Filialen einer Kette: aus der Auswahlliste oder als Marke in Wikidata
    /// erfasst (Globus, tegut, Bio Company ...).
    ///
    /// Kioske und Spätis ohne Markeneintrag bleiben aus der Filialsuche
    /// heraus. Mit ihnen stieg die Zahl in Berlin-Mitte von 228 auf 1166, und
    /// die 25 nächsten auf der Karte waren fast nur noch Spätis. Ihre Preise
    /// zählen im Preisvergleich trotzdem mit.
    static func isChainStore(_ store: Store) -> Bool {
        let id = store.retailer.id
        if RetailerRegistry.isWikidataIdentifier(id) { return true }
        return AppSettings.selectableRetailerIDs.contains(id)
    }
}
