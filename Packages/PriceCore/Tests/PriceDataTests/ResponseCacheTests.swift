import XCTest
@testable import PriceData

private func request(_ url: String, method: String = "GET") -> URLRequest {
    var request = URLRequest(url: URL(string: url)!)
    request.httpMethod = method
    return request
}

final class ResponseCacheTests: XCTestCase {

    private func cache(lifetime: TimeInterval = 3600) -> ResponseCache {
        ResponseCache(name: "test-\(UUID().uuidString)", lifetime: lifetime)
    }

    func testStoreAndLoad() async {
        let sut = cache()
        await sut.store(Data("hallo".utf8), for: "a")

        let entry = await sut.load(for: "a")
        XCTAssertEqual(entry.map { String(decoding: $0.data, as: UTF8.self) }, "hallo")
    }

    func testUnknownKeyYieldsNothing() async {
        let entry = await cache().load(for: "gibtsnicht")
        XCTAssertNil(entry)
    }

    /// Was zu alt ist, waere auch als "veraltet" markiert keine brauchbare
    /// Auskunft mehr.
    func testExpiredEntryIsDropped() async {
        let sut = cache(lifetime: 0)
        await sut.store(Data("alt".utf8), for: "a")
        let entry = await sut.load(for: "a")
        XCTAssertNil(entry)
    }

    func testClearRemovesEverything() async {
        let sut = cache()
        await sut.store(Data("x".utf8), for: "a")
        await sut.clear()
        let entry = await sut.load(for: "a")
        XCTAssertNil(entry)
    }

    func testFileNameIsStableAndDistinct() {
        let first = ResponseCache.fileName(for: "https://example.invalid/a")
        let again = ResponseCache.fileName(for: "https://example.invalid/a")
        let other = ResponseCache.fileName(for: "https://example.invalid/b")

        XCTAssertEqual(first, again, "Derselbe Schluessel muss dieselbe Datei ergeben")
        XCTAssertNotEqual(first, other)
        XCTAssertTrue(first.hasSuffix(".cache"))
    }
}

final class CachingTransportTests: XCTestCase {

    private func cache() -> ResponseCache {
        ResponseCache(name: "test-\(UUID().uuidString)")
    }

    func testSuccessfulResponseIsStoredAndReturned() async throws {
        let store = cache()
        let stub = StubTransport(json: "{\"a\":1}")
        let sut = CachingTransport(wrapping: stub, cache: store)

        let response = try await sut.send(request("https://example.invalid/x"))
        XCTAssertEqual(response.status, 200)
        XCTAssertNil(response.cachedAt, "Eine frische Antwort ist nicht aus dem Speicher")

        let entry = await store.load(for: "https://example.invalid/x")
        XCTAssertNotNil(entry)
    }

    /// Der Kern von Anforderung 32: ohne Netz die letzte bekannte Antwort --
    /// aber ausdruecklich als solche gekennzeichnet.
    func testOfflineFallsBackToCacheAndMarksIt() async throws {
        let store = cache()
        await store.store(Data("{\"alt\":true}".utf8), for: "https://example.invalid/x")

        let stub = StubTransport([.failure(.offline)])
        let sut = CachingTransport(wrapping: stub, cache: store)

        let response = try await sut.send(request("https://example.invalid/x"))
        XCTAssertEqual(String(decoding: response.body, as: UTF8.self), "{\"alt\":true}")
        XCTAssertNotNil(response.cachedAt,
                        "Ohne Kennzeichnung waere der Zwischenspeicher eine Luege")
    }

    func testOfflineWithoutCacheStillFails() async {
        let stub = StubTransport([.failure(.offline)])
        let sut = CachingTransport(wrapping: stub, cache: cache())

        do {
            _ = try await sut.send(request("https://example.invalid/leer"))
            XCTFail("Erwartet: Fehler")
        } catch let error as DataSourceError {
            XCTAssertEqual(error, .offline)
        } catch {
            XCTFail("Unerwarteter Fehlertyp: \(error)")
        }
    }

    /// Ein 404 bleibt ein 404. Dafuer eine alte Antwort auszuliefern waere
    /// eine Falschaussage ueber die Datenlage.
    func testNotFoundIsNotServedFromCache() async throws {
        let store = cache()
        await store.store(Data("{\"alt\":true}".utf8), for: "https://example.invalid/x")

        let stub = StubTransport([.success(.status(404))])
        let sut = CachingTransport(wrapping: stub, cache: store)

        let response = try await sut.send(request("https://example.invalid/x"))
        XCTAssertEqual(response.status, 404)
        XCTAssertNil(response.cachedAt)
    }

    /// Schreibanfragen werden nie zwischengespeichert -- ein erneut
    /// ausgeliefertes POST wuerde einen Beitrag vortaeuschen, der nie ankam.
    func testWritesAreNeverCached() async throws {
        let store = cache()
        let stub = StubTransport(json: "{\"id\":1}")
        let sut = CachingTransport(wrapping: stub, cache: store)

        _ = try await sut.send(request("https://example.invalid/prices", method: "POST"))

        let entry = await store.load(for: "https://example.invalid/prices")
        XCTAssertNil(entry)
    }

    func testErrorResponsesAreNotStored() async throws {
        let store = cache()
        let stub = StubTransport([.success(.status(500))])
        let sut = CachingTransport(wrapping: stub, cache: store)

        _ = try? await sut.send(request("https://example.invalid/x"))

        let entry = await store.load(for: "https://example.invalid/x")
        XCTAssertNil(entry, "Ein Serverfehler darf nicht als gueltige Antwort gelten")
    }

    func testCallbacksReportFreshAndCached() async throws {
        let store = cache()
        await store.store(Data("{}".utf8), for: "https://example.invalid/x")

        let recorder = CallbackRecorder()

        let fresh = CachingTransport(wrapping: StubTransport(json: "{}"),
                                     cache: store,
                                     onCacheHit: { _ in recorder.markCached() },
                                     onFreshResponse: { recorder.markFresh() })
        _ = try await fresh.send(request("https://example.invalid/x"))
        XCTAssertTrue(recorder.sawFresh)
        XCTAssertFalse(recorder.sawCached)

        let offline = CachingTransport(wrapping: StubTransport([.failure(.offline)]),
                                       cache: store,
                                       onCacheHit: { _ in recorder.markCached() },
                                       onFreshResponse: { recorder.markFresh() })
        _ = try await offline.send(request("https://example.invalid/x"))
        XCTAssertTrue(recorder.sawCached)
    }
}

/// Kleiner Mitschreiber fuer die Rueckrufe.
private final class CallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var fresh = false
    private var cached = false

    var sawFresh: Bool { lock.lock(); defer { lock.unlock() }; return fresh }
    var sawCached: Bool { lock.lock(); defer { lock.unlock() }; return cached }

    func markFresh() { lock.lock(); fresh = true; lock.unlock() }
    func markCached() { lock.lock(); cached = true; lock.unlock() }
}
