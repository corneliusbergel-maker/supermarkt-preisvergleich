import XCTest
@testable import PriceCore

final class ProductMatcherTests: XCTestCase {

    private func product(_ name: String,
                         brand: String? = "Coca-Cola",
                         quantity: String?,
                         barcode: String? = nil) -> Product {
        Product(
            barcode: barcode,
            name: name,
            brand: brand,
            quantity: quantity.flatMap { Quantity.parse($0) }
        )
    }

    // MARK: - Die Beispiele aus Anforderung #21

    func testDifferentSpellingsOfTheSameProductMatch() {
        // "Coca-Cola Original 1,5L" und "Coca Cola 1.5 Liter" sind dasselbe.
        let a = product("Coca-Cola Original 1,5L", quantity: "1,5 l")
        let b = product("Coca Cola 1.5 Liter", quantity: "1.5 l")

        let result = ProductMatcher.match(a, b)
        XCTAssertTrue(result.allowsPriceMerging,
                      "Sollte identisch sein, war: \(result.reason)")
    }

    func testZeroIsNeverMergedWithOriginal() {
        // Die wichtigste Trennregel der ganzen App.
        let original = product("Coca-Cola Original 1,5L", quantity: "1,5 l")
        let zero = product("Coca-Cola Zero 1,5L", quantity: "1,5 l")

        let result = ProductMatcher.match(original, zero)
        XCTAssertFalse(result.allowsPriceMerging)
        XCTAssertFalse(result.allowsUnitPriceComparison)
        if case .different = result {} else {
            XCTFail("Zero und Original muessen getrennt bleiben, war: \(result)")
        }
    }

    func testDifferentTotalQuantityIsNotTheSameProduct() {
        // 4 x 250 g (= 1000 g) ist nicht 1 x 250 g.
        let single = product("Barilla Spaghetti", brand: "Barilla", quantity: "250 g")
        let pack = product("Barilla Spaghetti", brand: "Barilla", quantity: "4 x 250 g")

        let result = ProductMatcher.match(single, pack)
        XCTAssertFalse(result.allowsPriceMerging,
                       "Unterschiedliche Gesamtmenge darf nie zusammengefuehrt werden")
        XCTAssertTrue(result.allowsUnitPriceComparison,
                      "Ueber den Grundpreis bleiben sie aber vergleichbar")
    }

    func testFiveHundredGramsIsNotOneKilogram() {
        let small = product("Nutella", brand: "Ferrero", quantity: "500 g")
        let large = product("Nutella", brand: "Ferrero", quantity: "1 kg")

        let result = ProductMatcher.match(small, large)
        XCTAssertFalse(result.allowsPriceMerging)
        XCTAssertTrue(result.allowsUnitPriceComparison)
    }

    func testMilkOneLitreVersusOneAndAHalf() {
        // Aus Anforderung #7: 1 l Milch darf nicht gegen 1,5 l verglichen werden.
        let a = product("Frische Vollmilch", brand: "Weihenstephan", quantity: "1 l")
        let b = product("Frische Vollmilch", brand: "Weihenstephan", quantity: "1,5 l")
        XCTAssertFalse(ProductMatcher.match(a, b).allowsPriceMerging)
    }

    // MARK: - Barcode

    func testSameBarcodeIsAlwaysIdentical() {
        let a = product("Coca-Cola", quantity: "1,5 l", barcode: "5449000054227")
        let b = product("Cola Original Taste", quantity: "1,5 l", barcode: "5449000054227")
        XCTAssertTrue(ProductMatcher.match(a, b).allowsPriceMerging)
    }

    func testLeadingZerosInBarcodesAreIgnored() {
        let a = product("Testware", brand: "X", quantity: "1 l", barcode: "05449000054227")
        let b = product("Testware", brand: "X", quantity: "1 l", barcode: "5449000054227")
        XCTAssertTrue(ProductMatcher.match(a, b).allowsPriceMerging)
    }

    func testDifferentBarcodesAreNeverMergedEvenWhenNamesAgree() {
        let a = product("Coca-Cola", quantity: "1,5 l", barcode: "5449000054227")
        let b = product("Coca-Cola", quantity: "1,5 l", barcode: "5449000000996")
        let result = ProductMatcher.match(a, b)
        XCTAssertFalse(result.allowsPriceMerging,
                       "Unterschiedliche Barcodes duerfen keine Preise zusammenfuehren")
        XCTAssertTrue(result.allowsUnitPriceComparison)
    }

    // MARK: - Marke

    func testDifferentBrandsNeverMatch() {
        let cola = product("Cola 1,5 l", brand: "Coca-Cola", quantity: "1,5 l")
        let pepsi = product("Cola 1,5 l", brand: "Pepsi", quantity: "1,5 l")
        XCTAssertFalse(ProductMatcher.match(cola, pepsi).allowsUnitPriceComparison)
    }

    func testCorporateSuffixesDoNotBreakBrandMatching() {
        // So liefert Open Food Facts die Marke tatsaechlich aus.
        let a = product("Coca-Cola Original Taste",
                        brand: "COCA-COLA SERVICES SA/NV, Coca-Cola",
                        quantity: "1 l")
        let b = product("Coca Cola", brand: "Coca-Cola", quantity: "1 l")
        XCTAssertTrue(ProductMatcher.match(a, b).allowsPriceMerging)
    }

