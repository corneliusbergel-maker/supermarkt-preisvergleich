import XCTest
@testable import PriceCore

private let basketNow = Date(timeIntervalSince1970: 1_770_000_000)

private func testStore(_ name: String, distanceMeters: Double = 1_000) -> Store {
    Store(id: name.lowercased(),
          retailer: Retailer(id: "wd:\(name.lowercased())", name: name),
          coordinate: Coordinate(latitude: 52.52, longitude: 13.405),
          name: name)
}

/// Baut ein Angebot fuer einen Posten in einem bestimmten Markt.
private func basketOffer(_ storeName: String,
                         product: String,
                         price: String,
                         distanceMeters: Double? = 1_000) -> PriceOffer {
    let observation = PriceObservation(
        id: "\(storeName)-\(product)",
        productID: product,
        price: Money(amount: Decimal(string: price)!),
        observedOn: basketNow,
        store: testStore(storeName),
        retailer: Retailer(id: "wd:\(storeName.lowercased())", name: storeName),
        source: "Open Prices"
    )
    return PriceOffer(observation: observation, distanceMeters: distanceMeters)
}

private func item(_ name: String, count: Int = 1, offers: [PriceOffer]) -> BasketItem {
    BasketItem(id: name, displayName: name, count: count, offers: offers)
}

// MARK: - Das Beispiel aus Anforderung #18

final class BasketRequirementExampleTests: XCTestCase {

    /// Die Preistabelle aus der Anforderung.
    private var shoppingList: [BasketItem] {
        [
            item("Milch", offers: [
                basketOffer("REWE", product: "Milch", price: "1.29"),
                basketOffer("Kaufland", product: "Milch", price: "1.19"),
                basketOffer("LIDL", product: "Milch", price: "1.25")
            ]),
            item("Nutella", offers: [
                basketOffer("REWE", product: "Nutella", price: "3.49"),
                basketOffer("Kaufland", product: "Nutella", price: "2.99"),
                basketOffer("LIDL", product: "Nutella", price: "3.19")
            ]),
            item("Cola", offers: [
                basketOffer("REWE", product: "Cola", price: "1.49"),
                basketOffer("Kaufland", product: "Cola", price: "1.39"),
                basketOffer("LIDL", product: "Cola", price: "1.45")
            ])
        ]
    }

    func testSingleStoreTotalMatchesTheRequirement() throws {
        let plan = try XCTUnwrap(BasketOptimizer.bestSingleStore(shoppingList))
        XCTAssertEqual(plan.total.amount, Decimal(string: "5.57"))
        XCTAssertEqual(plan.storeCount, 1)
        XCTAssertEqual(plan.baskets.first?.displayName, "Kaufland")
    }

    /// Die Anforderung nennt fuer "REWE + Kaufland" 5,37 EUR. Mit den dort
    /// angegebenen Preisen ist das nicht erreichbar: Kaufland ist bei jedem
    /// der drei Artikel am guenstigsten, jede Aufteilung wird also teurer.
    /// Der Optimierer muss das erkennen und darf keine Ersparnis erfinden.
    func testSplittingCannotBeatKauflandWithTheseNumbers() throws {
        let cheapest = try XCTUnwrap(BasketOptimizer.cheapestOverall(shoppingList))
        XCTAssertEqual(cheapest.total.amount, Decimal(string: "5.57"))
        XCTAssertEqual(cheapest.storeCount, 1,
                       "Alle Bestpreise liegen im selben Markt")

        let twoStores = try XCTUnwrap(BasketOptimizer.bestCombination(shoppingList, maxStores: 2))
        XCTAssertEqual(twoStores.total.amount, Decimal(string: "5.57"),
                       "Zwei Maerkte duerfen nicht guenstiger ausgewiesen werden als einer")
    }
}

// MARK: - Aufteilen lohnt sich wirklich

final class BasketSplittingTests: XCTestCase {

