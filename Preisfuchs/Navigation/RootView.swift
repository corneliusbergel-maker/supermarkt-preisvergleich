import SwiftUI

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

    @State private var selection: Destination = LaunchOptions.initialDestination ?? .home
    @State private var path = NavigationPath()

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
        // Für Bildschirmfotos in der CI. Ohne Startparameter passiert nichts;
        // Produkt und Preise kommen aus den echten APIs.
        .task {
            guard let barcode = LaunchOptions.initialBarcode,
                  let product = try? await appEnvironment.products.product(barcode: barcode)
            else { return }
            path.append(product)
        }
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
        case .home: HomeView()
        case .search: SearchView()
        case .shoppingList: ShoppingListView()
        case .favorites: FavoritesView()
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
