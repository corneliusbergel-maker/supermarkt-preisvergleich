import Foundation
import PriceCore

/// Zugriff auf die Produktdatenbank von Open Food Facts.
///
/// Kostenlos, ODbL-lizenziert, ohne Schluessel. Namensnennung ist Pflicht und
/// erfolgt in den App-Einstellungen.
///
/// Es werden **zwei** Dienste genutzt, weil sie unterschiedliche Staerken haben:
///
/// - `search.openfoodfacts.org` ist der Suchindex. Schnell und belastbar, aber
///   er fuehrt nur den Freitext `quantity` ("1 l"), nicht die bereits
///   normalisierte Zahl.
/// - `world.openfoodfacts.org/api/v2/product/{code}` liefert den vollstaendigen
///   Datensatz samt `product_quantity` in ml oder g -- die verlaesslichere
///   Grundlage fuer den Grundpreis.
///
/// Deshalb: suchen ueber den Index, und auf der Detailseite den Datensatz ueber
/// den Barcode nachladen.
public struct OpenFoodFactsClient: Sendable {

    private let runner: RequestRunner
    private let productHost: String
    private let searchHost: String

    public init(transport: HTTPTransport = URLSessionTransport(),
                productHost: String = "world.openfoodfacts.org",
                searchHost: String = "search.openfoodfacts.org") {
        self.runner = RequestRunner(transport: transport)
        self.productHost = productHost
        self.searchHost = searchHost
    }

    /// Felder, die abgefragt werden. Bewusst begrenzt -- ein vollstaendiger
    /// Produktdatensatz ist bei Open Food Facts sehr gross, und wir brauchen
    /// nur einen Bruchteil davon.
    private static let productFields = [
        "code", "product_name", "product_name_de", "brands",
        "quantity", "product_quantity", "product_quantity_unit",
        "image_front_small_url", "image_url", "categories_tags"
    ].joined(separator: ",")

    /// Der Index fuehrt `product_quantity` nicht, deshalb steht es hier nicht.
    private static let indexFields = [
        "code", "product_name", "brands", "quantity", "image_url", "categories_tags"
    ].joined(separator: ",")

    // MARK: - Barcode

    /// Loest einen Barcode auf und liefert den vollstaendigen Datensatz.
    ///
    /// Wirft `DataSourceError.notFound`, wenn das Produkt unbekannt ist --
    /// es wird kein Platzhalterprodukt erfunden.
    public func product(barcode: String) async throws -> Product {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { throw DataSourceError.notFound }

        var components = URLComponents()
        components.scheme = "https"
        components.host = productHost
        components.path = "/api/v2/product/\(digits).json"
        components.queryItems = [URLQueryItem(name: "fields", value: Self.productFields)]

        guard let url = components.url else { throw DataSourceError.invalidResponse }
        let data = try await runner.run(makeRequest(url))

        let envelope: SingleProductEnvelope
        do {
            envelope = try JSONDecoder().decode(SingleProductEnvelope.self, from: data)
        } catch {
            throw DataSourceError.decoding(String(describing: error))
        }

        guard envelope.status == 1, let dto = envelope.product else {
            throw DataSourceError.notFound
        }
        guard let product = dto.toProduct() else { throw DataSourceError.notFound }
        return product
    }

    // MARK: - Suche

    /// Freitextsuche.
    ///
    /// Nutzt den Suchindex und faellt bei einer voruebergehenden Stoerung auf
    /// die klassische Route zurueck. Ein endgueltiger Fehler wird
    /// weitergereicht und **nicht** als "keine Treffer" ausgegeben.
    public func search(_ terms: String,
                       page: Int = 1,
                       pageSize: Int = 20,
                       germanProductsOnly: Bool = true) async throws -> [Product] {
        do {
            return try await searchIndex(terms,
                                         page: page,
                                         pageSize: pageSize,
                                         germanProductsOnly: germanProductsOnly)
        } catch let error as DataSourceError where error.isRetryable {
            return try await searchLegacy(terms,
                                          page: page,
                                          pageSize: pageSize,
                                          germanProductsOnly: germanProductsOnly)
        }
    }

