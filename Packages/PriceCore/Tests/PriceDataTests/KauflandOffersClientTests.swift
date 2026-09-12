import XCTest
import PriceCore
@testable import PriceData

/// Auszug aus der echten Kaufland-Angebotsseite (abgerufen 2026-09-12), gekürzt
/// auf die Felder, die der Parser liest. Ergänzt um einen kaputten Eintrag,
/// einen ohne Preis, einen aus dem Ausland und eine Dublette.
private let fixture = #"""
<html><body><div data-reload-on-store-change></div><script>window.SSR = window.SSR || {}; window.SSR['e1d34382'] = {"component":"OfferTemplate","props":{"pageTitle":"Aktuelle Angebote","offerData":{"cycles":[{"categories":[{"name":"02_Obst__Gemuese__Pflanzen","offers":[
{"offerId":"ART.734689_KAV.3634320","dateFrom":"2026-09-10","dateTo":"2026-09-16","title":"Span./ital. Nektarinen, Pfirsiche oder Plattpfirsiche, lose ","price":2.99,"discount":25,"unit":"je kg","detailDescription":"Sorte laut Auszeichnung, Kl. I","country":"DE","label":"reducedPrice","formattedOldPrice":"3.99","formattedPrice":"2.99"},
{"offerId":"ART.1183941_KAV.3634320","dateFrom":"2026-09-10","dateTo":"2026-09-16","title":"Südafrik. Mandarinen ","price":1.99,"discount":20,"basePrice":"(1 kg = 2.66)","unit":"je 750-g-Netz","country":"DE","formattedBasePrice":"(1 kg = 2.66)","formattedOldPrice":"2.49","formattedPrice":"1.99"},
{"offerId":"ART.334791_KAV.3634320","dateFrom":"2026-09-10","dateTo":"2026-09-16","title":"MONTORSI","subtitle":"Pancetta Coppata ","price":2.49,"discount":37,"basePrice":"(1 kg = 24.90)","unit":"je 100-g-Packg.","detailTitle":"*Mit Kaufland Card","loyaltyDiscount":44,"country":"DE","formattedBasePrice":"(1 kg = 24.90)","formattedOldPrice":"3.99","formattedPrice":"2.49","loyaltyFormattedPrice":"2.22*","loyaltyFormattedOldPrice":"3.99"},
{"offerId":"ART.379961_KAV.3634320","dateFrom":"2026-09-10","dateTo":"2026-09-16","title":"K-CLASSIC","subtitle":"High Protein Pudding ","price":0,"discount":0,"unit":"je 200-g-Becher","detailTitle":"*Mit Kaufland Card","loyaltyDiscount":22,"country":"DE","label":"none","loyaltyFormattedPrice":"0.69*","loyaltyFormattedOldPrice":"0.89"},
{"offerId":42,"title":["kaputt"]},
{"offerId":"TEST.OHNE-PREIS","dateFrom":"2026-09-10","dateTo":"2026-09-16","title":"Ohne Preis","price":0,"discount":0,"country":"DE"},
{"offerId":"TEST.AUSLAND","dateFrom":"2026-09-10","dateTo":"2026-09-16","title":"Auslandsangebot","price":1.0,"formattedPrice":"1.00","country":"AT"}
]},{"name":"Doppelt","offers":[
{"offerId":"ART.1183941_KAV.3634320","dateFrom":"2026-09-10","dateTo":"2026-09-16","title":"Südafrik. Mandarinen ","price":1.99,"formattedPrice":"1.99","country":"DE"}
]}]}]}}};</script></body></html>
"""#

final class KauflandOffersClientTests: XCTestCase {

    private let source = URL(string: "https://filiale.kaufland.de/angebote/uebersicht.html")!

    private func parsed() throws -> [RetailerOffer] {
        try KauflandOfferParser.parse(html: fixture, sourceURL: source)
    }

    private func offer(_ id: String) throws -> RetailerOffer {
        try XCTUnwrap(parsed().first { $0.id == id })
    }

    /// Kaputte, preislose und ausländische Einträge fallen heraus, Dubletten
    /// erscheinen einmal – der Rest der Liste bleibt stehen.
    func testKeepsOnlyUsableOffersOnce() throws {
        XCTAssertEqual(try parsed().map(\.id), [
            "ART.734689_KAV.3634320",
            "ART.1183941_KAV.3634320",
            "ART.334791_KAV.3634320",
            "ART.379961_KAV.3634320"
        ])
    }

    func testPricesAndDatesAreReadExactly() throws {
        let nectarines = try offer("ART.734689_KAV.3634320")
        XCTAssertEqual(nectarines.title, "Span./ital. Nektarinen, Pfirsiche oder Plattpfirsiche, lose")
        XCTAssertEqual(nectarines.retailerName, "Kaufland")
        XCTAssertEqual(nectarines.price?.amount, Decimal(string: "2.99"))
        XCTAssertEqual(nectarines.regularPrice?.amount, Decimal(string: "3.99"))
        XCTAssertEqual(nectarines.discountPercent, 25)
        XCTAssertEqual(nectarines.unit, "je kg")
        XCTAssertEqual(nectarines.details, "Sorte laut Auszeichnung, Kl. I")
        XCTAssertEqual(nectarines.validFrom, RetailerOffer.day(from: "2026-09-10"))
        XCTAssertEqual(nectarines.validTo, RetailerOffer.day(from: "2026-09-16"))
        XCTAssertNil(nectarines.loyaltyPrice)
    }

    func testBasePriceIsWrittenTheGermanWay() throws {
        XCTAssertEqual(try offer("ART.1183941_KAV.3634320").basePriceText, "1 kg = 2,66 €")
    }

    /// Der Kartenpreis darf nie als normaler Angebotspreis erscheinen.
    func testLoyaltyCardPriceStaysSeparate() throws {
        let pancetta = try offer("ART.334791_KAV.3634320")
        XCTAssertEqual(pancetta.price?.amount, Decimal(string: "2.49"))
        XCTAssertEqual(pancetta.loyaltyPrice?.amount, Decimal(string: "2.22"))
        XCTAssertEqual(pancetta.discountPercent, 37)
        XCTAssertEqual(pancetta.loyaltyDiscountPercent, 44)
        XCTAssertFalse(pancetta.requiresLoyaltyCard)
        XCTAssertEqual(pancetta.displayName, "Pancetta Coppata")
        XCTAssertEqual(pancetta.brandLine, "MONTORSI")
    }

    func testCardOnlyOfferHasNoPriceWithoutCard() throws {
        let pudding = try offer("ART.379961_KAV.3634320")
        XCTAssertNil(pudding.price)
        XCTAssertNil(pudding.discountPercent)
        XCTAssertEqual(pudding.loyaltyPrice?.amount, Decimal(string: "0.69"))
        XCTAssertEqual(pudding.regularPrice?.amount, Decimal(string: "0.89"))
        XCTAssertEqual(pudding.loyaltyDiscountPercent, 22)
        XCTAssertTrue(pudding.requiresLoyaltyCard)
    }

    /// Ändert Kaufland die Seite, soll das als Fehler auffallen – nicht als
    /// „keine Angebote diese Woche“.
    func testPageWithoutOfferDataThrows() {
        XCTAssertThrowsError(
            try KauflandOfferParser.parse(html: "<html><body>Wartungsarbeiten</body></html>",
                                          sourceURL: source)
        ) { error in
            guard case .decoding? = error as? DataSourceError else {
                return XCTFail("Erwartet: decoding, erhalten: \(error)")
            }
        }
    }

    func testClientParsesTheDownloadedPage() async throws {
        let stub = StubTransport([.success(HTTPResponse(status: 200, body: Data(fixture.utf8)))])
        let offers = try await KauflandOffersClient(transport: stub).offers()
        XCTAssertEqual(offers.count, 4)
        XCTAssertEqual(stub.log.count, 1)
    }
}
