import XCTest
import PriceCore
@testable import PriceData

/// Beide Vorlagen sind **echte** Antworten der Open-Prices-API vom 2026-09-10,
/// auf die genutzten Felder gekuerzt. Insbesondere der zweite Datensatz ist
/// nicht konstruiert: So liegen Massenimporte tatsaechlich in der Datenbank.
private enum PriceFixtures {

    /// Ein vollstaendiger Datensatz: Kaufland Berlin, mit Kassenbon belegt.
    static let kauflandBerlin = """
    {"items":[{"id":329623,\
    "location":{"id":6575,"type":"OSM","osm_id":494497710,"osm_type":"WAY",\
    "osm_name":"Kaufland","osm_brand":"Kaufland","osm_address_postcode":"10407",\
    "osm_address_city":"Berlin","osm_address_country_code":"DE",\
    "osm_lat":52.5340406,"osm_lon":13.4565336,"website_url":null},\
    "proof":{"id":133042,"type":"RECEIPT"},\
    "price":1.66,"price_is_discounted":false,"price_without_discount":null,\
    "currency":"EUR","date":"2026-09-09","product_code":"4009233005802",\
    "owner":"testuser","source":null}],\
    "page":1,"pages":1,"size":1,"total":1}
    """

    /// Ein realer Massenimport ohne Datum und ohne Waehrung.
    /// Quelle laut Datensatz: "Smoothie - OpenFoodFacts".
    static let bulkImportWithoutDate = """
    {"items":[{"id":34207,\
    "location":{"id":1036,"type":"OSM","osm_id":5835803818,"osm_type":"NODE",\
    "osm_name":"REWE","osm_brand":"REWE","osm_address_postcode":"12685",\
    "osm_address_city":"Berlin","osm_address_country_code":"DE",\
    "osm_lat":52.5412661,"osm_lon":13.5649008,"website_url":null},\
    "proof":{"id":8940,"type":"RECEIPT"},\
    "price":1.49,"price_is_discounted":false,"price_without_discount":null,\
    "currency":null,"date":null,"product_code":"5060947548800",\
    "owner":"heuwerk","source":"Smoothie - OpenFoodFacts"}],\
    "page":1,"pages":1,"size":1,"total":1}
    """

    static let empty = """
    {"items":[],"page":1,"pages":0,"size":0,"total":0}
    """
}

final class OpenPricesDecodingTests: XCTestCase {

    private func client(_ json: String) -> OpenPricesClient {
        OpenPricesClient(transport: StubTransport(json: json))
    }

    func testRealRecordIsDecodedCompletely() async throws {
        let prices = try await client(PriceFixtures.kauflandBerlin)
            .prices(barcode: "4009233005802")
        let observation = try XCTUnwrap(prices.first)

        XCTAssertEqual(observation.price.amount, Decimal(string: "1.66"))
        XCTAssertEqual(observation.price.currency, "EUR")
        XCTAssertEqual(observation.productID, "ean:4009233005802")
        XCTAssertEqual(observation.source, "Open Prices")
        XCTAssertTrue(observation.hasProof, "Kassenbon zaehlt als Beleg")
        XCTAssertTrue(observation.isExactProductMatch)
        XCTAssertFalse(observation.isDiscounted)
    }

    func testStoreIsMappedFromLocation() async throws {
        let prices = try await client(PriceFixtures.kauflandBerlin)
            .prices(barcode: "4009233005802")
        let store = try XCTUnwrap(prices.first?.store)

        XCTAssertEqual(store.id, "way/494497710")
        XCTAssertEqual(store.retailer.name, "Kaufland")
        XCTAssertEqual(store.city, "Berlin")
        XCTAssertEqual(store.postalCode, "10407")
        XCTAssertTrue(store.coordinate.isValid)
    }

    /// Die Entfernung muss sich aus dem Datensatz tatsaechlich rechnen lassen --
    /// sonst nuetzt die Filiale nichts.
    func testDistanceCanBeComputedFromDecodedStore() async throws {
        let prices = try await client(PriceFixtures.kauflandBerlin)
            .prices(barcode: "4009233005802")
        let store = try XCTUnwrap(prices.first?.store)

        let berlinCentre = Coordinate(latitude: 52.52, longitude: 13.405)
        let meters = try XCTUnwrap(GeoDistance.straightLineMeters(from: berlinCentre,
                                                                 to: store.coordinate))
        // Prenzlauer Berg liegt wenige Kilometer vom Zentrum entfernt.
        XCTAssertGreaterThan(meters, 500)
        XCTAssertLessThan(meters, 8_000)
    }

    /// Der wichtigste Test dieser Datei.
    func testBulkImportWithoutDateOrCurrencyIsRejected() async throws {
        let prices = try await client(PriceFixtures.bulkImportWithoutDate)
            .prices(barcode: "5060947548800")
        XCTAssertTrue(prices.isEmpty,
                      "Ohne Datum liesse sich die Aktualitaet nicht angeben, ohne "
                      + "Waehrung waere der Betrag nicht vergleichbar. Beides "
                      + "anzunehmen waere geraten.")
    }

    func testEmptyResultIsEmptyNotAnError() async throws {
        let prices = try await client(PriceFixtures.empty).prices(barcode: "1234567890123")
        XCTAssertTrue(prices.isEmpty)
    }

    func testEmptyBarcodeNeverReachesTheNetwork() async throws {
        let stub = StubTransport(json: PriceFixtures.empty)
        let sut = OpenPricesClient(transport: stub)
        _ = try await sut.prices(barcode: "")
        XCTAssertEqual(stub.log.count, 0)
    }
}

final class OpenPricesConfidenceTests: XCTestCase {