    /// Quellen fuehren Marken unterschiedlich vollstaendig. Der Suchindex von
    /// Open Food Facts liefert ["Ferrero", "Nutella"], die klassische Route
    /// nur "Ferrero". Ohne gemeinsame Markenwortliste wuerde "nutella" einmal
    /// als Marke wegfallen und einmal als Bedeutungswort stehen bleiben --
    /// die Namen wirkten dann verschieden.
    func testDifferentlyCompleteBrandListsStillMatch() {
        let fromIndex = Product(barcode: nil, name: "Nutella Brotaufstrich",
                                brand: "Ferrero, Nutella",
                                quantity: Quantity.parse("600 g"))
        let fromLegacy = Product(barcode: nil, name: "Nutella", brand: "Ferrero",
                                 quantity: Quantity.parse("600 g"))

        let result = ProductMatcher.match(fromIndex, fromLegacy)
        XCTAssertTrue(result.allowsPriceMerging, "War: \(result.reason)")
    }

    /// Die Kehrseite derselben Regel: Ein trennendes Variantenwort darf nicht
    /// deshalb verschwinden, weil es zufaellig auch im Markennamen steht.
    /// Sonst wuerde Bio-Ware mit konventioneller zusammengefuehrt.
    func testVariantWordInsideTheBrandStillSeparates() {
        let bio = Product(barcode: nil, name: "Bio Vollmilch", brand: "Bio Company",
                          quantity: Quantity.parse("1 l"))
        let conventional = Product(barcode: nil, name: "Vollmilch", brand: "Bio Company",
                                   quantity: Quantity.parse("1 l"))

        XCTAssertFalse(ProductMatcher.match(bio, conventional).allowsPriceMerging,
                       "„bio“ darf nicht als blosses Markenwort weggefiltert werden")
    }

    // MARK: - Varianten

    func testBioIsAVariantThatSeparates() {
        let normal = product("Vollmilch", brand: "Berchtesgadener", quantity: "1 l")
        let bio = product("Bio Vollmilch", brand: "Berchtesgadener", quantity: "1 l")
        XCTAssertFalse(ProductMatcher.match(normal, bio).allowsPriceMerging)
    }

    func testLactoseFreeIsAVariantThatSeparates() {
        let normal = product("Vollmilch", brand: "Weihenstephan", quantity: "1 l")
        let free = product("Vollmilch laktosefrei", brand: "Weihenstephan", quantity: "1 l")
        XCTAssertFalse(ProductMatcher.match(normal, free).allowsPriceMerging)
    }

    func testMissingQuantityBlocksAnyMatch() {
        // Ohne Menge kein Vergleich -- lieber nichts anzeigen als raten.
        let known = product("Nutella", brand: "Ferrero", quantity: "450 g")
        let unknown = product("Nutella", brand: "Ferrero", quantity: nil)
        XCTAssertFalse(ProductMatcher.match(known, unknown).allowsUnitPriceComparison)
    }

    // MARK: - Gruppierung fuer die Suchergebnisliste

    func testSearchResultsGroupIntoDistinctArticles() {
        // Aus Anforderung #6: drei Ergebnisse, drei getrennte Artikel.
        let products = [
            product("Coca-Cola Original", quantity: "1,5 l"),
            product("Coca Cola 1.5 Liter", quantity: "1,5 l"),
            product("Coca-Cola Zero", quantity: "1,5 l"),
            product("Coca-Cola Original", quantity: "6 x 1,5 l")
        ]

        let groups = ProductMatcher.group(products)
        XCTAssertEqual(groups.count, 3, "Original, Zero und der 6er-Pack sind drei Artikel")
        XCTAssertTrue(groups.contains { $0.count == 2 },
                      "Die beiden Schreibweisen von Original gehoeren zusammen")
    }
}

final class ProductTextNormalizerTests: XCTestCase {

    func testUmlautsAreExpanded() {
        XCTAssertEqual(ProductTextNormalizer.normalize("Müllermilch Größe"),
                       "muellermilch groesse")
    }

    func testPunctuationBecomesSeparator() {
        XCTAssertEqual(ProductTextNormalizer.normalize("Coca-Cola"), "coca cola")
    }

    func testQuantityTokensAreRecognised() {
        XCTAssertTrue(ProductTextNormalizer.isQuantityToken("500g"))
        XCTAssertTrue(ProductTextNormalizer.isQuantityToken("5l"))
        XCTAssertTrue(ProductTextNormalizer.isQuantityToken("1kg"))
        XCTAssertFalse(ProductTextNormalizer.isQuantityToken("zero"))
        XCTAssertFalse(ProductTextNormalizer.isQuantityToken("4you"))
    }

    func testQuantityTokensDoNotLeakIntoCoreTokens() {
        let tokens = ProductTextNormalizer.coreTokens(name: "Coca-Cola Original 1,5L",
                                                      brand: "Coca-Cola")
        XCTAssertFalse(tokens.contains("5l"))
        XCTAssertTrue(tokens.isEmpty, "Uebrig bleiben duerfte hier nichts, war: \(tokens)")
    }

    func testVariantTokensAreExtracted() {
        let variants = ProductTextNormalizer.variantTokens(name: "Coca-Cola Zero Zucker",
                                                           brand: "Coca-Cola")
        XCTAssertEqual(variants, ["zero"])
    }
}
