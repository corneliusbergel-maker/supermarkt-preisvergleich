import SwiftUI

struct FavoritesView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isWide: Bool { sizeClass != .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                GlassCard {
                    EmptyState(
                        symbol: "star",
                        title: "Noch keine Favoriten",
                        message: "Markierte Produkte erscheinen hier mit ihrem günstigsten "
                               + "Preis, der Entfernung zum Markt und der Preisentwicklung.",
                        actionTitle: "Produkt suchen"
                    ) {}
                    .frame(maxWidth: .infinity)
                }

                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Label("Jeder Preis nennt seinen Stand", systemImage: "checkmark.seal")
                            .font(.cardTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Preisfuchs zeigt nie einen Betrag ohne Datum. Ist ein Preis "
                             + "älter oder unbelegt, steht das dabei – und wo gar nichts "
                             + "vorliegt, steht „keine Preisdaten“ statt einer Zahl.")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: Theme.Spacing.s) {
                            ConfidenceBadge(level: .confirmed, freshness: "heute")
                            ConfidenceBadge(level: .stale, freshness: "vor 6 Wochen")
                        }
                        .padding(.top, Theme.Spacing.xs)
                    }
                }
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
        .navigationTitle("Favoriten")
    }
}
