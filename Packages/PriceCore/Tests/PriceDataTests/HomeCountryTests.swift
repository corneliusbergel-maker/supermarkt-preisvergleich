import XCTest
import PriceCore
@testable import PriceData

/// Ohne Bezugspunkt darf die App keine ausländischen Preise zeigen.
///
/// Gemessen am 2026-09-11: Für Nutella 400 g stammten von den 100 neuesten
/// Preisen ohne Ortsangabe 96 aus Frankreich und keiner aus Deutschland. Die
/// App hatte einen französischen Preis als günstigsten ausgewiesen.
final class HomeCountryTests: XCTestCase {

    /// Derselbe Artikel bei Lidl, einmal in Berlin, einmal in Paris. Der
    /// französische Preis ist absichtlich der niedrigere -- genau so sah der
    /// Fehler aus.
    private let mixed = """
    {"items":[\
    {"id":1,"location":{"osm_id":1,"osm_type":"NODE","osm_brand":"Lidl",\
    "osm_lat":52.52,"osm_lon":13.405,"osm_address_country_code":"DE"},\
    "proof":{"id":1,"type":"PRICE_TAG"},\
    "price":3.99,"currency":"EUR","date":"2026-09-09","product_code":"3017620422003"},\
    {"id":2,"location":{"osm_id":2,"osm_type":"NODE","osm_brand":"Lidl",\
    "osm_lat":48.85,"osm_lon":2.35,"osm_address_country_code":"FR"},\
    "proof":{"id":2,"type":"PRICE_TAG"},\
    "price":3.53,"currency":"EUR","date":"2026-09-10","product_code":"3017620422003"},\
    {"id":3,"location":{"osm_id":3,"osm_type":"NODE","osm_brand":"Lidl",\
    "osm_lat":52.50,"osm_lon":13.40},\
    "proof":{"id":3,"type":"PRICE_TAG"},\
    "price":3.49,"currency":"EUR","date":"2026-09-10","product_code":"3017620422003"}\
    ],"total":3}
    """

    private let berlin = Coordinate(latitude: 52.52, longitude: 13.405)

    func testWithoutReferencePointOnlyGermanPricesRemain() async throws {
        let sut = OpenPricesClient(transport: StubTransport(json: mixed))
        let prices = try await sut.prices(barcode: "3017620422003")

        XCTAssertEqual(prices.map(\.price.amount), [Decimal(string: "3.99")!],
                       "Der französische 3,53-€-Preis darf nicht als günstigster erscheinen")
    }

    /// Ein Preis ohne Ländercode lässt nicht erkennen, ob er aus Deutschland
    /// stammt. Ihn trotzdem zu zeigen, hieße es anzunehmen.
    func testPriceWithoutCountryIsDroppedWithoutReferencePoint() async throws {
        let sut = OpenPricesClient(transport: StubTransport(json: mixed))
        let prices = try await sut.prices(barcode: "3017620422003")
        XCTAssertFalse(prices.contains { $0.price.amount == Decimal(string: "3.49")! })
    }

    /// Ohne Eingrenzung reichen 100 Treffer oft nicht bis zu den deutschen --
    /// die Abfrage selbst muss schon auf Deutschland zielen.
    func testWithoutReferencePointTheQueryTargetsGermany() async throws {
        let stub = StubTransport(json: mixed)
        _ = try await OpenPricesClient(transport: stub).prices(barcode: "3017620422003")

        let url = try XCTUnwrap(stub.lastRequest?.url?.absoluteString)
        XCTAssertTrue(url.contains("lat=51.1657"), url)
        XCTAssertTrue(url.contains("lon=10.4515"), url)
        XCTAssertTrue(url.contains("radius_km=500"), url)
    }

    /// Mit Standort gilt die Umkreissuche. Ein Nachbarland im Umkreis bleibt
    /// dann erhalten -- wer in Aachen wohnt, kauft auch in den Niederlanden.
    func testWithReferencePointTheUsersPositionIsUsed() async throws {
        let stub = StubTransport(json: mixed)
        let prices = try await OpenPricesClient(transport: stub)
            .prices(barcode: "3017620422003", near: berlin, radiusKm: 5)

        XCTAssertEqual(prices.count, 3, "Mit Bezugspunkt filtert der Umkreis, nicht das Land")
        let url = try XCTUnwrap(stub.lastRequest?.url?.absoluteString)
        XCTAssertTrue(url.contains("lat=52.52"), url)
        XCTAssertTrue(url.contains("radius_km=5"), url)
    }

    /// Ein Verlauf über Ländergrenzen hinweg mischt Märkte mit anderem
    /// Preisniveau -- und wäre damit keiner.
    func testHistoryIsLimitedToGermany() async throws {
        let stub = StubTransport(json: mixed)
        let since = Date(timeIntervalSince1970: 1_780_000_000)
        let history = try await OpenPricesClient(transport: stub)
            .priceHistory(barcode: "3017620422003", since: since)

        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history.first?.store?.countryCode, "DE")
        let url = try XCTUnwrap(stub.lastRequest?.url?.absoluteString)
        XCTAssertTrue(url.contains("radius_km=500"), url)
    }

    func testCountryCodeIsNormalised() {
        let store = Store(id: "node/1",
                          retailer: Retailer(id: "lidl", name: "Lidl"),
                          coordinate: berlin,
                          countryCode: " de ")
        XCTAssertEqual(store.countryCode, "DE")
    }
}
