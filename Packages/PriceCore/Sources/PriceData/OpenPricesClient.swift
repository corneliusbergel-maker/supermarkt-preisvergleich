import Foundation
import PriceCore

/// Zugriff auf die Preisdatenbank Open Prices.
///
/// Kostenlos, ODbL, Lesen ohne Schluessel. Die Preise sind von Nutzern erfasst
/// und in aller Regel mit einem Foto belegt -- in einer Stichprobe von 100
/// Berliner Datensaetzen am 2026-09-10 waren 82 % Preisschild-Fotos und 18 %
/// Kassenbons.
public struct OpenPricesClient: Sendable {

    private let runner: RequestRunner
    private let host: String

    public init(transport: HTTPTransport = URLSessionTransport(),
                host: String = "prices.openfoodfacts.org") {
        self.runner = RequestRunner(transport: transport)
        self.host = host
    }

    // MARK: - Preise zu einem Produkt

    /// Holt Preise fuer einen Barcode, optional auf einen Umkreis begrenzt.
    ///
    /// - Parameters:
    ///   - barcode: GTIN/EAN des Produkts.
    ///   - near: Mittelpunkt der Umkreissuche. `nil` sucht ohne Ortsbezug.
    ///   - radiusKm: Suchradius. Wird nur zusammen mit `near` gesendet.
    ///   - notOlderThan: Aeltere Beobachtungen werden gar nicht erst geladen.
    public func prices(barcode: String,
                       near: Coordinate? = nil,
                       radiusKm: Double = 25,
                       notOlderThan: Date? = nil,
                       limit: Int = 50) async throws -> [PriceObservation] {

        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { return [] }

        var items = [
            URLQueryItem(name: "product_code", value: digits),
            URLQueryItem(name: "size", value: String(min(100, max(1, limit)))),
            URLQueryItem(name: "order_by", value: "-date")
        ]

        if let near, near.isValid {
            items.append(URLQueryItem(name: "lat", value: String(near.latitude)))
            items.append(URLQueryItem(name: "lon", value: String(near.longitude)))
            items.append(URLQueryItem(name: "radius_km", value: String(max(1, radiusKm))))
        }
        if let notOlderThan {
            items.append(URLQueryItem(name: "date__gte",
                                      value: Self.dayFormatter.string(from: notOlderThan)))
        }

        return try await fetch(items)
    }

    /// Preisverlauf eines Produkts, unabhaengig vom Ort.
    ///
    /// Fuer den Verlauf zaehlt die zeitliche Tiefe mehr als die Naehe --
    /// ein Verlauf aus drei Punkten waere keiner.
    public func priceHistory(barcode: String,
                             since: Date,
                             limit: Int = 100) async throws -> [PriceObservation] {
        let digits = barcode.filter(\.isNumber)
        guard !digits.isEmpty else { return [] }

        return try await fetch([
            URLQueryItem(name: "product_code", value: digits),
            URLQueryItem(name: "date__gte", value: Self.dayFormatter.string(from: since)),
            URLQueryItem(name: "size", value: String(min(100, max(1, limit)))),
            URLQueryItem(name: "order_by", value: "date")
        ])
    }

    /// Aktuelle Aktionspreise im Umkreis.
    ///
    /// Liefert den Preis **zusammen mit dem Produkt**, soweit Open Prices es
    /// mitgibt. Ohne Namen wäre ein Angebot in einer Liste nicht brauchbar --
    /// und der Umweg über eine zweite Abfrage je Treffer wäre unverhältnismäßig.
    public func discountedPrices(near: Coordinate,
                                 radiusKm: Double = 25,
                                 notOlderThan: Date,
                                 limit: Int = 50) async throws -> [PricedProduct] {
        guard near.isValid else { return [] }

        return try await fetchPriced([
            URLQueryItem(name: "price_is_discounted", value: "true"),
            URLQueryItem(name: "lat", value: String(near.latitude)),
            URLQueryItem(name: "lon", value: String(near.longitude)),
            URLQueryItem(name: "radius_km", value: String(max(1, radiusKm))),
            URLQueryItem(name: "date__gte", value: Self.dayFormatter.string(from: notOlderThan)),
            URLQueryItem(name: "size", value: String(min(100, max(1, limit)))),
            URLQueryItem(name: "order_by", value: "-date")
        ])
    }

