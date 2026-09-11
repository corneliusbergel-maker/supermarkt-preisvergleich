import Foundation

/// Antwort einer HTTP-Anfrage, reduziert auf das, was die Clients brauchen.
public struct HTTPResponse: Sendable {
    public let status: Int
    public let body: Data
    public let headers: [String: String]

    public init(status: Int, body: Data, headers: [String: String] = [:]) {
        self.status = status
        self.body = body
        self.headers = headers
    }

    public var isSuccess: Bool { (200..<300).contains(status) }

    /// Wert des `Retry-After`-Kopfs in Sekunden, falls vorhanden.
    public var retryAfterSeconds: TimeInterval? {
        let value = headers.first { $0.key.lowercased() == "retry-after" }?.value
        guard let value, let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        return seconds
    }
}

/// Abstraktion ueber den Netzwerkzugriff.
///
/// Die Clients haengen an diesem Protokoll statt an `URLSession`, damit sie
/// sich ohne Netzverbindung testen lassen. Kein Test in diesem Projekt ruft
/// eine echte API auf -- Tests, die vom Netz abhaengen, schlagen frueher oder
/// spaeter aus Gruenden fehl, die nichts mit dem Code zu tun haben.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

/// Fehler, die beim Abruf einer Datenquelle auftreten koennen.
///
/// Bewusst nach *Ursache* unterschieden und nicht nur nach Statuscode: Die
/// Oberflaeche muss "du bist offline" anders behandeln als "die Quelle ist
/// gerade ueberlastet" -- im ersten Fall helfen gecachte Daten, im zweiten
/// hilft Abwarten.
public enum DataSourceError: Error, Equatable, Sendable {

    /// Keine Netzverbindung.
    case offline

    /// Zeitueberschreitung.
    case timedOut

    /// Abgebrochen, z. B. weil der Nutzer weitergetippt hat.
    case cancelled

    /// Zu viele Anfragen (HTTP 429).
    case rateLimited(retryAfter: TimeInterval?)

    /// Quelle voruebergehend nicht erreichbar (HTTP 5xx).
    ///
    /// Tritt bei Open Food Facts an der Suchroute unter Last tatsaechlich auf --
    /// am 2026-09-10 mit HTTP 503 beobachtet.
    case temporarilyUnavailable(status: Int)

    /// Angefragte Ressource existiert nicht.
    case notFound

    /// Nicht angemeldet oder Sitzung abgelaufen (HTTP 401/403).
    ///
    /// Eigener Fall, weil die Oberflaeche darauf anders reagieren muss:
    /// Hier hilft kein Abwarten, sondern nur eine neue Anmeldung.
    case unauthorized

    /// Sonstiger Fehlerstatus.
    case server(status: Int)

    /// Antwort war kein gueltiges HTTP oder nicht lesbar.
    case invalidResponse

    /// Antwort liess sich nicht in das erwartete Format uebersetzen.
    case decoding(String)

    /// Text fuer die Oberflaeche. Sagt, was los ist, ohne Fachbegriffe.
    public var userMessage: String {
        switch self {
        case .offline:
            return "Keine Internetverbindung. Angezeigte Daten können veraltet sein."
        case .timedOut:
            return "Die Anfrage hat zu lange gedauert."
        case .cancelled:
            return "Abgebrochen."
        case .rateLimited:
            return "Zu viele Anfragen in kurzer Zeit. Bitte kurz warten."
        case .temporarilyUnavailable:
            return "Die Datenquelle ist gerade überlastet. Bitte später erneut versuchen."
        case .notFound:
            return "Dazu liegen keine Daten vor."
        case .unauthorized:
            return "Deine Anmeldung ist abgelaufen. Bitte melde dich erneut an."
        case .server(let status):
            return "Die Datenquelle antwortet mit einem Fehler (\(status))."
        case .invalidResponse:
            return "Unerwartete Antwort der Datenquelle."
        case .decoding:
            return "Die Antwort der Datenquelle war nicht lesbar."
        }
    }

