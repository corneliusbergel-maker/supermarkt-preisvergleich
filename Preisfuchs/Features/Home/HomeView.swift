import SwiftData
import SwiftUI
import PriceCore

/// Die Startseite: persoenliches Preis-Dashboard.
///
/// Solange keine Datenquelle angebunden ist, stehen hier ehrliche
/// Leerzustaende -- keine Beispielpreise. Das ist Absicht und entspricht
/// Anforderung #38.
struct HomeView: View {

    @Binding var path: NavigationPath
    @Binding var selection: Destination

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: \FavoriteProduct.addedAt, order: .reverse)
    private var favorites: [FavoriteProduct]

    @State private var query = ""
    @State private var isScanning = false
    @State private var favoritesModel = FavoritesViewModel()

    private var isWide: Bool { sizeClass != .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                heroSection
                quickActions
                favoritesSection
                dealsSection
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
        .navigationTitle("Start")
        .toolbar(isWide ? .visible : .hidden, for: .navigationBar)
        .navigationDestination(for: Product.self) { product in
            ProductDetailView(product: product)
        }
        .sheet(isPresented: $isScanning) {
            BarcodeScanSheet { product in
                path.append(product)
            }
        }
    }

    // MARK: - Kopfbereich mit Verlauf

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            Text("Preisfuchs")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))

            Text("Was möchtest du\nvergleichen?")
                .font(.system(size: isWide ? 38 : 30, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            searchField
        }
        .padding(isWide ? Theme.Spacing.xl : Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(isWide ? Theme.heroWide : Theme.hero)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        )
        .padding(.top, Theme.Spacing.s)
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.m) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.white.opacity(0.7))

            TextField("Produkt suchen", text: $query)
                .textFieldStyle(.plain)
                .foregroundStyle(.white)
                .submitLabel(.search)
                .onSubmit { selection = .search }

            if Platform.supportsBarcodeScanner {
                Divider()
                    .frame(height: 20)
                    .overlay(Color.white.opacity(0.25))
                Button {
                    isScanning = true
                } label: {
                    Image(systemName: "barcode.viewfinder")
                        .foregroundStyle(.white.opacity(0.85))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Barcode scannen")
            }
        }
        .padding(.horizontal, Theme.Spacing.m)
        .padding(.vertical, Theme.Spacing.m)
        .background(.black.opacity(0.28), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 1))
    }

    // MARK: - Schnellaktionen

    private var quickActions: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.m)],
            spacing: Theme.Spacing.m
        ) {
            ActionTile(symbol: "magnifyingglass", title: "Suchen") {
                selection = .search
            }

            // Auf dem Mac gibt es keinen Barcode-Scanner. Die Kachel wird
            // deshalb gar nicht erst gezeigt statt tot dazustehen.
            if Platform.supportsBarcodeScanner {
                ActionTile(symbol: "barcode.viewfinder", title: "Scannen") {
                    isScanning = true
                }
            }

            ActionTile(symbol: "checklist", title: "Einkaufsliste") {
                selection = .shoppingList
            }
            ActionTile(symbol: "star", title: "Favoriten") {
                selection = .favorites
            }
        }
    }

    // MARK: - Favoriten

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            if favorites.isEmpty {
                SectionHeader(title: "Deine Favoriten")
                GlassCard {
                    EmptyState(
                        symbol: "star",
                        title: "Noch keine Favoriten",
                        message: "Markiere Produkte als Favorit. Sie erscheinen dann hier "
                               + "mit ihrem aktuell günstigsten Preis.",
                        actionTitle: "Produkt suchen"
                    ) {
                        selection = .search
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                SectionHeader(title: "Deine Favoriten", actionTitle: "Alle") {
                    selection = .favorites
                }
                ForEach(shownFavorites) { favorite in
                    NavigationLink(value: favorite.product) {
                        FavoriteRow(product: favorite.product,
                                    state: favoritesModel.state(for: favorite.product))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .task(id: favorites.count) {
            guard !shownFavorites.isEmpty else { return }
            await favoritesModel.refresh(products: shownFavorites.map(\.product),
                                         using: appEnvironment)
        }
    }

    /// Auf der Startseite nur die zuletzt hinzugefügten. Jeder Eintrag kostet
    /// eine Anfrage – die vollständige Liste steht im eigenen Bereich.
    private var shownFavorites: [FavoriteProduct] {
        Array(favorites.prefix(4))
    }

    // MARK: - Deals

    private var dealsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Deine besten Deals")
            DevelopmentNotice(feature: "Die Angebotserkennung",
                              dataSource: "Open Prices")
        }
    }
}

#Preview {
    RootView()
        .environment(AppEnvironment())
}
