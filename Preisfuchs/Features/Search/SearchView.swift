import SwiftUI
import PriceCore

struct SearchView: View {

    @Binding var path: NavigationPath

    /// Von der Startseite übergebener Suchbegriff. Wird beim Erscheinen
    /// übernommen und dann geleert.
    @Binding var searchHandoff: String?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var model = SearchViewModel()
    @State private var isScanning = false

    private var isWide: Bool { sizeClass != .compact }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                scannerRow
                content
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
        .navigationTitle("Suche")
        // Ausdrücklich oben verankert. Ohne Angabe legt iOS das Suchfeld an
        // den unteren Rand – dort sitzt aber unsere schwebende Tab-Leiste,
        // und beide überdecken sich.
        .searchable(text: $model.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Produkt suchen")
        .navigationDestination(for: Product.self) { product in
            ProductDetailView(product: product)
        }
        .sheet(isPresented: $isScanning) {
            BarcodeScanSheet { product in
                path.append(product)
            }
        }
        // Übernimmt einen auf der Startseite getippten Begriff. Der
        // CI-Startparameter (-uiQuery) dient nur Bildschirmfotos; die Suche
        // läuft in beiden Fällen ganz normal gegen die echte API.
        .task {
            if let handed = searchHandoff, !handed.isEmpty {
                model.query = handed
                searchHandoff = nil
            } else if let query = LaunchOptions.initialSearchQuery, model.query.isEmpty {
                model.query = query
            }
        }
        // An den Suchtext gebunden: Tippt der Nutzer weiter, bricht SwiftUI
        // den laufenden Aufruf ab, bevor daraus eine Anfrage wird.
        .task(id: model.query) { await model.search() }
    }

    // MARK: - Scanner

    @ViewBuilder
    private var scannerRow: some View {
        if Platform.supportsBarcodeScanner {
            ActionTile(symbol: "barcode.viewfinder", title: "Barcode scannen") {
                isScanning = true
            }
        } else {
            GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                Label("Barcode-Scannen ist nur auf iPhone und iPad verfügbar.",
                      systemImage: "info.circle")
                    .font(.cardBody)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: - Zustände

    @ViewBuilder
    private var content: some View {
        switch model.state {

        case .idle:
            GlassCard {
                EmptyState(
                    symbol: "magnifyingglass",
                    title: "Wonach suchst du?",
                    message: "Gib mindestens zwei Zeichen ein – zum Beispiel „Nutella“, "
                           + "„Milch“ oder „Barilla“."
                )
                .frame(maxWidth: .infinity)
            }

        case .searching:
            GlassCard {
                HStack(spacing: Theme.Spacing.m) {
                    ProgressView().tint(Theme.accent)
                    Text("Suche in der Produktdatenbank …")
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Theme.Spacing.l)
            }

        case .results(let groups):
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "\(groups.count) \(groups.count == 1 ? "Artikel" : "Artikel") gefunden")
                ForEach(groups) { group in
                    NavigationLink(value: group.representative) {
                        ProductRow(product: group.representative)
                    }
                    .buttonStyle(.plain)
                }
                attributionNote
            }

        case .noResults(let query):
            GlassCard {
                EmptyState(
                    symbol: "questionmark.circle",
                    title: "Nichts zu „\(query)“ gefunden",
                    message: "Die Produktdatenbank kennt dieses Produkt nicht – oder es ist "
                           + "anders benannt. Versuch es mit der Marke, oder scanne den "
                           + "Barcode."
                )
                .frame(maxWidth: .infinity)
            }

        case .failed(let message, let isRetryable):
            GlassCard {
                EmptyState(
                    symbol: "exclamationmark.triangle",
                    title: "Suche nicht möglich",
                    message: message,
                    actionTitle: isRetryable ? "Erneut versuchen" : nil
                ) {
                    Task { await model.retry() }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var attributionNote: some View {
        Text("Produktdaten: Open Food Facts (ODbL)")
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .padding(.top, Theme.Spacing.xs)
    }
}

// MARK: - Ergebniszeile

/// Ein Suchtreffer.
///
/// Zeigt bewusst **keinen** Preis: Für jeden Treffer einzeln Preise zu laden
/// hieße, bei zwanzig Ergebnissen zwanzig Anfragen zu stellen. Der Preis
/// steht auf der Detailseite – dort, wo er auch verglichen wird.
struct ProductRow: View {

    let product: Product

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            thumbnail

            VStack(alignment: .leading, spacing: 3) {
                if let brand = product.brand?.split(separator: ",").first {
                    Text(brand.trimmingCharacters(in: .whitespaces))
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }

                Text(product.name)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if let quantity = product.quantity {
                    Text(quantity.formatted())
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    // Ohne Menge kein Grundpreis - und das wird gesagt.
                    Text("Packungsgröße unbekannt")
                        .font(.cardBody)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            Spacer(minLength: 0)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(Theme.Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile,
                                                        style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        )
    }

    private var thumbnail: some View {
        // Produktbilder fehlen bei vielen Datensätzen. Der Platzhalter ist
        // deshalb der Normalfall, nicht die Ausnahme.
        AsyncImage(url: product.imageURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                Image(systemName: "shippingbox")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(width: 52, height: 52)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12,
                                                              style: .continuous))
    }
}
