import XCTest
import PriceCore
@testable import PriceData

/// Die Vorlagen in dieser Datei sind **echte** Antworten der
/// Open-Food-Facts-Dienste, abgerufen am 2026-09-10 und 2026-09-11.
/// Sie wurden nicht nachgebaut, sondern uebernommen -- nur auf die
/// abgefragten Felder gekuerzt.
private enum Fixtures {

    /// `search.openfoodfacts.org/search?q=nutella countries_tags:"en:germany"`
    /// Man beachte: `brands` ist hier ein **Feld**, nicht ein Text.
    static let index = """
    {"hits":[\
    {"code":"4000006055000","brands":["Nutella"],"product_name":"Nutella & Go"},\
    {"code":"0062020050526","brands":["Nutella"," Ferrero"],"product_name":"Nutella",\
    "image_url":"https://images.openfoodfacts.org/images/products/006/202/005/0526/front_en.16.400.jpg"},\
    {"code":"3017620406003","brands":["Ferrero"," Nutella"],"quantity":"600 g",\
    "product_name":"Nutella pâte à tartiner aux noisettes et au cacao 600g",\
    "image_url":"https://images.openfoodfacts.org/images/products/301/762/040/6003/front_fr.203.400.jpg"}],\
    "page":1,"page_size":3,"page_count":19,"count":57,"is_count_exact":true,"timed_out":false}
    """

    /// Derselbe Dienst fuer einen Barcode -- hier ohne `product_quantity`,
    /// weil der Index dieses Feld nicht fuehrt.
    static let indexSingle = """
    {"hits":[{"code":"5449000054227","brands":["Coca-Cola"],"quantity":"1 l",\
    "product_name":"Coca-Cola",\
    "image_url":"https://images.openfoodfacts.org/images/products/544/900/005/4227/front_en.361.400.jpg"}],\
    "page":1,"page_size":1,"page_count":1,"count":1,"timed_out":false}
    """

    /// `/cgi/search.pl` -- hier ist `brands` ein kommagetrennter Text.
    static let legacy = """
    {"count":2234,"page":1,"page_count":3,"page_size":3,"products":[\
    {"brands":"COCA-COLA SERVICES SA/NV, Coca-Cola","code":"5449000054227",\
    "product_name":"Coca-Cola Original Taste","product_quantity":1000,\
    "product_quantity_unit":"ml","quantity":"1 L"},\
    {"brands":"Coca-Cola","code":"5449000000439",\
    "product_name":"Coca Cola Original taste","product_quantity":1500,\
    "product_quantity_unit":"ml","quantity":"1.5l"},\
    {"brands":"Coca cola, Hawai","code":"5449000036872",\
    "product_name":"Hawai Tropical","product_quantity":1000,\
    "product_quantity_unit":"ml","quantity":"1 L"}],"skip":0}
    """

    /// `/api/v2/product/5449000054227.json`
    static let singleProduct = """
    {"code":"5449000054227","product":{\
    "brands":"COCA-COLA SERVICES SA/NV, Coca-Cola","code":"5449000054227",\
    "image_url":"https://images.openfoodfacts.org/images/products/544/900/005/4227/front_en.563.400.jpg",\
    "product_name":"Coca-Cola Original Taste","product_quantity":1000,\
    "product_quantity_unit":"ml","quantity":"1 L"},\
    "status":1,"status_verbose":"product found"}
    """

    static let notFound = """
    {"code":"0000000000000","status":0,"status_verbose":"product not found"}
    """
}

// MARK: - Suchindex (Hauptweg)

final class OpenFoodFactsIndexTests: XCTestCase {

    private func client(_ json: String) -> OpenFoodFactsClient {
        OpenFoodFactsClient(transport: StubTransport(json: json))
    }

    func testRealIndexResponseIsDecoded() async throws {
        let products = try await client(Fixtures.index).searchIndex("nutella")
        XCTAssertEqual(products.count, 3)
        XCTAssertEqual(products.first?.name, "Nutella & Go")
    }

    /// Der Index liefert `brands` als Feld, die klassische Route als Text.
    /// Beides muss zur selben Marke fuehren.
    func testBrandArrayIsJoined() async throws {
        let products = try await client(Fixtures.index).searchIndex("nutella")
        let ferrero = try XCTUnwrap(products.first { $0.barcode == "3017620406003" })
        XCTAssertEqual(ferrero.brand, "Ferrero, Nutella")
    }

