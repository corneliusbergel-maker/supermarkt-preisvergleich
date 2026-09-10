import XCTest
@testable import PriceCore

final class UnitPriceTests: XCTestCase {

    private func money(_ value: String) -> Money {
        Money(amount: Decimal(string: value)!, currency: "EUR")
    }

    /// Aus der Anforderung: 1,5 L fuer 1,49 EUR -> 0,993 EUR/l.
    func testColaExampleFromRequirements() throws {
        let quantity = try XCTUnwrap(Quantity.parse("1,5 l"))
        let unitPrice = try XCTUnwrap(UnitPrice.calculate(price: money("1.49"),
                                                          quantity: quantity))
        XCTAssertEqual(unitPrice.referenceAmount, 1)
        XCTAssertEqual(unitPrice.referenceUnit, .liter)
        XCTAssertEqual(DecimalParsing.round(unitPrice.price.amount, scale: 3),
                       Decimal(string: "0.993"))
        XCTAssertEqual(DecimalParsing.round(unitPrice.price.amount, scale: 2),
                       Decimal(string: "0.99"))
    }

    /// Aus der Anforderung: 4,99 EUR / 500 g -> 9,98 EUR/kg. Exakt, ohne Rest.
    func testFiveHundredGramsExample() throws {
        let quantity = try XCTUnwrap(Quantity.parse("500 g"))
        let unitPrice = try XCTUnwrap(UnitPrice.calculate(price: money("4.99"),
                                                          quantity: quantity))
        XCTAssertEqual(unitPrice.referenceUnit, .kilogram)
        XCTAssertEqual(unitPrice.price.amount, Decimal(string: "9.98"))
    }

    /// Aus der Anforderung: Produkt A 500 g / 3,99 EUR gegen B 1 kg / 6,49 EUR.
    func testLargerPackIsCheaperPerKilogram() throws {
        let small = try XCTUnwrap(Quantity.parse("500 g"))
        let large = try XCTUnwrap(Quantity.parse("1 kg"))

        let priceA = try XCTUnwrap(UnitPrice.calculate(price: money("3.99"), quantity: small))
        let priceB = try XCTUnwrap(UnitPrice.calculate(price: money("6.49"), quantity: large))

        XCTAssertEqual(priceA.price.amount, Decimal(string: "7.98"))
        XCTAssertEqual(priceB.price.amount, Decimal(string: "6.49"))
        XCTAssertTrue(priceB < priceA)

        // "Die 1-kg-Packung ist pro kg rund 19 % guenstiger."
        let advantage = try XCTUnwrap(priceB.relativeAdvantage(over: priceA))
        XCTAssertEqual(DecimalParsing.round(advantage, scale: 4), Decimal(string: "-0.1867"))
    }

    func testMultipackUsesTotalQuantity() throws {
        // 6 x 1,5 l = 9 l fuer 8,94 EUR -> 0,993... EUR/l
        let quantity = try XCTUnwrap(Quantity.parse("6 x 1,5 l"))
        let unitPrice = try XCTUnwrap(UnitPrice.calculate(price: money("8.94"),
                                                          quantity: quantity))
        XCTAssertEqual(DecimalParsing.round(unitPrice.price.amount, scale: 3),
                       Decimal(string: "0.993"))
    }

    func testSmallPackagesUseHundredGramBasis() throws {
        // Unter 250 g wird nach PAngV auf 100 g bezogen.
        let quantity = try XCTUnwrap(Quantity.parse("200 g"))
        let unitPrice = try XCTUnwrap(UnitPrice.calculate(price: money("2.50"),
                                                          quantity: quantity))
        XCTAssertEqual(unitPrice.referenceAmount, 100)
        XCTAssertEqual(unitPrice.referenceUnit, .gram)
        XCTAssertEqual(unitPrice.price.amount, Decimal(string: "1.25"))
    }

    func testPerBaseUnitBasisOverridesAutomatic() throws {
        let quantity = try XCTUnwrap(Quantity.parse("200 g"))
        let unitPrice = try XCTUnwrap(UnitPrice.calculate(price: money("2.50"),
                                                          quantity: quantity,
                                                          basis: .perBaseUnit))
        XCTAssertEqual(unitPrice.referenceUnit, .kilogram)
        XCTAssertEqual(unitPrice.price.amount, Decimal(string: "12.5"))
    }

