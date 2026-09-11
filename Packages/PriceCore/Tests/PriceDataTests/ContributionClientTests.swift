import XCTest
import PriceCore
@testable import PriceData

private func testStore() -> Store {
    Store(id: "way/494497710",
          retailer: Retailer(id: "kaufland", name: "Kaufland"),
          coordinate: Coordinate(latitude: 52.5340406, longitude: 13.4565336),
          name: "Kaufland",
          postalCode: "10407",
          city: "Berlin")
}

private func body(of request: URLRequest?) -> String {
    guard let data = request?.httpBody else { return "" }
    return String(decoding: data, as: UTF8.self)
}

final class StoreOSMIdentifierTests: XCTestCase {

    /// Beide Clients bauen die Kennung als "art/nummer". Zum Beitragen muss
    /// sie wieder zerlegt werden.
    func testIdentifierIsSplitIntoTypeAndNumber() {
        let store = testStore()
        XCTAssertEqual(store.osmType, "WAY")
        XCTAssertEqual(store.osmID, 494_497_710)
    }

    func testNodeIdentifier() {
        let store = Store(id: "node/58489979",
                          retailer: Retailer(id: "netto", name: "Netto"),
                          coordinate: Coordinate(latitude: 52.5, longitude: 13.4))
        XCTAssertEqual(store.osmType, "NODE")
        XCTAssertEqual(store.osmID, 58_489_979)
    }

    func testMalformedIdentifierYieldsNothing() {
        let store = Store(id: "kaputt",
                          retailer: Retailer(id: "x", name: "X"),
                          coordinate: Coordinate(latitude: 52.5, longitude: 13.4))
        XCTAssertNil(store.osmType)
        XCTAssertNil(store.osmID)
    }
}

final class ContributionSignInTests: XCTestCase {

    private let sessionJSON = """
    {"access_token":"tok_123","token_type":"bearer","user_id":"testuser",\
    "is_moderator":false}
    """

    func testSessionIsDecoded() async throws {
        let sut = OpenPricesContributionClient(transport: StubTransport(json: sessionJSON))
        let session = try await sut.signIn(username: "testuser", password: "geheim")

        XCTAssertEqual(session.accessToken, "tok_123")
        XCTAssertEqual(session.userID, "testuser")
        XCTAssertFalse(session.isModerator)
    }

    func testCredentialsAreFormEncoded() async throws {
        let stub = StubTransport(json: sessionJSON)
        let sut = OpenPricesContributionClient(transport: stub)
        _ = try await sut.signIn(username: "max mustermann", password: "a&b=c")

        let sent = body(of: stub.lastRequest)
        XCTAssertTrue(sent.contains("username=max%20mustermann"))
        // Sonderzeichen muessen maskiert sein, sonst zerfaellt das Formular.
        XCTAssertTrue(sent.contains("password=a%26b%3Dc"))
    }

    func testWrongCredentialsAreReportedAsUnauthorized() async {
        let stub = StubTransport([.success(.status(401))])
        let sut = OpenPricesContributionClient(transport: stub)
        do {
            _ = try await sut.signIn(username: "x", password: "y")
            XCTFail("Erwartet: Fehler")
        } catch let error as DataSourceError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)")
        }
        XCTAssertEqual(stub.log.count, 1, "Eine falsche Anmeldung wird nicht wiederholt")
    }
}

final class ContributionUploadTests: XCTestCase {

    private let proofJSON = """
    {"id":4242,"type":"PRICE_TAG","file_path":"0004/abc.webp"}
    """

    func testProofIdentifierIsReturned() async throws {
        let sut = OpenPricesContributionClient(transport: StubTransport(json: proofJSON))
        let proofID = try await sut.uploadPriceTag(imageData: Data([0xFF, 0xD8, 0xFF]),
                                                   store: testStore(),
                                                   currency: "EUR",
                                                   date: Date(timeIntervalSince1970: 1_770_000_000),
                                                   token: "tok_123")
        XCTAssertEqual(proofID, 4242)
    }

    func testMultipartCarriesStoreAndType() async throws {
        let stub = StubTransport(json: proofJSON)
        let sut = OpenPricesContributionClient(transport: stub)
        _ = try await sut.uploadPriceTag(imageData: Data([0xFF, 0xD8]),
                                         store: testStore(),
                                         currency: "EUR",
                                         date: Date(timeIntervalSince1970: 1_770_000_000),
                                         token: "tok_123")

        let sent = body(of: stub.lastRequest)
        XCTAssertTrue(sent.contains("name=\"type\""))
        XCTAssertTrue(sent.contains("PRICE_TAG"))
        XCTAssertTrue(sent.contains("494497710"), "Filialnummer muss mitgehen")
        XCTAssertTrue(sent.contains("WAY"), "Objektart muss mitgehen")
        XCTAssertTrue(sent.contains("filename=\"preisschild.jpg\""))

        let contentType = stub.lastRequest?.value(forHTTPHeaderField: "Content-Type") ?? ""
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
    }

