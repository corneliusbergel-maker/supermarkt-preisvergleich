import Foundation
import PriceCore

/// Zugriff auf die Produktdatenbank von Open Food Facts.
///
/// Kostenlos, ODbL-lizenziert, ohne Schluessel. Namensnennung ist Pflicht und
/// erfolgt in den App-Einstellungen.
public struct OpenFoodFactsClient: Sendable {

    private let runner: RequestRunner
    private let host: String

    public init(transport: HTTPTransport = URLSessionTransport(),
                host: String = "world.openfoodfacts.org") {
        self.runner = RequestRunner(transport: transport)
        self.host = host
    }

    /// Felder, die abgefragt werden. Bewusst begrenzt -- ein vollstaendiger
    /// Produktdatensatz ist bei Open Food Facts sehr gross, und wir brauchen
    /// nur einen Bruchteil davon.
    private static let fields = [
        "code", "product_name", "product_name_de", "brands",
        "quantity", "product_quantity", "product_quantity_unit",
        "image_front_small_url", "image_url", "categories_tags"
    ].joined(separator: ",")

    // MARK: - Barcode

    /// Loest einen gescannten Barcode auf.
    ///
    /// Wirft `DataSourceError.notFound`, wenn das Produkt unbekannt ist --
    /// es wird kein Platzhalterprodukt erfunden.
    public func product(barcode: String) async throws -> Product {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { throw DataSourceError.notFound }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v2/product/\(digits).json"
        components.queryItems = [URLQueryItem(name: "fields", value: Self.fields)]

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

    /// Freitextsuche nach Produkten.
    ///
    /// Nutzt `/cgi/search.pl`, weil `/api/v2/search` keine Freitextsuche kann.
    /// Diese Route ist die schwerere von beiden und antwortet unter Last mit
    /// HTTP 503 -- am 2026-09-10 selbst beobachtet. `RequestRunner` wiederholt
    /// deshalb mit wachsender Wartezeit, und der Fehler wird andernfalls
    /// ehrlich nach oben gereicht statt als "keine Treffer" ausgegeben.
    public func search(_ terms: String,
                       page: Int = 1,
                       pageSize: Int = 20,
                       germanProductsOnly: Bool = true) async throws -> [Product] {

        let trimmed = terms.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return [] }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/cgi/search.pl"

        var items = [
            URLQueryItem(name: "search_terms", value: trimmed),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "page_size", value: String(min(50, max(1, pageSize)))),
            URLQueryItem(name: "lc", value: "de"),
            URLQueryItem(name: "fields", value: Self.fields)
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

        // Produkte ohne verwertbare Menge fallen heraus: ohne Menge gibt es
        // keinen Grundpreis und keinen belastbaren Vergleich.
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

/// Ein Produktdatensatz, wie Open Food Facts ihn liefert.
struct OpenFoodFactsProductDTO: Decodable {

    let code: String?
    let productName: String?
    let productNameDe: String?
    let brands: String?
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
            brand: brands,
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
