import SwiftData
import SwiftUI
import PriceCore

struct FavoritesView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(sort: \FavoriteProduct.addedAt, order: .reverse)
    private var favorites: [FavoriteProduct]

    @State private var model = FavoritesViewModel()

    /// Führt aus dem leeren Zustand in die Suche.
    var onSearch: () -> Void = {}

    private var isWide: Bool { sizeClass != .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if favorites.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
        .navigationTitle("Favoriten")
        .navigationDestination(for: Product.self) { product in
            ProductDetailView(product: product)
        }
        .refreshable { await refresh() }
        // Neu laden, sobald der Bezugspunkt wechselt – und stündlich.
        .task(id: FavoritesReloadKey(coordinate: appEnvironment.activeCoordinate,
                                     refreshTick: appEnvironment.refreshTick)) {
            await refresh()
        }
        .toolbar {
            if !favorites.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(model.isRefreshing)
                }
            }
        }
    }

    private func refresh() async {
        await model.refresh(products: favorites.map(\.product), using: appEnvironment)
    }

    // MARK: - Liste

    private var list: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "\(favorites.count) \(favorites.count == 1 ? "Favorit" : "Favoriten")")

            ForEach(favorites) { favorite in
                NavigationLink(value: favorite.product) {
                    FavoriteRow(product: favorite.product,
                                state: model.state(for: favorite.product))
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button("Aus Favoriten entfernen", systemImage: "star.slash", role: .destructive) {
                        remove(favorite)
                    }
                }
            }

            if favorites.count > FavoritesViewModel.maximumProductsPerRefresh {
                Text("Preise werden für die \(FavoritesViewModel.maximumProductsPerRefresh) "
                     + "zuletzt hinzugefügten Favoriten geladen. Jede Abfrage belastet eine "
                     + "gemeinnützig betriebene Datenquelle.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Preisdaten: Open Prices (ODbL) · Entfernungen sind Luftlinie.")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var emptyState: some View {
        GlassCard {
            EmptyState(
                symbol: "star",
                title: "Noch keine Favoriten",
                message: "Markierte Produkte erscheinen hier mit ihrem günstigsten Preis, "
                       + "der Entfernung zum Markt und dem Stand der Daten.",
                // Ohne Knopf war der leere Tab eine Sackgasse.
                actionTitle: "Produkt suchen"
            ) {
                onSearch()
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func remove(_ favorite: FavoriteProduct) {
        model.forget(productID: favorite.productID)
        context.delete(favorite)
        try? context.save()
    }
}

private struct FavoritesReloadKey: Equatable {
    let coordinate: Coordinate?
    let refreshTick: Date
}

// MARK: - Eine Favoritenzeile

struct FavoriteRow: View {

    let product: Product
    let state: FavoritesViewModel.PriceState

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            ProductImage(url: product.imageURL, size: 48)

            VStack(alignment: .leading, spacing: 2) {
                Text(product.name)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                if let quantity = product.quantity {
                    Text(quantity.formatted())
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            priceColumn
        }
        .padding(Theme.Spacing.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile,
                                                        style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var priceColumn: some View {
        switch state {
        case .notLoaded:
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)

        case .loading:
            ProgressView().tint(Theme.accent)

        case .best(let offer):
            VStack(alignment: .trailing, spacing: 2) {
                Text(offer.price.roundedToCents.formatted())
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)

                Text(offer.observation.store?.displayName
                     ?? offer.observation.retailer?.name
                     ?? "Unbekannt")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if let meters = offer.distanceMeters {
                        Text(GeoDistance.formatted(meters: meters))
                    }
                    Text(offer.observation.freshnessDescription())
                }
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            }

        case .noData:
            // Kein Preis heißt kein Preis - hier steht bewusst keine Zahl.
            Text("Keine\nPreisdaten")
                .font(.caption)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.textTertiary)

        case .failed(let message):
            Text(message)
                .font(.caption)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(3)
        }
    }
}
