import XCTest
import PriceCore
@testable import PriceData

/// Die Vorlage ist eine **echte** Overpass-Antwort vom 2026-09-10 fuer den
/// Umkreis von 3 km um Berlin-Mitte, gekuerzt auf zwei Eintraege.
private enum OverpassFixtures {

    static let berlin = """
    {"version":0.6,"generator":"Overpass API 0.7.62.11",
     "elements":[
      {"type":"node","id":58489979,"lat":52.5098189,"lon":13.4073729,
       "tags":{"addr:city":"Berlin","addr:country":"DE","addr:housenumber":"83",
        "addr:postcode":"10179","addr:street":"Alte Jakobstraße",
        "brand":"Netto Marken-Discount","brand:wikidata":"Q879858",
        "name":"Netto Marken-Discount","opening_hours":"Mo-Sa 07:00-24:00; Su off",
        "shop":"supermarket",
        "website":"https://www.netto-online.de/filialen/Berlin-Mitte/Alte-Jakobstr-83/7714/",
        "wheelchair":"no"}},
      {"type":"way","id":494497710,"center":{"lat":52.5340406,"lon":13.4565336},
       "tags":{"brand":"Kaufland","brand:wikidata":"Q685967","name":"Kaufland",
        "shop":"supermarket","addr:city":"Berlin","addr:postcode":"10407"}}
     ]}
    """

    static let empty = """
    {"version":0.6,"elements":[]}
    """
}

final class OverpassDecodingTests: XCTestCase {

    private let berlin = Coordinate(latitude: 52.52, longitude: 13.405)

    private func client(_ json: String, cacheLifetime: TimeInterval = 3600) -> OverpassClient {
        OverpassClient(transport: StubTransport(json: json), cacheLifetime: cacheLifetime)
    }

    func testRealNodeIsDecodedCompletely() async throws {
        let stores = try await client(OverpassFixtures.berlin).stores(near: berlin)
        let netto = try XCTUnwrap(stores.first { $0.id == "node/58489979" })

        XCTAssertEqual(netto.retailer.name, "Netto Marken-Discount")
        XCTAssertEqual(netto.street, "Alte Jakobstraße")
        XCTAssertEqual(netto.houseNumber, "83")
        XCTAssertEqual(netto.postalCode, "10179")
        XCTAssertEqual(netto.city, "Berlin")
        XCTAssertEqual(netto.formattedAddress, "Alte Jakobstraße 83, 10179 Berlin")
        XCTAssertEqual(netto.openingHoursRaw, "Mo-Sa 07:00-24:00; Su off")
        XCTAssertNotNil(netto.websiteURL)
    }

    /// Die Wikidata-ID ist unabhaengig von der Schreibweise und deshalb der
    /// bessere Schluessel.
    func testWikidataIdentifierIsPreferredOverTheName() async throws {
        let stores = try await client(OverpassFixtures.berlin).stores(near: berlin)
        let netto = try XCTUnwrap(stores.first { $0.id == "node/58489979" })
        XCTAssertEqual(netto.retailer.id, "wd:Q879858")
    }

    /// Flaechen tragen ihre Koordinate in `center`, nicht direkt.
    func testWayUsesItsCentre() async throws {
        let stores = try await client(OverpassFixtures.berlin).stores(near: berlin)
        let kaufland = try XCTUnwrap(stores.first { $0.id == "way/494497710" })

        XCTAssertEqual(kaufland.coordinate.latitude, 52.5340406, accuracy: 0.000001)
        XCTAssertEqual(kaufland.coordinate.longitude, 13.4565336, accuracy: 0.000001)
    }

    func testDistanceCanBeComputedForEveryDecodedStore() async throws {
        let stores = try await client(OverpassFixtures.berlin).stores(near: berlin)
        XCTAssertFalse(stores.isEmpty)
        for store in stores {
            XCTAssertNotNil(GeoDistance.straightLineMeters(from: berlin, to: store.coordinate),
                            "Ohne Entfernung ist die Filiale fuer die App wertlos: \(store.id)")
        }
    }

    func testElementWithoutCoordinatesIsDropped() {
        let json = """
        {"elements":[{"type":"node","id":1,"tags":{"brand":"REWE","shop":"supermarket"}}]}
        """
        let response = try? JSONDecoder().decode(OverpassResponse.self, from: Data(json.utf8))
        XCTAssertNil(response?.elements.first?.toStore())
    }

    func testElementWithoutAnyNameIsDropped() {
        // Ein Laden ohne Namen und ohne Marke ist nicht zuordenbar.
        let json = """
        {"elements":[{"type":"node","id":2,"lat":52.5,"lon":13.4,
         "tags":{"shop":"supermarket"}}]}
        """
        let response = try? JSONDecoder().decode(OverpassResponse.self, from: Data(json.utf8))
        XCTAssertNil(response?.elements.first?.toStore())
    }

    func testMalformedWikidataFallsBackToTheName() {
        let json = """
        {"elements":[{"type":"node","id":3,"lat":52.5,"lon":13.4,
         "tags":{"brand":"REWE","brand:wikidata":"kaputt","shop":"supermarket"}}]}
        """
        let response = try? JSONDecoder().decode(OverpassResponse.self, from: Data(json.utf8))
        XCTAssertEqual(response?.elements.first?.toStore()?.retailer.id, "rewe")
    }

    func testEmptyResultIsEmptyNotAnError() async throws {
        let stores = try await client(OverpassFixtures.empty).stores(near: berlin)
        XCTAssertTrue(stores.isEmpty)
    }

