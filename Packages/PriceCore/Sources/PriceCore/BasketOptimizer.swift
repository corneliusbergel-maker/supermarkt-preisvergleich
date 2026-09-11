import Foundation

/// Ein Posten auf der Einkaufsliste.
public struct BasketItem: Hashable, Sendable, Identifiable {

    public let id: String

    /// Anzeigename, z. B. "Milch 1 l".
    public let displayName: String

    /// Wie oft der Posten gekauft werden soll.
    public let count: Int

    /// Alle bekannten Preise fuer diesen Posten.
    public let offers: [PriceOffer]

    public init(id: String, displayName: String, count: Int = 1, offers: [PriceOffer]) {
        self.id = id
        self.displayName = displayName
        self.count = max(1, count)
        self.offers = offers
    }

    /// Angebote, die einem Ort zugeordnet sind. Nur die taugen zur Planung --
    /// zu einem unbekannten Ort kann man nicht einkaufen fahren.
    var plannableOffers: [PriceOffer] {
        offers.filter { BasketOptimizer.locationKey(for: $0) != nil }
    }
}

/// Eine Zeile im Einkaufsplan: Posten, gewaehltes Angebot, Zeilensumme.
public struct BasketLine: Hashable, Sendable {
    public let item: BasketItem
    public let offer: PriceOffer

    public var lineTotal: Money { offer.price * item.count }
}

/// Was in einem einzelnen Markt gekauft wird.
public struct StoreBasket: Hashable, Sendable, Identifiable {

    public let id: String
    public let store: Store?
    public let retailer: Retailer?
    public let lines: [BasketLine]

    public var displayName: String {
        store?.displayName ?? retailer?.name ?? "Unbekannter Markt"
    }

    /// Entfernung zu diesem Markt, sofern bekannt.
    public var distanceMeters: Double? {
        lines.compactMap { $0.offer.distanceMeters }.min()
    }

    public var total: Money? {
        Money.sum(lines.map(\.lineTotal))
    }
}

/// Ein vollstaendiger Einkaufsplan.
public struct BasketPlan: Hashable, Sendable {

    public let strategy: Strategy
    public let baskets: [StoreBasket]

    /// Posten, fuer die es **nirgends** verwertbare Preisdaten gibt.
    /// Sie verschwinden nicht stillschweigend aus der Rechnung.
    public let itemsWithoutPrice: [BasketItem]

    /// Summe ueber alle Maerkte -- gilt ausdruecklich nur fuer die Posten in
    /// `baskets`, nicht fuer die gesamte Einkaufsliste.
    public let total: Money

    public var storeCount: Int { baskets.count }

    public var coveredItemCount: Int {
        baskets.reduce(0) { $0 + $1.lines.count }
    }

    /// Ist die Liste vollstaendig abgedeckt?
    public var isComplete: Bool { itemsWithoutPrice.isEmpty }

    /// Der am weitesten entfernte Markt des Plans.
    public var farthestStoreMeters: Double? {
        baskets.compactMap(\.distanceMeters).max()
    }

    public enum Strategy: Hashable, Sendable {
        /// Jeder Posten dort, wo er am guenstigsten ist -- ohne Ruecksicht auf
        /// die Anzahl der Maerkte.
        case cheapestOverall
        /// Alles in einem einzigen Markt.
        case singleStore
        /// Hoechstens n Maerkte.
        case atMostStores(Int)
        /// Preis plus angenommene Fahrtkosten.
        case bestValue

        public var label: String {
            switch self {
            case .cheapestOverall: return "Günstigste Variante"
            case .singleStore: return "Alles in einem Markt"
            case .atMostStores(let n): return "Höchstens \(n) Märkte"
            case .bestValue: return "Beste Kombination aus Preis und Weg"
            }
        }
    }
}

/// Berechnet Einkaufsplaene fuer eine Einkaufsliste.
///
/// Grundsatz: Ein Markt darf nur dann fuer einen Posten eingeplant werden,
/// wenn dort tatsaechlich ein Preis dafuer bekannt ist. Fehlende Preisdaten
/// werden **nie** als "gibt es dort nicht" oder "kostet dort dasselbe"
/// ausgelegt -- beides waere erfunden.
public enum BasketOptimizer {

