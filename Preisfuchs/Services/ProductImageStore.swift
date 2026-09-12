import CryptoKit
import Foundation
import PriceData

/// Lädt Produktbilder und stellt sie frei – jedes Bild nur einmal.
///
/// Freigestellte Bilder landen im Cache-Verzeichnis. Das System darf es bei
/// Speichermangel leeren; dann wird eben neu gerechnet.
actor ProductImageStore {

    static let shared = ProductImageStore()

    struct Loaded: Sendable {
        let data: Data
        let isCutout: Bool
    }

    private let directory: URL
    private var inFlight: [URL: Task<Loaded?, Never>] = [:]

    /// Einmal gescheitert heißt: Vision läuft auf diesem Gerät nicht (etwa
    /// im Simulator). Jedes weitere Bild zeigt dann direkt das Original.
    private var cutoutUnavailable = false

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("ProductCutouts", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func image(for url: URL) async -> Loaded? {
        // Dieselbe Adresse erscheint oft mehrfach gleichzeitig, etwa in
        // Suche und Favoriten. Gerechnet wird trotzdem nur einmal.
        if let running = inFlight[url] { return await running.value }

        let task = Task { await load(url) }
        inFlight[url] = task
        let result = await task.value
        inFlight[url] = nil
        return result
    }

    private func load(_ url: URL) async -> Loaded? {
        let key = Self.key(for: url)
        let cutoutFile = directory.appendingPathComponent(key + ".png")
        let noSubjectFile = directory.appendingPathComponent(key + ".none")

        if let cached = try? Data(contentsOf: cutoutFile) {
            return Loaded(data: cached, isCutout: true)
        }

        guard let original = await download(url) else { return nil }

        if cutoutUnavailable || FileManager.default.fileExists(atPath: noSubjectFile.path) {
            return Loaded(data: original, isCutout: false)
        }

        do {
            switch try ProductCutout.cutout(imageData: original) {
            case .cutout(let png):
                try? png.write(to: cutoutFile, options: .atomic)
                return Loaded(data: png, isCutout: true)
            case .noSubject:
                FileManager.default.createFile(atPath: noSubjectFile.path, contents: nil)
                return Loaded(data: original, isCutout: false)
            }
        } catch {
            cutoutUnavailable = true
            return Loaded(data: original, isCutout: false)
        }
    }

    private func download(_ url: URL) async -> Data? {
        var request = URLRequest(url: url)
        request.setValue(APIIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              !data.isEmpty else { return nil }
        return data
    }

    private static func key(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
