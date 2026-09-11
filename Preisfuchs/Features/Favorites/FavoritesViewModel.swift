import Foundation
import Observation
import PriceCore
import PriceData

/// Lädt zu favorisierten Produkten den jeweils günstigsten Preis (#26).
@MainActor
@Observable
final class FavoritesViewModel {

    /// Was zu einem Favoriten bekannt ist.
    enum PriceState {
        case notLoaded
        case loading
        case best(PriceOffer)
        /// Es gibt in Reichweite keinen belegten Preis.
        case noData
        case failed(String)
    }

    private(set) var states: [String: PriceState] = [:]
    private(set) var isRefreshing = false

    /// Obergrenze je Durchlauf.
    ///
    /// Jeder Favorit kostet eine Anfrage. Gegenüber einem gemeinnützig
    /// betriebenen Dienst ist eine Obergrenze die richtige Voreinstellung --
    /// und nacheinander statt gleichzeitig.
    static let maximumProductsPerRefresh = 12

    func state(for product: Product) -> PriceState {
        states[product.id] ?? .notLoaded
    }

    /// Holt für jeden Favoriten den günstigsten Preis.
    func refresh(products: [Product], using environment: AppEnvironment) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let settings = environment.settings
        let coordinate = environment.activeCoordinate
        let radiusKm = settings.maxDistanceMeters.map { $0 / 1000 } ?? 25

        for product in products.prefix(Self.maximumProductsPerRefresh) {
            if Task.isCancelled { return }

            guard let barcode = product.barcode, !barcode.isEmpty else {
                states[product.id] = .noData
                continue
            }

            states[product.id] = .loading

            do {
                let observations = try await environment.prices.prices(
                    barcode: barcode,
                    near: coordinate,
                    radiusKm: max(1, min(25, radiusKm)),
                    limit: 25
                )

                let offers = observations.map { observation -> PriceOffer in
                    let unitPrice = product.quantity.flatMap {
                        UnitPrice.calculate(price: observation.price, quantity: $0)
                    }
                    let distance: Double? = {
                        guard let coordinate, let store = observation.store else { return nil }
                        return GeoDistance.straightLineMeters(from: coordinate,
                                                              to: store.coordinate)
                    }()
                    return PriceOffer(observation: observation,
                                      unitPrice: unitPrice,
                                      distanceMeters: distance)
                }

                let comparison = PriceComparator.compare(
                    offers,
                    maxDistanceMeters: PriceComparator.effectiveDistanceLimit(
                        settings.maxDistanceMeters,
                        hasReferencePoint: coordinate != nil
                    ),
                    sortedBy: .price
                )

                if let best = comparison.offers.first {
                    states[product.id] = .best(best)
                } else {
                    // Auch "alles ausgefiltert" heißt für diese Zeile: hier
                    // steht kein Preis. Eine Zahl zu zeigen wäre falsch.
                    states[product.id] = .noData
                }

            } catch let error as DataSourceError {
                if error == .cancelled { return }
                states[product.id] = .failed(error.userMessage)
            } catch {
                states[product.id] = .failed("Preis konnte nicht geladen werden.")
            }
        }
    }

    func forget(productID: String) {
        states[productID] = nil
    }
}
