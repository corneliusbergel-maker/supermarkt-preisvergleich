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

    /// Vollständiger Datensatz, über den Barcode nachgeladen.
    ///
    /// Der Suchindex führt keine strukturierte Menge, nur den Freitext. Lässt
    /// der sich nicht deuten, fehlt der Grundpreis – dann lohnt sich die
    /// zusätzliche Abfrage.
    private(set) var detailedProduct: Product?

    /// Der Datensatz, mit dem gerechnet und der angezeigt wird.
    var displayProduct: Product { detailedProduct ?? product }

    private(set) var state: State = .idle
    private(set) var history: History?
    private(set) var detour: DetourAdvice?

    /// Veränderung gegenüber der letzten abweichenden Beobachtung (#25).
    /// `nil`, wenn es keine verwertbare Vorgeschichte gibt.
    private(set) var priceChange: PriceChange?

    /// Wie viele Preise es vor dem Anwenden der Filter gab -- damit die
    /// Oberfläche sagen kann, was der Filter gerade verbirgt.
    private(set) var totalBeforeFilter = 0

    /// Ein Supermarkt in der Übersicht „Preise nach Supermarkt“.
    struct ChainPrice: Identifiable {

        enum Source {
            /// Angebot direkt von der Kette, über `OfferMatcher` streng zugeordnet.
            case marketOffer(RetailerOffer, viaVariety: Bool)
            /// Von Menschen bei Open Prices eingetragen.
            case openPrices(PriceObservation)
        }

        /// Name wie in den Einstellungen, bei weiteren Märkten wie in den Daten.
        let chainName: String
        let price: Money?
        let source: Source?
        /// Filiale mit Beleg, sonst die nächste Filiale der Kette.
        let nearestStore: Store?
        let distanceMeters: Double?
        /// Offizielle Angebotsseite, soweit bekannt.
        let offersPage: URL?
        /// Aktuell genug und aus der Nähe – nur dann zählt der Preis als
        /// günstigster Supermarkt.
        let isCurrent: Bool
        /// Der Preis ist in einer weit entfernten Filiale belegt, etwa in einer
        /// anderen Stadt. Für die Filiale hier sagt er nichts.
        let isRemote: Bool
        /// `nearestStore` ist die Filiale, in der der Preis belegt ist.
        let storeHasPrice: Bool
        /// Die Kette veröffentlicht Angebote, die die App direkt liest.
        let hasDirectOffers: Bool

        var id: String { chainName }
    }

    /// Jede eingeschaltete Kette mit ihrem günstigsten bekannten Preis.
    /// Die günstigsten aktuellen zuerst, Ketten ohne Preis am Ende.
    private(set) var chainPrices: [ChainPrice] = []

    /// Preise aus der Umgebung und aus ganz Deutschland – Grundlage der Übersicht.
    private var nearbyObservations: [PriceObservation] = []
    private var historyObservations: [PriceObservation] = []

    private let historyWindowDays = 90

    /// Umkreis für die nächste Filiale je Kette. Derselbe wie die Voreinstellung
    /// der Filialsuche – so teilen sich beide den Zwischenspeicher.
    private let storeRadiusKm: Double = 5

    init(product: Product) {
        self.product = product
    }

    /// Lädt Preise, Verlauf und die Übersicht nach Supermarkt.
    func load(using environment: AppEnvironment) async {
        await loadPrices(using: environment)
        guard !Task.isCancelled else { return }
        await loadChainPrices(using: environment)
    }

    /// Lädt Preise und Verlauf aus Open Prices.
    private func loadPrices(using environment: AppEnvironment) async {
        nearbyObservations = []
        historyObservations = []

        guard let barcode = product.barcode, !barcode.isEmpty else {
            // Ohne Barcode lässt sich in Open Prices nichts sicher zuordnen.
            state = .loaded(.noData)
            return
        }

        state = .loading
        detour = nil
        history = nil
        priceChange = nil

        let settings = environment.settings
        let coordinate = environment.activeCoordinate
        let radiusKm = (settings.maxDistanceMeters.map { $0 / 1000 } ?? 25)

        // Nur nachladen, wenn ohne den vollständigen Datensatz kein Grundpreis
        // möglich wäre. Eine Abfrage zu sparen ist gegenüber einem
        // gemeinnützig betriebenen Dienst die richtige Voreinstellung.
        if product.quantity == nil {
            detailedProduct = try? await environment.products.product(barcode: barcode)
        }

        do {
            let observations = try await environment.prices.prices(
                barcode: barcode,
                near: coordinate,
                radiusKm: max(1, min(25, radiusKm)),
                limit: 50
            )
            guard !Task.isCancelled else { return }
            nearbyObservations = observations

            let offers = observations.map { makeOffer($0, from: coordinate) }
            totalBeforeFilter = offers.count

            let comparison = PriceComparator.compare(
                offers,
                // Immer über `includes` filtern: Auch mit allen Ketten aus
                // bleibt „Andere Märkte“ eine eigene Entscheidung.
                allowedRetailerIDs: allowedIdentifiers(in: offers, settings: settings),
                maxDistanceMeters: PriceComparator.effectiveDistanceLimit(
                    settings.maxDistanceMeters,
                    hasReferencePoint: coordinate != nil
                ),
                sortedBy: settings.sortCriterion,
                costPerKilometer: Money(amount: settings.costPerKilometer)
            )

            state = .loaded(comparison)
            detour = PriceComparator.detourAdvice(
                for: comparison.offers,
                costPerKilometer: Money(amount: settings.costPerKilometer)
            )

            await loadHistory(barcode: barcode,
                              shownPrice: comparison.offers.first?.observation,
                              using: environment)

        } catch let error as DataSourceError {
            guard !Task.isCancelled, error != .cancelled else { return }
            state = .failed(message: error.userMessage, isRetryable: error.offersManualRetry)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(message: "Die Preise konnten nicht geladen werden.",
                            isRetryable: true)
        }
    }

    // MARK: - Verlauf

    /// - Parameter shownPrice: der Preis in der Bestpreis-Karte. Die
    ///   Preisänderung darunter muss sich auf genau diesen Preis beziehen,
    ///   nicht auf den neuesten irgendwo in Deutschland.
    private func loadHistory(barcode: String,
                             shownPrice: PriceObservation?,
                             using environment: AppEnvironment) async {
        let since = Calendar(identifier: .gregorian)
            .date(byAdding: .day, value: -historyWindowDays, to: Date()) ?? Date()

        // Ein fehlender Verlauf ist kein Fehler der Seite -- der Preisvergleich
        // steht bereits. Deshalb wird hier still abgebrochen.
        guard let observations = try? await environment.prices.priceHistory(
            barcode: barcode, since: since, limit: 100
        ) else { return }

        historyObservations = observations
        history = makeHistory(from: observations)
        priceChange = shownPrice.flatMap { PriceChange.forPrice($0, history: observations) }
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

    // MARK: - Preise nach Supermarkt

    /// Baut die Übersicht in drei Schritten, damit nichts auf den langsamsten
    /// Dienst wartet: sofort mit den schon vorhandenen Angeboten, nach dem
    /// Auffrischen der Angebote erneut und zuletzt mit den Filialen.
    private func loadChainPrices(using environment: AppEnvironment) async {
        let settings = environment.settings
        let coordinate = environment.activeCoordinate
        let marketStore = environment.marketOffers
        let sources = marketStore.enabledSources(settings)
        let direct = Set(sources.compactMap { RetailerRegistry.identifier(forBrand: $0.settingsName) })

        chainPrices = makeChainPrices(offers: marketStore.currentOffers(from: sources),
                                      stores: [], settings: settings, coordinate: coordinate,
                                      directOfferChains: direct)

        // Aus dem gemeinsamen Speicher: Hat die Startseite die Angebote gerade
        // geladen, kostet das keinen weiteren Abruf.
        await marketStore.refresh(sources)
        guard !Task.isCancelled else { return }
        let offers = marketStore.currentOffers(from: sources)
        chainPrices = makeChainPrices(offers: offers, stores: [], settings: settings,
                                      coordinate: coordinate, directOfferChains: direct)

        guard let coordinate,
              let stores = try? await environment.stores.stores(near: coordinate,
                                                                radiusKm: storeRadiusKm),
              !Task.isCancelled else { return }
        chainPrices = makeChainPrices(offers: offers, stores: stores, settings: settings,
                                      coordinate: coordinate, directOfferChains: direct)
    }

    func makeChainPrices(offers: [RetailerOffer],
                         stores: [Store],
                         settings: AppSettings,
                         coordinate: Coordinate?,
                         directOfferChains: Set<String> = [],
                         now: Date = Date()) -> [ChainPrice] {
        let product = displayProduct
        func key(_ name: String?) -> String? { RetailerRegistry.identifier(forBrand: name) }

        /// Liegt die Filiale des Belegs in der Nähe? Ohne Bezugspunkt sucht die
        /// App ohnehin in ganz Deutschland – dann gilt jeder Beleg als nah.
        func isNearby(_ observation: PriceObservation) -> Bool {
            guard let coordinate else { return true }
            guard let observed = observation.store,
                  let meters = GeoDistance.straightLineMeters(from: coordinate, to: observed.coordinate)
            else { return false }
            return meters <= 25_000
        }

        var seen = Set<String>()
        let observations = (nearbyObservations + historyObservations)
            .filter { seen.insert($0.id).inserted }

        // Nur Angebote mit normalem Preis – Kartenpreise gelten nicht für alle.
        let matchedOffers = offers.compactMap { offer -> (RetailerOffer, OfferMatcher.Result)? in
            guard offer.price != nil else { return nil }
            let result = OfferMatcher.match(product, offer)
            return result.isMatch ? (offer, result) : nil
        }

        var names = AppSettings.selectableRetailers.filter { settings.isEnabled(retailerNamed: $0) }
        // Weitere Märkte, für die Open Prices einen Preis kennt – etwa Globus.
        if settings.includeOtherRetailers {
            for observation in observations {
                guard let name = observation.retailer?.name, let chainKey = key(name),
                      !AppSettings.selectableRetailerIDs.contains(chainKey),
                      !names.contains(where: { key($0) == chainKey }) else { continue }
                names.append(name)
            }
        }

        let rows = names.compactMap { name -> ChainPrice? in
            guard let chainKey = key(name) else { return nil }

            let bestOffer = matchedOffers
                .filter { key($0.0.retailerName) == chainKey }
                .min { ($0.0.price?.amount ?? 0) < ($1.0.price?.amount ?? 0) }

            let chainObservations = observations.filter { key($0.retailer?.name) == chainKey }
            let currentObservations = chainObservations.filter { $0.confidence(asOf: now) >= .medium }
            // Belege aus der Nähe zuerst, dann aus ganz Deutschland, dann ältere.
            let bestObservation = currentObservations.filter(isNearby).min { $0.price.amount < $1.price.amount }
                ?? currentObservations.min { $0.price.amount < $1.price.amount }
                ?? chainObservations.max { $0.observedOn < $1.observedOn }

            var source: ChainPrice.Source?
            var price: Money?
            var isCurrent = false

            // Ein gültiges Angebot schlägt einen älteren oder teureren Beleg.
            if let best = bestOffer, let offerPrice = best.0.price {
                let observationIsBetter = bestObservation.map {
                    $0.confidence(asOf: now) >= .medium && isNearby($0) && $0.price.amount < offerPrice.amount
                } ?? false
                if !observationIsBetter {
                    source = .marketOffer(best.0, viaVariety: best.1 == .matches(viaVariety: true))
                    price = offerPrice
                    isCurrent = true
                }
            }
            var isRemote = false
            if source == nil, let observation = bestObservation {
                source = .openPrices(observation)
                price = observation.price
                isRemote = !isNearby(observation)
                // Ein Preis aus einer anderen Stadt belegt nichts für die Filiale
                // hier – er darf nicht als günstigster Supermarkt erscheinen.
                isCurrent = observation.confidence(asOf: now) >= .medium && !isRemote
            }

            // Die richtige Filiale: die mit dem Beleg, wenn sie in der Nähe liegt,
            // sonst die nächste Filiale der Kette.
            var store: Store?
            var distance: Double?
            var storeHasPrice = false
            if let coordinate {
                if case .openPrices(let observation)? = source,
                   let observed = observation.store,
                   let meters = GeoDistance.straightLineMeters(from: coordinate, to: observed.coordinate),
                   meters <= 25_000 {
                    store = observed
                    distance = meters
                    storeHasPrice = true
                }
                if store == nil {
                    // Filialen ohne berechenbare Entfernung zählen nicht als „nächste“.
                    let nearest = stores
                        .filter { key($0.retailer.name) == chainKey }
                        .compactMap { candidate -> (Store, Double)? in
                            GeoDistance.straightLineMeters(from: coordinate, to: candidate.coordinate)
                                .map { (candidate, $0) }
                        }
                        .min { $0.1 < $1.1 }
                    store = nearest?.0
                    distance = nearest?.1
                }
            }

            return ChainPrice(chainName: name,
                              price: price,
                              source: source,
                              nearestStore: store,
                              distanceMeters: distance,
                              offersPage: RetailerOffersPages.all.first { $0.name == name }?.url,
                              isCurrent: isCurrent,
                              isRemote: isRemote,
                              storeHasPrice: storeHasPrice,
                              hasDirectOffers: directOfferChains.contains(chainKey))
        }

        // Aktuelle Preise aufsteigend, dann ältere, dann Ketten ohne Preis –
        // diese in der Reihenfolge der Einstellungen.
        return rows.enumerated().sorted { lhs, rhs in
            func group(_ row: ChainPrice) -> Int {
                row.price == nil ? 2 : (row.isCurrent ? 0 : 1)
            }
            let (left, right) = (group(lhs.element), group(rhs.element))
            if left != right { return left < right }
            if let a = lhs.element.price?.amount, let b = rhs.element.price?.amount, a != b { return a < b }
            return lhs.offset < rhs.offset
        }.map { $0.element }
    }

    // MARK: - Innereien

    /// Baut aus einer Beobachtung ein Angebot samt Grundpreis und Entfernung.
    func makeOffer(_ observation: PriceObservation, from coordinate: Coordinate?) -> PriceOffer {
        // Ohne bekannte Menge gibt es keinen Grundpreis -- und es wird auch
        // keiner geschätzt.
        let unitPrice = displayProduct.quantity.flatMap {
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