    /// Wie viele Maerkte bei der Kombinationssuche hoechstens betrachtet werden.
    ///
    /// Die exakte Suche nach der besten Marktkombination ist ein
    /// Mengenueberdeckungsproblem und waechst exponentiell. Deshalb werden nur
    /// die Maerkte mit der besten Abdeckung untersucht. Das ist eine bewusste
    /// Naeherung; sie ist hier dokumentiert statt versteckt.
    public static let maximumCandidateStores = 12

    static func locationKey(for offer: PriceOffer) -> String? {
        if let store = offer.observation.store { return "store:\(store.id)" }
        if let retailer = offer.observation.retailer { return "retailer:\(retailer.id)" }
        return nil
    }

    // MARK: - Jeder Posten dort, wo er am guenstigsten ist

    /// Anforderung #17: guenstigster Preis je Posten, egal in wie vielen Maerkten.
    public static func cheapestOverall(_ items: [BasketItem]) -> BasketPlan? {
        var chosen: [(BasketItem, PriceOffer)] = []
        var missing: [BasketItem] = []

        for item in items {
            if let best = item.plannableOffers.min(by: { $0.price.amount < $1.price.amount }) {
                chosen.append((item, best))
            } else {
                missing.append(item)
            }
        }

        return makePlan(strategy: .cheapestOverall, selections: chosen, missing: missing)
    }

    // MARK: - Alles in einem Markt

    /// Anforderung #18: der guenstigste Markt, in dem die Liste **vollstaendig**
    /// zu bekommen ist.
    ///
    /// Ein Markt kommt nur infrage, wenn fuer jeden Posten ein Preis vorliegt.
    /// Maerkte mit Luecken werden nicht "hochgerechnet".
    public static func bestSingleStore(_ items: [BasketItem]) -> BasketPlan? {
        let plannable = items.filter { !$0.plannableOffers.isEmpty }
        let missing = items.filter { $0.plannableOffers.isEmpty }
        guard !plannable.isEmpty else { return nil }

        var bestPlan: BasketPlan?

        for key in allLocationKeys(in: plannable) {
            var selections: [(BasketItem, PriceOffer)] = []
            var complete = true

            for item in plannable {
                let candidates = item.plannableOffers.filter { locationKey(for: $0) == key }
                guard let best = candidates.min(by: { $0.price.amount < $1.price.amount }) else {
                    complete = false
                    break
                }
                selections.append((item, best))
            }

            guard complete,
                  let plan = makePlan(strategy: .singleStore,
                                      selections: selections,
                                      missing: missing) else { continue }

            if bestPlan == nil || plan.total.amount < bestPlan!.total.amount {
                bestPlan = plan
            }
        }

        return bestPlan
    }

    /// Maerkte, die die Liste nur teilweise abdecken -- fuer den ehrlichen
    /// Hinweis "Kaufland hat Preise fuer 3 von 5 Artikeln".
    public static func coverageByStore(_ items: [BasketItem]) -> [(name: String, covered: Int, total: Int)] {
        let plannable = items.filter { !$0.plannableOffers.isEmpty }
        guard !plannable.isEmpty else { return [] }

        return allLocationKeys(in: plannable).map { key in
            let covered = plannable.filter { item in
                item.plannableOffers.contains { locationKey(for: $0) == key }
            }.count
            let name = plannable
                .flatMap(\.plannableOffers)
                .first { locationKey(for: $0) == key }
                .map { $0.observation.store?.displayName
                    ?? $0.observation.retailer?.name
                    ?? "Unbekannter Markt" } ?? "Unbekannter Markt"
            return (name: name, covered: covered, total: plannable.count)
        }
        .sorted { $0.covered > $1.covered }
    }

    // MARK: - Beste Kombination aus wenigen Maerkten

    /// Anforderung #18: die guenstigste Kombination aus hoechstens `maxStores`
    /// Maerkten, die die Liste vollstaendig abdeckt.
    public static func bestCombination(_ items: [BasketItem],
                                       maxStores: Int) -> BasketPlan? {
        guard maxStores >= 1 else { return nil }
        if maxStores == 1 { return bestSingleStore(items) }

        return searchCombinations(items,
                                  maxStores: maxStores,
                                  strategy: .atMostStores(maxStores)) { $0.total.amount }
    }

