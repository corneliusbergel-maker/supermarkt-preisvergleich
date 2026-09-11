import Foundation
import Observation
import PriceCore
import PriceData

/// Lädt und bewertet die Preise zu einem Produkt.
@MainActor
@Observable
final class ProductDetailViewModel {

    enum State {
        case idle
        case loading
        case loaded(PriceComparison)
        case failed(message: String, isRetryable: Bool)
    }

    /// Auswertung des Preisverlaufs (#10).
    ///
    /// Entsteht nur, wenn genügend Beobachtungen vorliegen. Ein „Verlauf“ aus
    /// zwei Punkten wäre eine Linie durch Zufall.
    struct History {

        struct Point: Identifiable {
            let date: Date
            let amount: Decimal
            var id: Date { date }
        }

        static let minimumPoints = 4

        let points: [Point]
        let lowest: Money
        let highest: Money
        let average: Money
        let days: Int

        /// Einordnung des aktuellen Bestpreises, z. B. „12 % unter dem
        /// Durchschnitt der letzten 90 Tage“. `nil`, wenn die Abweichung so
        /// klein ist, dass eine Aussage darüber Schein­genauigkeit wäre.
        func assessment(of current: Money) -> String? {
            guard average.amount > 0 else { return nil }
            let change = (current.amount - average.amount) / average.amount
            let percent = abs(NSDecimalNumber(decimal: change).doubleValue * 100)
            guard percent >= 3 else { return nil }

            let rounded = Int(percent.rounded())
            return change < 0
                ? "\(rounded) % unter dem Durchschnitt der letzten \(days) Tage"
                : "\(rounded) % über dem Durchschnitt der letzten \(days) Tage"
        }

        /// Gehört der Preis zu den niedrigsten des Zeitraums?
        func isNearLow(_ current: Money) -> Bool {
            guard highest.amount > lowest.amount else { return false }
            let span = highest.amount - lowest.amount
            return (current.amount - lowest.amount) <= span / 10
        }
    }

    let product: Product

    private(set) var state: State = .idle
    private(set) var history: History?
    private(set) var detour: DetourAdvice?

    /// Wie viele Preise es vor dem Anwenden der Filter gab -- damit die
    /// Oberfläche sagen kann, was der Filter gerade verbirgt.
    private(set) var totalBeforeFilter = 0

    private let historyWindowDays = 90

    init(product: Product) {
        self.product = product
    }

    /// Lädt Preise und Verlauf.
    func load(using environment: AppEnvironment) async {
        guard let barcode = product.barcode, !barcode.isEmpty else {
            // Ohne Barcode lässt sich in Open Prices nichts sicher zuordnen.
            state = .loaded(.noData)
            return
        }

        state = .loading
        detour = nil
        history = nil

        let settings = environment.settings
        let coordinate = environment.activeCoordinate
        let radiusKm = (settings.maxDistanceMeters.map { $0 / 1000 } ?? 25)

        do {
            let observations = try await environment.prices.prices(
                barcode: barcode,
                near: coordinate,
                radiusKm: max(1, min(25, radiusKm)),
                limit: 50
            )
            guard !Task.isCancelled else { return }

            let offers = observations.map { makeOffer($0, from: coordinate) }
            totalBeforeFilter = offers.count

            let comparison = PriceComparator.compare(
                offers,
                allowedRetailerIDs: settings.enabledRetailerIDs.isEmpty
                    ? nil
                    : allowedIdentifiers(in: offers, settings: settings),
                maxDistanceMeters: settings.maxDistanceMeters,
                sortedBy: settings.sortCriterion,
                costPerKilometer: Money(amount: settings.costPerKilometer)
            )

            state = .loaded(comparison)
            detour = PriceComparator.detourAdvice(
                for: comparison.offers,
                costPerKilometer: Money(amount: settings.costPerKilometer)
            )

            await loadHistory(barcode: barcode, using: environment)

        } catch let error as DataSourceError {
            guard !Task.isCancelled, error != .cancelled else { return }
            state = .failed(message: error.userMessage, isRetryable: error.isRetryable)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(message: "Die Preise konnten nicht geladen werden.",
                            isRetryable: true)
        }
    }

    // MARK: - Verlauf

    private func loadHistory(barcode: String, using environment: AppEnvironment) async {
        let since = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -historyWindowDays, to: Date()) ?? Date()

        // Ein fehlender Verlauf ist kein Fehler der Seite -- der Preisvergleich
        // steht bereits. Deshalb wird hier still abgebrochen.
        guard let observations = try? await environment.prices.priceHistory(
            barcode: barcode, since: since, limit: 100
        ) else { return }

        history = makeHistory(from: observations)
    }

    func makeHistory(from observations: [PriceObservation]) -> History? {
        let currency = observations.first?.price.currency ?? "EUR"
        let usable = observations.filter { $0.price.currency == currency }
        guard usable.count >= History.minimumPoints else { return nil }

        let amounts = usable.map(\.price.amount)
        guard let lowest = amounts.min(), let highest = amounts.max() else { return nil }

        let total = amounts.reduce(Decimal(0), +)
        let average = total / Decimal(amounts.count)

        let points = usable
            .map { History.Point(date: $0.observedOn, amount: $0.price.amount) }
            .sorted { $0.date < $1.date }

        return History(points: points,
                       lowest: Money(amount: lowest, currency: currency),
                       highest: Money(amount: highest, currency: currency),
                       average: Money(amount: average, currency: currency),
                       days: historyWindowDays)
    }

    // MARK: - Innereien

    /// Baut aus einer Beobachtung ein Angebot samt Grundpreis und Entfernung.
    func makeOffer(_ observation: PriceObservation, from coordinate: Coordinate?) -> PriceOffer {
        // Ohne bekannte Menge gibt es keinen Grundpreis -- und es wird auch
        // keiner geschätzt.
        let unitPrice = product.quantity.flatMap {
            UnitPrice.calculate(price: observation.price, quantity: $0)
        }

        let distance: Double? = {
            guard let coordinate, let store = observation.store else { return nil }
            return GeoDistance.straightLineMeters(from: coordinate, to: store.coordinate)
        }()

        return PriceOffer(observation: observation,
                          unitPrice: unitPrice,
                          distanceMeters: distance)
    }

    /// Übersetzt die eingeschalteten Ketten in die Kennungen, die in **diesen**
    /// Angeboten tatsächlich vorkommen.
    ///
    /// Nötig, weil Filialen aus OpenStreetMap eine Wikidata-Kennung tragen,
    /// Preise aus Open Prices aber nur den Markennamen. Ein Filter auf die
    /// eine Sorte würde die andere aussperren.
    private func allowedIdentifiers(in offers: [PriceOffer],
                                    settings: AppSettings) -> Set<String> {
        var allowed: Set<String> = []
        for offer in offers {
            guard let retailer = offer.observation.retailer else { continue }
            if settings.includes(retailer: retailer) {
                allowed.insert(retailer.id)
            }
        }
        return allowed
    }
}
