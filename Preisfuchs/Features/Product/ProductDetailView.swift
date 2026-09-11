import Charts
import SwiftData
import SwiftUI
import PriceCore

struct ProductDetailView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var context

    // Beide Listen sind klein; sie ganz zu laden und im Speicher zu pruefen
    // ist einfacher und verlaesslicher als ein Praedikat mit eingefangenem Wert.
    @Query private var favorites: [FavoriteProduct]
    @Query private var listEntries: [ShoppingListEntry]
    @Query private var alerts: [PriceAlert]

    @State private var model: ProductDetailViewModel
    @State private var routeTarget: Store?
    @State private var isEditingAlert = false
    @State private var isContributing = false

    private var isWide: Bool { sizeClass != .compact }

    init(product: Product) {
        _model = State(initialValue: ProductDetailViewModel(product: product))
    }

    private var isFavorite: Bool {
        favorites.contains { $0.productID == model.displayProduct.id }
    }

    private var isOnShoppingList: Bool {
        listEntries.contains { $0.productID == model.displayProduct.id }
    }

    private var existingAlert: PriceAlert? {
        alerts.first { $0.productID == model.displayProduct.id }
    }

    /// Der günstigste gerade angezeigte Preis, falls es einen gibt.
    private var bestPrice: Money? {
        guard case .loaded(let comparison) = model.state else { return nil }
        return comparison.offers.first?.price
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                actionRow
                priceSection
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
        .navigationTitle(model.displayProduct.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load(using: appEnvironment) }
        .sheet(item: $routeTarget) { store in
            RouteSheet(store: store)
        }
        .sheet(isPresented: $isEditingAlert) {
            PriceAlertSheet(product: model.displayProduct,
                            currentBest: bestPrice,
                            existing: existingAlert)
        }
        .sheet(isPresented: $isContributing) {
            ContributePriceSheet(product: model.displayProduct)
        }
    }

    // MARK: - Kopf

    private var header: some View {
        GlassCard {
            HStack(alignment: .top, spacing: Theme.Spacing.l) {
                AsyncImage(url: model.displayProduct.imageURL) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit()
                    default:
                        Image(systemName: "shippingbox")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(width: 84, height: 84)
                .background(Theme.surfaceRaised,
                            in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if let brand = model.displayProduct.brand?.split(separator: ",").first {
                        Text(brand.trimmingCharacters(in: .whitespaces))
                            .font(.caption)
                            .foregroundStyle(Theme.accent)
                    }
                    Text(model.displayProduct.name)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let quantity = model.displayProduct.quantity {
                        Text(quantity.formatted())
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        Text("Packungsgröße unbekannt – kein Grundpreis möglich")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    // MARK: - Aktionen

    private var actionRow: some View {
        // Raster statt fester Zeile: Auf schmalen Geräten und bei großer
        // Schrift brechen die Knöpfe um, statt zu zerquetschen.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: Theme.Spacing.m)],
            spacing: Theme.Spacing.m
        ) {
            actionButton(
                title: isFavorite ? "Favorit" : "Favorisieren",
                symbol: isFavorite ? "star.fill" : "star",
                isActive: isFavorite,
                action: toggleFavorite
            )

            actionButton(
                title: isOnShoppingList ? "Auf der Liste" : "Zur Liste",
                symbol: isOnShoppingList ? "checkmark.circle.fill" : "plus.circle",
                isActive: isOnShoppingList,
                action: toggleShoppingList
            )

            actionButton(
                title: alertTitle,
                symbol: existingAlert == nil ? "bell" : "bell.fill",
                isActive: existingAlert != nil,
                action: { isEditingAlert = true }
            )
        }
    }

    private var alertTitle: String {
        guard let threshold = existingAlert?.threshold else { return "Preisalarm" }
        return "unter \(threshold.roundedToCents.formatted())"
    }

    private func actionButton(title: String,
                              symbol: String,
                              isActive: Bool,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.cardTitle)
                .foregroundStyle(isActive ? Theme.ink : Theme.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
                .background {
                    if isActive {
                        Capsule().fill(Theme.accentFill)
                    } else {
                        Capsule()
                            .fill(Theme.surface)
                            .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 1))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func toggleFavorite() {
        let product = model.displayProduct
        if let existing = favorites.first(where: { $0.productID == product.id }) {
            context.delete(existing)
        } else {
            context.insert(FavoriteProduct(product: product))
        }
        try? context.save()
    }

    private func toggleShoppingList() {
        let product = model.displayProduct
        if let existing = listEntries.first(where: { $0.productID == product.id }) {
            context.delete(existing)
        } else {
            context.insert(ShoppingListEntry(product: product))
        }
        try? context.save()
    }

    // MARK: - Preise

    @ViewBuilder
    private var priceSection: some View {
        switch model.state {

        case .idle, .loading:
            GlassCard {
                HStack(spacing: Theme.Spacing.m) {
                    ProgressView().tint(Theme.accent)
                    Text("Preise werden gesucht …")
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Theme.Spacing.l)
            }

        case .failed(let message, let isRetryable):
            GlassCard {
                EmptyState(symbol: "exclamationmark.triangle",
                           title: "Preise nicht abrufbar",
                           message: message,
                           actionTitle: isRetryable ? "Erneut versuchen" : nil) {
                    Task { await model.load(using: appEnvironment) }
                }
                .frame(maxWidth: .infinity)
            }

        case .loaded(let comparison):
            switch comparison {
            case .offers(let offers):
                offersView(offers)
            case .filteredOut(let total):
                filteredOutView(total: total)
            case .noData:
                noDataView
            }
        }
    }

    @ViewBuilder
    private func offersView(_ offers: [PriceOffer]) -> some View {
        if let best = offers.first {
            bestPriceCard(best)
        }

        if let history = model.history, let best = offers.first {
            historyCard(history, current: best.price)
        }

        if let detour = model.detour {
            detourCard(detour)
        }

        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "Alle Preise (\(offers.count))")
            ForEach(offers) { offer in
                OfferRow(offer: offer) { store in
                    routeTarget = store
                }
            }
            contributeLink
            sourceNote
        }
    }

    private func bestPriceCard(_ offer: PriceOffer) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack {
                    Text("Günstigster Preis")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    if offer.observation.isDiscounted {
                        Label("Angebot", systemImage: "flame.fill")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.s)
                            .padding(.vertical, Theme.Spacing.xs)
                            .background(Theme.deal, in: Capsule())
                    }
                }

                HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.s) {
                    Text(offer.price.roundedToCents.formatted())
                        .font(.priceDisplay(38))
                        .foregroundStyle(Theme.textPrimary)

                    if let unitPrice = offer.unitPrice {
                        Text(unitPrice.formatted())
                            .font(.cardBody)
                            .foregroundStyle(Theme.accent)
                    }
                }

                HStack(spacing: Theme.Spacing.s) {
                    Text(offer.observation.store?.displayName
                         ?? offer.observation.retailer?.name
                         ?? "Unbekannter Markt")
                        .font(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)

                    if let meters = offer.distanceMeters {
                        Text("· \(GeoDistance.formatted(meters: meters))")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                confidenceBadge(for: offer)

                if let store = offer.observation.store {
                    Button {
                        routeTarget = store
                    } label: {
                        Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.cardTitle)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.m)
                            .background(Theme.accentFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func confidenceBadge(for offer: PriceOffer) -> some View {
        let level: ConfidenceBadge.Level
        switch offer.confidence() {
        case .high: level = .confirmed
        case .medium: level = .current
        case .low, .none: level = .stale
        }
        return ConfidenceBadge(level: level,
                               freshness: offer.observation.freshnessDescription())
    }

    // MARK: - Verlauf (#10)

    private func historyCard(_ history: ProductDetailViewModel.History,
                             current: Money) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                SectionHeader(title: "Preisverlauf, \(history.days) Tage")

                Chart(history.points) { point in
                    LineMark(
                        x: .value("Datum", point.date),
                        y: .value("Preis", NSDecimalNumber(decimal: point.amount).doubleValue)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(Theme.accent)

                    PointMark(
                        x: .value("Datum", point.date),
                        y: .value("Preis", NSDecimalNumber(decimal: point.amount).doubleValue)
                    )
                    .foregroundStyle(Theme.accent)
                    .symbolSize(18)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 150)

                HStack {
                    statistic("Niedrigster", history.lowest)
                    Spacer()
                    statistic("Durchschnitt", history.average)
                    Spacer()
                    statistic("Höchster", history.highest)
                }

                if let assessment = history.assessment(of: current) {
                    Label(assessment, systemImage: "chart.line.downtrend.xyaxis")
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if history.isNearLow(current) {
                    Label("Gehört zu den niedrigsten Preisen dieses Zeitraums",
                          systemImage: "arrow.down.right.circle")
                        .font(.cardBody)
                        .foregroundStyle(Theme.accent)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("Beruht auf \(history.points.count) belegten Beobachtungen. "
                     + "Für einen aussagekräftigen Verlauf braucht es mindestens "
                     + "\(ProductDetailViewModel.History.minimumPoints).")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statistic(_ title: String, _ value: Money) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
            Text(value.roundedToCents.formatted())
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: - Lohnt sich der Umweg? (#16)

    private func detourCard(_ advice: DetourAdvice) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                Label(advice.isWorthIt ? "Der Umweg lohnt sich" : "Der Umweg lohnt sich kaum",
                      systemImage: advice.isWorthIt ? "car.fill" : "figure.walk")
                    .font(.cardTitle)
                    .foregroundStyle(advice.isWorthIt ? Theme.accent : Theme.textPrimary)

                Text(advice.explanation)
                    .font(.cardBody)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Leerzustände

    private var noDataView: some View {
        GlassCard {
            EmptyState(
                symbol: "eurosign.circle",
                title: "Keine Preisdaten in deiner Nähe",
                message: "Für dieses Produkt liegt hier kein belegter Preis vor. "
                       + "Die Preisdatenbank wird von Menschen gefüllt – wenn du den "
                       + "Preis im Markt siehst, kannst du ihn beitragen.",
                // Ohne Barcode lässt sich ein Preis nicht zuordnen; dann wird
                // der Knopf gar nicht erst angeboten.
                actionTitle: model.displayProduct.barcode == nil ? nil : "Preis beitragen"
            ) {
                isContributing = true
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// Auch wenn es schon Preise gibt, darf man einen neueren beitragen --
    /// gerade dann, wenn die vorhandenen als veraltet markiert sind.
    @ViewBuilder
    private var contributeLink: some View {
        if model.displayProduct.barcode != nil {
            Button {
                isContributing = true
            } label: {
                Label("Preis aus dem Markt beitragen", systemImage: "plus.viewfinder")
                    .font(.cardBody)
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func filteredOutView(total: Int) -> some View {
        GlassCard {
            EmptyState(
                symbol: "line.3.horizontal.decrease.circle",
                title: "Alle Preise sind ausgefiltert",
                message: "Es gibt \(total) \(total == 1 ? "Preis" : "Preise") zu diesem "
                       + "Produkt, aber keiner passt zu deinen Einstellungen – "
                       + "prüfe Umkreis und ausgewählte Märkte."
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var sourceNote: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Preisdaten: Open Prices (ODbL) · Filialen: © OpenStreetMap-Mitwirkende")
            Text("Preise sind von Nutzern erfasst und mit Foto belegt. "
                 + "Entfernungen sind Luftlinie, nicht Fahrstrecke.")
        }
        .font(.caption)
        .foregroundStyle(Theme.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.top, Theme.Spacing.xs)
    }
}

// MARK: - Eine Zeile im Vergleich

struct OfferRow: View {

    let offer: PriceOffer
    let onRoute: (Store) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(offer.observation.store?.displayName
                     ?? offer.observation.retailer?.name
                     ?? "Unbekannter Markt")
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)

                HStack(spacing: Theme.Spacing.s) {
                    if let meters = offer.distanceMeters {
                        Label(GeoDistance.formatted(meters: meters), systemImage: "location")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text(offer.observation.freshnessDescription())
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }

                if offer.observation.isDiscounted {
                    Label("Angebot", systemImage: "flame.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.deal)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            VStack(alignment: .trailing, spacing: 3) {
                Text(offer.price.roundedToCents.formatted())
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)

                if let unitPrice = offer.unitPrice {
                    Text(unitPrice.formatted())
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                if let store = offer.observation.store {
                    Button("Route") { onRoute(store) }
                        .font(.caption)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(Theme.Spacing.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile,
                                                        style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        )
    }
}

// MARK: - Routenauswahl

struct RouteSheet: View {

    let store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var mode: RouteLauncher.Mode = .driving

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Verkehrsmittel", selection: $mode) {
                        ForEach(RouteLauncher.Mode.allCases) { mode in
                            Label(mode.label, systemImage: mode.symbol).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text(store.displayName)
                } footer: {
                    if let address = store.formattedAddress {
                        Text(address)
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    Button {
                        RouteLauncher.openAppleMaps(store: store, mode: mode)
                        dismiss()
                    } label: {
                        Label("In Apple Karten öffnen", systemImage: "map.fill")
                    }

                    Button {
                        RouteLauncher.openGoogleMaps(store: store, mode: mode)
                        dismiss()
                    } label: {
                        Label(RouteLauncher.isGoogleMapsAppAvailable
                              ? "In Google Maps öffnen"
                              : "Google Maps im Browser öffnen",
                              systemImage: "globe")
                    }
                } footer: {
                    if let hours = store.openingHoursRaw {
                        Text("Öffnungszeiten laut OpenStreetMap: \(hours)")
                    }
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
            .navigationTitle("Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