    /// Durchsucht Marktkombinationen und waehlt die nach `score` beste aus.
    ///
    /// Der Bewertungsmassstab wird von aussen hereingereicht, weil sich
    /// "guenstigster Warenwert" und "guenstigster Gesamtaufwand inklusive
    /// Fahrt" zu **unterschiedlichen** Kombinationen fuehren koennen. Wer
    /// erst nach Preis auswaehlt und danach die Fahrtkosten draufrechnet,
    /// findet den nahen, etwas teureren Markt nie.
    private static func searchCombinations(_ items: [BasketItem],
                                           maxStores: Int,
                                           strategy: BasketPlan.Strategy,
                                           score: (BasketPlan) -> Decimal) -> BasketPlan? {
        let plannable = items.filter { !$0.plannableOffers.isEmpty }
        let missing = items.filter { $0.plannableOffers.isEmpty }
        guard !plannable.isEmpty else { return nil }

        let candidates = topCandidateKeys(in: plannable)
        var bestPlan: BasketPlan?
        var bestScore: Decimal?

        for combination in combinations(of: candidates, upTo: min(maxStores, candidates.count)) {
            guard let plan = plan(for: plannable,
                                  allowedKeys: Set(combination),
                                  missing: missing,
                                  strategy: strategy) else { continue }

            let value = score(plan)
            if bestScore == nil
                || value < bestScore!
                || (value == bestScore! && plan.storeCount < bestPlan!.storeCount) {
                bestPlan = plan
                bestScore = value
            }
        }

        return bestPlan
    }

    /// Plant die Liste unter der Auflage, nur die erlaubten Maerkte zu nutzen.
    /// Gibt `nil` zurueck, sobald ein Posten dort nirgends einen Preis hat --
    /// eine Kombination, die die Liste nicht abdeckt, ist keine Loesung.
    private static func plan(for items: [BasketItem],
                             allowedKeys: Set<String>,
                             missing: [BasketItem],
                             strategy: BasketPlan.Strategy) -> BasketPlan? {
        var selections: [(BasketItem, PriceOffer)] = []

        for item in items {
            let candidateOffers = item.plannableOffers.filter {
                guard let key = locationKey(for: $0) else { return false }
                return allowedKeys.contains(key)
            }
            guard let best = candidateOffers.min(by: { $0.price.amount < $1.price.amount }) else {
                return nil
            }
            selections.append((item, best))
        }

        return makePlan(strategy: strategy, selections: selections, missing: missing)
    }

    // MARK: - Preis und Weg zusammen

    /// Anforderung #18: guenstigste Gesamtrechnung **einschliesslich**
    /// angenommener Fahrtkosten.
    ///
    /// Annahme, die in der Oberflaeche genannt werden muss: jeder Markt wird
    /// einzeln von zu Hause aus angefahren. Das ist eine Obergrenze -- eine
    /// echte Rundreise waere kuerzer, laesst sich aber ohne Routing-Dienst
    /// nicht berechnen.
    public static func bestValue(_ items: [BasketItem],
                                 maxStores: Int = 3,
                                 costPerKilometer: Money? = nil) -> BasketPlan? {
        let rate = costPerKilometer ?? PriceComparator.defaultCostPerKilometer
        let value: (BasketPlan) -> Decimal = { effectiveTotal(of: $0, rate: rate) }

        // Die Kombinationssuche arbeitet auf einer gekappten Marktliste
        // (siehe `maximumCandidateStores`). Der exakt ermittelte beste
        // Einzelmarkt kommt deshalb als zusaetzlicher Kandidat dazu, damit die
        // Kappung nie die naheliegendste Loesung verschluckt.
        let candidates = [
            searchCombinations(items, maxStores: max(1, maxStores), strategy: .bestValue, score: value),
            bestSingleStore(items)
        ].compactMap { $0 }

        guard let best = candidates.min(by: { value($0) < value($1) }) else { return nil }

        return BasketPlan(strategy: .bestValue,
                          baskets: best.baskets,
                          itemsWithoutPrice: best.itemsWithoutPrice,
                          total: best.total)
    }

