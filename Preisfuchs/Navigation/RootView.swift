import SwiftUI

/// Ziele, die kein eigener Hauptbereich sind, aber angesteuert werden koennen.
enum AppRoute: Hashable {
    case stores
    case marketOffers
}

/// Die fuenf Hauptbereiche der App.
enum Destination: String, CaseIterable, Identifiable, Hashable {
    case home
    case search
    case shoppingList
    case favorites
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Start"
        case .search: return "Suche"
        case .shoppingList: return "Einkaufsliste"
        case .favorites: return "Favoriten"
        case .settings: return "Einstellungen"
        }
    }

    /// Kurzform fuer die schmale Tab-Leiste auf dem iPhone.
    var shortTitle: String {
        switch self {
        case .shoppingList: return "Liste"
        case .settings: return "Mehr"
        default: return title
        }
    }

    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .search: return "magnifyingglass"
        case .shoppingList: return "checklist"
        case .favorites: return "star.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

/// Wurzelansicht. Entscheidet allein anhand der verfuegbaren Breite, ob die
/// Tab-Leiste oder die Seitenleiste gezeigt wird -- nicht anhand des
/// Geraetetyps. Dadurch bekommt auch ein iPhone im Querformat und ein
/// schmales Fenster auf dem Mac das jeweils passende Layout.
struct RootView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.scenePhase) private var scenePhase

    @State private var selection: Destination = LaunchOptions.initialDestination ?? .home
    @State private var path = NavigationPath()
    @State private var searchHandoff: String?

    var body: some View {
        Group {
            if sizeClass == .compact {
                compactLayout
            } else {
                regularLayout
            }
        }
        .background(Theme.ink.ignoresSafeArea())
        .tint(Theme.accent)
        .safeAreaInset(edge: .top) {
            // Sagt ausdruecklich, wenn gerade zwischengespeicherte Daten
            // gezeigt werden. Ohne diesen Hinweis waere der Zwischenspeicher
            // eine Luege -- die Preise saehen aus wie eben geladen.
            if let text = appEnvironment.freshness.bannerText {
                offlineBanner(text)
            }
        }
        // Für Bildschirmfotos in der CI. Ohne Startparameter passiert nichts;
        // Produkt und Preise kommen aus den echten APIs.
        .task {
            if let route = LaunchOptions.initialRoute {
                path.append(route)
            }
            guard let barcode = LaunchOptions.initialBarcode else { return }
            // Open Food Facts antwortet unter Last gelegentlich nicht. Ein
            // Bildschirmfoto ohne Produktseite sagt dann nichts über die App.
            for attempt in 1...3 {
                if let product = try? await appEnvironment.products.product(barcode: barcode) {
                    path.append(product)
                    return
                }
                try? await Task.sleep(for: .seconds(2 * attempt))
            }
        }
        // Jeder Tab beginnt bei seiner Wurzel. Alle Tabs teilen sich einen
        // Navigationspfad; ohne dieses Zurücksetzen blieb eine geöffnete
        // Produktseite beim Tabwechsel stehen, und die Tab-Leiste wirkte,
        // als reagiere sie nicht.
        .onChange(of: selection) { _, _ in
            path = NavigationPath()
        }
        // Stündlich neu laden, solange die App offen ist – und beim
        // Zurückkehren, wenn der letzte Stand älter als eine Stunde ist.
        .task { await appEnvironment.runHourlyRefresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { appEnvironment.refreshIfStale() }
        }
    }

    private func offlineBanner(_ text: String) -> some View {
        HStack(spacing: Theme.Spacing.s) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(.horizontal, Theme.Spacing.l)
        .padding(.vertical, Theme.Spacing.s)
        .frame(maxWidth: .infinity)
        .background(Theme.deal.opacity(0.22))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Theme.deal.opacity(0.5))
                .frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - iPhone hochkant

    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            NavigationStack(path: $path) {
                screen(for: selection)
                    .navigationBarTitleDisplayMode(.inline)
            }

            PillTabBar(selection: $selection)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.bottom, Theme.Spacing.s)
        }
    }

    // MARK: - iPad, Mac, iPhone quer

    private var regularLayout: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                ForEach(Destination.allCases) { destination in
                    Label(destination.title, systemImage: destination.symbol)
                        .tag(destination)
                }
            }
            .navigationTitle("Preisfuchs")
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
        } detail: {
            NavigationStack(path: $path) {
                screen(for: selection)
            }
        }
    }

    /// Die Seitenleiste braucht eine optionale Auswahl -- auf dem iPad kann
    /// die Auswahl leer sein, waehrend die App intern immer einen Bereich
    /// anzeigt. Eine Leerauswahl setzt den Bereich deshalb nicht zurueck.
    private var sidebarSelection: Binding<Destination?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue { selection = newValue }
            }
        )
    }

    @ViewBuilder
    private func screen(for destination: Destination) -> some View {
        switch destination {
        // Start und Suche koennen nach einem Scan direkt auf die Produktseite
        // springen und brauchen dafuer den Navigationspfad.
        case .home: HomeView(path: $path, selection: $selection, searchHandoff: $searchHandoff)
        case .search: SearchView(path: $path, searchHandoff: $searchHandoff)
        case .shoppingList: ShoppingListView(onSearch: { selection = .search })
        case .favorites: FavoritesView(onSearch: { selection = .search })
        case .settings: SettingsView()
        }
    }
}

/// Die schwebende Tab-Leiste aus den Referenzbildern: abgerundete Pille,
/// aktiver Eintrag als Kapsel mit Symbol und Beschriftung.
struct PillTabBar: View {

    @Binding var selection: Destination

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Destination.allCases) { destination in
                item(for: destination)
            }
        }
        .padding(Theme.Spacing.s)
        // Hintergrund, Kontur und Schatten liegen bewusst auf der Form und
        // nicht auf der Leiste selbst. Ein .shadow() auf dem Inhalt wuerde
        // die Cyan-Kapsel des aktiven Eintrags mit einfaerben und die ganze
        // Leiste gruenlich ueberstrahlen.
        .background {
            Capsule()
                .fill(Color(red: 0.075, green: 0.075, blue: 0.088))
                .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 1))
                .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
        }
    }

    private func item(for destination: Destination) -> some View {
        let isSelected = selection == destination

        return Button {
            withAnimation(.snappy(duration: 0.28)) { selection = destination }
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 15, weight: .semibold))
                if isSelected {
                    Text(destination.shortTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(isSelected ? Theme.ink : Theme.textSecondary)
            .padding(.horizontal, isSelected ? Theme.Spacing.m : Theme.Spacing.s)
            .padding(.vertical, 10)
            .background {
                if isSelected {
                    Capsule().fill(Theme.accentFill)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }
}
