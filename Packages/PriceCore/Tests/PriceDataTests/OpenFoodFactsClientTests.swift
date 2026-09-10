import XCTest
import PriceCore
@testable import PriceData

/// Die Vorlagen in dieser Datei sind **echte** Antworten der Open-Food-Facts-API,
/// abgerufen am 2026-09-10. Sie wurden nicht nachgebaut, sondern uebernommen --
/// nur auf die abgefragten Felder gekuerzt.
private enum Fixtures {

    /// GET /cgi/search.pl?search_terms=coca%20cola&json=1&page_size=3&fields=...
    static let search = """
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

    /// GET /api/v2/product/5449000054227.json?fields=...
    static let singleProduct = """
    {"code":"5449000054227","product":{\
    "brands":"COCA-COLA SERVICES SA/NV, Coca-Cola","code":"5449000054227",\
    "image_url":"https://images.openfoodfacts.org/images/products/544/900/005/4227/front_en.563.400.jpg",\
    "product_name":"Coca-Cola Original Taste","product_quantity":1000,\
    "product_quantity_unit":"ml","quantity":"1 L"},\
    "status":1,"status_verbose":"product found"}
    """

    /// So antwortet die API bei einem unbekannten Barcode.
    static let notFound = """
    {"code":"0000000000000","status":0,"status_verbose":"product not found"}
    """
}

final class OpenFoodFactsSearchTests: XCTestCase {

    private func client(_ json: String) -> OpenFoodFactsClient {
        OpenFoodFactsClient(transport: StubTransport(json: json))
    }

    func testRealSearchResponseIsDecoded() async throws {
        let products = try await client(Fixtures.search).search("coca cola")
        XCTAssertEqual(products.count, 3)

        let first = try XCTUnwrap(products.first)
        XCTAssertEqual(first.name, "Coca-Cola Original Taste")
        XCTAssertEqual(first.barcode, "5449000054227")
        XCTAssertEqual(first.quantity?.totalInBaseUnit, Decimal(1))
        XCTAssertEqual(first.quantity?.baseUnit, .liter)
    }

    /// Die echte Antwort enthaelt "1.5l" -- ohne Leerzeichen, mit Punkt.
    /// Der strukturierte Wert (1500 ml) muss dabei den Ausschlag geben.
    func testCompactQuantityStringFromRealData() async throws {
        let products = try await client(Fixtures.search).search("coca cola")
        let oneAndAHalf = try XCTUnwrap(products.first { $0.barcode == "5449000000439" })
        XCTAssertEqual(oneAndAHalf.quantity?.totalInBaseUnit, Decimal(string: "1.5"))
    }

    /// Der ganze Zweck der Produktdaten: daraus muss ein Grundpreis werden.
    func testUnitPriceCanBeComputedFromDecodedProduct() async throws {
        let products = try await client(Fixtures.search).search("coca cola")
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
        let products = try await client(Fixtures.search).search("coca cola")
        let fromApi = try XCTUnwrap(products.first)
        let manual = Product(barcode: nil, name: "Coca Cola", brand: "Coca-Cola",
                             quantity: Quantity.parse("1 l"))

        XCTAssertTrue(ProductMatcher.match(fromApi, manual).allowsUnitPriceComparison)
    }

    func testTooShortQueryDoesNotHitTheNetwork() async throws {
        let stub = StubTransport(json: Fixtures.search)
        let sut = OpenFoodFactsClient(transport: stub)
        let products = try await sut.search("c")
        XCTAssertTrue(products.isEmpty)
        XCTAssertEqual(stub.log.count, 0, "Ein einzelner Buchstabe darf keine Anfrage ausloesen")
    }

    func testProductsWithoutNameAreDropped() async throws {
        let json = """
        {"count":2,"products":[\
        {"code":"111","product_name":"","brands":"X","quantity":"1 l"},\
        {"code":"222","product_name":"Echtes Produkt","brands":"X","quantity":"1 l"}]}
        """
        let products = try await client(json).search("test")
        XCTAssertEqual(products.map(\.name), ["Echtes Produkt"])
    }

    /// Open Food Facts liefert `product_quantity` mal als Zahl, mal als Text.
    func testQuantityAsStringIsAlsoAccepted() async throws {
        let json = """
        {"count":1,"products":[{"code":"333","product_name":"Test",\
        "brands":"X","product_quantity":"750","product_quantity_unit":"ml",\
        "quantity":"750 ml"}]}
        """
        let products = try await client(json).search("test")
        XCTAssertEqual(products.first?.quantity?.totalInBaseUnit, Decimal(string: "0.75"))
    }

    func testMissingQuantityLeavesProductWithoutUnitPrice() async throws {
        let json = """
        {"count":1,"products":[{"code":"444","product_name":"Ohne Menge","brands":"X"}]}
        """
        let products = try await client(json).search("test")
        let product = try XCTUnwrap(products.first)
        XCTAssertNil(product.quantity)
        XCTAssertFalse(product.isComparable,
                       "Ohne Menge darf kein Grundpreis behauptet werden")
    }

    func testUnreadableResponseIsReportedNotSwallowed() async {
        let sut = client("<html>kaputt</html>")
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
}

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

    func testEmptyBarcodeNeverReachesTheNetwork() async {
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
