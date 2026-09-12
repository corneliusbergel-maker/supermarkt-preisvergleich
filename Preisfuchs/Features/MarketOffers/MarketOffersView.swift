import SwiftUI
import PriceCore

/// Alle Angebote direkt von den Ketten, durchsuchbar und nach Kette filterbar.
struct MarketOffersView: View {

    enum Period: String, CaseIterable, Identifiable {
        case current = "Aktuell"
        case upcoming = "Demnächst"
        var id: String { rawValue }
    }

    private static let allChains = "alle"

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var query = ""
    @State private var period: Period = .current
    @State private var chain = MarketOffersView.allChains

    private var isWide: Bool { sizeClass != .compact }
    private var store: MarketOffersStore { appEnvironment.marketOffers }

    private var enabledSources: [MarketOffersStore.Source] {
        store.enabledSources(appEnvironment.settings)
    }

    private var selectedSources: [MarketOffersStore.Source] {
        chain == Self.allChains ? enabledSources : enabledSources.filter { $0.id == chain }
    }

    private var shown: [RetailerOffer] {
        let base = period == .current
            ? store.currentOffers(from: selectedSources)
            : store.upcomingOffers(from: selectedSources)
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return base }
        return base.filter { offer in
            [offer.title, offer.subtitle, offer.details]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(term) }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.m) {
                searchField

                if enabledSources.count > 1 {
                    Picker("Kette", selection: $chain) {
                        Text("Alle").tag(Self.allChains)
                        ForEach(enabledSources) { source in
                            Text(source.displayName).tag(source.id)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Picker("Zeitraum", selection: $period) {
                    ForEach(Period.allCases) { period in
                        Text(period.rawValue).tag(period)
                    }
                }
                .pickerStyle(.segmented)

                MarketOffersSourceNote(sources: selectedSources, store: store)

                list

                if selectedSources.count == 1, let source = selectedSources.first {
                    Link(destination: source.pageURL) {
                        Label("Angebotsseite von \(source.displayName) öffnen",
                              systemImage: "arrow.up.right.square")
                            .font(.cardBody)
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, Theme.Spacing.s)
                }
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
        .navigationTitle("Angebote der Märkte")
        .refreshable { await store.refresh(enabledSources, force: true) }
        .task { await store.refresh(enabledSources) }
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.textTertiary)
            TextField("Angebote durchsuchen", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.textPrimary)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, 12)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 1))
        .padding(.top, Theme.Spacing.s)
    }

    @ViewBuilder
    private var list: some View {
        let offers = shown
        if !offers.isEmpty {
            Text(offers.count == 1 ? "1 Angebot" : "\(offers.count) Angebote")
                .font(.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            ForEach(offers) { offer in
                MarketOfferRow(offer: offer)
            }
        } else {
            switch store.combinedState(of: selectedSources) {
            case .idle, .loading:
                GlassCard {
                    HStack(spacing: Theme.Spacing.m) {
                        ProgressView().tint(Theme.accent)
                        Text("Angebote werden geladen …")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

            case .failed(let message, let isRetryable):
                GlassCard {
                    EmptyState(symbol: "exclamationmark.triangle",
                               title: "Angebote nicht abrufbar",
                               message: message,
                               actionTitle: isRetryable ? "Erneut versuchen" : nil) {
                        Task { await store.refresh(selectedSources, force: true) }
                    }
                    .frame(maxWidth: .infinity)
                }

            case .loaded:
                GlassCard {
                    EmptyState(symbol: "tag",
                               title: query.isEmpty ? "Keine Angebote" : "Nichts gefunden",
                               message: query.isEmpty
                                   ? "Für diesen Zeitraum sind keine Angebote veröffentlicht."
                                   : "Kein Angebot passt zu „\(query)“.")
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
