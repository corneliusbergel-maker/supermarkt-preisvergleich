import XCTest
@testable import PriceCore

private let changeNow = Date(timeIntervalSince1970: 1_770_000_000)

private func day(_ daysAgo: Int) -> Date {
    Calendar(identifier: .gregorian).date(byAdding: .day, value: -daysAgo, to: changeNow)!
}

private func euro(_ value: String) -> Money {
    Money(amount: Decimal(string: value)!)
}

private func observation(_ price: String, daysAgo: Int, currency: String = "EUR") -> PriceObservation {
    PriceObservation(id: "\(price)-\(daysAgo)",
                     productID: "ean:1",
                     price: Money(amount: Decimal(string: price)!, currency: currency),
                     observedOn: day(daysAgo),
                     source: "Test")
}

final class PriceChangeTests: XCTestCase {

    /// Aus Anforderung 25: 1,69 EUR auf 1,39 EUR sind -0,30 EUR und -17,8 %.
    func testRequirementExample() throws {
        let change = try XCTUnwrap(PriceChange(previous: euro("1.69"),
                                               previousDate: day(1),
                                               current: euro("1.39"),
                                               currentDate: day(0)))

        XCTAssertEqual(change.direction, .down)
        XCTAssertEqual(change.absolute.amount, Decimal(string: "0.30"))
        XCTAssertEqual(DecimalParsing.round(try XCTUnwrap(change.relative), scale: 3),
                       Decimal(string: "-0.178"))
        XCTAssertEqual(change.percentText(), "−17,8 %")
    }

    /// Ebenfalls aus Anforderung 25: steigender Preis.
    func testRisingPrice() throws {
        let change = try XCTUnwrap(PriceChange(previous: euro("1.60"),
                                               previousDate: day(2),
                                               current: euro("1.80"),
                                               currentDate: day(0)))
        XCTAssertEqual(change.direction, .up)
        XCTAssertEqual(change.absolute.amount, Decimal(string: "0.20"))
        XCTAssertEqual(change.percentText(), "+12,5 %")
    }

    func testAbsoluteDifferenceIsAlwaysPositive() throws {
        let down = try XCTUnwrap(PriceChange(previous: euro("2.00"), previousDate: day(1),
                                             current: euro("1.00"), currentDate: day(0)))
        let up = try XCTUnwrap(PriceChange(previous: euro("1.00"), previousDate: day(1),
                                           current: euro("2.00"), currentDate: day(0)))
        XCTAssertEqual(down.absolute.amount, Decimal(1))
        XCTAssertEqual(up.absolute.amount, Decimal(1))
    }

    func testUnchangedPriceIsNotWorthShowing() throws {
        let change = try XCTUnwrap(PriceChange(previous: euro("1.49"), previousDate: day(5),
                                               current: euro("1.49"), currentDate: day(0)))
        XCTAssertEqual(change.direction, .unchanged)
        XCTAssertFalse(change.isWorthShowing)
        XCTAssertNil(change.summary())
        XCTAssertNil(change.percentText())
    }

    /// Unter einem Cent ist die Aussage bedeutungslos.
    func testSubCentDifferenceIsNotShown() throws {
        let change = try XCTUnwrap(PriceChange(previous: euro("1.499"), previousDate: day(3),
                                               current: euro("1.495"), currentDate: day(0)))
        XCTAssertFalse(change.isWorthShowing)
    }

    func testDifferentCurrenciesCannotBeCompared() {
        let change = PriceChange(previous: Money(amount: 1, currency: "CHF"),
                                 previousDate: day(1),
                                 current: Money(amount: 1, currency: "EUR"),
                                 currentDate: day(0))
        XCTAssertNil(change)
    }

    /// Eine verdrehte Reihenfolge wuerde das Vorzeichen umkehren.
    func testReversedDatesAreRejected() {
        let change = PriceChange(previous: euro("1.00"), previousDate: day(0),
                                 current: euro("2.00"), currentDate: day(5))
        XCTAssertNil(change)
    }

