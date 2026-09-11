import MapKit
import SwiftUI
import PriceCore

/// Wählt einen Ort von Hand (#14).
///
/// Der Weg für alle, die den Standort nicht freigeben wollen – und auf dem
/// Mac der Hauptweg, weil die Ortung dort nur WLAN-basiert und ungenau ist.
///
/// Gesucht wird über `MKLocalSearch` aus MapKit. Das ist in iOS enthalten,
/// kostet nichts und braucht keinen Schlüssel – anders als externe
/// Geocoding-Dienste.
struct ManualPlaceSheet: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var query = ""
    @State private var results: [Place] = []
    @State private var isSearching = false
    @State private var message: String?

    struct Place: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let detail: String?
        let latitude: Double
        let longitude: Double

        var coordinate: Coordinate {
            Coordinate(latitude: latitude, longitude: longitude)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Stadt oder Adresse", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                } footer: {
                    Text("Der gewählte Ort hat Vorrang vor der Ortung. Entfernungen und "
                         + "Filialen beziehen sich dann auf ihn.")
                }
                .listRowBackground(Theme.surface)

                if isSearching {
                    Section {
                        HStack {
                            ProgressView().tint(Theme.accent)
                            Text("Suche …").foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .listRowBackground(Theme.surface)
                }

                if let message {
                    Section {
                        Text(message)
                            .font(.cardBody)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.surface)
                }

                if !results.isEmpty {
                    Section("Treffer") {
                        ForEach(results) { place in
                            Button {
                                choose(place)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(place.name)
                                        .foregroundStyle(Theme.textPrimary)
                                    if let detail = place.detail {
                                        Text(detail)
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.ink)
            .navigationTitle("Ort wählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func search() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        isSearching = true
        message = nil
        results = []
        defer { isSearching = false }

        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.resultTypes = [.address, .pointOfInterest]

        do {
            let response = try await MKLocalSearch(request: request).start()
            let found = response.mapItems.compactMap { item -> Place? in
                let coordinate = item.placemark.coordinate
                let candidate = Coordinate(latitude: coordinate.latitude,
                                           longitude: coordinate.longitude)
                // Ein Treffer ohne brauchbare Koordinate nützt nichts.
                guard candidate.isValid else { return nil }

                let name = item.name
                    ?? item.placemark.locality
                    ?? trimmed
                let detail = [item.placemark.postalCode, item.placemark.locality,
                              item.placemark.country]
                    .compactMap { $0 }
                    .joined(separator: ", ")

                return Place(name: name,
                             detail: detail.isEmpty ? nil : detail,
                             latitude: coordinate.latitude,
                             longitude: coordinate.longitude)
            }

            results = found
            if found.isEmpty {
                message = "Zu „\(trimmed)“ wurde kein Ort gefunden."
            }
        } catch {
            // Der Dienst antwortet auch mit einem Fehler, wenn es schlicht
            // keine Treffer gibt -- deshalb hier keine dramatische Meldung.
            message = "Die Ortssuche war nicht erfolgreich. Prüfe die Schreibweise "
                    + "oder die Internetverbindung."
        }
    }

    private func choose(_ place: Place) {
        let settings = appEnvironment.settings
        settings.manualPlaceName = place.name
        settings.manualLatitude = place.latitude
        settings.manualLongitude = place.longitude
        dismiss()
    }
}