    func testBrandFromArrayStillMatchesBrandFromText() async throws {
        let fromIndex = try await client(Fixtures.index).searchIndex("nutella")
        let indexProduct = try XCTUnwrap(fromIndex.first { $0.barcode == "3017620406003" })

        let fromLegacy = Product(barcode: nil, name: "Nutella", brand: "Ferrero",
                                 quantity: Quantity.parse("600 g"))

        XCTAssertTrue(ProductMatcher.match(indexProduct, fromLegacy).allowsUnitPriceComparison,
                      "Marke aus Feld und Marke aus Text muessen zusammenfinden")
    }

    /// Der Index fuehrt kein `product_quantity`. Die Menge muss deshalb aus
    /// dem Freitext kommen -- und das muss funktionieren.
    func testQuantityIsParsedFromTextWhenStructuredFieldIsAbsent() async throws {
        let products = try await client(Fixtures.index).searchIndex("nutella")
        let sixHundred = try XCTUnwrap(products.first { $0.barcode == "3017620406003" })
        XCTAssertEqual(sixHundred.quantity?.totalInBaseUnit, Decimal(string: "0.6"))
        XCTAssertEqual(sixHundred.quantity?.baseUnit, .kilogram)
    }

    func testLowercaseLitreFromIndexIsUnderstood() async throws {
        let products = try await client(Fixtures.indexSingle).searchIndex("cola")
        XCTAssertEqual(products.first?.quantity?.totalInBaseUnit, Decimal(1))
    }

    func testProductWithoutQuantityHasNoUnitPrice() async throws {
        let products = try await client(Fixtures.index).searchIndex("nutella")
        let noQuantity = try XCTUnwrap(products.first { $0.barcode == "4000006055000" })
        XCTAssertNil(noQuantity.quantity)
        XCTAssertFalse(noQuantity.isComparable)
    }
}

// MARK: - Rückfall auf die klassische Route

final class OpenFoodFactsFallbackTests: XCTestCase {

    /// Der Suchindex ist der Hauptweg. Faellt er voruebergehend aus, muss die
    /// klassische Route einspringen, statt dem Nutzer "nichts gefunden" zu
    /// melden.
    func testTemporaryIndexFailureFallsBackToLegacy() async throws {
        let stub = StubTransport([
            .success(.status(503)),                 // Index gestoert
            .success(.status(503)),                 // Wiederholung ebenfalls
            .success(.status(503)),                 // letzter Versuch
            .success(HTTPResponse(status: 200, body: Data(Fixtures.legacy.utf8)))
        ])
        let sut = OpenFoodFactsClient(transport: stub)

        let products = try await sut.search("coca cola")
        XCTAssertEqual(products.count, 3, "Die klassische Route hat uebernommen")
        XCTAssertGreaterThan(stub.log.count, 3)
    }

    /// Ein endgueltiger Fehler darf nicht in einen Rueckfall muenden, der ihn
    /// verschleiert.
    func testUnreadableIndexResponseIsReportedNotHidden() async {
        let sut = OpenFoodFactsClient(transport: StubTransport(json: "<html>kaputt</html>"))
        do {
            _ = try await sut.search("coca cola")
            XCTFail("Erwartet: Fehler")
        } catch let error as DataSourceError {
            guard case .decoding = error else {
                return XCTFail("Erwartet: .decoding, war \(error)")
            }
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)")
        }
    }

    func testTooShortQueryNeverReachesTheNetwork() async throws {
        let stub = StubTransport(json: Fixtures.index)
        let sut = OpenFoodFactsClient(transport: stub)
        let products = try await sut.search("c")
        XCTAssertTrue(products.isEmpty)
        XCTAssertEqual(stub.log.count, 0, "Ein einzelner Buchstabe darf keine Anfrage ausloesen")
    }
}

// MARK: - Klassische Route

final class OpenFoodFactsLegacySearchTests: XCTestCase {

    private func client(_ json: String) -> OpenFoodFactsClient {
        OpenFoodFactsClient(transport: StubTransport(json: json))
    }

    func testRealLegacyResponseIsDecoded() async throws {
        let products = try await client(Fixtures.legacy).searchLegacy("coca cola")
        XCTAssertEqual(products.count, 3)

        let first = try XCTUnwrap(products.first)
        XCTAssertEqual(first.name, "Coca-Cola Original Taste")
        XCTAssertEqual(first.barcode, "5449000054227")
        XCTAssertEqual(first.quantity?.totalInBaseUnit, Decimal(1))
    }