    /// Warenwert plus angenommene Fahrtkosten (Hin- und Rueckweg je Markt).
    public static func effectiveTotal(of plan: BasketPlan, rate: Money) -> Decimal {
        let travel = plan.baskets.reduce(Decimal(0)) { sum, basket in
            guard let meters = basket.distanceMeters else { return sum }
            return sum + Decimal(meters * 2 / 1000) * rate.amount
        }
        return plan.total.amount + travel
    }

    // MARK: - Vorschlaege fuer die Oberflaeche

    /// Liefert die Plaene, die dem Nutzer zur Wahl gestellt werden.
    /// Doppelte Vorschlaege (gleiche Maerkte, gleiche Summe) fallen heraus.
    public static func recommendations(_ items: [BasketItem],
                                       maxStores: Int = 3,
                                       costPerKilometer: Money? = nil) -> [BasketPlan] {
        let candidates = [
            cheapestOverall(items),
            bestSingleStore(items),
            bestCombination(items, maxStores: 2),
            bestValue(items, maxStores: maxStores, costPerKilometer: costPerKilometer)
        ].compactMap { $0 }

        var seen: Set<String> = []
        var unique: [BasketPlan] = []
        for plan in candidates {
            let fingerprint = plan.baskets.map(\.id).sorted().joined(separator: "|")
                + "@\(plan.total.amount)"
            if seen.insert(fingerprint).inserted { unique.append(plan) }
        }
        return unique
    }

    // MARK: - Innereien

    private static func allLocationKeys(in items: [BasketItem]) -> [String] {
        var keys: Set<String> = []
        for item in items {
            for offer in item.plannableOffers {
                if let key = locationKey(for: offer) { keys.insert(key) }
            }
        }
        return keys.sorted()
    }

    /// Beschraenkt die Kombinationssuche auf die Maerkte mit der besten
    /// Abdeckung. Ohne diese Kappung waechst der Aufwand exponentiell.
    private static func topCandidateKeys(in items: [BasketItem]) -> [String] {
        let keys = allLocationKeys(in: items)
        guard keys.count > maximumCandidateStores else { return keys }

        let ranked = keys.map { key -> (String, Int) in
            let covered = items.filter { item in
                item.plannableOffers.contains { locationKey(for: $0) == key }
            }.count
            return (key, covered)
        }
        .sorted { $0.1 > $1.1 }

        return Array(ranked.prefix(maximumCandidateStores).map(\.0))
    }

    /// Alle Teilmengen der Groesse 1 bis `limit`.
    private static func combinations(of keys: [String], upTo limit: Int) -> [[String]] {
        var result: [[String]] = []

        func build(start: Int, current: [String]) {
            if !current.isEmpty { result.append(current) }
            guard current.count < limit else { return }
            for index in start..<keys.count {
                build(start: index + 1, current: current + [keys[index]])
            }
        }

        build(start: 0, current: [])
        return result
    }

    private static func makePlan(strategy: BasketPlan.Strategy,
                                 selections: [(BasketItem, PriceOffer)],
                                 missing: [BasketItem]) -> BasketPlan? {
        guard !selections.isEmpty else { return nil }

        var grouped: [String: [BasketLine]] = [:]
        for (item, offer) in selections {
            guard let key = locationKey(for: offer) else { continue }
            grouped[key, default: []].append(BasketLine(item: item, offer: offer))
        }
        guard !grouped.isEmpty else { return nil }

        let baskets = grouped
            .map { key, lines -> StoreBasket in
                StoreBasket(id: key,
                            store: lines.first?.offer.observation.store,
                            retailer: lines.first?.offer.observation.retailer,
                            lines: lines.sorted { $0.item.displayName < $1.item.displayName })
            }
            .sorted { ($0.total?.amount ?? 0) > ($1.total?.amount ?? 0) }

        guard let total = Money.sum(baskets.flatMap { $0.lines.map(\.lineTotal) }) else {
            return nil
        }

        return BasketPlan(strategy: strategy,
                          baskets: baskets,
                          itemsWithoutPrice: missing,
                          total: total)
    }
}