    /// Suche ueber `search.openfoodfacts.org`.
    public func searchIndex(_ terms: String,
                            page: Int = 1,
                            pageSize: Int = 20,
                            germanProductsOnly: Bool = true) async throws -> [Product] {

        let trimmed = terms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        // Der Index versteht Lucene-Syntax; der Laenderfilter wird an die
        // Suchanfrage angehaengt.
        let query = germanProductsOnly
            ? "\(trimmed) countries_tags:\"en:germany\""
            : trimmed

        var components = URLComponents()
        components.scheme = "https"
        components.host = searchHost
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "page_size", value: String(min(50, max(1, pageSize)))),
            // Liefert deutsche Produktnamen statt der jeweiligen Hauptsprache.
            URLQueryItem(name: "langs", value: "de"),
            URLQueryItem(name: "fields", value: Self.indexFields)
        ]

        guard let url = components.url else { throw DataSourceError.invalidResponse }
        let data = try await runner.run(makeRequest(url))

        let response: SearchIndexEnvelope
        do {
            response = try JSONDecoder().decode(SearchIndexEnvelope.self, from: data)
        } catch {
            throw DataSourceError.decoding(String(describing: error))
        }
        return response.hits.compactMap { $0.toProduct() }
    }

    /// Suche ueber die klassische Route `/cgi/search.pl`.
    ///
    /// Nur noch Rueckfallebene: Sie antwortet unter Last regelmaessig mit
    /// HTTP 503 -- am 2026-09-11 dreimal hintereinander beobachtet, waehrend
    /// der Index in 0,3 Sekunden lieferte.
    public func searchLegacy(_ terms: String,
                             page: Int = 1,
                             pageSize: Int = 20,
                             germanProductsOnly: Bool = true) async throws -> [Product] {

        let trimmed = terms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents()
        components.scheme = "https"
        components.host = productHost
        components.path = "/cgi/search.pl"

        var items = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "page_size", value: String(min(50, max(1, pageSize)))),
            URLQueryItem(name: "lc", value: "de"),
            URLQueryItem(name: "fields", value: Self.productFields)
        ]

        if germanProductsOnly {
            items.append(contentsOf: [
                URLQueryItem(name: "tagtype_0", value: "countries"),
                URLQueryItem(name: "tag_contains_0", value: "contains"),
                URLQueryItem(name: "tag_0", value: "germany")
            ])
        }
        components.queryItems = items

        guard let url = components.url else { throw DataSourceError.invalidResponse }
        let data = try await runner.run(makeRequest(url))

        let envelope: SearchEnvelope
        do {
            envelope = try JSONDecoder().decode(SearchEnvelope.self, from: data)
        } catch {
            throw DataSourceError.decoding(String(describing: error))
        }
        return envelope.products.compactMap { $0.toProduct() }
    }

    private func makeRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(APIIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

// MARK: - Uebertragungsformate

/// Antwort von `/api/v2/product/{code}.json`.
struct SingleProductEnvelope: Decodable {
    let status: Int
    let product: OpenFoodFactsProductDTO?
}

/// Antwort von `/cgi/search.pl`.
struct SearchEnvelope: Decodable {
    let count: Int?
    let products: [OpenFoodFactsProductDTO]
}

/// Antwort von `search.openfoodfacts.org/search`.
/// Die Treffer heissen dort `hits`, nicht `products`.
struct SearchIndexEnvelope: Decodable {
    let hits: [OpenFoodFactsProductDTO]
    let count: Int?
    let page: Int?
    let pageCount: Int?

    enum CodingKeys: String, CodingKey {
        case hits, count, page
        case pageCount = "page_count"
    }
}

/// Ein Produktdatensatz.
struct OpenFoodFactsProductDTO: Decodable {

    let code: String?
    let productName: String?
    let productNameDe: String?
    let brands: FlexibleStringList?
    let quantity: String?
    let productQuantity: FlexibleNumber?
    let productQuantityUnit: String?
    let imageFrontSmallURL: String?
    let imageURL: String?
    let categoriesTags: [String]?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case productNameDe = "product_name_de"
        case brands
        case quantity
        case productQuantity = "product_quantity"
        case productQuantityUnit = "product_quantity_unit"
        case imageFrontSmallURL = "image_front_small_url"
        case imageURL = "image_url"
        case categoriesTags = "categories_tags"
    }

    /// Uebersetzt in das Modell der App.
    ///
    /// Gibt `nil` zurueck, wenn kein brauchbarer Name vorliegt. Ein Produkt
    /// ohne Namen waere in der Liste nicht unterscheidbar.
    func toProduct() -> Product? {
        let name = [productNameDe, productName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
        guard let name else { return nil }

        let parsedQuantity = Quantity.fromOpenFoodFacts(
            productQuantity: productQuantity?.decimalValue,
            productQuantityUnit: productQuantityUnit,
            quantityText: quantity
        )

        let imageString = [imageFrontSmallURL, imageURL]
            .compactMap { $0 }
            .first { !$0.isEmpty }

        return Product(
            barcode: code?.isEmpty == false ? code : nil,
            name: name,
            brand: brands?.joined,
            quantity: parsedQuantity,
            imageURL: imageString.flatMap(URL.init(string:)),
            categories: categoriesTags ?? []
        )
    }
}

/// Zahl, die als Zahl **oder** als Zeichenkette geliefert werden kann.
///
/// Open Food Facts ist an dieser Stelle uneinheitlich: `product_quantity` kommt
/// mal als `1000`, mal als `"1000"`. Ein Decoder, der nur eines von beidem
/// akzeptiert, laesst je nach Datensatz die Menge wegfallen -- und damit den
/// Grundpreis.
struct FlexibleNumber: Decodable {

    let decimalValue: Decimal?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let double = try? container.decode(Double.self) {
            // Ueber den String und mit festem Gebietsschema, damit weder das
            // Geraetegebietsschema noch die Binaerdarstellung von Double das
            // Ergebnis verfaelscht.
            decimalValue = Decimal(string: String(double),
                                   locale: Locale(identifier: "en_US_POSIX"))
            return
        }
        if let string = try? container.decode(String.self) {
            decimalValue = DecimalParsing.decimal(from: string)
            return
        }
        // Auch `null` und unerwartete Typen sind kein Fehler -- die Menge ist
        // dann eben unbekannt, und die App zeigt keinen Grundpreis.
        decimalValue = nil
    }
}

/// Text, der als Zeichenkette **oder** als Liste geliefert werden kann.
///
/// `/cgi/search.pl` liefert `brands` als kommagetrennten Text
/// ("Ferrero, Nutella"), der Suchindex dagegen als Feld
/// `["Ferrero", " Nutella"]`. Ein Decoder fuer nur eine der beiden Formen
/// verliert je nach Quelle die Marke -- und damit die Markenpruefung im
/// Produktabgleich.
struct FlexibleStringList: Decodable {

    let values: [String]

    var joined: String? {
        let cleaned = values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ", ")
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let list = try? container.decode([String].self) {
            values = list
            return
        }
        if let text = try? container.decode(String.self) {
            values = text.split(separator: ",").map(String.init)
            return
        }
        values = []
    }
}