    // MARK: - Innereien

    private func fetchPriced(_ queryItems: [URLQueryItem]) async throws -> [PricedProduct] {
        try await fetchPage(queryItems).items.compactMap { item in
            guard let observation = item.toObservation() else { return nil }
            return PricedProduct(observation: observation,
                                 product: item.product?.toProduct(),
                                 discountPercent: item.discountPercent)
        }
    }

    private func fetch(_ queryItems: [URLQueryItem]) async throws -> [PriceObservation] {
        try await fetchPage(queryItems).items.compactMap { $0.toObservation() }
    }

    private func fetchPage(_ queryItems: [URLQueryItem]) async throws -> OpenPricesPage {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v1/prices"
        components.queryItems = queryItems

        guard let url = components.url else { throw DataSourceError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue(APIIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let data = try await runner.run(request)

        do {
            return try JSONDecoder().decode(OpenPricesPage.self, from: data)
        } catch {
            throw DataSourceError.decoding(String(describing: error))
        }
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

/// Ein Preis zusammen mit dem Produkt, zu dem er gehoert.
public struct PricedProduct: Sendable, Identifiable {

    public let observation: PriceObservation

    /// `nil`, wenn Open Prices zu dem Barcode keinen Produktdatensatz fuehrt.
    /// Dann fehlt der Name -- und die App zeigt den Eintrag nicht an, statt
    /// einen Platzhalter zu erfinden.
    public let product: Product?

    /// Rabatt in ganzen Prozent, nur wenn der Ursprungspreis bekannt ist.
    public let discountPercent: Int?

    public var id: String { observation.id }

    public init(observation: PriceObservation, product: Product?, discountPercent: Int?) {
        self.observation = observation
        self.product = product
        self.discountPercent = discountPercent
    }
}

// MARK: - Uebertragungsformate

struct OpenPricesPage: Decodable {
    let items: [OpenPricesItemDTO]
    let total: Int?
    let page: Int?
    let pages: Int?
}

struct OpenPricesItemDTO: Decodable {

    let id: Int
    let price: FlexibleNumber?
    let priceIsDiscounted: Bool?
    let priceWithoutDiscount: FlexibleNumber?
    let currency: String?
    let date: String?
    let productCode: String?
    let source: String?
    let owner: String?
    let location: OpenPricesLocationDTO?
    let proof: OpenPricesProofDTO?

    /// Open Prices haengt den Produktdatensatz mit an. Die Feldnamen stimmen
    /// mit denen von Open Food Facts ueberein, deshalb laesst sich derselbe
    /// Decoder verwenden.
    let product: OpenFoodFactsProductDTO?

    enum CodingKeys: String, CodingKey {
        case id, price, currency, date, source, owner, location, proof, product
        case priceIsDiscounted = "price_is_discounted"
        case priceWithoutDiscount = "price_without_discount"
        case productCode = "product_code"
    }

    /// Uebersetzt in das Modell der App.
    ///
    /// Gibt `nil` zurueck, sobald eine Angabe fehlt, ohne die der Preis nicht
    /// verantwortbar anzeigbar waere:
    ///
    /// - **ohne Datum** liesse sich nicht sagen, wie aktuell er ist. Die App
    ///   zeigt grundsaetzlich keinen Betrag ohne Stand.
    /// - **ohne Waehrung** waere er nicht vergleichbar. "Wird schon Euro sein"
    ///   ist geraten, nicht gewusst.
    ///
    /// Beides kommt in den Rohdaten vereinzelt vor -- vor allem in
    /// Massenimporten. In einer Stichprobe von 100 aktuellen Berliner
    /// Datensaetzen (2026-09-10) trat es kein einziges Mal auf, der Verlust ist
    /// also gering.
    func toObservation() -> PriceObservation? {
        guard let amount = price?.decimalValue, amount > 0 else { return nil }
        guard let currency, !currency.isEmpty else { return nil }
        guard let date, let observedOn = OpenPricesClient.dayFormatter.date(from: date) else {
            return nil
        }

        let store = location?.toStore()
        let retailer = store?.retailer ?? RetailerRegistry.retailer(brandName: location?.osmBrand)

        return PriceObservation(
            id: "openprices:\(id)",
            productID: productCode.map { "ean:\($0)" } ?? "openprices:\(id)",
            price: Money(amount: amount, currency: currency),
            observedOn: observedOn,
            store: store,
            retailer: retailer,
            isDiscounted: priceIsDiscounted ?? false,
            hasProof: proof?.hasUsableProof ?? false,
            // Open Prices fuehrt Preise am Barcode. Liegt einer vor, ist die
            // Zuordnung eindeutig; sonst ist sie es ausdruecklich nicht.
            isExactProductMatch: productCode?.isEmpty == false,
            source: "Open Prices"
        )
    }

    /// Rabatt in ganzen Prozent, sofern der Ursprungspreis bekannt ist.
    /// Ohne Ursprungspreis wird kein Prozentwert behauptet.
    var discountPercent: Int? {
        guard priceIsDiscounted == true,
              let now = price?.decimalValue,
              let before = priceWithoutDiscount?.decimalValue,
              before > 0, now < before else { return nil }
        let ratio = (before - now) / before * 100
        return Int(NSDecimalNumber(decimal: DecimalParsing.round(ratio, scale: 0)).doubleValue)
    }
}

struct OpenPricesLocationDTO: Decodable {

    let osmId: Int?
    let osmType: String?
    let osmName: String?
    let osmBrand: String?
    let osmAddressPostcode: String?
    let osmAddressCity: String?
    let osmAddressCountryCode: String?
    let osmLat: Double?
    let osmLon: Double?
    let websiteURL: String?

    enum CodingKeys: String, CodingKey {
        case osmId = "osm_id"
        case osmType = "osm_type"
        case osmName = "osm_name"
        case osmBrand = "osm_brand"
        case osmAddressPostcode = "osm_address_postcode"
        case osmAddressCity = "osm_address_city"
        case osmAddressCountryCode = "osm_address_country_code"
        case osmLat = "osm_lat"
        case osmLon = "osm_lon"
        case websiteURL = "website_url"
    }

    /// Ohne Koordinaten laesst sich keine Entfernung berechnen und keine Route
    /// starten -- ein solcher Ort ist fuer die App wertlos und wird verworfen.
    func toStore() -> Store? {
        guard let osmId, let osmType,
              let latitude = osmLat, let longitude = osmLon else { return nil }

        let coordinate = Coordinate(latitude: latitude, longitude: longitude)
        guard coordinate.isValid else { return nil }

        guard let retailer = RetailerRegistry.retailer(brandName: osmBrand)
                ?? RetailerRegistry.retailer(brandName: osmName) else { return nil }

        return Store(
            id: "\(osmType.lowercased())/\(osmId)",
            retailer: retailer,
            coordinate: coordinate,
            name: osmName,
            // Open Prices fuehrt keine Strasse als eigenes Feld. Sie aus dem
            // Anzeigenamen herauszuschneiden waere Ratearbeit -- die Route
            // fuehrt ohnehin ueber die Koordinaten.
            street: nil,
            houseNumber: nil,
            postalCode: osmAddressPostcode,
            city: osmAddressCity,
            openingHoursRaw: nil,
            websiteURL: websiteURL.flatMap(URL.init(string:))
        )
    }
}

struct OpenPricesProofDTO: Decodable {
    let id: Int?
    let type: String?

    /// Zaehlt als Beleg nur, was ein Foto vom Preisschild oder Kassenbon ist.
    var hasUsableProof: Bool {
        guard let type else { return false }
        return ["PRICE_TAG", "RECEIPT"].contains(type.uppercased())
    }
}
