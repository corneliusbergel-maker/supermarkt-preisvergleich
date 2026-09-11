import SwiftData
import SwiftUI
import PriceCore

struct ShoppingListView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var context
    @Environment(\.horizontalSizeClass) private var sizeClass

    @Query(sort: \ShoppingListEntry.addedAt, order: .forward)
    private var entries: [ShoppingListEntry]

    @State private var model = ShoppingListViewModel()
    @State private var shoppingMode: PlanBox?

    /// Führt aus dem leeren Zustand in die Suche.
    var onSearch: () -> Void = {}

    private var isWide: Bool { sizeClass != .compact }

    /// `BasketPlan` ist nicht `Identifiable` -- fuer `.sheet(item:)` braucht es
    /// eine Huelle mit eigener Kennung.
    struct PlanBox: Identifiable {
        let id = UUID()
        let plan: BasketPlan
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                if entries.isEmpty {
                    emptyState
                } else {
                    itemList
                    optimiseSection
                }
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
        .navigationTitle("Einkaufsliste")
        .navigationDestination(for: Product.self) { product in
            ProductDetailView(product: product)
        }
        .sheet(item: $shoppingMode) { box in
            ShoppingModeView(plan: box.plan)
        }
    }

    // MARK: - Posten

    private var itemList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "\(entries.count) \(entries.count == 1 ? "Posten" : "Posten")")

            ForEach(entries) { entry in
                ShoppingListRow(
                    entry: entry,
                    onToggle: { toggle(entry) },
                    onIncrement: { changeCount(entry, by: 1) },
                    onDecrement: { changeCount(entry, by: -1) },
                    onDelete: { remove(entry) }
                )
            }
        }
    }

    // MARK: - Optimierung

    private var optimiseSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            switch model.state {

            case .idle:
                Button {
                    Task { await model.optimise(entries: entries, using: appEnvironment) }
                } label: {
                    Label("Günstigsten Einkauf berechnen", systemImage: "function")
                        .font(.cardTitle)
                        .foregroundStyle(Theme.ink)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.m)
                        .background(Theme.accentFill, in: Capsule())
                }
                .buttonStyle(.plain)

            case .loading(let done, let total):
                GlassCard {
                    VStack(spacing: Theme.Spacing.s) {
                        ProgressView(value: Double(done), total: Double(total))
                            .tint(Theme.accent)
                        Text("Preise werden geladen … \(done) von \(total)")
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

            case .plans(let plans):
                plansView(plans)

            case .noData:
                GlassCard {
                    EmptyState(
                        symbol: "eurosign.circle",
                        title: "Keine Preisdaten für diese Liste",
                        message: "Zu keinem Posten liegt in deiner Reichweite ein belegter "
                               + "Preis vor. Prüfe Umkreis und ausgewählte Märkte – oder trage "
                               + "Preise bei, wenn du sie im Markt siehst."
                    )
                    .frame(maxWidth: .infinity)
                }

            case .failed(let message):
                GlassCard {
                    EmptyState(symbol: "exclamationmark.triangle",
                               title: "Berechnung nicht möglich",
                               message: message,
                               actionTitle: "Erneut versuchen") {
                        Task { await model.optimise(entries: entries, using: appEnvironment) }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func plansView(_ plans: [BasketPlan]) -> some View {
        SectionHeader(title: "Vorschläge", actionTitle: "Neu berechnen") {
            Task { await model.optimise(entries: entries, using: appEnvironment) }
        }

        ForEach(Array(plans.enumerated()), id: \.offset) { _, plan in
            PlanCard(plan: plan, assumedCost: model.assumedCostPerKilometer) {
                shoppingMode = PlanBox(plan: plan)
            }
        }

        if !model.itemsWithoutPrice.isEmpty {
            GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Label("Nicht eingerechnet", systemImage: "exclamationmark.circle")
                        .font(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Für diese Posten liegt kein belegter Preis vor: "
                         + model.itemsWithoutPrice.joined(separator: ", ") + ". "
                         + "Die Summen oben decken sie nicht ab.")
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }

        if !model.coverage.isEmpty {
            GlassCard(padding: Theme.Spacing.l, radius: Theme.Radius.tile) {
                VStack(alignment: .leading, spacing: Theme.Spacing.s) {
                    Text("Abdeckung je Markt")
                        .font(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    ForEach(model.coverage.prefix(6), id: \.name) { entry in
                        HStack {
                            Text(entry.name)
                                .font(.cardBody)
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Text("\(entry.covered) von \(entry.total)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(entry.covered == entry.total
                                                 ? Theme.accent : Theme.textTertiary)
                        }
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        GlassCard {
            EmptyState(
                symbol: "checklist",
                title: "Deine Einkaufsliste ist leer",
                message: "Füge Produkte über die Suche hinzu. Preisfuchs rechnet dann aus, "
                       + "in welchem Markt – oder in welcher Kombination aus wenigen Märkten – "
                       + "der ganze Einkauf am günstigsten wird.",
                // Ohne Knopf war der leere Tab eine Sackgasse.
                actionTitle: "Produkt suchen"
            ) {
                onSearch()
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Bearbeiten

    private func toggle(_ entry: ShoppingListEntry) {
        entry.isChecked.toggle()
        try? context.save()
    }

    private func changeCount(_ entry: ShoppingListEntry, by delta: Int) {
        entry.count = max(1, entry.count + delta)
        try? context.save()
        model.reset()          // Die alte Rechnung gilt nicht mehr.
    }

    private func remove(_ entry: ShoppingListEntry) {
        context.delete(entry)
        try? context.save()
        model.reset()
    }
}

// MARK: - Eine Zeile

struct ShoppingListRow: View {

    let entry: ShoppingListEntry
    let onToggle: () -> Void
    let onIncrement: () -> Void
    let onDecrement: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.m) {
            Button(action: onToggle) {
                Image(systemName: entry.isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(entry.isChecked ? Theme.accent : Theme.textTertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(entry.isChecked ? "Erledigt" : "Offen")

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.cardTitle)
                    .foregroundStyle(entry.isChecked ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(entry.isChecked)
                    .lineLimit(1)

                if let quantityText = entry.quantityText {
                    Text(quantityText)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            HStack(spacing: Theme.Spacing.s) {
                Button(action: onDecrement) {
                    Image(systemName: "minus")
                }
                .disabled(entry.count <= 1)

                Text("\(entry.count)")
                    .font(.cardTitle)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .frame(minWidth: 20)

                Button(action: onIncrement) {
                    Image(systemName: "plus")
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.m)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile,
                                                        style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        )
        .contextMenu {
            Button("Entfernen", systemImage: "trash", role: .destructive, action: onDelete)
        }
    }
}

// MARK: - Ein Einkaufsplan

struct PlanCard: View {

    let plan: BasketPlan
    let assumedCost: Money?

    /// Startet den Einkaufsmodus mit genau diesem Plan.
    let onStartShopping: () -> Void

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                HStack(alignment: .firstTextBaseline) {
                    Text(plan.strategy.label)
                        .font(.cardTitle)
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(plan.total.roundedToCents.formatted())
                        .font(.priceDisplay(24))
                        .foregroundStyle(Theme.accent)
                }

                Text("\(plan.storeCount) \(plan.storeCount == 1 ? "Markt" : "Märkte") · "
                     + "\(plan.coveredItemCount) \(plan.coveredItemCount == 1 ? "Posten" : "Posten")")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                ForEach(plan.baskets) { basket in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(basket.displayName)
                                .font(.cardBody)
                                .foregroundStyle(Theme.textPrimary)
                            if let meters = basket.distanceMeters {
                                Text("· \(GeoDistance.formatted(meters: meters))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            if let total = basket.total {
                                Text(total.roundedToCents.formatted())
                                    .font(.cardBody)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        Text(basket.lines.map(\.item.displayName).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                }

                if plan.strategy == .bestValue, let assumedCost {
                    Text("Bei angenommenen \(assumedCost.formatted())/km, jeder Markt einzeln "
                         + "angefahren. Das ist eine Obergrenze – eine Rundfahrt wäre kürzer.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !plan.isComplete {
                    Text("Deckt nicht die ganze Liste ab.")
                        .font(.caption)
                        .foregroundStyle(Theme.deal)
                }

                Button(action: onStartShopping) {
                    Label("Einkauf starten", systemImage: "cart.fill")
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
