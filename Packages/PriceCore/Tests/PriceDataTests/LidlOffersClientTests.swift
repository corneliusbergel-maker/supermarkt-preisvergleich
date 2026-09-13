import XCTest
import PriceCore
@testable import PriceData

/// Auszug aus lidl.de/c/online-prospekte (abgerufen 2026-09-13): Verweise auf
/// zwei Aktionsprospekte, einer davon doppelt, und einen anderen Prospekt.
private let pageFixture = #"""
<html><body>
<a href="https://www.lidl.de/l/prospekte/aktionsprospekt-14-09-2026-19-09-2026-aaacd7/ar/0?_ab=1&amp;lf=HHZ">KW 38</a>
<a href="https://www.lidl.de/l/prospekte/aktionsprospekt-21-09-2026-26-09-2026-a801ff/ar/0?_ab=1&amp;lf=HHZ">KW 39</a>
<a href="https://www.lidl.de/l/prospekte/aktionsprospekt-14-09-2026-19-09-2026-aaacd7/ar/0">KW 38</a>
<a href="https://www.lidl.de/l/prospekte/august-september-reise-highlights-12-8-2026-15-9-2026/ar/0?lf=RHF">Reisen</a>
</body></html>
"""#

/// Auszug aus endpoints.leaflets.schwarz/v4/flyer (abgerufen 2026-09-13),
/// gekürzt auf die gelesenen Felder. Ergänzt um einen Eintrag ohne Preis und
/// einen in fremder Währung.
private let flyerFixture = #"""
{"success":true,"flyer":{"name":"Aktionsprospekt","startDate":"2026-09-12","endDate":"2026-09-19","offerStartDate":"2026-09-14","offerEndDate":"2026-09-19","products":{
"100408587":{"productId":"100408587","title":"PARKSIDE® Winkelschleifer »PWS 125 I9«","brand":"PARKSIDE®","currencyText":"EUR","wonCategoryPrimary":"Bedürfniswelten/Baumarkt & Garten/Elektrowerkzeuge","canonicalUrl":"/p/parkside-winkelschleifer-pws-125-i9/p100408587","price":"19.99","description":"<p>Leistungsstark</p>"},
"100401111":{"productId":"100401111","title":"KILBEGGAN Berry Selection 32,5% Vol","brand":"KILBEGGAN","currencyText":"EUR","wonCategoryPrimary":"Bedürfniswelten/Wein, Bier und Spirituosen/Spirituosen","canonicalUrl":"/p/kilbeggan-berry-selection/p100401111","price":"11.99","description":"Kilbeggan Berry Selection 32,5% Vol., 0,7-l‑Flasche vereint irische Whiskey-Tradition"},
"100402222":{"productId":"100402222","title":"Buitenverwachting Sauvignon Blanc Constantia trocken, Weißwein 2025","currencyText":"EUR","wonCategoryPrimary":"Bedürfniswelten/Wein, Bier und Spirituosen/Wein","canonicalUrl":"/p/buitenverwachting/p100402222","price":"9.99","description":"mineralisch &amp; frisch S&uuml;dafrika, Constantia Sauvignon Blanc, trocken"},
"100403333":{"productId":"100403333","title":"Ohne Preis","currencyText":"EUR","price":""},
"100404444":{"productId":"100404444","title":"Fremdwährung","currencyText":"CHF","price":"5.00"}
}}}
"""#

final class LidlOffersClientTests: XCTestCase {

    private func parsed() throws -> [RetailerOffer] {
        try LidlOfferParser.parse(flyerJSON: Data(flyerFixture.utf8))
    }

    private func offer(_ id: String) throws -> RetailerOffer {
        try XCTUnwrap(parsed().first { $0.id == id })
    }

    func testFindsEachFlyerOnceAndOnlyActionFlyers() {
        XCTAssertEqual(LidlOfferParser.flyerIdentifiers(in: pageFixture), [
            "aktionsprospekt-14-09-2026-19-09-2026-aaacd7",
            "aktionsprospekt-21-09-2026-26-09-2026-a801ff"
        ])
    }

    /// Ohne Preis und in fremder Währung fällt heraus; Getränke stehen vorn.
    func testKeepsUsableProductsDrinksFirst() throws {
        XCTAssertEqual(try parsed().map(\.id), [
            "lidl:100402222@2026-09-14",
            "lidl:100401111@2026-09-14",
            "lidl:100408587@2026-09-14"
        ])
    }

    func testBrandIsSeparatedFromArticle() throws {
        let whiskey = try offer("lidl:100401111@2026-09-14")
        XCTAssertEqual(whiskey.retailerName, "Lidl")
        XCTAssertEqual(whiskey.title, "KILBEGGAN")
        XCTAssertEqual(whiskey.subtitle, "Berry Selection 32,5% Vol")
        XCTAssertEqual(whiskey.price?.amount, Decimal(string: "11.99"))
        XCTAssertEqual(whiskey.unit, "0,7-l-Flasche")
        XCTAssertEqual(whiskey.validFrom, RetailerOffer.day(from: "2026-09-14"))
        XCTAssertEqual(whiskey.validTo, RetailerOffer.day(from: "2026-09-19"))
        XCTAssertEqual(whiskey.sourceURL.absoluteString,
                       "https://www.lidl.de/p/kilbeggan-berry-selection/p100401111")
    }

    func testTrademarkSignsAndTagsAreRemoved() throws {
        let grinder = try offer("lidl:100408587@2026-09-14")
        XCTAssertEqual(grinder.title, "PARKSIDE")
        XCTAssertEqual(grinder.subtitle, "Winkelschleifer »PWS 125 I9«")
        XCTAssertEqual(grinder.details, "Leistungsstark")
    }

    func testEntitiesAreDecodedAndBrandlessTitlesStayWhole() throws {
        let wine = try offer("lidl:100402222@2026-09-14")
        XCTAssertEqual(wine.title, "Buitenverwachting Sauvignon Blanc Constantia trocken, Weißwein 2025")
        XCTAssertNil(wine.subtitle)
        XCTAssertEqual(wine.details, "mineralisch & frisch Südafrika, Constantia Sauvignon Blanc, trocken")
    }

    func testLongDescriptionsAreShortenedAtAWord() {
        let text = String(repeating: "Wort ", count: 60)
        let short = LidlOfferParser.shortened(text, limit: 20)
        XCTAssertTrue(short.hasSuffix(" …"))
        XCTAssertLessThanOrEqual(short.count, 22)
    }

    /// Übersicht und zwei Prospekte; fehlt einer, bleibt der andere stehen.
    func testClientLoadsPageAndKeepsWorkingFlyers() async throws {
        let stub = StubTransport([
            .success(HTTPResponse(status: 200, body: Data(pageFixture.utf8))),
            .success(HTTPResponse(status: 200, body: Data(flyerFixture.utf8))),
            .success(.status(404))
        ])
        let offers = try await LidlOffersClient(transport: stub).offers()
        XCTAssertEqual(offers.count, 3)
        XCTAssertEqual(stub.log.count, 3)
    }

    func testPageWithoutFlyersIsAnError() async {
        let stub = StubTransport([.success(HTTPResponse(status: 200, body: Data("<html></html>".utf8)))])
        do {
            _ = try await LidlOffersClient(transport: stub).offers()
            XCTFail("Ohne Prospekt darf keine leere Liste als Erfolg durchgehen")
        } catch {
            XCTAssertTrue(error is DataSourceError)
        }
    }
}
