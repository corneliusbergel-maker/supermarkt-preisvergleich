import XCTest
@testable import PriceCore

// MARK: - Testbausteine

private let referenceNow = Date(timeIntervalSince1970: 1_770_000_000)

private func daysAgo(_ days: Int, from now: Date = referenceNow) -> Date {
    Calendar(identifier: .gregorian).date(byAdding: .day, value: -days, to: now)!
}

private func retailer(_ name: String) -> Retailer {
    Retailer(id: "wd:\(name.lowercased())", name: name)
}

private func store(_ name: String, lat: Double, lon: Double) -> Store {
    Store(id: "node/\(abs(name.hashValue))",
          retailer: retailer(name),
          coordinate: Coordinate(latitude: lat, longitude: lon))
}

private func offer(_ retailerName: String,
                   price: String,
                   ageInDays: Int = 1,
                   distanceMeters: Double? = nil,
                   discounted: Bool = false,
                   hasProof: Bool = true,
                   exactMatch: Bool = true,
                   unitPrice: UnitPrice? = nil) -> PriceOffer {
    let observation = PriceObservation(
        id: "\(retailerName)-\(price)",
        productID: "ean:5449000054227",
        price: Money(amount: Decimal(string: price)!),
        observedOn: daysAgo(ageInDays),
        store: nil,
        retailer: retailer(retailerName),
        isDiscounted: discounted,
        hasProof: hasProof,
        isExactProductMatch: exactMatch,
        source: "Open Prices"
    )
    return PriceOffer(observation: observation,
                      unitPrice: unitPrice,
                      distanceMeters: distanceMeters)
}

// MARK: - Verlaesslichkeit

final class PriceConfidenceTests: XCTestCase {

    func testFreshProvenExactMatchIsHigh() {
        let sut = offer("REWE", price: "1.49", ageInDays: 2)
        XCTAssertEqual(sut.confidence(asOf: referenceNow), .high)
    }

    func testEightDaysOldDropsToMedium() {
        let sut = offer("REWE", price: "1.49", ageInDays: 8)
        XCTAssertEqual(sut.confidence(asOf: referenceNow), .medium)
    }

    func testOlderThanThirtyDaysIsLow() {
        let sut = offer("REWE", price: "1.49", ageInDays: 31)
        XCTAssertEqual(sut.confidence(asOf: referenceNow), .low)
    }

    func testWithoutProofNeverReachesHigh() {
        let sut = offer("REWE", price: "1.49", ageInDays: 1, hasProof: false)
        XCTAssertEqual(sut.confidence(asOf: referenceNow), .medium)
    }

    func testUncertainProductMatchNeverReachesHigh() {
        // Die App darf keine Genauigkeit behaupten, die sie nicht hat.
        let sut = offer("REWE", price: "1.49", ageInDays: 1, exactMatch: false)
        XCTAssertEqual(sut.confidence(asOf: referenceNow), .medium)
    }

    func testFutureDateIsTreatedAsUnreliable() {
        let sut = offer("REWE", price: "1.49", ageInDays: -5)
        XCTAssertEqual(sut.confidence(asOf: referenceNow), .low)
    }

    func testFreshnessWording() {
        XCTAssertEqual(offer("A", price: "1", ageInDays: 0)
            .observation.freshnessDescription(asOf: referenceNow), "heute")
        XCTAssertEqual(offer("A", price: "1", ageInDays: 1)
            .observation.freshnessDescription(asOf: referenceNow), "gestern")
        XCTAssertEqual(offer("A", price: "1", ageInDays: 5)
            .observation.freshnessDescription(asOf: referenceNow), "vor 5 Tagen")
    }
}

// MARK: - Sortierung und Filter

final class PriceComparatorTests: XCTestCase {

    /// Die Zahlen aus Anforderung #7.
    private var requirementOffers: [PriceOffer] {
        [
            offer("REWE", price: "1.49"),
            offer("EDEKA", price: "1.59"),
            offer("Kaufland", price: "1.39"),
            offer("ALDI", price: "1.45"),
            offer("LIDL", price: "1.49")
        ]
    }

    func testCheapestComesFirst() throws {
        let result = PriceComparator.compare(requirementOffers, now: referenceNow)
        let offers = result.offers
        XCTAssertEqual(offers.first?.observation.retailer?.name, "Kaufland")
        XCTAssertEqual(offers.last?.observation.retailer?.name, "EDEKA")
    }

    func testEmptyInputIsNoDataNotAnEmptyList() {
        // Entscheidend: die UI darf daraus nie "0,00 EUR" machen.
        let result = PriceComparator.compare([], now: referenceNow)
        if case .noData = result {} else { XCTFail("Erwartet: .noData, war \(result)") }
        XCTAssertFalse(result.hasData)
    }

