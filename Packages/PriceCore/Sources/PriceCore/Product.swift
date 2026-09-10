import Foundation

/// Ein Produkt, so wie es aus einer Datenquelle kommt.
///
/// Alle Felder ausser `name` sind optional, weil reale Datensaetze
/// unvollstaendig sind. Fehlende Felder bleiben `nil` -- sie werden nirgends
/// mit Platzhaltern aufgefuellt.
public struct Product: Hashable, Sendable, Identifiable {

    /// GTIN/EAN. Der einzige wirklich eindeutige Schluessel, den wir haben.
    public let barcode: String?

    /// Anzeigename aus der Quelle.
    public let name: String

    /// Markenangabe. Open Food Facts liefert hier oft mehrere durch Komma
    /// getrennte Werte, z. B. "COCA-COLA SERVICES SA/NV, Coca-Cola".
    public let brand: String?

    /// Geparste Menge. `nil`, wenn die Quelle keine verlaessliche Angabe hat --
    /// dann zeigt die App keinen Grundpreis.
    public let quantity: Quantity?

    public let imageURL: URL?

    /// Kategorie-Tags der Quelle, z. B. "en:colas".
    public let categories: [String]

    public init(barcode: String?,
                name: String,
                brand: String? = nil,
                quantity: Quantity? = nil,
                imageURL: URL? = nil,
                categories: [String] = []) {
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.imageURL = imageURL
        self.categories = categories
    }

    /// Stabile Identitaet. Ohne Barcode wird aus den normalisierten Merkmalen
    /// ein Schluessel gebildet -- nie aus einer Zufallszahl, damit derselbe
    /// Datensatz ueber App-Starts hinweg denselben Schluessel behaelt.
    public var id: String {
        if let barcode, !barcode.isEmpty { return "ean:\(barcode)" }
        let brandKey = ProductTextNormalizer.normalize(brand ?? "")
        let nameKey = ProductTextNormalizer.normalize(name)
        let quantityKey = quantity.map { "\($0.totalInBaseUnit)\($0.baseUnit.rawValue)" } ?? "?"
        return "attr:\(brandKey)|\(nameKey)|\(quantityKey)"
    }

    /// Hat dieses Produkt genug Daten fuer einen belastbaren Preisvergleich?
    public var isComparable: Bool {
        quantity != nil
    }
}

/// Textnormalisierung fuer Marken- und Produktnamen.
public enum ProductTextNormalizer {

    /// Rechtsformen und Vertriebszusaetze, die keine Produktinformation sind.
    private static let corporateSuffixes: Set<String> = [
        "gmbh", "ag", "kg", "co", "sa", "nv", "bv", "sarl", "srl", "spa",
        "ltd", "inc", "plc", "services", "deutschland", "germany", "gmbhcokg"
    ]

    /// Fuellwoerter ohne unterscheidende Bedeutung.
    private static let stopwords: Set<String> = [
        "der", "die", "das", "und", "mit", "ohne", "im", "in", "aus", "von",
        "the", "and", "with", "taste", "flavour", "flavor", "geschmack",
        "getraenk", "erfrischungsgetraenk", "produkt", "packung", "pack"
    ]

    /// Varianten-Woerter, deren **Abwesenheit** dasselbe bedeutet wie das
    /// Standardprodukt. "Coca-Cola Original" und "Coca Cola" sind dasselbe.
    private static let neutralVariantWords: Set<String> = [
        "original", "originaltaste", "classic", "klassisch", "regular", "standard"
    ]

