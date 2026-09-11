import XCTest
@testable import PriceData

final class RequestRunnerTests: XCTestCase {

    private let request = URLRequest(url: URL(string: "https://example.invalid/x")!)

    /// Kurze Wartezeit, damit die Tests nicht sekundenlang schlafen.
    private func runner(_ stub: StubTransport, attempts: Int = 3) -> RequestRunner {
        RequestRunner(transport: stub, maxAttempts: attempts, baseDelay: 0.01)
    }

    func testSuccessNeedsOnlyOneAttempt() async throws {
        let stub = StubTransport(json: "{}")
        _ = try await runner(stub).run(request)
        XCTAssertEqual(stub.log.count, 1)
    }

    /// Der Fall, der bei Open Food Facts wirklich auftritt: die Suchroute
    /// antwortet unter Last mit 503 und ist beim naechsten Versuch wieder da.
    func testTemporaryFailureIsRetriedAndThenSucceeds() async throws {
        let stub = StubTransport([
            .success(.status(503)),
            .success(HTTPResponse(status: 200, body: Data("{\"ok\":true}".utf8)))
        ])
        let data = try await runner(stub).run(request)
        XCTAssertEqual(stub.log.count, 2)
        XCTAssertFalse(data.isEmpty)
    }

    func testGivesUpAfterTheConfiguredNumberOfAttempts() async {
        let stub = StubTransport([.success(.status(503))])
        do {
            _ = try await runner(stub, attempts: 3).run(request)
            XCTFail("Erwartet: Fehler")
        } catch let error as DataSourceError {
            XCTAssertEqual(error, .temporarilyUnavailable(status: 503))
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)")
        }
        XCTAssertEqual(stub.log.count, 3, "Genau drei Versuche, nicht mehr")
    }

    func testNotFoundIsFinalAndNotRetried() async {
        let stub = StubTransport([.success(.status(404))])
        do {
            _ = try await runner(stub).run(request)
            XCTFail("Erwartet: Fehler")
        } catch let error as DataSourceError {
            XCTAssertEqual(error, .notFound)
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)")
        }
        XCTAssertEqual(stub.log.count, 1)
    }

    func testOfflineIsFinalAndNotRetried() async {
        // Ohne Netz hilft Wiederholen nicht -- es verzoegert nur die Meldung.
        let stub = StubTransport([.failure(.offline)])
        do {
            _ = try await runner(stub).run(request)
            XCTFail("Erwartet: Fehler")
        } catch let error as DataSourceError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)")
        }
        XCTAssertEqual(stub.log.count, 1)
    }

    func testRateLimitIsRetried() async throws {
        let stub = StubTransport([
            .success(.status(429, headers: ["Retry-After": "0"])),
            .success(HTTPResponse(status: 200, body: Data("{}".utf8)))
        ])
        _ = try await runner(stub).run(request)
        XCTAssertEqual(stub.log.count, 2)
    }

    func testTimeoutIsRetried() async throws {
        let stub = StubTransport([
            .failure(.timedOut),
            .success(HTTPResponse(status: 200, body: Data("{}".utf8)))
        ])
        _ = try await runner(stub).run(request)
        XCTAssertEqual(stub.log.count, 2)
    }
}

final class DataSourceErrorTests: XCTestCase {

    func testStatusMapping() {
        XCTAssertEqual(DataSourceError.from(status: 404), .notFound)
        XCTAssertEqual(DataSourceError.from(status: 401), .unauthorized)
        XCTAssertEqual(DataSourceError.from(status: 403), .unauthorized)
        XCTAssertEqual(DataSourceError.from(status: 429, retryAfter: 12),
                       .rateLimited(retryAfter: 12))
        XCTAssertEqual(DataSourceError.from(status: 503),
                       .temporarilyUnavailable(status: 503))
        XCTAssertEqual(DataSourceError.from(status: 418), .server(status: 418))
    }

    func testUrlErrorMapping() {
        XCTAssertEqual(DataSourceError(urlError: URLError(.notConnectedToInternet)), .offline)
        XCTAssertEqual(DataSourceError(urlError: URLError(.networkConnectionLost)), .offline)
        XCTAssertEqual(DataSourceError(urlError: URLError(.timedOut)), .timedOut)
        XCTAssertEqual(DataSourceError(urlError: URLError(.cancelled)), .cancelled)
        // Abgewiesene oder abgebrochene Verbindungen sind vorübergehend -- sie
        // landeten früher als „Unerwartete Antwort“ ohne Wiederholen.
        XCTAssertEqual(DataSourceError(urlError: URLError(.cannotConnectToHost)), .unreachable)
        XCTAssertEqual(DataSourceError(urlError: URLError(.cannotFindHost)), .unreachable)
        XCTAssertEqual(DataSourceError(urlError: URLError(.badServerResponse)), .unreachable)
    }

    func testRetryability() {
        XCTAssertTrue(DataSourceError.unreachable.isRetryable)
        XCTAssertTrue(DataSourceError.temporarilyUnavailable(status: 503).isRetryable)
        XCTAssertTrue(DataSourceError.timedOut.isRetryable)
        XCTAssertTrue(DataSourceError.rateLimited(retryAfter: nil).isRetryable)
        XCTAssertFalse(DataSourceError.offline.isRetryable)
        XCTAssertFalse(DataSourceError.notFound.isRetryable)
        XCTAssertFalse(DataSourceError.decoding("x").isRetryable)
    }

    /// Ohne Netz wird nicht automatisch wiederholt -- ein Knopf muss es aber
    /// geben, sonst steckt man nach der Rückkehr ins Netz fest.
    func testManualRetryIsOfferedWhereItCanHelp() {
        XCTAssertTrue(DataSourceError.offline.offersManualRetry)
        XCTAssertTrue(DataSourceError.unreachable.offersManualRetry)
        XCTAssertTrue(DataSourceError.invalidResponse.offersManualRetry)
        XCTAssertTrue(DataSourceError.server(status: 400).offersManualRetry)
        XCTAssertFalse(DataSourceError.notFound.offersManualRetry)
        XCTAssertFalse(DataSourceError.unauthorized.offersManualRetry)
        XCTAssertFalse(DataSourceError.cancelled.offersManualRetry)
    }

    func testEveryErrorHasAReadableMessage() {
        let all: [DataSourceError] = [
            .offline, .timedOut, .cancelled, .rateLimited(retryAfter: nil),
            .temporarilyUnavailable(status: 503), .unreachable, .notFound, .unauthorized,
            .server(status: 400), .invalidResponse, .decoding("x")
        ]
        for error in all {
            XCTAssertFalse(error.userMessage.isEmpty, "Ohne Text: \(error)")
            XCTAssertFalse(error.userMessage.contains("Error"),
                           "Keine Fachbegriffe in der Nutzermeldung: \(error)")
        }
    }

    func testRetryAfterHeaderIsRead() {
        let response = HTTPResponse(status: 429, body: Data(),
                                    headers: ["retry-after": " 30 "])
        XCTAssertEqual(response.retryAfterSeconds, 30)
    }
}
