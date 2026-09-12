import SwiftUI
import PriceCore

/// Startseite: je Kette die ersten gültigen Angebote, direkt von der Kette.
struct MarketOffersSection: View {

    @Environment(AppEnvironment.self) private var appEnvironment

    /// Öffnet die vollständige Liste.
    let showAll: () -> Void

    /// Angebote je Kette auf der Startseite.
    private let perSource = 2

    private var store: MarketOffersStore { appEnvironment.marketOffers }

    var body: some View {
        let sources = store.enabledSources(appEnvironment.settings)
        let currentCount = store.currentOffers(from: sources).count

        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if currentCount == 0 {
                SectionHeader(title: "Angebote direkt vom Markt")
            } else {
                SectionHeader(title: "Angebote direkt vom Markt",
                              actionTitle: "Alle \(currentCount)",
                              action: showAll)
            }

            ForEach(sources) { source in
                sourceBlock(source)
            }

            MarketOffersSourceNote(sources: sources, store: store)
        }
        // Stündlich, beim Herunterziehen und wenn in den Einstellungen eine
        // Kette dazukommt.
        .task(id: ReloadKey(tick: appEnvironment.refreshTick, sources: sources.map(\.id))) {
            await store.refresh(sources)
        }
    }

    @ViewBuilder
    private func sourceBlock(_ source: MarketOffersStore.Source) -> some View {
        let status = store.status(of: source)
        let now = Date()
        let current = status.offers.filter { $0.isValid(on: now) }
        // Sonntags ist die Aktionswoche bei ALDI Nord schon vorbei. Dann die
        // ersten Angebote ab dem nächsten Aktionstag – die Zeile sagt „ab …“ –
        // statt einer Kachel „keine Angebote“.
        let top = Array((current.isEmpty ? status.offers.filter { $0.startsAfter(now) } : current)
            .prefix(perSource))

        if !top.isEmpty {
            ForEach(top) { offer in
                Button(action: showAll) {
                    MarketOfferRow(offer: offer)
                }
                .buttonStyle(.plain)
            }
        } else {
            switch status.state {
            case .idle, .loading:
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    HStack(spacing: Theme.Spacing.m) {
                        ProgressView().tint(Theme.accent)
                        Text("Angebote von \(source.displayName) werden geladen …")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

            case .failed(let message, let isRetryable):
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("\(source.displayName): \(message)")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if isRetryable {
                            Button("Erneut versuchen") {
                                Task { await store.refresh([source], force: true) }
                            }
                            .font(.cardTitle)
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }

            case .loaded:
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    Text("\(source.displayName) hat gerade keine Angebote veröffentlicht.")
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private struct ReloadKey: Equatable {
        let tick: Date
        let sources: [String]
    }
}