    func testRetailerFilterIsApplied() throws {
        let result = PriceComparator.compare(
            requirementOffers,
            allowedRetailerIDs: ["wd:rewe", "wd:lidl"],
            now: referenceNow
        )
        XCTAssertEqual(result.offers.count, 2)
        XCTAssertEqual(result.offers.first?.price.amount, Decimal(string: "1.49"))
    }

    func testFilteringEverythingOutIsItsOwnState() {
        let result = PriceComparator.compare(
            requirementOffers,
            allowedRetailerIDs: ["wd:penny"],
            now: referenceNow
        )
        guard case .filteredOut(let total) = result else {
            return XCTFail("Erwartet: .filteredOut, war \(result)")
        }
        XCTAssertEqual(total, 5, "Die UI soll sagen koennen, wie viel der Filter verbirgt")
    }

    /// Ohne Standort hat kein Angebot eine Entfernung. Wuerde der Radius
    /// trotzdem angewendet, verschwaende jeder einzelne Preis -- genau das ist
    /// im Simulator ohne Standortfreigabe passiert.
    func testWithoutAReferencePointThereIsNoDistanceLimit() {
        XCTAssertNil(PriceComparator.effectiveDistanceLimit(5_000, hasReferencePoint: false))
        XCTAssertEqual(PriceComparator.effectiveDistanceLimit(5_000, hasReferencePoint: true), 5_000)
        XCTAssertNil(PriceComparator.effectiveDistanceLimit(nil, hasReferencePoint: true))
    }

    func testOffersSurviveWithoutLocationWhenTheLimitIsDropped() {
        let offers = [
            offer("REWE", price: "1.49", distanceMeters: nil),
            offer("EDEKA", price: "1.19", distanceMeters: nil)
        ]
        let limit = PriceComparator.effectiveDistanceLimit(5_000, hasReferencePoint: false)
        let result = PriceComparator.compare(offers, maxDistanceMeters: limit, now: referenceNow)

        XCTAssertEqual(result.offers.count, 2)
        XCTAssertEqual(result.offers.first?.observation.retailer?.name, "EDEKA")
    }

    func testUnknownDistanceIsExcludedWhenARadiusIsSet() {
        // Unbekannte Entfernung als "im Radius" zu werten waere geraten.
        let offers = [
            offer("REWE", price: "1.49", distanceMeters: 800),
            offer("EDEKA", price: "1.19", distanceMeters: nil)
        ]
        let result = PriceComparator.compare(offers, maxDistanceMeters: 5000, now: referenceNow)
        XCTAssertEqual(result.offers.count, 1)
        XCTAssertEqual(result.offers.first?.observation.retailer?.name, "REWE")
    }

    func testOffersWithoutUnitPriceSortToTheEnd() {
        let withUnit = offer("REWE", price: "3.00", unitPrice: UnitPrice(
            price: Money(amount: Decimal(string: "6.00")!),
            referenceAmount: 1, referenceUnit: .kilogram))
        let withoutUnit = offer("EDEKA", price: "1.00")

        let sorted = PriceComparator.sort([withoutUnit, withUnit],
                                          by: .unitPrice, now: referenceNow)
        XCTAssertEqual(sorted.first?.observation.retailer?.name, "REWE")
        XCTAssertEqual(sorted.last?.observation.retailer?.name, "EDEKA")
    }

    func testUnitPriceSortingBeatsAbsolutePrice() {
        // 1 kg fuer 6 EUR ist besser als 200 g fuer 2 EUR (10 EUR/kg).
        let bigPack = offer("REWE", price: "6.00", unitPrice: UnitPrice(
            price: Money(amount: Decimal(string: "6.00")!),
            referenceAmount: 1, referenceUnit: .kilogram))
        let smallPack = offer("EDEKA", price: "2.00", unitPrice: UnitPrice(
            price: Money(amount: Decimal(string: "1.00")!),
            referenceAmount: 100, referenceUnit: .gram))

        let byPrice = PriceComparator.sort([bigPack, smallPack], by: .price, now: referenceNow)
        XCTAssertEqual(byPrice.first?.observation.retailer?.name, "EDEKA")

        let byUnitPrice = PriceComparator.sort([bigPack, smallPack],
                                               by: .unitPrice, now: referenceNow)
        XCTAssertEqual(byUnitPrice.first?.observation.retailer?.name, "REWE")
    }

    func testDiscountSortingPutsOffersFirst() {
        let normalCheap = offer("REWE", price: "1.20")
        let discounted = offer("LIDL", price: "1.30", discounted: true)
        let sorted = PriceComparator.sort([normalCheap, discounted],
                                          by: .discount, now: referenceNow)
        XCTAssertEqual(sorted.first?.observation.retailer?.name, "LIDL")
    }

