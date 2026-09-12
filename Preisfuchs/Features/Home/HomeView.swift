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

    /// Übergibt den auf der Startseite getippten Suchbegriff an den Such-Tab.
    @Binding var searchHandoff: String?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppEnvironment.self) private var appEnvironment

    @Query(sort: \FavoriteProduct.addedAt, order: .reverse)
    private var favorites: [FavoriteProduct]

    @State private var query = ""
    @State private var isScanning = false
    @State private var favoritesModel = FavoritesViewModel()
    @State private var dealsModel = DealsViewModel()

    private var isWide: Bool { sizeClass != .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                heroSection
                // Ohne Bezugspunkt bleiben Deals, Filialen und Entfernungen
                // leer. Die Frage danach gehört deshalb ganz nach oben.
                if !appEnvironment.hasLocation {
                    LocationPromptCard()
                }
                quickActions
                favoritesSection
                dealsSection
                if appEnvironment.settings.isEnabled(retailerNamed: MarketOffersStore.retailerName) {
                    MarketOffersSection {
                        path.append(AppRoute.marketOffers)
                    }
                }
                retailerOffersSection
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .refreshable { appEnvironment.refreshNow() }
        .background(Theme.ink)
        .navigationTitle("Start")
        .toolbar(isWide ? .visible : .hidden, for: .navigationBar)
        .navigationDestination(for: Product.self) { product in
            ProductDetailView(product: product)
        }
        .navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .stores: StoresView()
            case .marketOffers: MarketOffersView()
            }
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
                .onSubmit {
                    // Der Begriff muss mit in den Such-Tab. Vorher ging er beim
                    // Wechsel verloren, und die Suche stand leer da.
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    searchHandoff = trimmed
                    query = ""
                    selection = .search
                }

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
            // Keine eigene Favoriten-Kachel: Die Tab-Leiste führt schon dorthin,
            // und die Favoriten stehen direkt darunter. Mit ihr waren es fünf
            // Kacheln im Zweierraster – die letzte stand verwaist allein.
            ActionTile(symbol: "mappin.and.ellipse", title: "Filialen") {
                path.append(AppRoute.stores)
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
        .task(id: reloadKey) {
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

    /// Wann Favoriten und Deals neu geladen werden: wenn sich die Favoriten
    /// oder der Bezugspunkt ändern – und stündlich über `refreshTick`.
    ///
    /// Vorher hing es nur an den Favoriten. Traf der Standort erst nach dem
    /// Öffnen der Startseite ein – der Normalfall direkt nach der Freigabe –,
    /// blieb „Kein Bezugspunkt" stehen, bis man einen Favoriten hinzufügte.
    private var reloadKey: HomeReloadKey {
        HomeReloadKey(favoriteCount: favorites.count,
                      coordinate: appEnvironment.activeCoordinate,
                      refreshTick: appEnvironment.refreshTick)
    }

    // MARK: - Deals (#28)

    private var dealsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Deine besten Deals")

            switch dealsModel.state {

            case .idle, .loading:
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    HStack(spacing: Theme.Spacing.m) {
                        ProgressView().tint(Theme.accent)
                        Text("Angebote in deiner Nähe werden gesucht …")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

            case .needsLocation:
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Label("Kein Bezugspunkt", systemImage: "location.slash")
                            .font(.cardTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Angebote hängen davon ab, wo du bist. Gib den Standort frei "
                             + "oder wähle in den Einstellungen einen Ort.")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

            case .empty:
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    Text("Gerade sind keine Aktionspreise in deiner Nähe belegt. "
                         + "Angebote stehen nur dann hier, wenn sie jemand mit Beleg "
                         + "eingetragen hat – erfunden wird keines.")
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .failed(let message):
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    Text(message)
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

            case .deals(let deals):
                ForEach(deals) { deal in
                    if let product = deal.product {
                        NavigationLink(value: product) {
                            DealRow(deal: deal)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .task(id: reloadKey) {
            await dealsModel.load(using: appEnvironment,
                                  favoriteIDs: Set(favorites.map(\.productID)))
        }
    }

    // MARK: - Prospekte der Märkte

    /// Links zu den offiziellen Angebotsseiten der eingeschalteten Ketten.
    ///
    /// Die Seiten selbst liest Preisfuchs nicht aus (siehe
    /// `RetailerOffersPages`). Dort stehen die Angebote aber immer so aktuell,
    /// wie die Kette sie veröffentlicht – einen Tipp entfernt.
    private var retailerOffersSection: some View {
        let pages = RetailerOffersPages.all.filter {
            appEnvironment.settings.isEnabled(retailerNamed: $0.name)
        }

        return VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Prospekte der Märkte")

            if pages.isEmpty {
                GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                    Text("In den Einstellungen ist keine Kette mit eigener Angebotsseite "
                         + "eingeschaltet.")
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.s)],
                    spacing: Theme.Spacing.s
                ) {
                    ForEach(pages) { page in
                        Link(destination: page.url) {
                            HStack(spacing: Theme.Spacing.xs) {
                                // Passt der volle Name nicht, steht die kurze Form
                                // da. „Netto Marken-…“ las sich wie ein Fehler.
                                ViewThatFits(in: .horizontal) {
                                    Text(page.name)
                                    Text(page.shortName ?? page.name)
                                }
                                .font(.cardTitle)
                                .lineLimit(1)
                                .accessibilityLabel(page.name)
                                Spacer(minLength: Theme.Spacing.xs)
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, 12)
                            .background(Theme.surface,
                                        in: RoundedRectangle(cornerRadius: Theme.Radius.chip,
                                                             style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                                    .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
                            )
                        }
                        .accessibilityHint("Öffnet die Angebotsseite von \(page.name) im Browser")
                    }
                }

                Text("Die Angebote stehen tagesaktuell auf den Seiten der Märkte. Die von "
                     + "Kaufland holt Preisfuchs direkt in die App; die übrigen Ketten "
                     + "untersagen oder blockieren das Auslesen ihrer Seiten.")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Schlüssel für das Neuladen der Startseite.
private struct HomeReloadKey: Equatable {
    let favoriteCount: Int
    let coordinate: Coordinate?
    let refreshTick: Date
}

#Preview {
    RootView()
        .environment(AppEnvironment())
}