    private func observation(daysAgo: Int) async throws -> PriceObservation {
        let calendar = Calendar(identifier: .gregorian)
        let date = calendar.date(byAdding: .day, value: -daysAgo, to: Date())!
        let day = OpenPricesClient.dayFormatter.string(from: date)

        let json = """
        {"items":[{"id":1,\
        "location":{"osm_id":1,"osm_type":"NODE","osm_name":"REWE","osm_brand":"REWE",\
        "osm_lat":52.52,"osm_lon":13.405,"osm_address_country_code":"DE"},\
        "proof":{"id":1,"type":"PRICE_TAG"},\
        "price":1.49,"price_is_discounted":false,"currency":"EUR",\
        "date":"\(day)","product_code":"4009233005802"}],"total":1}
        """
        let prices = try await OpenPricesClient(transport: StubTransport(json: json))
            .prices(barcode: "4009233005802")
        return try XCTUnwrap(prices.first)
    }

    func testFreshProvenPriceIsConfirmed() async throws {
        let sut = try await observation(daysAgo: 1)
        XCTAssertEqual(sut.confidence(), .high)
    }

    func testTwoWeekOldPriceIsOnlyCurrent() async throws {
        let sut = try await observation(daysAgo: 14)
        XCTAssertEqual(sut.confidence(), .medium)
    }

    func testTwoMonthOldPriceIsMarkedStale() async throws {
        let sut = try await observation(daysAgo: 60)
        XCTAssertEqual(sut.confidence(), .low)
    }

    func testPriceWithoutProofNeverBecomesConfirmed() async throws {
        let day = OpenPricesClient.dayFormatter.string(from: Date())
        let json = """
        {"items":[{"id":2,\
        "location":{"osm_id":1,"osm_type":"NODE","osm_brand":"REWE",\
        "osm_lat":52.52,"osm_lon":13.405,"osm_address_country_code":"DE"},\
        "price":2.00,"currency":"EUR","date":"\(day)","product_code":"123"}],"total":1}
        """
        let prices = try await OpenPricesClient(transport: StubTransport(json: json))
            .prices(barcode: "123")
        let sut = try XCTUnwrap(prices.first)
        XCTAssertFalse(sut.hasProof)
        XCTAssertEqual(sut.confidence(), .medium)
    }
}

final class OpenPricesDiscountTests: XCTestCase {

    func testDiscountPercentIsComputedFromOriginalPrice() throws {
        let json = """
        {"items":[{"id":3,\
        "location":{"osm_id":1,"osm_type":"NODE","osm_brand":"LIDL",\
        "osm_lat":52.52,"osm_lon":13.405,"osm_address_country_code":"DE"},\
        "proof":{"id":1,"type":"PRICE_TAG"},\
        "price":1.29,"price_is_discounted":true,"price_without_discount":1.69,\
        "currency":"EUR","date":"2026-09-09","product_code":"123"}],"total":1}
        """
        let page = try JSONDecoder().decode(OpenPricesPage.self, from: Data(json.utf8))
        let item = try XCTUnwrap(page.items.first)

        // Die Anforderung nennt zu 1,29 statt 1,69 einen Rabatt von 22 %.
        // Nachgerechnet sind es 23,67 %, gerundet also 24 %. Der Test haelt
        // den korrekten Wert fest, nicht den genannten.
        XCTAssertEqual(item.discountPercent, 24)
        XCTAssertEqual(item.toObservation()?.isDiscounted, true)
    }

    func testNoPercentageWithoutAnOriginalPrice() throws {
        let json = """
        {"items":[{"id":4,\
        "location":{"osm_id":1,"osm_type":"NODE","osm_brand":"LIDL",\
        "osm_lat":52.52,"osm_lon":13.405,"osm_address_country_code":"DE"},\
        "price":1.29,"price_is_discounted":true,"price_without_discount":null,\
        "currency":"EUR","date":"2026-09-09","product_code":"123"}],"total":1}
        """
        let page = try JSONDecoder().decode(OpenPricesPage.self, from: Data(json.utf8))
        let item = try XCTUnwrap(page.items.first)

        XCTAssertNil(item.discountPercent,
                     "Ohne Ursprungspreis darf kein Rabatt in Prozent behauptet werden")
        XCTAssertEqual(item.toObservation()?.isDiscounted, true,
                       "Dass es ein Angebot ist, steht trotzdem fest")
    }
}

final class OpenPricesLocationTests: XCTestCase {

    func testLocationWithoutCoordinatesIsDropped() throws {
        let json = """
        {"items":[{"id":5,\
        "location":{"osm_id":1,"osm_type":"NODE","osm_brand":"REWE"},\
        "price":1.00,"currency":"EUR","date":"2026-09-09","product_code":"123"}],"total":1}
        """
        let page = try JSONDecoder().decode(OpenPricesPage.self, from: Data(json.utf8))
        let item = try XCTUnwrap(page.items.first)

        XCTAssertNil(item.location?.toStore(),
                     "Ohne Koordinaten gibt es keine Entfernung und keine Route")
        // Die Kette bleibt trotzdem erhalten - der Preis ist nicht wertlos.
        XCTAssertEqual(item.toObservation()?.retailer?.id, "rewe")
    }

    func testNullIslandCoordinatesAreRejected() throws {
        let json = """
        {"items":[{"id":6,\
        "location":{"osm_id":1,"osm_type":"NODE","osm_brand":"REWE",\
        "osm_lat":0,"osm_lon":0},\
        "price":1.00,"currency":"EUR","date":"2026-09-09","product_code":"123"}],"total":1}
        """
        let page = try JSONDecoder().decode(OpenPricesPage.self, from: Data(json.utf8))
        XCTAssertNil(page.items.first?.location?.toStore())
    }
}
