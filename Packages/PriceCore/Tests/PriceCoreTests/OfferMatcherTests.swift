import XCTest
@testable import PriceCore

private func quantity(_ amount: String, _ unit: MeasurementUnit, packs: Int = 1) -> Quantity {
    Quantity(packCount: packs, unitAmount: Decimal(string: amount)!, unit: unit)!
}

private func product(_ brand: String?, _ name: String, _ quantity: Quantity?) -> Product {
    Product(barcode: "4000000000000", name: name, brand: brand, quantity: quantity)
}

/// Angebote wie am 2026-09-13 auf kaufland.de und aldi-nord.de veröffentlicht.
private func offer(_ title: String, _ subtitle: String?, details: String? = nil, unit: String?) -> RetailerOffer {
    RetailerOffer(id: "\(title)|\(subtitle ?? "")|\(unit ?? "")",
                  retailerName: "Kaufland",
                  title: title,
                  subtitle: subtitle,
                  details: details,
                  price: Money(amount: Decimal(string: "1.79")!),
                  unit: unit,
                  validFrom: RetailerOffer.day(from: "2026-09-10")!,
                  validTo: RetailerOffer.day(from: "2026-09-16"),
                  sourceURL: URL(string: "https://filiale.kaufland.de/angebote/uebersicht.html")!)
}

final class OfferMatcherTests: XCTestCase {

    // MARK: - Passt

    func testSameBrandNameAndSizeMatches() {
        let result = OfferMatcher.match(
            product("Barilla", "Integrale Vollkornpasta", quantity("500", .gram)),
            offer("BARILLA", "Integrale Vollkornpasta", details: "aus 100 % Vollkorn-Hartweizengrieß",
                  unit: "je 500-g-Packg.")
        )
        XCTAssertEqual(result, .matches(viaVariety: false))
    }

    /// „versch. Sorten“ und eine Größenspanne decken die einzelne Sorte ab.
    func testVarietyOfferCoversASingleVariety() {
        let result = OfferMatcher.match(
            product("Dr. Oetker", "Ristorante Pizza Salame", quantity("320", .gram)),
            offer("DR. OETKER", "Ristorante Pizza", details: "versch. Sorten", unit: "je 320 - 410-g-Packg.")
        )
        XCTAssertEqual(result, .matches(viaVariety: true))
    }

    func testDecorativeBrandWordsAndTyposDoNotBlock() {
        let result = OfferMatcher.match(
            product("Original Wagner", "Rustipani Ofenbrot", quantity("170", .gram)),
            offer("ORIGNAL WAGNER", "Rustipani Ofenbrot oder Air-Fryer-Snack", details: "versch. Sorten",
                  unit: "je 170 - 195-g-Packg.")
        )
        XCTAssertTrue(result.isMatch)
    }

    func testBottleSizesAreRead() {
        let result = OfferMatcher.match(
            product("Gerolsteiner", "Limo", quantity("0.75", .liter)),
            offer("GEROLSTEINER", "Limo", unit: "0,75-L-Flasche")
        )
        XCTAssertTrue(result.isMatch)
    }

    // MARK: - Passt nicht

    func testOtherArticleOfTheSameBrandDoesNotMatch() {
        let result = OfferMatcher.match(
            product("Original Wagner", "Big City Cheese", quantity("415", .gram)),
            offer("ORIGINAL WAGNER", "Piccolinis", details: "versch. Sorten", unit: "je 9 St. = 270-g-Packg.")
        )
        XCTAssertFalse(result.isMatch)
    }

    func testOtherPackSizeDoesNotMatch() {
        let result = OfferMatcher.match(
            product("Kerrygold", "Extra", quantity("250", .gram)),
            offer("KERRYGOLD", "Extra XXL", unit: "400-g-Packung")
        )
        XCTAssertFalse(result.isMatch)
    }

    func testVariantWordInTheOfferSeparates() {
        let result = OfferMatcher.match(
            product("Weihenstephan", "H-Milch", quantity("1", .liter)),
            offer("WEIHENSTEPHAN", "H-Milch laktosefrei", unit: "je 1-l-Packg.")
        )
        XCTAssertFalse(result.isMatch)
    }

    func testVariantWordOfTheProductNeedsTheOffer() {
        let result = OfferMatcher.match(
            product("Coca-Cola", "Coca-Cola Zero Cola", quantity("1", .liter)),
            offer("COCA-COLA", "Cola", unit: "je 1-l-Fl.")
        )
        XCTAssertFalse(result.isMatch)
    }

    func testOtherBrandDoesNotMatch() {
        let result = OfferMatcher.match(
            product("Milka", "Alpenmilch Schokolade", quantity("100", .gram)),
            offer("RITTER SPORT", "Alpenmilch Schokolade", unit: "je 100-g-Tafel")
        )
        XCTAssertFalse(result.isMatch)
    }

    func testUnbrandedOfferNeverMatches() {
        let result = OfferMatcher.match(
            product("Kaufland", "Mandarinen", quantity("750", .gram)),
            offer("Südafrik. Mandarinen", nil, unit: "je 750-g-Netz")
        )
        XCTAssertFalse(result.isMatch)
    }

    func testUnknownPackageDoesNotMatch() {
        let result = OfferMatcher.match(
            product("Schöller", "Eis-Box", quantity("1", .liter)),
            offer("SCHÖLLER", "Eis-Box", unit: "Packung")
        )
        XCTAssertFalse(result.isMatch)
    }

    func testProductWithoutQuantityDoesNotMatch() {
        let result = OfferMatcher.match(
            product("Barilla", "Pesto", nil),
            offer("BARILLA", "Pesto", details: "versch. Sorten", unit: "je 190 - 200-g-Glas")
        )
        XCTAssertFalse(result.isMatch)
    }

    // MARK: - Packungsangaben

    func testPackageRangesAreReadInBaseUnits() {
        let range = OfferMatcher.packageRange(in: ["je 3 - 4 St. = 270 - 440-ml-Packg."])
        XCTAssertEqual(range?.dimension, .volume)
        XCTAssertEqual(range?.lower, Decimal(string: "0.27"))
        XCTAssertEqual(range?.upper, Decimal(string: "0.44"))
    }

    func testMultipacksMultiply() {
        let range = OfferMatcher.packageRange(in: ["je 6 x 1,5-l-Fl."])
        XCTAssertEqual(range?.lower, Decimal(9))
        XCTAssertEqual(range?.upper, Decimal(9))
    }

    func testTextWithoutAmountYieldsNothing() {
        XCTAssertNil(OfferMatcher.packageRange(in: ["Packung", "Stück"]))
    }
}
