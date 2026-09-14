import XCTest
import PriceCore
@testable import PriceData

/// Auszug aus den Verweisen der ALDI-SÜD-Startseite (abgerufen 2026-09-14):
/// Sortimentskategorien in beliebiger Reihenfolge, doppelt, dazu Wochenangebote
/// und Non-Food.
private let landingFixture = #"""
<nav>
<a href="/produkte/getraenke/k/1588161425467173">Getränke</a>
<a href="/produkte/wochenangebote/k/1588161426582123">Wochenangebote</a>
<a href="/produkte/markenprodukte/k/1588161425467261">Markenprodukte</a>
<a href="/produkte/garten/k/1588161426582150">Garten</a>
<a href="/produkte/getraenke/k/1588161425467173">Getränke</a>
<a href="/produkte/milchprodukte-eier/k/1588161425467093">Milchprodukte &amp; Eier</a>
</nav>
"""#

final class AldiSuedCatalogClientTests: XCTestCase {

    /// Markenprodukte zuerst, keine Wochenangebote, kein Non-Food, keine Dubletten.
    func testCategoriesFollowThePreferredOrder() {
        XCTAssertEqual(AldiSuedCatalogParser.categoryPaths(in: landingFixture), [
            "/produkte/markenprodukte/k/1588161425467261",
            "/produkte/getraenke/k/1588161425467173",
            "/produkte/milchprodukte-eier/k/1588161425467093"
        ])
    }

    func testLandingWithoutCategoriesIsAnError() async {
        let stub = StubTransport([.success(HTTPResponse(status: 200, body: Data("<html></html>".utf8)))])
        do {
            _ = try await AldiSuedCatalogClient(transport: stub).categoryPaths()
            XCTFail("Ohne Kategorien darf keine leere Liste als Erfolg durchgehen")
        } catch {
            XCTAssertTrue(error is DataSourceError)
        }
    }
}