    /// Der erwartete Betrag wird aus demselben Formatierer gebaut, nicht
    /// abgetippt.
    ///
    /// Grund: `NumberFormatter` setzt im Deutschen ein **schmales geschütztes**
    /// Leerzeichen zwischen Zahl und Währungszeichen, kein gewöhnliches. Ein
    /// fest eingetragener Erwartungstext prüft damit die Typografie des
    /// Systems statt der eigenen Logik -- und bricht, sobald Apple sie
    /// anpasst. Geprüft werden soll hier, dass Betrag, Richtungswort und
    /// Zeitangabe richtig zusammengesetzt werden.
    func testDayCountAndWording() throws {
        let fiftyCents = euro("0.50").formatted()

        let yesterday = try XCTUnwrap(PriceChange(previous: euro("2.00"), previousDate: day(1),
                                                  current: euro("1.50"), currentDate: day(0)))
        XCTAssertEqual(yesterday.dayCount, 1)
        XCTAssertEqual(yesterday.summary(), "\(fiftyCents) günstiger als gestern")

        let older = try XCTUnwrap(PriceChange(previous: euro("2.00"), previousDate: day(14),
                                              current: euro("2.50"), currentDate: day(0)))
        XCTAssertEqual(older.dayCount, 14)
        XCTAssertEqual(older.summary(), "\(fiftyCents) teurer als vor 14 Tagen")
    }

    func testWordingForSameDay() throws {
        let sameDay = try XCTUnwrap(PriceChange(previous: euro("2.00"), previousDate: day(0),
                                                current: euro("1.80"), currentDate: day(0)))
        XCTAssertEqual(sameDay.dayCount, 0)
        XCTAssertEqual(sameDay.summary()?.hasSuffix("günstiger als zuletzt"), true)
    }
}

final class PriceChangeFromObservationsTests: XCTestCase {

    func testNewestIsComparedWithTheLastDifferentPrice() throws {
        let series = [
            observation("1.69", daysAgo: 30),
            observation("1.59", daysAgo: 10),
            observation("1.39", daysAgo: 0)
        ]
        let change = try XCTUnwrap(PriceChange.fromObservations(series))

        XCTAssertEqual(change.current.amount, Decimal(string: "1.39"))
        XCTAssertEqual(change.previous.amount, Decimal(string: "1.59"))
        XCTAssertEqual(change.direction, .down)
    }

    /// Zwei gleiche Messungen hintereinander sind keine Veraenderung.
    /// Gesucht wird die juengste Beobachtung mit einem **anderen** Betrag.
    func testIdenticalRepeatsAreSkipped() throws {
        let series = [
            observation("1.69", daysAgo: 30),
            observation("1.39", daysAgo: 5),
            observation("1.39", daysAgo: 0)
        ]
        let change = try XCTUnwrap(PriceChange.fromObservations(series))
        XCTAssertEqual(change.previous.amount, Decimal(string: "1.69"))
        XCTAssertEqual(change.direction, .down)
    }

    func testSingleObservationHasNoHistory() {
        XCTAssertNil(PriceChange.fromObservations([observation("1.49", daysAgo: 0)]))
    }

    func testAllIdenticalPricesYieldNoChange() {
        let series = [
            observation("1.49", daysAgo: 20),
            observation("1.49", daysAgo: 10),
            observation("1.49", daysAgo: 0)
        ]
        XCTAssertNil(PriceChange.fromObservations(series),
                     "Ohne Unterschied gibt es nichts zu melden")
    }

    func testEmptySeriesYieldsNothing() {
        XCTAssertNil(PriceChange.fromObservations([]))
    }

    func testOtherCurrenciesAreIgnored() throws {
        let series = [
            observation("2.00", daysAgo: 20, currency: "CHF"),
            observation("1.69", daysAgo: 10),
            observation("1.39", daysAgo: 0)
        ]
        let change = try XCTUnwrap(PriceChange.fromObservations(series))
        XCTAssertEqual(change.previous.amount, Decimal(string: "1.69"),
                       "Der Franken-Preis darf nicht als Vergleich dienen")
    }
}
