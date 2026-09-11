import XCTest
@testable import PriceCore

final class RetailerRegistryTests: XCTestCase {

    /// Der Fall, der die Vereinheitlichung ueberhaupt noetig macht: In den
    /// echten Daten kommen beide Schreibweisen nebeneinander vor.
    func testSpellingVariantsOfTheSameChainShareAnIdentifier() {
        let variants = ["REWE", "Rewe", "rewe", " ReWe "]
        let identifiers = Set(variants.compactMap { RetailerRegistry.identifier(forBrand: $0) })
        XCTAssertEqual(identifiers, ["rewe"])
    }

    func testUmlautsAreNormalised() {
        XCTAssertEqual(RetailerRegistry.identifier(forBrand: "Aldi Süd"), "aldi-sued")
        XCTAssertEqual(RetailerRegistry.identifier(forBrand: "ALDI SUED"), "aldi-sued")
    }

    func testPunctuationBecomesASeparator() {
        XCTAssertEqual(RetailerRegistry.identifier(forBrand: "Netto Marken-Discount"),
                       "netto-marken-discount")
        XCTAssertEqual(RetailerRegistry.identifier(forBrand: "E.Leclerc"), "e-leclerc")
    }

    /// Genauso wichtig wie das Zusammenfuehren: das Nicht-Zusammenfuehren.
    /// "Netto" und "Netto Marken-Discount" sind zwei verschiedene Unternehmen.
    func testSimilarNamesAreNotMerged() {
        XCTAssertNotEqual(RetailerRegistry.identifier(forBrand: "Netto"),
                          RetailerRegistry.identifier(forBrand: "Netto Marken-Discount"))
        XCTAssertNotEqual(RetailerRegistry.identifier(forBrand: "Aldi Süd"),
                          RetailerRegistry.identifier(forBrand: "Aldi Nord"))
    }

    func testEmptyOrMeaninglessNamesYieldNothing() {
        XCTAssertNil(RetailerRegistry.identifier(forBrand: nil))
        XCTAssertNil(RetailerRegistry.identifier(forBrand: ""))
        XCTAssertNil(RetailerRegistry.identifier(forBrand: "   "))
        XCTAssertNil(RetailerRegistry.identifier(forBrand: "!!!"))
    }

    func testDisplayNameKeepsTheOriginalSpelling() {
        let retailer = RetailerRegistry.retailer(brandName: "REWE")
        XCTAssertEqual(retailer?.id, "rewe")
        XCTAssertEqual(retailer?.name, "REWE",
                       "In der Oberflaeche soll stehen, was in den Daten steht")
    }

    func testWikidataIdentifiersAreValidated() {
        XCTAssertEqual(RetailerRegistry.identifier(forWikidata: "Q879858"), "wd:Q879858")
        XCTAssertEqual(RetailerRegistry.identifier(forWikidata: " q879858 "), "wd:Q879858")
        XCTAssertNil(RetailerRegistry.identifier(forWikidata: "879858"))
        XCTAssertNil(RetailerRegistry.identifier(forWikidata: "QABC"))
        XCTAssertNil(RetailerRegistry.identifier(forWikidata: nil))
    }

    /// Die Filialsuche zeigt nur Ketten. Eine Wikidata-Kennung weist einen
    /// Laden als Filiale einer erfassten Marke aus, ein bloßer Name nicht.
    func testWikidataIdentifiersAreRecognised() throws {
        let fromWikidata = try XCTUnwrap(RetailerRegistry.identifier(forWikidata: "Q879858"))
        XCTAssertTrue(RetailerRegistry.isWikidataIdentifier(fromWikidata))

        let fromName = try XCTUnwrap(RetailerRegistry.identifier(forBrand: "Lido Multishop"))
        XCTAssertFalse(RetailerRegistry.isWikidataIdentifier(fromName))
    }

    /// Der Haendlerfilter der App arbeitet mit diesen Kennungen -- wenn sie
    /// nicht stabil sind, verschluckt er Treffer.
    func testFilteringByIdentifierCatchesBothSpellings() {
        let allowed: Set<String> = ["rewe", "kaufland"]
        let brandsFromData = ["Rewe", "REWE", "Kaufland", "Lidl"]

        let kept = brandsFromData.filter { brand in
            guard let id = RetailerRegistry.identifier(forBrand: brand) else { return false }
            return allowed.contains(id)
        }
        XCTAssertEqual(kept, ["Rewe", "REWE", "Kaufland"])
    }
}
