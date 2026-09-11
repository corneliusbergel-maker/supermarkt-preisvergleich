import Foundation
import Observation
import PriceCore
import PriceData

/// Berechnet den günstigsten Einkauf für die Liste (#17, #18).
@MainActor
@Observable
final class ShoppingListViewModel {

    enum State {
        case idle
        case loading(done: Int, total: Int)
        case plans([BasketPlan])
        /// Für keinen Posten gibt es verwertbare Preise.
        case noData
        case failed(String)
    }

    private(set) var state: State = .idle

    /// Abdeckung je Markt – für die ehrliche Aussage „Kaufland hat Preise für
    /// 3 von 5 Artikeln“.
    private(set) var coverage: [(name: String, covered: Int, total: Int)] = []

    /// Posten, für die es nirgends einen belegten Preis gibt.
    private(set) var itemsWithoutPrice: [String] = []

    /// Angenommene Fahrtkosten des letzten Durchlaufs – die Oberfläche nennt
    /// sie beim Ergebnis, weil es eine Annahme ist und kein Messwert.
    private(set) var assumedCostPerKilometer: Money?

    /// Obergrenze je Durchlauf. Jeder Posten kostet eine Anfrage.
    static let maximumItems = 15

    func optimise(entries: [ShoppingListEntry], using environment: AppEnvironment) async {
        let usable = Array(entries.prefix(Self.maximumItems))
        guard !usable.isEmpty else {
            state = .idle
            return
        }

        let settings = environment.settings
        let coordinate = environment.activeCoordinate
        let radiusKm = settings.maxDistanceMeters.map { $0 / 1000 } ?? 25
        assumedCostPerKilometer = Money(amount: settings.costPerKilometer)

        state = .loading(done: 0, total: usable.count)
        itemsWithoutPrice = []

        var basketItems: [BasketItem] = []

        for (index, entry) in usable.enumerated() {
            if Task.isCancelled { return }
            state = .loading(done: index, total: usable.count)

            let product = entry.product

            guard let barcode = entry.barcode, !barcode.isEmpty else {
                basketItems.append(BasketItem(id: entry.productID,
                                              displayName: entry.name,
                                              count: entry.count,
                                              offers: []))
                continue
            }

            do {
                let observations = try await environment.prices.prices(
                    barcode: barcode,
                    near: coordinate,
                    radiusKm: max(1, min(25, radiusKm)),
                    limit: 30
                )

                let offers = observations
                    .filter { settings.includes(retailer: $0.retailer) }
                    .map { observation -> PriceOffer in
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
                    .filter { offer in
                        // Entfernungsfilter hier schon anwenden, damit der
                        // Optimierer keine Märkte einplant, die der Nutzer
                        // ausgeschlossen hat. Ohne Bezugspunkt entfällt der
                        // Filter – sonst bliebe ohne Standortfreigabe nichts
                        // übrig.
                        guard let limit = PriceComparator.effectiveDistanceLimit(
                            settings.maxDistanceMeters,
                            hasReferencePoint: coordinate != nil
                        ) else { return true }
                        guard let distance = offer.distanceMeters else { return false }
                        return distance <= limit
                    }

                basketItems.append(BasketItem(id: entry.productID,
                                              displayName: entry.name,
                                              count: entry.count,
                                              offers: offers))

            } catch let error as DataSourceError {
                if error == .cancelled { return }
                state = .failed(error.userMessage)
                return
            } catch {
                state = .failed("Die Preise konnten nicht geladen werden.")
                return
            }
        }

        if Task.isCancelled { return }

        coverage = BasketOptimizer.coverageByStore(basketItems)

        let plans = BasketOptimizer.recommendations(
            basketItems,
            maxStores: 3,
            costPerKilometer: Money(amount: settings.costPerKilometer)
        )

        itemsWithoutPrice = plans.first?.itemsWithoutPrice.map(\.displayName)
            ?? basketItems.filter { $0.offers.isEmpty }.map(\.displayName)

        state = plans.isEmpty ? .noData : .plans(plans)
    }

    func reset() {
        state = .idle
        coverage = []
        itemsWithoutPrice = []
    }
}
