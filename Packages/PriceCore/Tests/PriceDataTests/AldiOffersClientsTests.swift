import XCTest
import PriceCore
@testable import PriceData

// MARK: - ALDI Nord

/// Aufbau wie auf aldi-nord.de/angebote.html (abgerufen 2026-09-12): Die
/// Angebote liegen als JSON-Text in `props.pageProps.apiData`. Das
/// Rinderhackfleisch ist ein gekürzter echter Eintrag; die Fassbrause trägt die
/// echten Preisangaben, Kennung und Randfälle sind als TEST markiert.
private let aldiNordFixture = #"""
<html><body><script id="__NEXT_DATA__" type="application/json">{"props":{"pageProps":{"apiData":"[[\"OFFER_GET\",{\"req\":{\"locale\":\"de\",\"week\":\"current\"},\"res\":{\"algoliaDataMap\":{\"TEST.FASSBRAUSE\":{\"isAvailable\":true,\"isRecall\":false,\"name\":\"Fassbrause\",\"depositValue\":0.25,\"currentPrice\":{\"priceValue\":0.79,\"strikePrice\":{\"strikePriceValue\":0.99,\"strikePriceLabel\":\"UVP\"},\"basePrice\":[{\"basePriceValue\":1.58,\"basePriceScale\":\"Liter\"}],\"priceTagLabels\":{\"promoText1\":\"-20 %\"},\"validFrom\":1788991200,\"validUntil\":1789250399},\"promotionPrices\":[{\"validFromLocalDate\":\"2026-09-10\",\"validUntilLocalDate\":\"2026-09-12\",\"priceValue\":0.79}],\"objectID\":\"TEST.FASSBRAUSE\"},\"175\":{\"isAvailable\":true,\"brandName\":\"MEINE METZGEREI\",\"isRecall\":false,\"currentPrice\":{\"priceValue\":9.49,\"basePrice\":[{\"basePriceValue\":9.49,\"basePriceScale\":\"kg\"}],\"validFrom\":1788732000,\"validUntil\":1789250399},\"shortDescription\":\"Frisch; vielseitig verwendbar\",\"productSlug\":\"rinderhackfleisch-xxl-175\",\"depositValue\":0,\"promotionPrices\":[{\"validFrom\":1788732000,\"validUntil\":1789250399,\"priceValue\":9.49,\"validFromLocalDate\":\"2026-09-07\",\"validUntilLocalDate\":\"2026-09-12\"}],\"salesUnit\":\"1-kg-Packung\",\"name\":\"Rinderhackfleisch XXL\",\"objectID\":\"175\"},\"TEST.RUECKRUF\":{\"isAvailable\":true,\"isRecall\":true,\"name\":\"Rückruf\",\"currentPrice\":{\"priceValue\":1.0},\"promotionPrices\":[{\"validFromLocalDate\":\"2026-09-07\",\"validUntilLocalDate\":\"2026-09-12\"}]},\"TEST.NICHT-VERFUEGBAR\":{\"isAvailable\":false,\"name\":\"Ausverkauft\",\"currentPrice\":{\"priceValue\":1.0},\"promotionPrices\":[{\"validFromLocalDate\":\"2026-09-07\",\"validUntilLocalDate\":\"2026-09-12\"}]}},\"categories\":[{\"title\":\"Aktion Mo. 7.9.\",\"startDate\":\"2026-09-07\",\"endDate\":\"2026-09-12\",\"content\":[{\"title\":\"Frische-Aktion\",\"productIds\":[\"175\"]}]}]}}],[\"PAGE_MGNL_GET\",{\"req\":{},\"res\":{}}]]"}}}</script></body></html>
"""#

final class AldiNordOffersClientTests: XCTestCase {

    private let source = URL(string: "https://www.aldi-nord.de/angebote.html")!

    private func parsed() throws -> [RetailerOffer] {
        try AldiNordOfferParser.parse(html: aldiNordFixture, sourceURL: source)
    }

    /// Aktionsblöcke zuerst, Rückrufe und nicht verfügbare Artikel nie.
    func testOrderFollowsThePageAndSkipsRecalls() throws {
        XCTAssertEqual(try parsed().map(\.id),
                       ["aldi-nord:175@2026-09-07", "aldi-nord:TEST.FASSBRAUSE@2026-09-10"])
    }

    func testPriceBasePriceAndValidity() throws {
        let mince = try XCTUnwrap(parsed().first)
        XCTAssertEqual(mince.retailerName, "ALDI Nord")
        XCTAssertEqual(mince.title, "MEINE METZGEREI")
        XCTAssertEqual(mince.displayName, "Rinderhackfleisch XXL")
        XCTAssertEqual(mince.price?.amount, Decimal(string: "9.49"))
        XCTAssertEqual(mince.unit, "1-kg-Packung")
        XCTAssertEqual(mince.basePriceText, "1\u{00A0}kg\u{00A0}=\u{00A0}9,49\u{00A0}€")
        XCTAssertEqual(mince.details, "Frisch; vielseitig verwendbar")
        XCTAssertEqual(mince.validFrom, RetailerOffer.day(from: "2026-09-07"))
        XCTAssertEqual(mince.validTo, RetailerOffer.day(from: "2026-09-12"))
        XCTAssertNil(mince.deposit)
        XCTAssertNil(mince.regularPrice)
    }

    func testStrikePriceDepositAndLitre() throws {
        let drink = try XCTUnwrap(parsed().last)
        XCTAssertEqual(drink.price?.amount, Decimal(string: "0.79"))
        XCTAssertEqual(drink.regularPrice?.amount, Decimal(string: "0.99"))
        XCTAssertEqual(drink.regularPriceLabel, "UVP")
        XCTAssertEqual(drink.discountPercent, 20)
        XCTAssertEqual(drink.deposit?.amount, Decimal(string: "0.25"))
        XCTAssertEqual(drink.basePriceText, "1\u{00A0}l\u{00A0}=\u{00A0}1,58\u{00A0}€")
        XCTAssertEqual(drink.validFrom, RetailerOffer.day(from: "2026-09-10"))
    }

    func testPageWithoutDataThrows() {
        XCTAssertThrowsError(try AldiNordOfferParser.parse(html: "<html></html>", sourceURL: source))
    }

    /// Laufende Woche und Vorschau; was in beiden gleich steht, erscheint einmal.
    func testClientLoadsCurrentWeekAndPreview() async throws {
        let stub = StubTransport([
            .success(HTTPResponse(status: 200, body: Data(aldiNordFixture.utf8))),
            .success(HTTPResponse(status: 200, body: Data(aldiNordFixture.utf8)))
        ])
        let offers = try await AldiNordOffersClient(transport: stub).offers()
        XCTAssertEqual(offers.count, 2)
        XCTAssertEqual(stub.log.count, 2)
    }

    /// Fehlt die Vorschau, bleibt die laufende Woche stehen.
    func testMissingPreviewKeepsCurrentWeek() async throws {
        let stub = StubTransport([
            .success(HTTPResponse(status: 200, body: Data(aldiNordFixture.utf8))),
            .success(.status(404))
        ])
        let offers = try await AldiNordOffersClient(transport: stub).offers()
        XCTAssertEqual(offers.count, 2)
    }
}

// MARK: - ALDI SÜD

/// Übersicht mit Links auf Aktionstage, wie auf aldi-sued.de/angebote.
private let aldiSuedLanding = #"""
<html><body>
<a href="/angebote/2026-09-11">Ab Fr. 11.09.</a>
<a href="/angebote/2026-09-11?theme=Frischekracher">Frischekracher</a>
<a href="/angebote/2026-09-14">Ab Mo. 14.09.</a>
<a href="/angebote/2026-08-01">Alt</a>
</body></html>
"""#

/// Tagesseite im Nuxt-Format (`__NUXT_DATA__`): eine flache Liste, in der
/// Objekte auf Positionen verweisen. Hähnchenschenkel-Steaks und Schnitzel
/// tragen echte Werte von aldi-sued.de; die Kennung des Schnitzels ist als
/// TEST markiert.
private let aldiSuedDay = #"""
<html><body><script type="application/json" data-nuxt-data="nuxt-app" data-ssr="true" id="__NUXT_DATA__">[["ShallowReactive",1],{"data":2},{"products":3,"pagination":4},[5,20],{"offset":6,"limit":7,"totalCount":8},{"sku":9,"name":10,"brandName":11,"sellingSize":12,"onSaleDate":13,"price":14},0,30,2,"000000000317945001","Hähnchenschenkel-Steaks 500 g, BBQ","BBQ","0,5 kg","2026-09-11",{"amount":15,"amountRelevant":15,"amountRelevantDisplay":16,"comparisonDisplay":17,"wasPriceDisplay":18,"savingsDisplay":19,"currencyCode":27,"bottleDeposit":6},329,"3,29 €","6,58 €/1 kg","3,99 €","17 %",["Reactive",21],{"sku":22,"name":23,"brandName":24,"sellingSize":25,"onSaleDate":13,"price":26},"TEST.SCHNITZEL","Riesen Wiesn-Schnitzel 500 g","WIESN  SCHMANKERL","0,5 kg",{"amount":28,"amountRelevant":28,"amountRelevantDisplay":29,"comparisonDisplay":30,"wasPriceDisplay":31,"savingsDisplay":31,"currencyCode":27,"bottleDeposit":6},"EUR",399,"3,99 €","7,98 €/1 kg",null]</script></body></html>
"""#

final class AldiSuedOffersClientTests: XCTestCase {

    private let dayURL = URL(string: "https://www.aldi-sued.de/angebote/2026-09-11")!

    func testDayLinksWithoutThemeFilters() {
        XCTAssertEqual(AldiSuedOfferParser.dayPaths(inLanding: aldiSuedLanding),
                       ["/angebote/2026-08-01", "/angebote/2026-09-11", "/angebote/2026-09-14"])
    }

    func testProductsAreResolvedFromThePayload() throws {
        let day = try XCTUnwrap(RetailerOffer.day(from: "2026-09-11"))
        let page = try AldiSuedOfferParser.parseDay(html: aldiSuedDay, day: day, sourceURL: dayURL)

        XCTAssertEqual(page.totalCount, 2)
        XCTAssertEqual(page.pageSize, 30)
        XCTAssertEqual(page.offers.map(\.id), ["aldi-sued:000000000317945001", "aldi-sued:TEST.SCHNITZEL"])

        let steaks = page.offers[0]
        XCTAssertEqual(steaks.retailerName, "ALDI SÜD")
        XCTAssertEqual(steaks.price?.amount, Decimal(string: "3.29"))
        XCTAssertEqual(steaks.regularPrice?.amount, Decimal(string: "3.99"))
        XCTAssertEqual(steaks.discountPercent, 17)
        XCTAssertEqual(steaks.unit, "0,5 kg")
        XCTAssertEqual(steaks.basePriceText, "1\u{00A0}kg\u{00A0}=\u{00A0}6,58\u{00A0}€")
        XCTAssertEqual(steaks.validFrom, day)
        XCTAssertNil(steaks.validTo, "ALDI SÜD nennt kein Enddatum – es wird keins erfunden")

        let schnitzel = page.offers[1]
        XCTAssertEqual(schnitzel.brandLine, "WIESN SCHMANKERL", "Doppelte Leerzeichen der Quelle fallen weg")
        XCTAssertNil(schnitzel.regularPrice)
        XCTAssertNil(schnitzel.discountPercent)
        XCTAssertNil(schnitzel.deposit)
    }

    func testPageWithoutPayloadThrows() {
        let day = RetailerOffer.day(from: "2026-09-11")!
        XCTAssertThrowsError(try AldiSuedOfferParser.parseDay(html: "<html></html>", day: day, sourceURL: dayURL))
    }

    /// Nur Aktionstage im Fenster werden geladen; der Tag vom August nicht.
    func testClientLoadsOnlyNearbyDays() async throws {
        let stub = StubTransport([
            .success(HTTPResponse(status: 200, body: Data(aldiSuedLanding.utf8))),
            .success(HTTPResponse(status: 200, body: Data(aldiSuedDay.utf8))),
            .success(HTTPResponse(status: 200, body: Data(aldiSuedDay.utf8)))
        ])
        let now = try XCTUnwrap(RetailerOffer.day(from: "2026-09-12"))
        let offers = try await AldiSuedOffersClient(transport: stub).offers(now: now)

        XCTAssertEqual(stub.log.count, 3, "Übersicht plus zwei Aktionstage")
        XCTAssertEqual(offers.count, 2, "Dieselben Artikel an zwei Tagen erscheinen einmal")
    }

    func testBooleanIsNoAmount() {
        XCTAssertNil(OfferFormatting.amount(number: NSNumber(value: true)))
        XCTAssertEqual(OfferFormatting.amount("5,29 €"), Decimal(string: "5.29"))
        XCTAssertEqual(OfferFormatting.percent("-20 %"), 20)
        XCTAssertNil(OfferFormatting.percent("2 für 1"))
    }
}