    /// Der wichtigste Vergleichstest: 100-g-Basis und kg-Basis muessen
    /// gegeneinander korrekt sortieren.
    func testDifferentBasesCompareCorrectly() throws {
        let small = try XCTUnwrap(Quantity.parse("200 g"))     // -> EUR/100 g
        let large = try XCTUnwrap(Quantity.parse("1 kg"))      // -> EUR/kg

        let a = try XCTUnwrap(UnitPrice.calculate(price: money("2.50"), quantity: small))
        let b = try XCTUnwrap(UnitPrice.calculate(price: money("11.00"), quantity: large))

        XCTAssertEqual(a.normalizedPerBaseUnit, Decimal(string: "12.5"))
        XCTAssertEqual(b.normalizedPerBaseUnit, Decimal(11))
        XCTAssertTrue(b < a, "11 EUR/kg muss guenstiger sein als 1,25 EUR/100 g")
    }

    func testVolumeAndMassAreNotComparable() throws {
        let volume = try XCTUnwrap(Quantity.parse("1 l"))
        let mass = try XCTUnwrap(Quantity.parse("1 kg"))
        let a = try XCTUnwrap(UnitPrice.calculate(price: money("1.00"), quantity: volume))
        let b = try XCTUnwrap(UnitPrice.calculate(price: money("2.00"), quantity: mass))
        XCTAssertNil(a.relativeAdvantage(over: b))
    }

    func testCountUnitsAlwaysUsePieceBasis() throws {
        let quantity = try XCTUnwrap(Quantity.parse("10 Stk"))
        let unitPrice = try XCTUnwrap(UnitPrice.calculate(price: money("2.00"),
                                                          quantity: quantity))
        XCTAssertEqual(unitPrice.referenceAmount, 1)
        XCTAssertEqual(unitPrice.referenceUnit, .piece)
        XCTAssertEqual(unitPrice.price.amount, Decimal(string: "0.2"))
    }
}

final class MoneyTests: XCTestCase {

    func testSumIsExactWhereDoubleWouldDrift() {
        // 0,10 + 0,20 ist mit Double nicht exakt 0,30. Mit Decimal schon.
        let values = [
            Money(amount: Decimal(string: "0.10")!),
            Money(amount: Decimal(string: "0.20")!)
        ]
        XCTAssertEqual(Money.sum(values)?.amount, Decimal(string: "0.30"))
    }

    func testHundredCentsAddUpExactly() {
        let cents = Array(repeating: Money(amount: Decimal(string: "0.01")!), count: 100)
        XCTAssertEqual(Money.sum(cents)?.amount, Decimal(1))
    }

    func testSumOfEmptyListIsNilNotZero() {
        // Eine leere Einkaufsliste kostet nicht "0 EUR" -- sie hat keinen Preis.
        XCTAssertNil(Money.sum([]))
    }

    func testMixedCurrenciesRefuseToSum() {
        let values = [Money(amount: 1, currency: "EUR"), Money(amount: 1, currency: "CHF")]
        XCTAssertNil(Money.sum(values))
    }

    /// Aus der Anforderung: 1,69 EUR auf 1,39 EUR ist -17,8 %.
    func testRelativeChangeMatchesRequirementExample() throws {
        let old = Money(amount: Decimal(string: "1.69")!)
        let new = Money(amount: Decimal(string: "1.39")!)
        let change = try XCTUnwrap(new.relativeChange(from: old))
        XCTAssertEqual(DecimalParsing.round(change, scale: 3), Decimal(string: "-0.178"))
    }

    func testRelativeChangeFromZeroIsUndefined() {
        let change = Money(amount: 1).relativeChange(from: Money(amount: 0))
        XCTAssertNil(change)
    }

    func testParsingApiStrings() {
        XCTAssertEqual(Money(string: "1.49")?.amount, Decimal(string: "1.49"))
        XCTAssertNil(Money(string: "n/a"))
    }
}
