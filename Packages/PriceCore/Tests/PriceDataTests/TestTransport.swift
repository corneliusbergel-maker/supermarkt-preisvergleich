import Foundation
@testable import PriceData

/// Zaehlt Aufrufe und schneidet die Anfragen mit -- ueber Kopien der
/// Stub-Struktur hinweg.
final class CallLog: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    private var requests: [URLRequest] = []

    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    /// Alle gesendeten Anfragen in ihrer Reihenfolge.
    var recorded: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    var lastRequest: URLRequest? {
        lock.lock(); defer { lock.unlock() }
        return requests.last
    }

    func next(_ request: URLRequest) -> Int {
        lock.lock(); defer { lock.unlock() }
        requests.append(request)
        defer { value += 1 }
        return value
    }
}

/// Ersetzt das Netzwerk im Test.
///
/// Kein Test in diesem Projekt ruft eine echte API auf. Netzabhaengige Tests
/// schlagen frueher oder spaeter aus Gruenden fehl, die nichts mit dem Code zu
/// tun haben -- und melden Fehler, die keine sind.
struct StubTransport: HTTPTransport {

    /// Ergebnisse in der Reihenfolge der Aufrufe. Das letzte gilt fuer alle
    /// weiteren Aufrufe.
    let outcomes: [Result<HTTPResponse, DataSourceError>]
    let log = CallLog()

    init(_ outcomes: [Result<HTTPResponse, DataSourceError>]) {
        self.outcomes = outcomes
    }

    /// Kurzform fuer eine erfolgreiche JSON-Antwort.
    init(json: String, status: Int = 200) {
        self.init([.success(HTTPResponse(status: status,
                                         body: Data(json.utf8)))])
    }

    /// Zuletzt gesendete Anfrage -- zum Pruefen von Kopfzeilen und Rumpf.
    var lastRequest: URLRequest? { log.lastRequest }

    /// Alle gesendeten Anfragen in ihrer Reihenfolge.
    var recordedRequests: [URLRequest] { log.recorded }

    func send(_ request: URLRequest) async throws -> HTTPResponse {
        let index = min(log.next(request), outcomes.count - 1)
        switch outcomes[index] {
        case .success(let response): return response
        case .failure(let error): throw error
        }
    }
}

extension HTTPResponse {
    static func status(_ code: Int, headers: [String: String] = [:]) -> HTTPResponse {
        HTTPResponse(status: code, body: Data(), headers: headers)
    }
}
