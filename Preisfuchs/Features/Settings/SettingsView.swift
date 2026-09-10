import SwiftUI

struct SettingsView: View {

    /// Auswahl der Handelsketten (Anforderung #29).
    /// Noch ohne Speicherung -- die Anbindung an SwiftData folgt.
    @State private var enabledRetailers: Set<String> = [
        "REWE", "EDEKA", "Kaufland", "Lidl", "Aldi Süd", "Aldi Nord"
    ]

    /// Maximale Entfernung in Metern, `nil` heisst unbegrenzt (Anforderung #30).
    @State private var maxDistanceMeters: Double? = 5_000

    private let retailers = [
        "REWE", "EDEKA", "Kaufland", "Lidl", "Aldi Süd", "Aldi Nord",
        "Penny", "Netto Marken-Discount", "Norma"
    ]

    private let distanceOptions: [(label: String, meters: Double?)] = [
        ("1 km", 1_000), ("2 km", 2_000), ("5 km", 5_000),
        ("10 km", 10_000), ("25 km", 25_000), ("Unbegrenzt", nil)
    ]

    var body: some View {
        List {
            distanceSection
            retailerSection
            locationSection
            attributionSection
            aboutSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.ink)
        .navigationTitle("Einstellungen")
    }

    // MARK: - Entfernung

    private var distanceSection: some View {
        Section {
            Picker("Maximale Entfernung", selection: Binding(
                get: { maxDistanceMeters },
                set: { maxDistanceMeters = $0 }
            )) {
                ForEach(distanceOptions, id: \.label) { option in
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

    // MARK: - Händler

    private var retailerSection: some View {
        Section {
            ForEach(retailers, id: \.self) { retailer in
                Toggle(retailer, isOn: Binding(
                    get: { enabledRetailers.contains(retailer) },
                    set: { isOn in
                        if isOn { enabledRetailers.insert(retailer) }
                        else { enabledRetailers.remove(retailer) }
                    }
                ))
            }
        } header: {
            Text("Berücksichtigte Märkte")
        } footer: {
            Text("Abgewählte Ketten fließen nicht in den Preisvergleich ein.")
        }
        .listRowBackground(Theme.surface)
    }

    // MARK: - Standort

    private var locationSection: some View {
        Section {
            LabeledContent("Standort") {
                Text(Platform.prefersManualLocation ? "Manuell wählen" : "Noch nicht freigegeben")
                    .foregroundStyle(Theme.textSecondary)
            }
        } header: {
            Text("Standort")
        } footer: {
            Text(Platform.prefersManualLocation
                 ? "Auf dem Mac ist die Ortung nur WLAN-basiert und ungenau. "
                 + "Die manuelle Ortswahl liefert hier bessere Ergebnisse."
                 : "Der Standort wird ausschließlich zur Entfernungsberechnung genutzt "
                 + "und verlässt das Gerät nicht. Du kannst stattdessen auch einen Ort "
                 + "von Hand wählen.")
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