    /// Hier liegen die Bestpreise tatsaechlich in verschiedenen Maerkten.
    private var shoppingList: [BasketItem] {
        [
            item("Milch", offers: [
                basketOffer("REWE", product: "Milch", price: "1.00"),
                basketOffer("Kaufland", product: "Milch", price: "2.00")
            ]),
            item("Nutella", offers: [
                basketOffer("REWE", product: "Nutella", price: "4.00"),
                basketOffer("Kaufland", product: "Nutella", price: "3.00")
            ])
        ]
    }

    func testCheapestOverallSplitsAcrossTwoStores() throws {
        let plan = try XCTUnwrap(BasketOptimizer.cheapestOverall(shoppingList))
        XCTAssertEqual(plan.total.amount, Decimal(4))
        XCTAssertEqual(plan.storeCount, 2)
    }

    func testSingleStoreIsMoreExpensiveHere() throws {
        let plan = try XCTUnwrap(BasketOptimizer.bestSingleStore(shoppingList))
        XCTAssertEqual(plan.total.amount, Decimal(5))
        XCTAssertEqual(plan.storeCount, 1)
    }

    func testQuantityIsMultipliedIntoTheTotal() throws {
        let list = [
            item("Milch", count: 3, offers: [
                basketOffer("REWE", product: "Milch", price: "1.00")
            ])
        ]
        let plan = try XCTUnwrap(BasketOptimizer.cheapestOverall(list))
        XCTAssertEqual(plan.total.amount, Decimal(3))
    }
}

// MARK: - Ehrlichkeit bei Datenluecken

final class BasketDataHonestyTests: XCTestCase {

    func testItemWithoutAnyPriceIsReportedNotDropped() throws {
        let list = [
            item("Milch", offers: [basketOffer("REWE", product: "Milch", price: "1.29")]),
            item("Waschmittel", offers: [])
        ]
        let plan = try XCTUnwrap(BasketOptimizer.cheapestOverall(list))

        XCTAssertEqual(plan.total.amount, Decimal(string: "1.29"))
        XCTAssertEqual(plan.itemsWithoutPrice.map(\.displayName), ["Waschmittel"])
        XCTAssertFalse(plan.isComplete,
                       "Die Summe deckt nicht die ganze Liste - das muss sichtbar sein")
    }

    func testStoreWithGapsIsNotUsedAsSingleStore() throws {
        // Kaufland hat keinen Preis fuer Nutella. Es waere erfunden,
        // dort trotzdem die ganze Liste zu planen.
        let list = [
            item("Milch", offers: [
                basketOffer("REWE", product: "Milch", price: "1.29"),
                basketOffer("Kaufland", product: "Milch", price: "0.99")
            ]),
            item("Nutella", offers: [
                basketOffer("REWE", product: "Nutella", price: "3.49")
            ])
        ]
        let plan = try XCTUnwrap(BasketOptimizer.bestSingleStore(list))
        XCTAssertEqual(plan.baskets.first?.displayName, "REWE")
        XCTAssertEqual(plan.total.amount, Decimal(string: "4.78"))
    }

    func testCoverageIsReportedPerStore() {
        let list = [
            item("Milch", offers: [
                basketOffer("REWE", product: "Milch", price: "1.29"),
                basketOffer("Kaufland", product: "Milch", price: "0.99")
            ]),
            item("Nutella", offers: [
                basketOffer("REWE", product: "Nutella", price: "3.49")
            ]),
            item("Cola", offers: [
                basketOffer("REWE", product: "Cola", price: "1.49")
            ])
        ]
        let coverage = BasketOptimizer.coverageByStore(list)

        XCTAssertEqual(coverage.first?.name, "REWE")
        XCTAssertEqual(coverage.first?.covered, 3)
        XCTAssertEqual(coverage.first?.total, 3)

        let kaufland = coverage.first { $0.name == "Kaufland" }
        XCTAssertEqual(kaufland?.covered, 1, "Kaufland deckt nur 1 von 3 Artikeln ab")
    }