    /// Lohnt sich ein erneuter Versuch?
    public var isRetryable: Bool {
        switch self {
        case .timedOut, .rateLimited, .temporarilyUnavailable:
            return true
        case .offline, .cancelled, .notFound, .server, .invalidResponse, .decoding, .unauthorized:
            return false
        }
    }

    /// Uebersetzt einen `URLError` in die passende Ursache.
    public init(urlError: URLError) {
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed:
            self = .offline
        case .timedOut:
            self = .timedOut
        case .cancelled:
            self = .cancelled
        default:
            self = .invalidResponse
        }
    }

    /// Leitet den Fehler aus einem HTTP-Status ab.
    public static func from(status: Int, retryAfter: TimeInterval? = nil) -> DataSourceError {
        switch status {
        case 404: return .notFound
        case 401, 403: return .unauthorized
        case 429: return .rateLimited(retryAfter: retryAfter)
        case 500...599: return .temporarilyUnavailable(status: status)
        default: return .server(status: status)
        }
    }
}

// MARK: - URLSession

public struct URLSessionTransport: HTTPTransport {

    private let session: URLSession

    public init(timeout: TimeInterval = 20) {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout * 2
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .useProtocolCachePolicy
        self.session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw DataSourceError.invalidResponse
            }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String {
                    headers[key] = value
                }
            }
            return HTTPResponse(status: http.statusCode, body: data, headers: headers)
        } catch let error as URLError {
            throw DataSourceError(urlError: error)
        }
    }
}

// MARK: - Gemeinsame Grundlage der Clients

/// Kennzeichnung der App gegenueber den Datenquellen.
///
/// Open Food Facts erwartet ausdruecklich einen aussagekraeftigen
/// `User-Agent`. Ein anonymer Zugriff gilt dort als unhoeflich und kann
/// gesperrt werden.
public enum APIIdentity {
    public static let userAgent =
        "Preisfuchs/0.1 (iOS; +https://github.com/corneliusbergel-maker/supermarkt-preisvergleich)"
}

/// Fuehrt Anfragen aus und wiederholt sie bei voruebergehenden Stoerungen.
public struct RequestRunner: Sendable {

    private let transport: HTTPTransport
    private let maxAttempts: Int
    private let baseDelay: TimeInterval

    /// - Parameters:
    ///   - maxAttempts: Gesamtzahl der Versuche, nicht der Wiederholungen.
    ///   - baseDelay: Grundwartezeit; sie verdoppelt sich je Versuch.
    public init(transport: HTTPTransport,
                maxAttempts: Int = 3,
                baseDelay: TimeInterval = 0.6) {
        self.transport = transport
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
    }

    public func run(_ request: URLRequest) async throws -> Data {
        var lastError: DataSourceError = .invalidResponse

        for attempt in 1...maxAttempts {
            do {
                let response = try await transport.send(request)
                if response.isSuccess { return response.body }

                let error = DataSourceError.from(status: response.status,
                                                 retryAfter: response.retryAfterSeconds)
                guard error.isRetryable, attempt < maxAttempts else { throw error }
                lastError = error
                try await wait(for: error, attempt: attempt)

            } catch let error as DataSourceError {
                guard error.isRetryable, attempt < maxAttempts else { throw error }
                lastError = error
                try await wait(for: error, attempt: attempt)
            }
        }

        throw lastError
    }

    /// Wartet exponentiell laenger -- und haelt sich an `Retry-After`, wenn die
    /// Gegenstelle einen Wert nennt.
    private func wait(for error: DataSourceError, attempt: Int) async throws {
        var delay = baseDelay * pow(2, Double(attempt - 1))
        if case .rateLimited(let retryAfter) = error, let retryAfter {
            delay = max(delay, retryAfter)
        }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}
