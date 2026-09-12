import XCTest
@testable import PriceCore

final class RetailerOfferTests: XCTestCase {

    private func berlin(_ month: Int, _ day: Int, _ hour: Int, _ minute: Int) -> Date {
        RetailerOffer.calendar.date(from: DateComponents(year: 2026, month: month, day: day,
                                                         hour: hour, minute: minute))!
    }

    private func offer(from: String, to: String,
                       price: Money? = Money(amount: 1),
                       loyaltyPrice: Money? = nil) -> RetailerOffer {
        RetailerOffer(id: "test",
                      retailerName: "Kaufland",
                      title: "Test",
                      price: price,
                      loyaltyPrice: loyaltyPrice,
                      validFrom: RetailerOffer.day(from: from)!,
                      validTo: RetailerOffer.day(from: to)!,
                      sourceURL: URL(string: "https://filiale.kaufland.de/")!)
    }

    /// Prospekte nennen „bis Mittwoch“ – der Mittwoch zählt ganz mit.
    func testFirstAndLastDayCount() {
        let week = offer(from: "2026-09-10", to: "2026-09-16")
        XCTAssertTrue(week.isValid(on: berlin(9, 10, 0, 1)))
        XCTAssertTrue(week.isValid(on: berlin(9, 16, 23, 30)))
        XCTAssertFalse(week.isValid(on: berlin(9, 17, 0, 10)))
        XCTAssertFalse(week.isValid(on: berlin(9, 9, 23, 59)))
    }

    func testUpcomingOffersAreRecognised() {
        let nextWeek = offer(from: "2026-09-17", to: "2026-09-23")
        XCTAssertTrue(nextWeek.startsAfter(berlin(9, 12, 12, 0)))
        XCTAssertFalse(nextWeek.startsAfter(berlin(9, 17, 8, 0)))
    }

    func testInvalidDaysAreRejected() {
        XCTAssertNil(RetailerOffer.day(from: "2026-02-30"))
        XCTAssertNil(RetailerOffer.day(from: "12.09.2026"))
        XCTAssertNotNil(RetailerOffer.day(from: "2026-09-12"))
    }

    /// ALDI SÜD nennt nur „verfügbar seit“ – ohne Enddatum gilt das Angebot ab
    /// dem ersten Tag.
    func testOfferWithoutEndDate() {
        let openEnded = RetailerOffer(id: "offen",
                                      retailerName: "ALDI SÜD",
                                      title: "Test",
                                      price: Money(amount: 1),
                                      validFrom: RetailerOffer.day(from: "2026-09-11")!,
                                      validTo: nil,
                                      sourceURL: URL(string: "https://www.aldi-sued.de/")!)
        XCTAssertFalse(openEnded.isValid(on: berlin(9, 10, 23, 0)))
        XCTAssertTrue(openEnded.isValid(on: berlin(9, 11, 8, 0)))
        XCTAssertTrue(openEnded.isValid(on: berlin(9, 30, 8, 0)))
    }

    func testCardOnlyOffer() {
        let cardOnly = offer(from: "2026-09-10", to: "2026-09-16",
                             price: nil, loyaltyPrice: Money(amount: Decimal(string: "0.69")!))
        XCTAssertTrue(cardOnly.requiresLoyaltyCard)
        XCTAssertFalse(offer(from: "2026-09-10", to: "2026-09-16").requiresLoyaltyCard)
    }
}
