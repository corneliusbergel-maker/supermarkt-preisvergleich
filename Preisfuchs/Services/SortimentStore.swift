import Foundation
import Observation
import PriceCore
import PriceData

/// Regalpreise aus dem ALDI-SÜD-Sortiment – langsam geladen, dauerhaft gespeichert.
///
/// Regalpreise ändern sich selten. Deshalb lädt die App das Sortiment höchstens
/// einmal am Tag, Seite für Seite mit Pausen – so belastet sie ALDI SÜD nicht
/// mehr als ein Mensch, der durch die Kategorien blättert. Bricht ein Durchlauf
/// ab, geht es beim nächsten Anstoß an derselben Kategorie weiter.
@MainActor
@Observable
final class SortimentStore {

    struct Item: Codable {
        let id: String
        let title: String
        let subtitle: String?
        /// Betrag als Text – verlustfrei, anders als eine Gleitkommazahl.
        let price: String
        let unit: String?
        let basePriceText: String?
        let deposit: String?
        let sourceURL: URL
        let fetchedAt: Date
    }

    private struct Snapshot: Codable {
        var items: [String: Item] = [:]
        var completedPaths: [String] = []
        var lastCompletedAt: Date?
    }

    static let refreshInterval: TimeInterval = 24 * 60 * 60
    /// Was so lange nicht mehr auf der Seite stand, fällt heraus.
    static let maximumAge: TimeInterval = 7 * 24 * 60 * 60
    static let pause: Duration = .seconds(2)
    static let maximumPagesPerCategory = 30

    /// Das Sortiment als Angebote ohne Enddatum, bereit für den Abgleich.
    private(set) var items: [RetailerOffer] = []
    private(set) var isRunning = false

    var lastCompletedAt: Date? { snapshot.lastCompletedAt }

    private let client: AldiSuedCatalogClient
    private let fileURL: URL
    private var snapshot: Snapshot

    init(client: AldiSuedCatalogClient) {
        self.client = client
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        fileURL = base.appendingPathComponent("aldi-sued-sortiment.json")
        snapshot = (try? Data(contentsOf: fileURL))
            .flatMap { try? JSONDecoder().decode(Snapshot.self, from: $0) } ?? Snapshot()
        items = Self.offers(from: snapshot.items)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard !isRunning else { return }
        if snapshot.completedPaths.isEmpty, let last = snapshot.lastCompletedAt,
           now.timeIntervalSince(last) < Self.refreshInterval {
            return
        }

        isRunning = true
        defer { isRunning = false }

        guard let paths = try? await client.categoryPaths() else { return }

        for path in paths where !snapshot.completedPaths.contains(path) {
            var number = 1
            while number <= Self.maximumPagesPerCategory {
                guard !Task.isCancelled,
                      let page = try? await client.page(path: path, number: number) else {
                    // Abgebrochen oder gerade nicht erreichbar: Stand sichern und
                    // beim nächsten Anstoß an dieser Kategorie weitermachen.
                    publishAndSave()
                    return
                }
                let fetchedAt = Date()
                for offer in page.items {
                    snapshot.items[offer.id] = Item(offer, fetchedAt: fetchedAt)
                }
                guard page.hasMore else { break }
                number += 1
                try? await Task.sleep(for: Self.pause)
            }
            snapshot.completedPaths.append(path)
            publishAndSave()
            try? await Task.sleep(for: Self.pause)
        }

        let cutoff = Date().addingTimeInterval(-Self.maximumAge)
        snapshot.items = snapshot.items.filter { $0.value.fetchedAt >= cutoff }
        snapshot.completedPaths = []
        snapshot.lastCompletedAt = Date()
        publishAndSave()
    }

    private func publishAndSave() {
        items = Self.offers(from: snapshot.items)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private static func offers(from items: [String: Item]) -> [RetailerOffer] {
        items.values.compactMap { item in
            guard let amount = Decimal(string: item.price), amount > 0 else { return nil }
            return RetailerOffer(
                id: item.id,
                retailerName: AldiSuedCatalogClient.retailerName,
                title: item.title,
                subtitle: item.subtitle,
                price: Money(amount: amount),
                unit: item.unit,
                basePriceText: item.basePriceText,
                deposit: item.deposit.flatMap { Decimal(string: $0) }.map { Money(amount: $0) },
                validFrom: item.fetchedAt,
                validTo: nil,
                sourceURL: item.sourceURL
            )
        }
    }
}

extension SortimentStore.Item {
    init(_ offer: RetailerOffer, fetchedAt: Date) {
        id = offer.id
        title = offer.title
        subtitle = offer.subtitle
        price = "\(offer.price?.amount ?? 0)"
        unit = offer.unit
        basePriceText = offer.basePriceText
        deposit = offer.deposit.map { "\($0.amount)" }
        sourceURL = offer.sourceURL
        self.fetchedAt = fetchedAt
    }
}
