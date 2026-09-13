import XCTest
@testable import PriceCore

private func line(_ text: String, _ height: Double) -> PriceTagText.Line {
    PriceTagText.Line(text: text, height: height)
}

final class PriceTagTextTests: XCTestCase {

    /// Typisches Regalschild: Marke, Artikel, Menge, Grundpreis, großer Preis.
    func testLargestPriceWinsAndBasePriceIsIgnored() {
        let lines = [
            line("REWE Beste Wahl", 0.05),
            line("Gouda jung", 0.05),
            line("400 g", 0.04),
            line("1 kg = 5,98 €", 0.03),
            line("2,39", 0.20)
        ]
        XCTAssertEqual(PriceTagText.bestPrice(in: lines), Decimal(string: "2.39"))
    }

    func testDepositIsNotThePrice() {
        let lines = [
            line("zzgl. 0,25 € Pfand", 0.05),
            line("0,79 €", 0.15)
        ]
        XCTAssertEqual(PriceTagText.bestPrice(in: lines), Decimal(string: "0.79"))
    }

    /// Hochgestellte Cents liest die Erkennung als „1 79“.
    func testSuperscriptCentsAreRead() {
        let lines = [
            line("Aktion", 0.05),
            line("1 79", 0.22)
        ]
        XCTAssertEqual(PriceTagText.bestPrice(in: lines), Decimal(string: "1.79"))
    }

    func testSeparatedPriceBeatsSplitDigits() {
        let lines = [
            line("12 50", 0.30),
            line("1,99", 0.10)
        ]
        XCTAssertEqual(PriceTagText.bestPrice(in: lines), Decimal(string: "1.99"))
    }

    func testTextWithoutPriceYieldsNothing() {
        XCTAssertNil(PriceTagText.bestPrice(in: [line("Gouda jung", 0.10)]))
    }

    /// Lange Ziffernfolgen sind eher Artikelnummern als Preise.
    func testLongNumbersAreNotPrices() {
        XCTAssertNil(PriceTagText.bestPrice(in: [line("1234,56", 0.30)]))
        XCTAssertNil(PriceTagText.bestPrice(in: [line("4001234567890", 0.30)]))
    }
}