    func testOffersWithoutAKnownLocationAreNotPlanned() throws {
        // Zu einem unbekannten Ort kann man nicht einkaufen fahren.
        let orphan = PriceOffer(observation: PriceObservation(
            id: "orphan",
            productID: "Milch",
            price: Money(amount: Decimal(string: "0.10")!),
            observedOn: basketNow,
            store: nil,
            retailer: nil,
            source: "Open Prices"
        ))
        let list = [
            item("Milch", offers: [
                orphan,
                basketOffer("REWE", product: "Milch", price: "1.29")
            ])
        ]
        let plan = try XCTUnwrap(BasketOptimizer.cheapestOverall(list))
        XCTAssertEqual(plan.total.amount, Decimal(string: "1.29"),
                       "Der ortlose 0,10-EUR-Preis darf keinen Plan erzeugen")
    }

    func testEmptyListYieldsNoPlan() {
        XCTAssertNil(BasketOptimizer.cheapestOverall([]))
        XCTAssertNil(BasketOptimizer.bestSingleStore([]))
    }
}

// MARK: - Preis gegen Weg

final class BasketBestValueTests: XCTestCase {

    func testNearbyStoreWinsWhenTheCheapOneIsFarAway() throws {
        // Fern: 2,00 EUR gespart, aber 20 km entfernt (40 km hin und zurueck
        // ergeben bei 0,30 EUR/km rund 12 EUR Fahrtkosten).
        let list = [
            item("Milch", offers: [
                basketOffer("Fernmarkt", product: "Milch", price: "1.00", distanceMeters: 20_000),
                basketOffer("Nahmarkt", product: "Milch", price: "2.00", distanceMeters: 500)
            ]),
            item("Nutella", offers: [
                basketOffer("Fernmarkt", product: "Nutella", price: "2.00", distanceMeters: 20_000),
                basketOffer("Nahmarkt", product: "Nutella", price: "3.00", distanceMeters: 500)
            ])
        ]

        let cheapest = try XCTUnwrap(BasketOptimizer.cheapestOverall(list))
        XCTAssertEqual(cheapest.baskets.first?.displayName, "Fernmarkt")
        XCTAssertEqual(cheapest.total.amount, Decimal(3))

        let value = try XCTUnwrap(BasketOptimizer.bestValue(list))
        XCTAssertEqual(value.baskets.first?.displayName, "Nahmarkt",
                       "Mit eingepreister Fahrt gewinnt der nahe Markt")
        XCTAssertEqual(value.total.amount, Decimal(5))
    }

    func testEffectiveTotalAddsRoundTripTravel() throws {
        let list = [
            item("Milch", offers: [
                basketOffer("Nahmarkt", product: "Milch", price: "2.00", distanceMeters: 1_000)
            ])
        ]
        let plan = try XCTUnwrap(BasketOptimizer.cheapestOverall(list))
        let rate = Money(amount: Decimal(string: "0.30")!)

        // 2,00 EUR Ware + 2 km Hin- und Rueckweg mal 0,30 EUR = 2,60 EUR
        XCTAssertEqual(BasketOptimizer.effectiveTotal(of: plan, rate: rate),
                       Decimal(string: "2.60"))
    }

    func testRecommendationsAreDeduplicated() throws {
        // Wenn alle Strategien zum selben Plan fuehren, darf er nur einmal
        // vorgeschlagen werden.
        let list = [
            item("Milch", offers: [
                basketOffer("REWE", product: "Milch", price: "1.00")
            ])
        ]
        let plans = BasketOptimizer.recommendations(list)
        XCTAssertEqual(plans.count, 1)
    }

    func testRecommendationsOfferBothStrategiesWhenTheyDiffer() {
        let list = [
            item("Milch", offers: [
                basketOffer("Fernmarkt", product: "Milch", price: "1.00", distanceMeters: 20_000),
                basketOffer("Nahmarkt", product: "Milch", price: "2.00", distanceMeters: 500)
            ]),
            item("Nutella", offers: [
                basketOffer("Fernmarkt", product: "Nutella", price: "2.00", distanceMeters: 20_000),
                basketOffer("Nahmarkt", product: "Nutella", price: "3.00", distanceMeters: 500)
            ])
        ]
        let plans = BasketOptimizer.recommendations(list)
        XCTAssertGreaterThanOrEqual(plans.count, 2,
                                    "Guenstigster Preis und beste Kombination unterscheiden sich hier")
    }
}