    func testAuthorizationHeaderIsSet() async throws {
        let stub = StubTransport(json: proofJSON)
        let sut = OpenPricesContributionClient(transport: stub)
        _ = try await sut.uploadPriceTag(imageData: Data([0xFF]),
                                         store: testStore(),
                                         currency: "EUR",
                                         date: Date(),
                                         token: "tok_123")

        XCTAssertEqual(stub.lastRequest?.value(forHTTPHeaderField: "Authorization"),
                       "bearer tok_123")
    }

    func testStoreWithoutOsmIdentifierIsRejectedBeforeSending() async {
        let broken = Store(id: "kaputt",
                           retailer: Retailer(id: "x", name: "X"),
                           coordinate: Coordinate(latitude: 52.5, longitude: 13.4))
        let stub = StubTransport(json: proofJSON)
        let sut = OpenPricesContributionClient(transport: stub)

        do {
            _ = try await sut.uploadPriceTag(imageData: Data([0xFF]), store: broken,
                                             currency: "EUR", date: Date(), token: "t")
            XCTFail("Erwartet: Fehler")
        } catch {
            // erwartet
        }
        XCTAssertEqual(stub.log.count, 0, "Ohne Filialkennung gar nicht erst senden")
    }
}

final class ContributionPriceTests: XCTestCase {

    private func submit(discounted: Bool,
                        original: Money?,
                        stub: StubTransport) async throws {
        let sut = OpenPricesContributionClient(transport: stub)
        try await sut.submitPrice(barcode: "3017620422003",
                                  price: Money(amount: Decimal(string: "3.53")!),
                                  date: Date(timeIntervalSince1970: 1_770_000_000),
                                  store: testStore(),
                                  proofID: 4242,
                                  isDiscounted: discounted,
                                  priceWithoutDiscount: original,
                                  token: "tok_123")
    }

    func testPayloadCarriesEverythingTheApiNeeds() async throws {
        let stub = StubTransport(json: "{\"id\":1}")
        try await submit(discounted: false, original: nil, stub: stub)

        let sent = body(of: stub.lastRequest)
        XCTAssertTrue(sent.contains("\"product_code\":\"3017620422003\""))
        XCTAssertTrue(sent.contains("\"proof_id\":4242"))
        XCTAssertTrue(sent.contains("\"currency\":\"EUR\""))
        XCTAssertTrue(sent.contains("\"location_osm_id\":494497710"))
        XCTAssertTrue(sent.contains("\"location_osm_type\":\"WAY\""))
    }

    /// Ein Ursprungspreis wird nur gesendet, wenn er wirklich bekannt ist --
    /// sonst stünde in einer öffentlichen Datenbank ein erfundener Wert.
    func testOriginalPriceIsOmittedWhenUnknown() async throws {
        let stub = StubTransport(json: "{\"id\":1}")
        try await submit(discounted: true, original: nil, stub: stub)
        XCTAssertFalse(body(of: stub.lastRequest).contains("price_without_discount"))
    }

    func testOriginalPriceIsSentWhenKnown() async throws {
        let stub = StubTransport(json: "{\"id\":1}")
        try await submit(discounted: true,
                         original: Money(amount: Decimal(string: "4.49")!),
                         stub: stub)
        XCTAssertTrue(body(of: stub.lastRequest).contains("price_without_discount"))
    }

    /// Der wichtigste Test dieser Datei: Ein Schreibvorgang darf nicht
    /// wiederholt werden. Kommt die Anfrage durch und geht nur die Antwort
    /// verloren, entstünde sonst ein Doppeleintrag in einer öffentlichen
    /// Datenbank.
    func testWritesAreNeverRetried() async {
        let stub = StubTransport([.success(.status(503))])
        do {
            try await submit(discounted: false, original: nil, stub: stub)
            XCTFail("Erwartet: Fehler")
        } catch {
            // erwartet
        }
        XCTAssertEqual(stub.log.count, 1,
                       "Genau ein Versuch - auch bei einem Fehler, der beim Lesen "
                       + "wiederholt würde")
    }
}
