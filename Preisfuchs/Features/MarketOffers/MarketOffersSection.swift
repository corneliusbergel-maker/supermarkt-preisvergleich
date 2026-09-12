import SwiftUI
import PriceCore

/// Startseite: die größten Ersparnisse aus den Kaufland-Wochenangeboten.
struct MarketOffersSection: View {

    @Environment(AppEnvironment.self) private var appEnvironment

    /// Öffnet die vollständige Liste.
    let showAll: () -> Void

    private var store: MarketOffersStore { appEnvironment.marketOffers }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            let current = store.currentOffers
            if current.isEmpty {
                SectionHeader(title: "Kaufland-Angebote")
            } else {
                SectionHeader(title: "Kaufland-Angebote",
                              actionTitle: "Alle \(current.count)",
                              action: showAll)
            }

            content

            MarketOffersSourceNote(fetchedAt: store.fetchedAt)
        }
        // Stündlich und beim Herunterziehen neu – `refreshTick` kommt aus der
        // App-Umgebung.
        .task(id: appEnvironment.refreshTick) {
            await store.refresh()
        }
    }

    @ViewBuilder
    private var content: some View {
        let top = store.topOffers(limit: 4)
        if !top.isEmpty {
            ForEach(top) { offer in
                Button(action: showAll) {
                    MarketOfferRow(offer: offer)
                }
                .buttonStyle(.plain)
            }
        } else {
            switch store.state {
            case .idle, .loading:
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    HStack(spacing: Theme.Spacing.m) {
                        ProgressView().tint(Theme.accent)
                        Text("Kaufland-Angebote werden geladen …")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

            case .failed(let message, let isRetryable):
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text(message)
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if isRetryable {
                            Button("Erneut versuchen") {
                                Task { await store.refresh(force: true) }
                            }
                            .font(.cardTitle)
                            .foregroundStyle(Theme.accent)
                        }
                    }
                }

            case .loaded:
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    Text("Kaufland hat für heute keine gültigen Angebote veröffentlicht.")
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
