import Foundation
import PriceCore

/// Das Dauersortiment von ALDI SÜD mit Regalpreisen, direkt von aldi-sued.de.
///
/// Geprüft am 2026-09-14: `robots.txt` sperrt nur `/tools` und die Suche
/// (`?q=`) und erlaubt Seitenzahlen ausdrücklich. Die Kategorieseiten
/// (`/produkte/<kategorie>/k/<id>`) enthalten je 30 Produkte mit Marke, Name,
/// Verkaufsgröße und Preis; „Markenprodukte“ allein umfasst 548 Artikel.
///
/// Der Client lädt nur einzelne Seiten. Wie schnell und wie oft, entscheidet
/// `SortimentStore` in der App – bewusst langsam und höchstens täglich.
public struct AldiSuedCatalogClient: Sendable {

    public static let retailerName = AldiSuedOffersClient.retailerName
    public static let landingURL = URL(string: "https://www.aldi-sued.de/")!

    /// Lebensmittel und Alltagsbedarf, Markenprodukte zuerst – dort stehen die
    /// meisten Artikel, die es auch in Open Food Facts gibt. Themenseiten
    /// („XXL“, „Neuheiten“) und Non-Food fehlen absichtlich.
    public static let categorySlugs = [
        "markenprodukte", "getraenke", "suessigkeiten-salzige-snacks", "milchprodukte-eier",
        "kaese", "backwaren-aufstriche-cerealien", "tiefkuehlung", "wurst-aufschnitt",
        "fleisch-fisch", "konserven-fertiggerichte", "nudeln-reis-huelsenfruechte",
        "saucen-oele-gewuerze", "backzutaten-mehl-zucker", "vegetarisch-vegan",
        "alkoholische-getraenke", "drogerie-kosmetik", "haushaltsartikel", "babyartikel",
        "tierbedarf"
    ]

    public struct Page: Sendable {
        public let items: [RetailerOffer]
        public let hasMore: Bool
    }

    private let runner: RequestRunner

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.runner = RequestRunner(transport: transport, maxAttempts: 2, baseDelay: 3)
    }

    /// Kategorieadressen in der Reihenfolge von `categorySlugs`. Aus der
    /// Startseite gelesen, weil sich die Nummern hinter `/k/` ändern können.
    public func categoryPaths() async throws -> [String] {
        let html = try await OfferFormatting.html(at: Self.landingURL, runner: runner)
        let paths = AldiSuedCatalogParser.categoryPaths(in: html)
        guard !paths.isEmpty else {
            throw DataSourceError.decoding("ALDI SÜD: keine Sortimentskategorien gefunden")
        }
        return paths
    }

    /// Eine Seite einer Kategorie. `hasMore` sagt, ob es eine weitere gibt.
    public func page(path: String, number: Int, now: Date = Date()) async throws -> Page {
        guard let categoryURL = URL(string: "https://www.aldi-sued.de" + path),
              var components = URLComponents(url: categoryURL, resolvingAgainstBaseURL: false)
        else { throw DataSourceError.invalidResponse }

        if number > 1 {
            components.queryItems = [URLQueryItem(name: "page", value: String(number))]
        }
        guard let pageURL = components.url else { throw DataSourceError.invalidResponse }

        let html = try await OfferFormatting.html(at: pageURL, runner: runner)
        let parsed = try AldiSuedOfferParser.parseDay(
            html: html,
            day: RetailerOffer.calendar.startOfDay(for: now),
            sourceURL: categoryURL
        )

        var hasMore = false
        if let total = parsed.totalCount, let size = parsed.pageSize, size > 0 {
            hasMore = number * size < total
        }
        return Page(items: parsed.offers, hasMore: hasMore && !parsed.offers.isEmpty)
    }
}

enum AldiSuedCatalogParser {

    /// `/produkte/<kategorie>/k/<id>` aus der Startseite, geordnet nach
    /// `AldiSuedCatalogClient.categorySlugs`.
    static func categoryPaths(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"href="(/produkte/([a-z0-9-]+)/k/\d+)""#) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        var bySlug: [String: String] = [:]
        for match in regex.matches(in: html, range: range) {
            guard let path = Range(match.range(at: 1), in: html),
                  let slug = Range(match.range(at: 2), in: html) else { continue }
            let key = String(html[slug])
            if bySlug[key] == nil {
                bySlug[key] = String(html[path])
            }
        }
        return AldiSuedCatalogClient.categorySlugs.compactMap { bySlug[$0] }
    }
}
