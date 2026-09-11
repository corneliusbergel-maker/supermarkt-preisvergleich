import SwiftUI
import PriceCore

/// Der Einkaufsmodus (#41): führt Markt für Markt durch den geplanten Einkauf.
///
/// Gedacht für die Situation, in der die App tatsächlich nützlich ist — mit
/// dem Wagen im Gang, nicht am Schreibtisch. Deshalb große Ziele zum Antippen,
/// wenig Text und eine sichtbare Restmenge.
struct ShoppingModeView: View {

    let plan: BasketPlan

    @Environment(\.dismiss) private var dismiss
    @State private var currentStoreIndex = 0
    @State private var checkedItemIDs: Set<String> = []
    @State private var routeTarget: Store?

    private var baskets: [StoreBasket] { plan.baskets }

    private var currentBasket: StoreBasket? {
        baskets.indices.contains(currentStoreIndex) ? baskets[currentStoreIndex] : nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()

                if let basket = currentBasket {
                    content(for: basket)
                } else {
                    EmptyState(symbol: "checkmark.circle",
                               title: "Nichts zu erledigen",
                               message: "Dieser Plan enthält keine Märkte.")
                }
            }
            .navigationTitle("Einkauf")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
            .sheet(item: $routeTarget) { store in
                RouteSheet(store: store)
            }
        }
    }

    private func content(for basket: StoreBasket) -> some View {
        VStack(spacing: 0) {
            header(for: basket)

            ScrollView {
                VStack(spacing: Theme.Spacing.s) {
                    ForEach(basket.lines, id: \.item.id) { line in
                        itemRow(line)
                    }
                }
                .padding(Theme.Spacing.l)
            }

            footer(for: basket)
        }
    }

    // MARK: - Kopf

    private func header(for basket: StoreBasket) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(basket.displayName)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("Markt \(currentStoreIndex + 1) von \(baskets.count)")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }

            HStack(spacing: Theme.Spacing.m) {
                if let total = basket.total {
                    Text(total.roundedToCents.formatted())
                        .font(.priceDisplay(20))
                        .foregroundStyle(.white)
                }
                if let meters = basket.distanceMeters {
                    Text(GeoDistance.formatted(meters: meters))
                        .font(.cardBody)
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                if let store = basket.store {
                    Button {
                        routeTarget = store
                    } label: {
                        Label("Route", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.ink)
                            .padding(.horizontal, Theme.Spacing.m)
                            .padding(.vertical, Theme.Spacing.s)
                            .background(Theme.accentFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            ProgressView(value: Double(doneCount(in: basket)),
                         total: Double(max(1, basket.lines.count)))
                .tint(.white)
        }
        .padding(Theme.Spacing.l)
        .background(Theme.hero)
    }

    // MARK: - Posten

    private func itemRow(_ line: BasketLine) -> some View {
        let isChecked = checkedItemIDs.contains(line.item.id)

        return Button {
            // Großzügiges Ziel: Die ganze Zeile schaltet um, nicht nur das
            // Kästchen. Im Laden tippt man ungenau.
            if isChecked {
                checkedItemIDs.remove(line.item.id)
            } else {
                checkedItemIDs.insert(line.item.id)
            }
        } label: {
            HStack(spacing: Theme.Spacing.m) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 28))
                    .foregroundStyle(isChecked ? Theme.accent : Theme.textTertiary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(line.item.displayName)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(isChecked ? Theme.textTertiary : Theme.textPrimary)
                        .strikethrough(isChecked)
                        .multilineTextAlignment(.leading)

                    if line.item.count > 1 {
                        Text("\(line.item.count) ×")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer(minLength: Theme.Spacing.s)

                VStack(alignment: .trailing, spacing: 2) {
                    Text(line.lineTotal.roundedToCents.formatted())
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)

                    if let unitPrice = line.offer.unitPrice {
                        Text(unitPrice.formatted())
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(Theme.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile,
                                                            style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(isChecked ? Theme.accent.opacity(0.35) : Theme.surfaceStroke,
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isChecked ? [.isSelected, .isButton] : .isButton)
    }

    // MARK: - Fuß

    private func footer(for basket: StoreBasket) -> some View {
        VStack(spacing: Theme.Spacing.s) {
            if let remaining = remainingText(in: basket) {
                Text(remaining)
                    .font(.cardBody)
                    .foregroundStyle(Theme.textSecondary)
            }

            HStack(spacing: Theme.Spacing.m) {
                if currentStoreIndex > 0 {
                    Button("Zurück") {
                        currentStoreIndex -= 1
                    }
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textSecondary)
                }

                if currentStoreIndex < baskets.count - 1 {
                    Button {
                        currentStoreIndex += 1
                    } label: {
                        Label("Nächster Markt", systemImage: "arrow.right")
                            .font(.cardTitle)
                            .foregroundStyle(Theme.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.m)
                            .background(Theme.accentFill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        dismiss()
                    } label: {
                        Label("Einkauf beenden", systemImage: "checkmark")
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
        .padding(Theme.Spacing.l)
        .background(Theme.ink)
    }

    // MARK: - Innereien

    private func doneCount(in basket: StoreBasket) -> Int {
        basket.lines.filter { checkedItemIDs.contains($0.item.id) }.count
    }

    private func remainingText(in basket: StoreBasket) -> String? {
        let open = basket.lines.count - doneCount(in: basket)
        switch open {
        case 0: return "Hier ist alles erledigt."
        case 1: return "Noch 1 Posten in diesem Markt."
        default: return "Noch \(open) Posten in diesem Markt."
        }
    }
}
