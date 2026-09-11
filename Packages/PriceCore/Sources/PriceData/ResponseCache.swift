import Foundation

/// Legt Antworten auf der Platte ab, damit die App ohne Netz nicht leer ist (#32).
///
/// Bewusst **nur Leseanfragen**. Eine zwischengespeicherte Schreibanfrage
/// erneut auszuliefern wäre sinnlos und gefährlich.
public actor ResponseCache {

    public struct Entry: Sendable {
        public let data: Data
        public let storedAt: Date
    }

    private let directory: URL
    private let lifetime: TimeInterval
    private let fileManager = FileManager.default

    /// - Parameter lifetime: Wie lange ein Eintrag höchstens ausgeliefert wird.
    ///   Voreinstellung: 7 Tage. Was älter ist, wäre auch als „veraltet"
    ///   markiert keine brauchbare Auskunft mehr.
    public init(name: String = "responses", lifetime: TimeInterval = 7 * 24 * 60 * 60) {
        let base = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        self.directory = base.appendingPathComponent("Preisfuchs/\(name)", isDirectory: true)
        self.lifetime = lifetime
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func store(_ data: Data, for key: String) {
        let url = directory.appendingPathComponent(Self.fileName(for: key))
        try? data.write(to: url, options: .atomic)
    }

    public func load(for key: String, now: Date = Date()) -> Entry? {
        let url = directory.appendingPathComponent(Self.fileName(for: key))
        guard let data = try? Data(contentsOf: url),
              let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let modified = attributes[.modificationDate] as? Date else { return nil }

        guard now.timeIntervalSince(modified) < lifetime else {
            try? fileManager.removeItem(at: url)
            return nil
        }
        return Entry(data: data, storedAt: modified)
    }

    public func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Stabiler Dateiname aus dem Schlüssel.
    ///
    /// FNV-1a statt einer Prüfsumme aus CryptoKit: Für einen Zwischenspeicher
    /// genügt das völlig, und es hält das Paket frei von zusätzlichen
    /// Abhängigkeiten. Eine Kollision hieße hier schlimmstenfalls, dass ein
    /// Eintrag überschrieben wird.
    static func fileName(for key: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x1000_0000_01b3
        }
        return String(format: "%016llx.cache", hash)
    }
}

/// Reicht Anfragen durch und hält Antworten vor.
///
/// Bei Netzproblemen wird die letzte bekannte Antwort ausgeliefert -- **mit
/// einer Kopfzeile**, die sagt, wann sie geholt wurde. Die Oberfläche kann
/// daran erkennen, dass die Zahlen nicht frisch sind, und es dazuschreiben.
///
/// Ohne diese Kennzeichnung wäre der Zwischenspeicher eine Lüge: Der Nutzer
/// sähe Preise, die aussehen wie eben geladen.
public struct CachingTransport: HTTPTransport {

    /// Kopfzeile mit dem Zeitpunkt des ursprünglichen Abrufs (ISO 8601).
    public static let cacheDateHeader = "X-Preisfuchs-Cached-At"

    private let wrapped: HTTPTransport
    private let cache: ResponseCache
    private let onCacheHit: (@Sendable (Date) -> Void)?
    private let onFreshResponse: (@Sendable () -> Void)?

    /// - Parameters:
    ///   - onCacheHit: Wird gerufen, wenn eine Antwort aus dem Zwischenspeicher
    ///     kam. So kann die Oberfläche einen Hinweis einblenden, ohne dass die
    ///     Datenschicht die Oberfläche kennen muss.
    ///   - onFreshResponse: Wird bei einer frisch geholten Antwort gerufen --
    ///     damit ein solcher Hinweis auch wieder verschwindet.
    public init(wrapping transport: HTTPTransport = URLSessionTransport(),
                cache: ResponseCache = ResponseCache(),
                onCacheHit: (@Sendable (Date) -> Void)? = nil,
                onFreshResponse: (@Sendable () -> Void)? = nil) {
        self.wrapped = transport
        self.cache = cache
        self.onCacheHit = onCacheHit
        self.onFreshResponse = onFreshResponse
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let method = request.httpMethod?.uppercased() ?? "GET"
        let key = request.url?.absoluteString ?? ""

        // Nur Leseanfragen. Ein zwischengespeichertes POST erneut auszuliefern
        // wäre sinnlos -- und würde einen Beitrag vortäuschen, der nie ankam.
        guard method == "GET", !key.isEmpty else {
            return try await wrapped.send(request)
        }

        do {
            let response = try await wrapped.send(request)
            if response.isSuccess {
                await cache.store(response.body, for: key)
                onFreshResponse?()
            }
            return response

        } catch let error as DataSourceError {
            // Nur bei Netzproblemen einspringen. Ein 404 bleibt ein 404 --
            // dafür eine alte Antwort zu zeigen wäre falsch.
            guard error == .offline || error == .timedOut,
                  let entry = await cache.load(for: key) else { throw error }

            onCacheHit?(entry.storedAt)
            return HTTPResponse(
                status: 200,
                body: entry.data,
                headers: [Self.cacheDateHeader: ISO8601DateFormatter().string(from: entry.storedAt)]
            )
        }
    }
}

public extension HTTPResponse {

    /// Zeitpunkt des ursprünglichen Abrufs, wenn die Antwort aus dem
    /// Zwischenspeicher stammt. `nil` bei frisch geholten Antworten.
    var cachedAt: Date? {
        let value = headers.first { $0.key.lowercased() == CachingTransport.cacheDateHeader.lowercased() }?.value
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value)
    }
}
