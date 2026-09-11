import SwiftUI
import PriceCore

struct SettingsView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isChoosingPlace = false

    var body: some View {
        @Bindable var settings = appEnvironment.settings

        List {
            distanceSection(settings)
            sortSection(settings)
            retailerSection
            locationSection
            travelCostSection(settings)
            attributionSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ink)
        .navigationTitle("Einstellungen")
        .sheet(isPresented: $isChoosingPlace) {
            ManualPlaceSheet()
        }
    }

    // MARK: - Umkreis (#30)

    private func distanceSection(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings

        return Section {
            Picker("Maximale Entfernung", selection: $settings.maxDistanceMeters) {
                ForEach(AppSettings.distanceOptions, id: \.label) { option in
                    Text(option.label).tag(option.meters)
                }
            }
        } header: {
            Text("Umkreis")
        } footer: {
            Text("Märkte ohne bekannte Entfernung werden bei gesetztem Umkreis "
                 + "ausgeblendet. Sie als „in Reichweite“ zu behandeln wäre geraten.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Sortierung (#31)

    private func sortSection(_ settings: AppSettings) -> some View {
        @Bindable var settings = settings

        return Section {
            Picker("Sortieren nach", selection: $settings.sortCriterion) {
                ForEach(PriceSortCriterion.allCases, id: \.self) { criterion in
                    Text(criterion.label).tag(criterion)
                }
            }
        } header: {
            Text("Preisvergleich")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Händler (#29)

    private var retailerSection: some View {
        Section {
            ForEach(AppSettings.selectableRetailers, id: \.self) { retailer in
                Toggle(retailer, isOn: Binding(
                    get: { appEnvironment.settings.isEnabled(retailerNamed: retailer) },
                    set: { _ in appEnvironment.settings.toggle(retailerNamed: retailer) }
                ))
            }
        } header: {
            Text("Berücksichtigte Märkte")
        } footer: {
            Text("Abgewählte Ketten fließen nicht in den Preisvergleich ein. "
                 + "Unterschiedliche Schreibweisen derselben Kette – etwa „Rewe“ "
                 + "und „REWE“ – werden dabei zusammengeführt.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Standort (#14, #34)

    private var locationSection: some View {
        Section {
            LabeledContent("Bezugspunkt") {
                Text(appEnvironment.activeLocationDescription ?? "Nicht gesetzt")
                    .foregroundStyle(Theme.textSecondary)
            }

            switch appEnvironment.location.authorization {
            case .notDetermined:
                Button("Standort freigeben") {
                    appEnvironment.location.requestPermission()
                }
            case .authorized:
                Button("Standort aktualisieren") {
                    appEnvironment.location.updateLocationOnce()
                }
                .disabled(appEnvironment.location.isLocating)
            case .denied, .restricted:
                Label("Standortzugriff nicht erlaubt", systemImage: "location.slash")
                    .foregroundStyle(Theme.textSecondary)
            }

            if let error = appEnvironment.location.lastError {
                Text(error)
                    .font(.cardBody)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button("Ort von Hand wählen") {
                isChoosingPlace = true
            }

            if appEnvironment.settings.manualPlaceName != nil {
                Button("Gewählten Ort entfernen", role: .destructive) {
                    appEnvironment.settings.clearManualPlace()
                }
            }
        } header: {
            Text("Standort")
        } footer: {
            Text(appEnvironment.location.authorization.explanation)
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Fahrtkosten

    private func travelCostSection(_ settings: AppSettings) -> some View {
        Section {
            LabeledContent("Angenommene Fahrtkosten") {
                Text(Money(amount: settings.costPerKilometer).formatted() + "/km")
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            Stepper("Anpassen",
                    value: Binding(
                        get: { NSDecimalNumber(decimal: settings.costPerKilometer).doubleValue },
                        set: { settings.costPerKilometer = Decimal($0) }
                    ),
                    in: 0...2, step: 0.05)
        } header: {
            Text("Weg einrechnen")
        } footer: {
            Text("Diese Zahl ist eine Annahme, kein Messwert. Sie geht in „Beste "
                 + "Kombination aus Preis und Weg“ ein und wird beim Ergebnis genannt. "
                 + "Gerechnet wird mit Hin- und Rückweg je Markt.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Datenquellen

    /// Namensnennung ist bei ODbL-Daten Lizenzpflicht, keine Höflichkeit.
    private var attributionSection: some View {
        Section {
            attributionRow(source: "Open Food Facts",
                           purpose: "Produktdaten, Barcodes, Packungsgrößen",
                           license: "ODbL")
            attributionRow(source: "Open Prices",
                           purpose: "Preisdaten mit Beleg",
                           license: "ODbL")
            attributionRow(source: "© OpenStreetMap-Mitwirkende",
                           purpose: "Filialen, Adressen, Öffnungszeiten",
                           license: "ODbL")
        } header: {
            Text("Datenquellen")
        } footer: {
            Text("Preisfuchs nutzt ausschließlich offene Datenquellen. Es werden keine "
                 + "Händler-Websites ausgelesen und keine kostenpflichtigen Preisdienste "
                 + "verwendet.")
        }
        .listRowBackground(Theme.surface)
    }

    private func attributionRow(source: String, purpose: String, license: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(source).font(.cardTitle)
                Spacer()
                Text(license)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(purpose)
                .font(.cardBody)
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.vertical, 2)
    }

    // MARK: - Über

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: appVersion)
            LabeledContent("Laufende Kosten", value: "keine")
        } header: {
            Text("Über")
        } footer: {
            Text("Die App kommt ohne Server, ohne Konto und ohne API-Schlüssel aus. "
                 + "Alle Anfragen gehen direkt von deinem Gerät an die offenen "
                 + "Datenquellen.")
        }
        .listRowBackground(Theme.surface)
    }

    private var appVersion: String {
        let bundle = Bundle.main
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (version?, build?): return "\(version) (\(build))"
        case let (version?, nil): return version
        default: return "unbekannt"
        }
    }
}
