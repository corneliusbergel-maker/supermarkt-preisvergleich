import SwiftUI
import PriceCore
#if canImport(UIKit)
import UIKit
#endif

/// Bittet sichtbar um einen Bezugspunkt: Standort freigeben oder Ort wählen.
///
/// Ohne Bezugspunkt bleiben Deals und Filialen leer, und Entfernungen fehlen.
/// Auf dem ersten echten Gerät war das der Hauptgrund, warum die App leer
/// wirkte: Gefragt wurde nur an zwei versteckten Stellen, in den
/// Einstellungen und in der Filialansicht.
///
/// Beide Wege stehen gleichberechtigt nebeneinander. Wer die Ortung ablehnt,
/// soll nicht in einer Sackgasse landen.
struct LocationPromptCard: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var isChoosingPlace = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Label("Wo kaufst du ein?", systemImage: "location.fill")
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)

                Text(explanation)
                    .font(.cardBody)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let error = appEnvironment.location.lastError {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: Theme.Spacing.s) {
                    primaryAction

                    Button {
                        isChoosingPlace = true
                    } label: {
                        Text("Ort wählen")
                            .font(.cardTitle)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, Theme.Spacing.m)
                            .background(Theme.surfaceRaised, in: Capsule())
                            .overlay(Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(isPresented: $isChoosingPlace) {
            ManualPlaceSheet()
        }
    }

    private var authorization: LocationService.Authorization {
        appEnvironment.location.authorization
    }

    private var explanation: String {
        switch authorization {
        case .notDetermined:
            return "Preise, Deals und Filialen richten sich danach, wo du bist. "
                 + "Gib den Standort frei oder wähle einen Ort – zum Beispiel deine Stadt."
        case .authorized:
            return "Dein Standort wird gerade bestimmt. Alternativ kannst du einen Ort wählen."
        case .denied:
            return "Der Standortzugriff ist aus. Du kannst ihn in den iOS-Einstellungen "
                 + "erlauben – oder einfach einen Ort wählen."
        case .restricted:
            return "Der Standortzugriff ist auf diesem Gerät gesperrt. Wähle einen Ort, "
                 + "dann funktioniert alles genauso."
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        switch authorization {
        case .notDetermined:
            primaryButton("Standort freigeben") {
                appEnvironment.location.requestPermission()
            }
        case .denied:
            primaryButton("Einstellungen") {
                openSystemSettings()
            }
        case .authorized:
            if appEnvironment.location.isLocating {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
            } else {
                primaryButton("Erneut orten") {
                    appEnvironment.location.updateLocationOnce()
                }
            }
        case .restricted:
            EmptyView()
        }
    }

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.cardTitle)
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.m)
                .background(Theme.accentFill, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
    }
}
