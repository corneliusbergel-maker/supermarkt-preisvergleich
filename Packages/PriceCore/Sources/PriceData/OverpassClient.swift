import Foundation
import PriceCore

/// Serialisiert Anfragen: eine nach der anderen, nie parallel.
///
/// Die oeffentliche Overpass-Instanz erlaubt pro IP nur **zwei** gleichzeitige
/// Abfragen -- am 2026-09-10 ueber `/api/status` gemessen ("Rate limit: 2").
/// Ein Actor allein genuegt dafuer nicht: Actor-Methoden koennen an
/// `await`-Stellen verschraenkt ausgefuehrt werden. Deshalb werden die
/// Vorgaenge hier ausdruecklich aneinandergehaengt.
actor SerialQueue {

    private var tail: Task<Void, Never> = Task {}

    func enqueue<T: Sendable>(_ operation: @Sendable @escaping () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> {
            _ = await previous.value
            return try await operation()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}

/// Einfacher Zwischenspeicher mit Verfallszeit.
///
/// Filialen ziehen nicht um, waehrend man einkauft. Sie erneut abzufragen
/// waere unhoeflich gegenueber einem Dienst, den die OSM-Gemeinschaft
/// kostenlos bereitstellt.
actor StoreCache {

    private struct Entry {
        let stores: [Store]
        let storedAt: Date
    }

    private var entries: [String: Entry] = [:]
    private let lifetime: TimeInterval

    init(lifetime: TimeInterval = 7 * 24 * 60 * 60) {
        self.lifetime = lifetime
    }

    func stores(for key: String, now: Date = Date()) -> [Store]? {
        guard let entry = entries[key] else { return nil }
        guard now.timeIntervalSince(entry.storedAt) < lifetime else {
            entries[key] = nil
            return nil
        }
        return entry.stores
    }

    func store(_ stores: [Store], for key: String, now: Date = Date()) {
        entries[key] = Entry(stores: stores, storedAt: now)
    }

    func clear() { entries.removeAll() }
}

/// Filialdaten aus OpenStreetMap ueber die Overpass-API.
///
/// Kostenlos und ohne Schluessel. Die Namensnennung
/// "© OpenStreetMap-Mitwirkende" ist Lizenzpflicht und steht in den
/// App-Einstellungen.
public struct OverpassClient: Sendable {

    private let transport: HTTPTransport
    private let endpoint: URL
    private let queue: SerialQueue
    private let cache: StoreCache

    /// Ladenarten, die fuer einen Lebensmittel-Preisvergleich in Frage kommen.
    /// Drogerien sind bewusst dabei -- Shampoo und Waschmittel gehoeren auf
    /// jede Einkaufsliste.
    private static let shopTypes = "supermarket|convenience|chemist|beverages|greengrocer"

    public init(transport: HTTPTransport = URLSessionTransport(timeout: 40),
                endpoint: URL = URL(string: "https://overpass-api.de/api/interpreter")!,
                cacheLifetime: TimeInterval = 7 * 24 * 60 * 60) {
        self.transport = transport
        self.endpoint = endpoint
        self.queue = SerialQueue()
        self.cache = StoreCache(lifetime: cacheLifetime)
    }

    /// Filialen im Umkreis.
    ///
    /// - Parameters:
    ///   - coordinate: Mittelpunkt.
    ///   - radiusKm: Radius; wird auf 25 km begrenzt, weil groessere Abfragen
    ///     bei Overpass regelmaessig ins Zeitlimit laufen.
    ///   - ignoreCache: Erzwingt eine frische Abfrage.
    public func stores(near coordinate: Coordinate,
                       radiusKm: Double = 5,
                       ignoreCache: Bool = false) async throws -> [Store] {

        guard coordinate.isValid else { return [] }
        let radius = min(25, max(0.5, radiusKm))
        let key = Self.cacheKey(coordinate: coordinate, radiusKm: radius)

        if !ignoreCache, let cached = await cache.stores(for: key) {
            return cached
        }

        let stores = try await queue.enqueue { [transport, endpoint] in
            let query = Self.query(coordinate: coordinate, radiusMeters: radius * 1000)

            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue(APIIdentity.userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                             forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("data=\(Self.escape(query))".utf8)

            // Wiederholungen bewusst sparsam: Wer ein Limit reisst, soll nicht
            // noch fester dagegen druecken.
            let runner = RequestRunner(transport: transport, maxAttempts: 2, baseDelay: 2)
            let data = try await runner.run(request)

            let response: OverpassResponse
            do {
                response = try JSONDecoder().decode(OverpassResponse.self, from: data)
            } catch {
                throw DataSourceError.decoding(String(describing: error))
            }
            return response.elements.compactMap { $0.toStore() }
        }

        await cache.store(stores, for: key)
        return stores
    }

    /// Leert den Zwischenspeicher, z. B. wenn der Nutzer den Ort wechselt.
    public func clearCache() async {
        await cache.clear()
    }

    // MARK: - Abfrage

    static func query(coordinate: Coordinate, radiusMeters: Double) -> String {
        let latitude = String(format: "%.6f", coordinate.latitude)
        let longitude = String(format: "%.6f", coordinate.longitude)
        let radius = String(format: "%.0f", radiusMeters)

        return """
        [out:json][timeout:25];
        (
          node["shop"~"^(\(shopTypes))$"](around:\(radius),\(latitude),\(longitude));
          way["shop"~"^(\(shopTypes))$"](around:\(radius),\(latitude),\(longitude));
        );
        out center tags;
        """
    }

    /// Rundet auf etwa 1 km, damit kleine Standortwechsel nicht jedes Mal eine
    /// neue Abfrage ausloesen.
    static func cacheKey(coordinate: Coordinate, radiusKm: Double) -> String {
        let latitude = (coordinate.latitude * 100).rounded() / 100
        let longitude = (coordinate.longitude * 100).rounded() / 100
        return String(format: "%.2f,%.2f@%.1f", latitude, longitude, radiusKm)
    }

    private static func escape(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}

// MARK: - Uebertragungsformate

struct OverpassResponse: Decodable {
    let elements: [OverpassElementDTO]
}

struct OverpassElementDTO: Decodable {

    let type: String
    let id: Int
    let lat: Double?
    let lon: Double?
    let center: OverpassCentre?
    let tags: [String: String]?

    struct OverpassCentre: Decodable {
        let lat: Double
        let lon: Double
    }

    /// Knoten tragen die Koordinate direkt, Flaechen ueber `center`.
    var coordinate: Coordinate? {
        if let lat, let lon { return Coordinate(latitude: lat, longitude: lon) }
        if let center { return Coordinate(latitude: center.lat, longitude: center.lon) }
        return nil
    }

    func toStore() -> Store? {
        guard let coordinate, coordinate.isValid, let tags else { return nil }

        // Die Wikidata-ID der Marke ist der verlaesslichste Schluessel -- sie
        // ist unabhaengig von der Schreibweise. Wo sie fehlt, entscheidet der
        // Name.
        let brandName = tags["brand"] ?? tags["name"]
        let retailer: Retailer?
        if let wikidata = RetailerRegistry.identifier(forWikidata: tags["brand:wikidata"]),
           let name = brandName {
            retailer = Retailer(id: wikidata, name: name)
        } else {
            retailer = RetailerRegistry.retailer(brandName: brandName)
        }
        guard let retailer else { return nil }

        return Store(
            id: "\(type)/\(id)",
            retailer: retailer,
            coordinate: coordinate,
            name: tags["name"],
            street: tags["addr:street"],
            houseNumber: tags["addr:housenumber"],
            postalCode: tags["addr:postcode"],
            city: tags["addr:city"],
            // Roh uebernommen. Die Syntax von `opening_hours` ist komplex; sie
            // halb auszuwerten hiesse, falsche Oeffnungszeiten zu behaupten.
            openingHoursRaw: tags["opening_hours"],
            websiteURL: tags["website"].flatMap(URL.init(string:))
        )
    }
}