    func testInvalidCoordinateNeverReachesTheNetwork() async throws {
        let stub = StubTransport(json: OverpassFixtures.berlin)
        let sut = OverpassClient(transport: stub)
        let stores = try await sut.stores(near: Coordinate(latitude: 0, longitude: 0))
        XCTAssertTrue(stores.isEmpty)
        XCTAssertEqual(stub.log.count, 0)
    }
}

final class OverpassQueryTests: XCTestCase {

    func testQueryContainsRadiusAndPosition() {
        let query = OverpassClient.query(
            coordinate: Coordinate(latitude: 52.52, longitude: 13.405),
            radiusMeters: 3000
        )
        XCTAssertTrue(query.contains("around:3000,52.520000,13.405000"))
        XCTAssertTrue(query.contains("[out:json][timeout:25]"))
        XCTAssertTrue(query.contains("out center tags;"),
                      "Ohne `center` haetten Flaechen keine Koordinate")
        XCTAssertTrue(query.contains("supermarket"))
        XCTAssertTrue(query.contains("chemist"), "Drogerien gehoeren dazu - Shampoo, Waschmittel")
    }

    func testNearbyPositionsShareACacheKey() {
        // 20 Meter Unterschied duerfen keine neue Abfrage ausloesen.
        let a = OverpassClient.cacheKey(coordinate: Coordinate(latitude: 52.5201, longitude: 13.4050),
                                        radiusKm: 5)
        let b = OverpassClient.cacheKey(coordinate: Coordinate(latitude: 52.5203, longitude: 13.4051),
                                        radiusKm: 5)
        XCTAssertEqual(a, b)
    }

    func testDistantPositionsDoNotShareACacheKey() {
        let berlin = OverpassClient.cacheKey(coordinate: Coordinate(latitude: 52.52, longitude: 13.405),
                                             radiusKm: 5)
        let munich = OverpassClient.cacheKey(coordinate: Coordinate(latitude: 48.14, longitude: 11.58),
                                             radiusKm: 5)
        XCTAssertNotEqual(berlin, munich)
    }

    func testDifferentRadiusMeansDifferentCacheEntry() {
        let small = OverpassClient.cacheKey(coordinate: Coordinate(latitude: 52.52, longitude: 13.405),
                                            radiusKm: 2)
        let large = OverpassClient.cacheKey(coordinate: Coordinate(latitude: 52.52, longitude: 13.405),
                                            radiusKm: 10)
        XCTAssertNotEqual(small, large)
    }
}

final class OverpassCachingTests: XCTestCase {

    private let berlin = Coordinate(latitude: 52.52, longitude: 13.405)

    /// Overpass laesst pro IP nur zwei gleichzeitige Abfragen zu. Jede
    /// vermiedene Anfrage ist deshalb bares Kontingent.
    func testSecondCallIsServedFromCache() async throws {
        let stub = StubTransport(json: OverpassFixtures.berlin)
        let sut = OverpassClient(transport: stub, cacheLifetime: 3600)

        _ = try await sut.stores(near: berlin)
        _ = try await sut.stores(near: berlin)

        XCTAssertEqual(stub.log.count, 1, "Die zweite Abfrage muss aus dem Speicher kommen")
    }

    func testExpiredCacheIsRefetched() async throws {
        let stub = StubTransport(json: OverpassFixtures.berlin)
        let sut = OverpassClient(transport: stub, cacheLifetime: 0)

        _ = try await sut.stores(near: berlin)
        _ = try await sut.stores(near: berlin)

        XCTAssertEqual(stub.log.count, 2)
    }

    func testCacheCanBeBypassed() async throws {
        let stub = StubTransport(json: OverpassFixtures.berlin)
        let sut = OverpassClient(transport: stub, cacheLifetime: 3600)

        _ = try await sut.stores(near: berlin)
        _ = try await sut.stores(near: berlin, ignoreCache: true)

        XCTAssertEqual(stub.log.count, 2)
    }

    func testClearingTheCacheForcesAFreshRequest() async throws {
        let stub = StubTransport(json: OverpassFixtures.berlin)
        let sut = OverpassClient(transport: stub, cacheLifetime: 3600)

        _ = try await sut.stores(near: berlin)
        await sut.clearCache()
        _ = try await sut.stores(near: berlin)

        XCTAssertEqual(stub.log.count, 2)
    }

    /// Mehrere gleichzeitige Anfragen duerfen sich nicht ueberholen und
    /// muessen alle ein Ergebnis liefern.
    func testConcurrentRequestsAllComplete() async throws {
        let stub = StubTransport(json: OverpassFixtures.berlin)
        let sut = OverpassClient(transport: stub, cacheLifetime: 0)

        let positions = [
            Coordinate(latitude: 52.52, longitude: 13.40),
            Coordinate(latitude: 53.55, longitude: 9.99),
            Coordinate(latitude: 48.14, longitude: 11.58),
            Coordinate(latitude: 50.94, longitude: 6.96)
        ]

        let results = try await withThrowingTaskGroup(of: Int.self) { group in
            for position in positions {
                group.addTask { try await sut.stores(near: position).count }
            }
            var counts: [Int] = []
            for try await count in group { counts.append(count) }
            return counts
        }

        XCTAssertEqual(results.count, positions.count)
        XCTAssertTrue(results.allSatisfy { $0 == 2 })
        XCTAssertEqual(stub.log.count, positions.count)
    }
}
