import Foundation
import Observation
import PriceCore
import PriceData

/// Steuert die Produktsuche.
@MainActor
@Observable
final class SearchViewModel {

    /// Was die Ansicht gerade zeigen soll.
    ///
    /// „Nichts gefunden" und „Suche gescheitert" sind bewusst zwei
    /// verschiedene Zustaende. Einen Serverfehler als leeres Ergebnis
    /// darzustellen waere eine Falschaussage ueber die Datenlage.
    enum State {
        case idle
        case searching
        case results([ProductGroup])
        case noResults(query: String)
        case failed(message: String, isRetryable: Bool)
    }

    /// Ein Artikel mit allen Schreibweisen, unter denen er gefunden wurde.
    struct ProductGroup: Identifiable {
        let representative: Product
        let variants: [Product]

        var id: String { representative.id }
        var sourceCount: Int { variants.count }
    }

    var query: String = ""
    private(set) var state: State = .idle

    private let client: OpenFoodFactsClient

    /// Wartezeit, bevor getippter Text zu einer Anfrage wird.
    ///
    /// Ohne sie loest jeder Tastendruck eine Abfrage aus -- das belastet einen
    /// gemeinnuetzig betriebenen Dienst ohne jeden Nutzen.
    private let debounce: Duration

    /// Der Client ist zustandslos, deshalb ist die Voreinstellung unbedenklich.
    /// Der Parameter bleibt, damit sich in Tests ein anderer einsetzen laesst.
    init(client: OpenFoodFactsClient = OpenFoodFactsClient(),
         debounce: Duration = .milliseconds(350)) {
        self.client = client
        self.debounce = debounce
    }

    /// Fuehrt die Suche zum aktuellen `query` aus.
    ///
    /// Wird ueber `.task(id:)` an den Text gebunden; tippt der Nutzer weiter,
    /// bricht SwiftUI den laufenden Aufruf ab, und die Wartezeit unten sorgt
    /// dafuer, dass es gar nicht erst zur Anfrage kommt.
    func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count >= 2 else {
            state = .idle
            return
        }

        do {
            try await Task.sleep(for: debounce)
        } catch {
            return          // abgebrochen, weil weitergetippt wurde
        }

        state = .searching

        do {
            let found = try await client.search(trimmed)
            guard !Task.isCancelled else { return }

            let groups = ProductMatcher.group(found).compactMap { group -> ProductGroup? in
                guard let representative = group.first else { return nil }
                return ProductGroup(representative: representative, variants: group)
            }

            state = groups.isEmpty ? .noResults(query: trimmed) : .results(groups)

        } catch let error as DataSourceError {
            guard !Task.isCancelled, error != .cancelled else { return }
            state = .failed(message: error.userMessage, isRetryable: error.offersManualRetry)
        } catch {
            guard !Task.isCancelled else { return }
            state = .failed(message: "Die Suche ist fehlgeschlagen.", isRetryable: true)
        }
    }

    /// Erneuter Versuch nach einem Fehler -- ohne Wartezeit, der Nutzer hat
    /// gerade bewusst getippt.
    func retry() async {
        state = .searching
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            state = .idle
            return
        }
        do {
            let found = try await client.search(trimmed)
            let groups = ProductMatcher.group(found).compactMap { group -> ProductGroup? in
                guard let representative = group.first else { return nil }
                return ProductGroup(representative: representative, variants: group)
            }
            state = groups.isEmpty ? .noResults(query: trimmed) : .results(groups)
        } catch let error as DataSourceError {
            state = .failed(message: error.userMessage, isRetryable: error.offersManualRetry)
        } catch {
            state = .failed(message: "Die Suche ist fehlgeschlagen.", isRetryable: true)
        }
    }
}
