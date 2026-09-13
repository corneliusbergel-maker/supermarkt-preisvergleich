import Foundation

/// Entscheidet, ob ein Angebot einer Kette zu einem Produkt aus Open Food Facts
/// passt.
///
/// Angebote tragen keinen Barcode, nur Marke, Artikelnamen und Packungsangabe.
/// Die Zuordnung ist deshalb streng – im Zweifel passt ein Angebot **nicht**.
/// Ein falsch zugeordneter Preis wäre schlimmer als keiner.
///
/// Es müssen alle vier Punkte zutreffen:
/// 1. **Marke:** Das Angebot nennt die Marke des Produkts.
/// 2. **Name:** Jedes Namenswort des Produkts steht im Angebot – oder die Kette
///    schreibt „versch. Sorten“, und jedes Namenswort des Angebots steht im
///    Produktnamen („Ristorante Pizza, versch. Sorten“ deckt „Ristorante Pizza
///    Salame“ ab).
/// 3. **Sorte:** Kein Sortenwort („Zero“, „laktosefrei“, „Bio“) widerspricht.
/// 4. **Menge:** Die Produktmenge liegt in der Packungsangabe des Angebots.
public enum OfferMatcher {

    public enum Result: Hashable, Sendable {
        /// Passt. `viaVariety` heißt: nur über „versch. Sorten“ zugeordnet.
        case matches(viaVariety: Bool)
        case noMatch(reason: String)

        public var isMatch: Bool {
            if case .matches = self { return true }
            return false
        }
    }

    /// Wörter, die in Markennamen nur Zierde sind („Original Wagner“). Kaufland
    /// schreibt die Marke auch mal „ORIGNAL WAGNER“ – ohne diese Liste fiele
    /// das Angebot heraus.
    private static let decorativeBrandWords: Set<String> = ["original", "orignal", "classic"]

    public static func match(_ product: Product, _ offer: RetailerOffer) -> Result {

        // 1. Marke. Angebote ohne Artikelzeile sind Eigen- oder Frischware
        // („Südafrik. Mandarinen“) – dort gibt es nichts Sicheres zuzuordnen.
        guard let articleName = offer.subtitle, !articleName.isEmpty else {
            return .noMatch(reason: "Angebot ohne Marke")
        }
        let brandAlternatives = (product.brand ?? "")
            .split(separator: ",")
            .map { ProductTextNormalizer.brandTokens(String($0)).subtracting(decorativeBrandWords) }
            .filter { !$0.isEmpty }
        guard !brandAlternatives.isEmpty else {
            return .noMatch(reason: "Produkt ohne Marke")
        }
        let offerBrand = ProductTextNormalizer.brandTokens(offer.title)
        guard brandAlternatives.contains(where: { $0.isSubset(of: offerBrand) }) else {
            return .noMatch(reason: "Andere Marke")
        }

        // 2. Name – auf beiden Seiten mit derselben Markenwortliste bereinigt.
        let brandWords = brandAlternatives.reduce(offerBrand) { $0.union($1) }
        let productName = ProductTextNormalizer.coreTokens(name: product.name, brandTokens: brandWords)
        let offerName = ProductTextNormalizer.coreTokens(name: articleName, brandTokens: brandWords)
        let offerWords = ProductTextNormalizer.coreTokens(
            name: [articleName, offer.details].compactMap { $0 }.joined(separator: " "),
            brandTokens: brandWords
        )
        guard !productName.isEmpty, !offerName.isEmpty else {
            return .noMatch(reason: "Name zu unbestimmt")
        }

        let isVariety = offersVarieties(offer)
        let nameCovered = productName.isSubset(of: offerWords)
        let varietyCovered = isVariety && offerName.isSubset(of: productName)
        guard nameCovered || varietyCovered else {
            return .noMatch(reason: "Anderer Artikel")
        }

        // 3. Sorte. Ein Sortenwort im Angebot, das dem Produkt fehlt, trennt –
        // „H-Milch laktosefrei“ ist keine gewöhnliche Milch.
        let variantWords = ProductTextNormalizer.distinguishingVariantWords
        guard offerName.intersection(variantWords).isSubset(of: productName) else {
            return .noMatch(reason: "Andere Sorte")
        }

        // 4. Menge.
        guard let quantity = product.quantity else {
            return .noMatch(reason: "Produktmenge unbekannt")
        }
        guard let range = packageRange(in: [offer.unit, articleName].compactMap { $0 }) else {
            return .noMatch(reason: "Packungsangabe des Angebots unbekannt")
        }
        guard quantity.dimension == range.dimension,
              quantity.totalInBaseUnit >= range.lower,
              quantity.totalInBaseUnit <= range.upper else {
            return .noMatch(reason: "Andere Packungsgröße")
        }

        return .matches(viaVariety: !nameCovered)
    }

    // MARK: - Hilfen

    /// Schreibt die Kette „versch. Sorten“ oder „versch. Ausformungen“?
    static func offersVarieties(_ offer: RetailerOffer) -> Bool {
        let text = [offer.subtitle, offer.details, offer.unit].compactMap { $0 }.joined(separator: " ")
        let words = Set(ProductTextNormalizer.normalize(text).split(separator: " ").map(String.init))
        return words.contains("versch") || words.contains("verschiedene")
    }

    /// Gesamtmenge einer Packungsangabe als Spanne in der Basiseinheit.
    struct PackageRange: Hashable {
        let dimension: UnitDimension
        let lower: Decimal
        let upper: Decimal
    }

    /// Liest die erste Mengenangabe aus den Texten. Der Grundpreis
    /// („1 kg = 2,66 €“) wird bewusst nicht übergeben – er ist keine Packung.
    static func packageRange(in texts: [String]) -> PackageRange? {
        // „je 320 - 410-g-Packg.“, „0,75-L-Flasche“, „je 6 x 1,5-l-Fl.“
        guard let pattern = try? NSRegularExpression(
            pattern: "(?:(\\d+)\\s*x\\s*)?(\\d+(?:[.,]\\d+)?)(?:\\s*-\\s*(\\d+(?:[.,]\\d+)?))?\\s*-?\\s*(kg|g|ml|cl|l)(?![a-zäöüß])"
        ) else { return nil }

        for raw in texts {
            let text = raw.lowercased().replacingOccurrences(of: "\u{00A0}", with: " ")
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = pattern.firstMatch(in: text, range: range) else { continue }

            func group(_ index: Int) -> String? {
                guard let groupRange = Range(match.range(at: index), in: text) else { return nil }
                return String(text[groupRange])
            }

            guard let unitText = group(4),
                  let unit = MeasurementUnit.parse(unitText),
                  let lowText = group(2),
                  let low = DecimalParsing.decimal(from: lowText), low > 0 else { continue }

            let high = group(3).flatMap { DecimalParsing.decimal(from: $0) } ?? low
            guard high >= low else { continue }
            let packs = Decimal(group(1).flatMap { Int($0) } ?? 1)

            return PackageRange(dimension: unit.dimension,
                                lower: low * unit.factorToBase * packs,
                                upper: high * unit.factorToBase * packs)
        }
        return nil
    }
}