    /// Die echte Antwort enthaelt "1.5l" -- ohne Leerzeichen, mit Punkt.
    /// Der strukturierte Wert (1500 ml) muss dabei den Ausschlag geben.
    func testCompactQuantityStringFromRealData() async throws {
        let products = try await client(Fixtures.legacy).searchLegacy("coca cola")
        let oneAndAHalf = try XCTUnwrap(products.first { $0.barcode == "5449000000439" })
        XCTAssertEqual(oneAndAHalf.quantity?.totalInBaseUnit, Decimal(string: "1.5"))
    }

    /// Der ganze Zweck der Produktdaten: daraus muss ein Grundpreis werden.
    func testUnitPriceCanBeComputedFromDecodedProduct() async throws {
        let products = try await client(Fixtures.legacy).searchLegacy("coca cola")
        let oneAndAHalf = try XCTUnwrap(products.first { $0.barcode == "5449000000439" })
        let quantity = try XCTUnwrap(oneAndAHalf.quantity)

        let unitPrice = try XCTUnwrap(UnitPrice.calculate(
            price: Money(amount: Decimal(string: "1.49")!),
            quantity: quantity
        ))
        XCTAssertEqual(DecimalParsing.round(unitPrice.price.amount, scale: 3),
                       Decimal(string: "0.993"))
    }

    func testBrandWithCorporateSuffixStillMatchesPlainBrand() async throws {
        // Die echte Marke lautet "COCA-COLA SERVICES SA/NV, Coca-Cola".
        let products = try await client(Fixtures.legacy).searchLegacy("coca cola")
        let fromApi = try XCTUnwrap(products.first)
        let manual = Product(barcode: nil, name: "Coca Cola", brand: "Coca-Cola",
                             quantity: Quantity.parse("1 l"))

        XCTAssertTrue(ProductMatcher.match(fromApi, manual).allowsUnitPriceComparison)
    }

    func testProductsWithoutNameAreDropped() async throws {
        let json = """
        {"count":2,"products":[\
        {"code":"111","product_name":"","brands":"X","quantity":"1 l"},\
        {"code":"222","product_name":"Echtes Produkt","brands":"X","quantity":"1 l"}]}
        """
        let products = try await client(json).searchLegacy("test")
        XCTAssertEqual(products.map(\.name), ["Echtes Produkt"])
    }

    /// Open Food Facts liefert `product_quantity` mal als Zahl, mal als Text.
    func testQuantityAsStringIsAlsoAccepted() async throws {
        let json = """
        {"count":1,"products":[{"code":"333","product_name":"Test",\
        "brands":"X","product_quantity":"750","product_quantity_unit":"ml",\
        "quantity":"750 ml"}]}
        """
        let products = try await client(json).searchLegacy("test")
        XCTAssertEqual(products.first?.quantity?.totalInBaseUnit, Decimal(string: "0.75"))
    }
}

// MARK: - Barcode

final class OpenFoodFactsBarcodeTests: XCTestCase {

    func testRealProductResponseIsDecoded() async throws {
        let sut = OpenFoodFactsClient(transport: StubTransport(json: Fixtures.singleProduct))
        let product = try await sut.product(barcode: "5449000054227")

        XCTAssertEqual(product.name, "Coca-Cola Original Taste")
        XCTAssertEqual(product.quantity?.totalInBaseUnit, Decimal(1))
        XCTAssertNotNil(product.imageURL)
    }

    func testUnknownBarcodeIsNotFound() async {
        let sut = OpenFoodFactsClient(transport: StubTransport(json: Fixtures.notFound))
        await assertThrows(.notFound) { _ = try await sut.product(barcode: "0000000000000") }
    }

    func testNonNumericBarcodeNeverReachesTheNetwork() async {
        let stub = StubTransport(json: Fixtures.notFound)
        let sut = OpenFoodFactsClient(transport: stub)
        await assertThrows(.notFound) { _ = try await sut.product(barcode: "abc") }
        XCTAssertEqual(stub.log.count, 0)
    }

    func testHttpNotFoundIsMappedNotRetried() async {
        let stub = StubTransport([.success(.status(404))])
        let sut = OpenFoodFactsClient(transport: stub)
        await assertThrows(.notFound) { _ = try await sut.product(barcode: "123") }
        XCTAssertEqual(stub.log.count, 1, "404 ist endgueltig, kein Wiederholungsfall")
    }
}

// MARK: - Hilfe

extension XCTestCase {
    func assertThrows(_ expected: DataSourceError,
                      file: StaticString = #filePath,
                      line: UInt = #line,
                      _ block: () async throws -> Void) async {
        do {
            try await block()
            XCTFail("Erwartet: \(expected)", file: file, line: line)
        } catch let error as DataSourceError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)", file: file, line: line)
        }
    }
}
