import SwiftUI

struct ShoppingListView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    private var isWide: Bool { sizeClass != .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {

                GlassCard {
                    EmptyState(
                        symbol: "checklist",
                        title: "Deine Einkaufsliste ist leer",
                        message: "Füge Produkte hinzu. Preisfuchs rechnet dann aus, "
                               + "in welchem Markt – oder in welcher Kombination aus "
                               + "wenigen Märkten – der ganze Einkauf am günstigsten wird.",
                        actionTitle: "Produkt hinzufügen"
                    ) {}
                    .frame(maxWidth: .infinity)
                }

                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    SectionHeader(title: "Wie optimiert wird")

                    GlassCard {
                        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                            strategyRow(symbol: "eurosign.circle",
                                        title: "Günstigste Variante",
                                        detail: "Jeder Posten dort, wo er am billigsten ist – "
                                              + "auch wenn das mehrere Märkte bedeutet.")
                            strategyRow(symbol: "bag",
                                        title: "Alles in einem Markt",
                                        detail: "Nur Märkte, für die zu jedem Posten ein Preis "
                                              + "bekannt ist. Lücken werden nicht hochgerechnet.")
                            strategyRow(symbol: "car",
                                        title: "Beste Kombination aus Preis und Weg",
                                        detail: "Rechnet die Fahrt mit ein. Die Annahme "
                                              + "(0,30 €/km, jeder Markt einzeln angefahren) "
                                              + "wird beim Ergebnis genannt.")
                        }
                    }
                }

                DevelopmentNotice(feature: "Die Preisberechnung für die Liste",
                                  dataSource: "Open Prices")
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
        .navigationTitle("Einkaufsliste")
    }

    private func strategyRow(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Theme.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.cardBody)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
