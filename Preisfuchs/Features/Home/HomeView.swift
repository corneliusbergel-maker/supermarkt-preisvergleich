import SwiftUI

/// Die Startseite: persoenliches Preis-Dashboard.
///
/// Solange keine Datenquelle angebunden ist, stehen hier ehrliche
/// Leerzustaende -- keine Beispielpreise. Das ist Absicht und entspricht
/// Anforderung #38.
struct HomeView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var query = ""

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

            if Platform.supportsBarcodeScanner {
                Divider()
                    .frame(height: 20)
                    .overlay(Color.white.opacity(0.25))
                Image(systemName: "barcode.viewfinder")
                    .foregroundStyle(.white.opacity(0.85))
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
            ActionTile(symbol: "magnifyingglass", title: "Suchen") {}

            // Auf dem Mac gibt es keinen Barcode-Scanner. Die Kachel wird
            // deshalb gar nicht erst gezeigt statt tot dazustehen.
            if Platform.supportsBarcodeScanner {
                ActionTile(symbol: "barcode.viewfinder", title: "Scannen") {}
            }

            ActionTile(symbol: "checklist", title: "Einkaufsliste") {}
            ActionTile(symbol: "mappin.and.ellipse", title: "Filialen") {}
        }
    }

    // MARK: - Favoriten

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Deine Favoriten")

            GlassCard {
                EmptyState(
                    symbol: "star",
                    title: "Noch keine Favoriten",
                    message: "Markiere Produkte als Favorit. Sie erscheinen dann hier "
                           + "mit ihrem aktuell günstigsten Preis.",
                    actionTitle: "Produkt suchen"
                ) {}
                .frame(maxWidth: .infinity)
            }
        }
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
