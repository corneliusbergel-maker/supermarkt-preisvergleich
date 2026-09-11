import Foundation
import Observation
import PriceCore
import PriceData

/// Vergleicht dasselbe Produkt in anderen Packungsgrößen (#41).
///
/// „Die 1-kg-Packung ist pro kg 18 % günstiger" — die Aussage, für die der
/// Grundpreis überhaupt da ist.
///
/// **Bewusst auf Abruf statt automatisch.** Jede Packungsgröße kostet eine
/// eigene Preisabfrage. Sie ungefragt bei jedem Produktaufruf zu stellen wäre
/// gegenüber einem gemeinnützig betriebenen Dienst unhöflich — und meistens
/// interessiert es niemanden.
@MainActor
@Observable
final class PackSizeComparisonViewModel {

    enum State {
        case notLoaded
        case loading
        case comparisons([Comparison])
        case noneFound
        case failed(String)
    }

    struct Comparison: Identifiable {
        let product: Product
        let bestPrice: Money
        let unitPrice: UnitPrice
        let storeName: String?

        /// Vorteil gegenüber der aktuell geöffneten Packung.
        /// Negativ heißt: diese Größe ist pro Einheit günstiger.
        let advantage: Decimal?

        var id: String { product.id }

        /// Text wie „18 % günstiger pro kg". `nil`, wenn der Unterschied zu
        /// klein für eine Aussage ist.
        func advantageText() -> String? {
            guard let advantage else { return nil }
            let percent = abs(NSDecimalNumber(decimal: advantage).doubleValue * 100)
            guard percent >= 1 else { return nil }

            let rounded = Int(percent.rounded())
            let unit = unitPrice.referenceAmount == 1
                ? unitPrice.referenceUnit.symbol
                : "\(unitPrice.referenceAmount) \(unitPrice.referenceUnit.symbol)"
            return advantage < 0
                ? "\(rounded) % günstiger pro \(unit)"
                : "\(rounded) % teurer pro \(unit)"
        }
    }

    private(set) var state: State = .notLoaded

    /// Höchstens so viele andere Größen werden geprüft.
    static let maximumSizes = 3

    func load(reference: Product,
              referenceUnitPrice: UnitPrice?,
              using environment: AppEnvironment) async {

        guard let referenceQuantity = reference.quantity else {
            state = .noneFound
            return
        }

        state = .loading

        do {
            let candidates = try await environment.products.search(reference.name, pageSize: 30)
            guard !Task.isCancelled else { return }

            // Nur andere Größen desselben Artikels -- `comparable` heißt
            // genau das: gleiches Produkt, andere Gesamtmenge.
            var seenTotals: Set<Decimal> = [referenceQuantity.totalInBaseUnit]
            var wanted: [Product] = []

            for candidate in candidates {
                guard wanted.count < Self.maximumSizes else { break }
                guard let quantity = candidate.quantity,
                      seenTotals.insert(quantity.totalInBaseUnit).inserted else { continue }

                let match = ProductMatcher.match(reference, candidate)
                guard case .comparable = match else { continue }
                wanted.append(candidate)
            }

            guard !wanted.isEmpty else {
                state = .noneFound
                return
            }

            var results: [Comparison] = []
            for product in wanted {
                if Task.isCancelled { return }
                if let comparison = await compare(product,
                                                  against: referenceUnitPrice,
                                                  using: environment) {
                    results.append(comparison)
                }
            }

            // Günstigster Grundpreis zuerst.
            results.sort { $0.unitPrice.normalizedPerBaseUnit < $1.unitPrice.normalizedPerBaseUnit }
            state = results.isEmpty ? .noneFound : .comparisons(results)

        } catch let error as DataSourceError {
            guard !Task.isCancelled, error != .cancelled else { return }
            state = .failed(error.userMessage)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed("Der Vergleich war nicht möglich.")
        }
    }

    /// Holt den günstigsten Preis für eine Packungsgröße und rechnet den
    /// Grundpreis. Gibt `nil` zurück, wenn kein Preis vorliegt -- eine Größe
    /// ohne Preis ist kein Vergleich.
    private func compare(_ product: Product,
                         against reference: UnitPrice?,
                         using environment: AppEnvironment) async -> Comparison? {

        guard let barcode = product.barcode, let quantity = product.quantity else { return nil }

        let settings = environment.settings
        let coordinate = environment.activeCoordinate
        let radiusKm = settings.maxDistanceMeters.map { $0 / 1000 } ?? 25

        guard let observations = try? await environment.prices.prices(
            barcode: barcode,
            near: coordinate,
            radiusKm: max(1, min(25, radiusKm)),
            limit: 20
        ) else { return nil }

        let usable = observations.filter { settings.includes(retailer: $0.retailer) }
        guard let best = usable.min(by: { $0.price.amount < $1.price.amount }),
              let unitPrice = UnitPrice.calculate(price: best.price, quantity: quantity)
        else { return nil }

        return Comparison(
            product: product,
            bestPrice: best.price,
            unitPrice: unitPrice,
            storeName: best.store?.displayName ?? best.retailer?.name,
            advantage: reference.flatMap { unitPrice.relativeAdvantage(over: $0) }
        )
    }
}