    func testTiesAreBrokenByConfidence() {
        let stale = offer("REWE", price: "1.49", ageInDays: 40)
        let fresh = offer("LIDL", price: "1.49", ageInDays: 1)
        let sorted = PriceComparator.sort([stale, fresh], by: .price, now: referenceNow)
        XCTAssertEqual(sorted.first?.observation.retailer?.name, "LIDL")
    }

    func testBestValueWeighsDistance() {
        // Anforderung #16: 1,29 EUR in 12 km gegen 1,39 EUR in 1,5 km.
        let far = offer("Kaufland", price: "1.29", distanceMeters: 12_000)
        let near = offer("REWE", price: "1.39", distanceMeters: 1_500)

        let byPrice = PriceComparator.sort([far, near], by: .price, now: referenceNow)
        XCTAssertEqual(byPrice.first?.observation.retailer?.name, "Kaufland")

        let byValue = PriceComparator.sort([far, near], by: .bestValue, now: referenceNow)
        XCTAssertEqual(byValue.first?.observation.retailer?.name, "REWE",
                       "Mit eingepreister Fahrt gewinnt der nahe Markt")
    }
}

// MARK: - Lohnt sich der Umweg?

final class DetourAdviceTests: XCTestCase {

    func testTenCentsForTenKilometresIsNotWorthIt() throws {
        let offers = [
            offer("Kaufland", price: "1.29", distanceMeters: 12_000),
            offer("REWE", price: "1.39", distanceMeters: 1_500)
        ]
        let advice = try XCTUnwrap(PriceComparator.detourAdvice(for: offers))

        XCTAssertEqual(advice.savings.amount, Decimal(string: "0.10"))
        XCTAssertEqual(advice.extraDistanceMeters, 10_500, accuracy: 0.001)
        XCTAssertFalse(advice.isWorthIt)
        XCTAssertTrue(advice.explanation.contains("lohnt sich eher nicht"))
    }

    func testSevenEurosForFourKilometresIsWorthIt() throws {
        // Anforderung #41: 4 km weiter, dafuer 7 EUR gespart.
        let offers = [
            offer("Kaufland", price: "12.99", distanceMeters: 5_000),
            offer("REWE", price: "19.99", distanceMeters: 1_000)
        ]
        let advice = try XCTUnwrap(PriceComparator.detourAdvice(for: offers))

        XCTAssertEqual(advice.savings.amount, Decimal(string: "7.00"))
        XCTAssertTrue(advice.isWorthIt)
        XCTAssertTrue(advice.explanation.contains("lohnt sich also"))
    }

    func testNoAdviceWhenTheCheapestIsAlsoTheNearest() {
        let offers = [
            offer("Kaufland", price: "1.19", distanceMeters: 900),
            offer("REWE", price: "1.39", distanceMeters: 1_500)
        ]
        XCTAssertNil(PriceComparator.detourAdvice(for: offers))
    }

    func testNoAdviceWithoutDistances() {
        let offers = [offer("Kaufland", price: "1.19"), offer("REWE", price: "1.39")]
        XCTAssertNil(PriceComparator.detourAdvice(for: offers))
    }
}

// MARK: - Entfernung

final class GeoDistanceTests: XCTestCase {

    func testOneDegreeOfLatitudeIsAboutOneHundredElevenKilometres() throws {
        let from = Coordinate(latitude: 51.0, longitude: 7.0)
        let to = Coordinate(latitude: 52.0, longitude: 7.0)
        let meters = try XCTUnwrap(GeoDistance.straightLineMeters(from: from, to: to))
        XCTAssertEqual(meters, 111_195, accuracy: 200)
    }

    func testSamePointIsZero() throws {
        let point = Coordinate(latitude: 52.52, longitude: 13.405)
        let meters = try XCTUnwrap(GeoDistance.straightLineMeters(from: point, to: point))
        XCTAssertEqual(meters, 0, accuracy: 0.001)
    }

    func testNullIslandIsRejectedAsADataError() {
        // 0/0 ist praktisch immer ein fehlendes Feld, kein Ort im Atlantik.
        let broken = Coordinate(latitude: 0, longitude: 0)
        let berlin = Coordinate(latitude: 52.52, longitude: 13.405)
        XCTAssertNil(GeoDistance.straightLineMeters(from: broken, to: berlin))
    }

    func testOutOfRangeCoordinatesAreRejected() {
        let broken = Coordinate(latitude: 95, longitude: 13)
        let berlin = Coordinate(latitude: 52.52, longitude: 13.405)
        XCTAssertNil(GeoDistance.straightLineMeters(from: berlin, to: broken))
    }

    func testFormatting() {
        XCTAssertEqual(GeoDistance.formatted(meters: 850), "850 m")
        XCTAssertEqual(GeoDistance.formatted(meters: 2_400), "2,4 km")
    }
}
