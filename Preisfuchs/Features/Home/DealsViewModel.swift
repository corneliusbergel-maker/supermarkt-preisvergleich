import Foundation
import Observation
import PriceCore
import PriceData

/// Sucht Angebote, die für **diesen** Nutzer interessant sind (#28).
///
/// Ausdrücklich keine zufällige Angebotsliste. Die Reihenfolge entsteht aus:
///
/// 1. **Favoriten zuerst** – was jemand markiert hat, kauft er vermutlich auch.
/// 2. **Tiefe des Rabatts**, sofern der Ursprungspreis bekannt ist.
/// 3. **Nähe**, weil ein Angebot 20 km entfernt selten eines ist.
///
/// Alles davon wird auf dem Gerät gerechnet. Es wird kein Nutzungsprofil
/// aufgebaut und nichts über das Verhalten nach außen gegeben.
@MainActor
@Observable
final class DealsViewModel {

    enum State {
        case idle
        case needsLocation
        case loading
        case deals([Deal])
        case empty
        case failed(String)
    }

    struct Deal: Identifiable {
        let priced: PricedProduct
        let distanceMeters: Double?
        let isFavorite: Bool

        var id: String { priced.id }
        var product: Product? { priced.product }
        var price: Money { priced.observation.price }

        /// Grundpreis, sofern die Menge bekannt ist.
        var unitPrice: UnitPrice? {
            guard let quantity = product?.quantity else { return nil }
            return UnitPrice.calculate(price: price, quantity: quantity)
        }
    }

    private(set) var state: State = .idle

    /// Wie weit zurück Angebote berücksichtigt werden.
    ///
    /// Aktionen laufen in der Regel eine Woche. Ältere als „aktuelles Angebot"
    /// zu zeigen wäre irreführend.
    private let maximumAgeInDays = 10

    private let maximumDeals = 8

    func load(using environment: AppEnvironment, favoriteIDs: Set<String>) async {
        guard let coordinate = environment.activeCoordinate else {
            state = .needsLocation
            return
        }

        state = .loading

        let settings = environment.settings
        let radiusKm = settings.maxDistanceMeters.map { $0 / 1000 } ?? 25
        let since = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -maximumAgeInDays, to: Date()) ?? Date()

        do {
            let found = try await environment.prices.discountedPrices(
                near: coordinate,
                radiusKm: max(1, min(25, radiusKm)),
                notOlderThan: since,
                limit: 60
            )
            guard !Task.isCancelled else { return }

            let limit = PriceComparator.effectiveDistanceLimit(
                settings.maxDistanceMeters,
                hasReferencePoint: true
            )

            let deals = found
                // Ohne Produktnamen wäre der Eintrag nicht lesbar. Einen
                // Platzhalter zu erfinden kommt nicht in Frage.
                .filter { $0.product != nil }
                .filter { settings.includes(retailer: $0.observation.retailer) }
                .compactMap { priced -> Deal? in
                    let distance = priced.observation.store.flatMap {
                        GeoDistance.straightLineMeters(from: coordinate, to: $0.coordinate)
                    }
                    if let limit {
                        guard let distance, distance <= limit else { return nil }
                    }
                    let isFavorite = priced.product.map { favoriteIDs.contains($0.id) } ?? false
                    return Deal(priced: priced, distanceMeters: distance, isFavorite: isFavorite)
                }
                .sorted(by: Self.moreInteresting)

            state = deals.isEmpty ? .empty : .deals(Array(deals.prefix(maximumDeals)))

        } catch let error as DataSourceError {
            guard !Task.isCancelled, error != .cancelled else { return }
            state = .failed(error.userMessage)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed("Angebote konnten nicht geladen werden.")
        }
    }

    /// Die Rangfolge aus dem Klassenkommentar, in Code gegossen.
    static func moreInteresting(_ lhs: Deal, _ rhs: Deal) -> Bool {
        if lhs.isFavorite != rhs.isFavorite { return lhs.isFavorite }

        // Ein bekannter Rabatt schlägt einen unbekannten -- bei unbekanntem
        // wissen wir nur, *dass* es ein Angebot ist, nicht wie gut.
        switch (lhs.priced.discountPercent, rhs.priced.discountPercent) {
        case let (left?, right?) where left != right:
            return left > right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        switch (lhs.distanceMeters, rhs.distanceMeters) {
        case let (left?, right?) where left != right:
            return left < right
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return lhs.price.amount < rhs.price.amount
        }
    }
}