    /// Varianten-Woerter, die Produkte zwingend voneinander trennen.
    /// "Zero" darf niemals mit "Original" zusammengefuehrt werden.
    public static let distinguishingVariantWords: Set<String> = [
        "zero", "light", "diet", "zuckerfrei", "ohnezucker", "sugarfree",
        "koffeinfrei", "entkoffeiniert", "caffeinefree", "decaf",
        "cherry", "kirsch", "vanille", "vanilla", "lemon", "zitrone", "lime",
        "orange", "peach", "pfirsich", "mango", "erdbeer", "strawberry",
        "bio", "organic", "demeter",
        "vegan", "vegetarisch",
        "laktosefrei", "lactosefree", "glutenfrei", "glutenfree",
        "vollmilch", "halbfett", "fettarm", "magermilch", "entrahmt",
        "vollkorn", "dinkel", "weizen", "roggen",
        "mild", "kraeftig", "intense", "extra", "fein", "grob",
        "dunkel", "hell", "weiss", "braun", "schwarz",
        "gesalzen", "ungesalzen", "gezuckert", "ungezuckert",
        "haltbar", "frisch", "tiefgekuehlt", "tk",
        "nachfuellpack", "nachfuell", "refill", "konzentrat", "sensitive"
    ]

    /// Vereinheitlicht Text: Kleinschreibung, Umlaute aufgeloest,
    /// Satzzeichen entfernt, Mehrfach-Leerzeichen zusammengezogen.
    public static func normalize(_ text: String) -> String {
        var result = text.lowercased()

        // Deutsche Sonderzeichen bewusst explizit, bevor Diakritika fallen.
        let replacements = ["ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss", "&": " und "]
        for (from, to) in replacements {
            result = result.replacingOccurrences(of: from, with: to)
        }

        result = result.folding(options: [.diacriticInsensitive],
                                locale: Locale(identifier: "de_DE"))

        // Alles, was kein Buchstabe oder keine Ziffer ist, wird zum Trenner.
        let allowed = CharacterSet.alphanumerics
        result = String(result.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })

        return result.split(separator: " ").joined(separator: " ")
    }

    /// Zerlegt einen Markennamen in vergleichbare Tokens.
    /// Aus "COCA-COLA SERVICES SA/NV, Coca-Cola" wird {"coca", "cola"}.
    public static func brandTokens(_ brand: String?) -> Set<String> {
        guard let brand else { return [] }
        let tokens = normalize(brand).split(separator: " ").map(String.init)
        return Set(tokens.filter { !corporateSuffixes.contains($0) && $0.count > 1 })
    }

    /// Zerlegt einen Produktnamen in die bedeutungstragenden Tokens.
    /// Marken-, Mengen-, Fuell- und Neutralwoerter fallen heraus.
    public static func coreTokens(name: String, brand: String?) -> Set<String> {
        let brandSet = brandTokens(brand)
        let tokens = normalize(name).split(separator: " ").map(String.init)
        return Set(tokens.filter { token in
            token.count > 1
            && !brandSet.contains(token)
            && !stopwords.contains(token)
            && !neutralVariantWords.contains(token)
            && !corporateSuffixes.contains(token)
            && MeasurementUnit.parse(token) == nil     // "l", "ml", "kg" ...
            && !token.allSatisfy(\.isNumber)           // reine Mengenzahlen
            && !isQuantityToken(token)                 // "5l", "500g", "1kg"
        })
    }

    /// Erkennt zusammengeschriebene Mengenangaben wie "500g" oder "5l".
    ///
    /// Die Normalisierung zerlegt "1,5L" in "1" und "5l" -- ohne diese Pruefung
    /// bliebe "5l" als vermeintlich bedeutungstragendes Wort stehen und koennte
    /// zwei identische Produkte faelschlich trennen.
    static func isQuantityToken(_ token: String) -> Bool {
        let digits = token.prefix(while: \.isNumber)
        guard !digits.isEmpty else { return false }
        let rest = String(token.dropFirst(digits.count))
        return !rest.isEmpty && MeasurementUnit.parse(rest) != nil
    }

    /// Die Teilmenge der Tokens, die Produkte zwingend trennt.
    public static func variantTokens(name: String, brand: String?) -> Set<String> {
        coreTokens(name: name, brand: brand).intersection(distinguishingVariantWords)
    }
}
