import XCTest
@testable import PriceCore

final class DecimalParsingTests: XCTestCase {

    func testGermanDecimalComma() {
        XCTAssertEqual(DecimalParsing.decimal(from: "1,5"), Decimal(string: "1.5"))
        XCTAssertEqual(DecimalParsing.decimal(from: "0,99"), Decimal(string: "0.99"))
    }

    func testEnglishDecimalPoint() {
        XCTAssertEqual(DecimalParsing.decimal(from: "1.5"), Decimal(string: "1.5"))
    }

    func testThousandsSeparatorIsNotADecimalSeparator() {
        // "1.500 ml" meint 1500 ml, nicht 1,5 ml.
        XCTAssertEqual(DecimalParsing.decimal(from: "1.500"), Decimal(1500))
        XCTAssertEqual(DecimalParsing.decimal(from: "1,500"), Decimal(1500))
    }

    func testLeadingZeroKeepsDecimalMeaning() {
        // "0,500 kg" meint 0,5 kg -- die Ausnahme von der Regel darueber.
        XCTAssertEqual(DecimalParsing.decimal(from: "0,500"), Decimal(string: "0.5"))
        XCTAssertEqual(DecimalParsing.decimal(from: "0.500"), Decimal(string: "0.5"))
    }

    func testBothSeparatorsRightmostWins() {
        XCTAssertEqual(DecimalParsing.decimal(from: "1.234,56"), Decimal(string: "1234.56"))
        XCTAssertEqual(DecimalParsing.decimal(from: "1,234.56"), Decimal(string: "1234.56"))
    }

    func testGarbageReturnsNilInsteadOfZero() {
        // Wichtig: kein stiller Fallback auf 0 -- das waere ein erfundener Wert.
        XCTAssertNil(DecimalParsing.decimal(from: "abc"))
        XCTAssertNil(DecimalParsing.decimal(from: ""))
        XCTAssertNil(DecimalParsing.decimal(from: "1,5 kg"))
    }
}

final class QuantityParsingTests: XCTestCase {

    func testSimpleVolume() throws {
        let quantity = try XCTUnwrap(Quantity.parse("1,5 L"))
        XCTAssertEqual(quantity.packCount, 1)
        XCTAssertEqual(quantity.unitAmount, Decimal(string: "1.5"))
        XCTAssertEqual(quantity.unit, .liter)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(string: "1.5"))
    }

    func testSimpleMassWithoutSpace() throws {
        let quantity = try XCTUnwrap(Quantity.parse("500g"))
        XCTAssertEqual(quantity.unit, .gram)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(string: "0.5"))
    }

    func testMilliliters() throws {
        let quantity = try XCTUnwrap(Quantity.parse("750 ml"))
        XCTAssertEqual(quantity.unit, .milliliter)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(string: "0.75"))
    }

    func testMultipackWithAsciiX() throws {
        let quantity = try XCTUnwrap(Quantity.parse("6 x 1,5 l"))
        XCTAssertEqual(quantity.packCount, 6)
        XCTAssertEqual(quantity.unitAmount, Decimal(string: "1.5"))
        XCTAssertTrue(quantity.isMultipack)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(9))
    }

    func testMultipackWithTypographicMultiplicationSign() throws {
        let quantity = try XCTUnwrap(Quantity.parse("4 \u{00D7} 250 g"))
        XCTAssertEqual(quantity.packCount, 4)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(1))
    }

    func testMultipackWithoutSpaces() throws {
        let quantity = try XCTUnwrap(Quantity.parse("2x200g"))
        XCTAssertEqual(quantity.packCount, 2)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(string: "0.4"))
    }

    func testParenthesisedMultipackWins() throws {
        let quantity = try XCTUnwrap(Quantity.parse("500 g (2 x 250 g)"))
        XCTAssertEqual(quantity.packCount, 2)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(string: "0.5"))
    }

    func testCountUnit() throws {
        let quantity = try XCTUnwrap(Quantity.parse("10 Stück"))
        XCTAssertEqual(quantity.unit, .piece)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(10))
    }

    func testUnparsableReturnsNil() {
        // Lieber gar keine Menge als eine geratene.
        XCTAssertNil(Quantity.parse(""))
        XCTAssertNil(Quantity.parse("Familienpackung"))
        XCTAssertNil(Quantity.parse("6er Pack"))
        XCTAssertNil(Quantity.parse("0 g"))
    }

    func testDimensionsDoNotMix() throws {
        let volume = try XCTUnwrap(Quantity.parse("1 l"))
        let mass = try XCTUnwrap(Quantity.parse("1 kg"))
        XCTAssertFalse(volume.isComparable(with: mass))
    }

    func testSameTotalAcrossDifferentUnits() throws {
        let grams = try XCTUnwrap(Quantity.parse("1000 g"))
        let kilos = try XCTUnwrap(Quantity.parse("1 kg"))
        XCTAssertTrue(grams.hasSameTotal(as: kilos))
    }

    func testDifferentTotalIsRejected() throws {
        // Aus der Anforderung: 4 x 250 g ist NICHT 1 x 250 g.
        let single = try XCTUnwrap(Quantity.parse("250 g"))
        let pack = try XCTUnwrap(Quantity.parse("4 x 250 g"))
        XCTAssertFalse(single.hasSameTotal(as: pack))
    }
}

final class OpenFoodFactsQuantityTests: XCTestCase {

    func testStructuredFieldsArePreferred() throws {
        // So liefert die echte API Coca-Cola 1 L.
        let quantity = try XCTUnwrap(Quantity.fromOpenFoodFacts(
            productQuantity: Decimal(1000),
            productQuantityUnit: "ml",
            quantityText: "1 L"
        ))
        XCTAssertEqual(quantity.unit, .milliliter)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(1))
    }

    func testMultipackFromTextIsAdoptedOnlyIfTotalMatches() throws {
        let quantity = try XCTUnwrap(Quantity.fromOpenFoodFacts(
            productQuantity: Decimal(9000),
            productQuantityUnit: "ml",
            quantityText: "6 x 1,5 l"
        ))
        XCTAssertEqual(quantity.packCount, 6)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(9))
    }

    func testContradictingTextIsIgnoredInFavourOfStructuredData() throws {
        // Text behauptet 9 l, strukturiert stehen 1,5 l -> strukturiert gewinnt.
        let quantity = try XCTUnwrap(Quantity.fromOpenFoodFacts(
            productQuantity: Decimal(1500),
            productQuantityUnit: "ml",
            quantityText: "6 x 1,5 l"
        ))
        XCTAssertEqual(quantity.packCount, 1)
        XCTAssertEqual(quantity.totalInBaseUnit, Decimal(string: "1.5"))
    }

    func testNoDataMeansNoQuantity() {
        XCTAssertNil(Quantity.fromOpenFoodFacts(productQuantity: nil,
                                                productQuantityUnit: nil,
                                                quantityText: nil))
    }
}
