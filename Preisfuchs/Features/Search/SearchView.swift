import SwiftUI

struct SearchView: View {

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var query = ""

    private var isWide: Bool { sizeClass != .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {

                if Platform.supportsBarcodeScanner {
                    ActionTile(symbol: "barcode.viewfinder",
                               title: "Barcode scannen") {}
                } else {
                    // Ehrlicher Hinweis statt einer Schaltflaeche, die nichts tut.
                    GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                        Label("Barcode-Scannen ist nur auf iPhone und iPad verfügbar.",
                              systemImage: "info.circle")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                DevelopmentNotice(feature: "Die Produktsuche",
                                  dataSource: "Open Food Facts")

                GlassCard {
                    VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                        Text("Wonach die Suche später unterscheidet")
                            .font(.cardTitle)
                            .foregroundStyle(Theme.textPrimary)
                        Text("Marke, Produktname, Variante und Packungsgröße werden "
                             + "getrennt behandelt. „Coca-Cola Zero“ wird nie mit "
                             + "„Coca-Cola Original“ zusammengeführt, und 500 g wird "
                             + "nie direkt gegen 1 kg verglichen – nur über den "
                             + "Grundpreis.")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
        .navigationTitle("Suche")
        .searchable(text: $query, prompt: "Produkt suchen")
    }
}
