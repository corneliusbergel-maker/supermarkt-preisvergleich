import MapKit
import SwiftUI
import PriceCore

/// Filialen in der Umgebung: Karte und Liste (#13).
struct StoresView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var model = StoresViewModel()
    @State private var camera: MapCameraPosition = .automatic
    @State private var routeTarget: Store?

    private var isWide: Bool { sizeClass != .compact }

    private let radiusOptions: [Double] = [1, 2, 5, 10]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                content
            }
            .padding(.horizontal, isWide ? Theme.Spacing.xl : Theme.Spacing.l)
            .floatingTabBarInset(isCompact: !isWide)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.ink)
        .navigationTitle("Filialen")
        .task { await model.load(using: appEnvironment) }
        .sheet(item: $routeTarget) { store in
            RouteSheet(store: store)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {

        case .idle, .loading:
            GlassCard {
                HStack(spacing: Theme.Spacing.m) {
                    ProgressView().tint(Theme.accent)
                    Text("Filialen werden gesucht …")
                        .font(.cardBody)
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, Theme.Spacing.l)
            }

        case .needsLocation:
            GlassCard {
                EmptyState(
                    symbol: "location.slash",
                    title: "Kein Bezugspunkt",
                    message: "Ohne Standort lässt sich nicht sagen, welche Märkte in deiner "
                           + "Nähe liegen. Gib den Standort frei oder wähle einen Ort von "
                           + "Hand – beides funktioniert.",
                    actionTitle: appEnvironment.location.authorization == .notDetermined
                        ? "Standort freigeben" : nil
                ) {
                    appEnvironment.location.requestPermission()
                }
                .frame(maxWidth: .infinity)
            }

        case .failed(let message, let isRetryable):
            GlassCard {
                EmptyState(symbol: "exclamationmark.triangle",
                           title: "Filialen nicht abrufbar",
                           message: message,
                           actionTitle: isRetryable ? "Erneut versuchen" : nil) {
                    Task { await model.load(using: appEnvironment) }
                }
                .frame(maxWidth: .infinity)
            }

        case .empty:
            radiusPicker
            GlassCard {
                EmptyState(
                    symbol: "mappin.slash",
                    title: "Keine Märkte im Umkreis",
                    message: "Im Radius von \(Int(model.radiusKm)) km ist keine Filiale "
                           + "eingetragen, die zu deinen ausgewählten Ketten passt. "
                           + "Vergrößere den Radius oder erlaube mehr Märkte in den "
                           + "Einstellungen."
                )
                .frame(maxWidth: .infinity)
            }

        case .stores(let entries):
            radiusPicker
            mapCard(entries)
            list(entries)
            attribution
        }
    }

    // MARK: - Radius

    private var radiusPicker: some View {
        HStack(spacing: Theme.Spacing.s) {
            ForEach(radiusOptions, id: \.self) { radius in
                Button {
                    Task { await model.load(using: appEnvironment, radiusKm: radius) }
                } label: {
                    Text("\(Int(radius)) km")
                        .font(.caption)
                        .foregroundStyle(model.radiusKm == radius ? Theme.ink : Theme.textSecondary)
                        .padding(.horizontal, Theme.Spacing.m)
                        .padding(.vertical, Theme.Spacing.s)
                        .background {
                            if model.radiusKm == radius {
                                Capsule().fill(Theme.accentFill)
                            } else {
                                Capsule()
                                    .fill(Theme.surface)
                                    .overlay(Capsule().strokeBorder(Theme.surfaceStroke,
                                                                    lineWidth: 1))
                            }
                        }
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: - Karte

    private func mapCard(_ entries: [StoresViewModel.Entry]) -> some View {
        Map(position: $camera) {
            ForEach(entries) { entry in
                Marker(entry.store.displayName,
                       systemImage: "cart.fill",
                       coordinate: CLLocationCoordinate2D(
                           latitude: entry.store.coordinate.latitude,
                           longitude: entry.store.coordinate.longitude))
                .tint(Theme.accent)
            }

            // Nur zeichnen, wenn der Standort freigegeben ist -- sonst zeigt
            // MapKit gar nichts an, und die Anzeige wäre irreführend.
            if appEnvironment.location.authorization.allowsLocating {
                UserAnnotation()
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: isWide ? 320 : 240)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        )
    }

    // MARK: - Liste

    private func list(_ entries: [StoresViewModel.Entry]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            SectionHeader(title: "\(entries.count) \(entries.count == 1 ? "Filiale" : "Filialen")")

            ForEach(entries) { entry in
                StoreRow(entry: entry) { routeTarget = entry.store }
            }
        }
    }

    private var attribution: some View {
        Text("Filialdaten: © OpenStreetMap-Mitwirkende (ODbL). "
             + "Entfernungen sind Luftlinie, nicht Fahrstrecke.")
            .font(.caption)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Eine Filialzeile

struct StoreRow: View {

    let entry: StoresViewModel.Entry
    let onRoute: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.store.displayName)
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)

                if let address = entry.store.formattedAddress {
                    Text(address)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let hours = entry.store.openingHoursRaw {
                    // Roh aus OpenStreetMap. Die Syntax halb auszuwerten
                    // hieße, falsche Öffnungszeiten zu behaupten.
                    Label(hours, systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: Theme.Spacing.s)

            VStack(alignment: .trailing, spacing: Theme.Spacing.s) {
                if let meters = entry.distanceMeters {
                    Text(GeoDistance.formatted(meters: meters))
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }
                Button("Route", action: onRoute)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
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
