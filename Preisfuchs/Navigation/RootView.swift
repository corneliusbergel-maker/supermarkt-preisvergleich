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
    @State private var selection: Destination = .home

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
    }

    // MARK: - iPhone hochkant

    private var compactLayout: some View {
        ZStack(alignment: .bottom) {
            NavigationStack {
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
            List(Destination.allCases, selection: $selection) { destination in
                NavigationLink(value: destination) {
                    Label(destination.title, systemImage: destination.symbol)
                }
            }
            .navigationTitle("Preisfuchs")
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
        } detail: {
            NavigationStack {
                screen(for: selection)
            }
        }
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
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 1))
        .shadow(color: .black.opacity(0.45), radius: 18, y: 8)
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
