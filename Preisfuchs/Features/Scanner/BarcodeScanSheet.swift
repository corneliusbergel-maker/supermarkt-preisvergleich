import AVFoundation
import SwiftUI
import PriceCore
import PriceData
#if canImport(UIKit)
import UIKit
#endif

/// Scannt einen Barcode und löst ihn zu einem Produkt auf (#19).
struct BarcodeScanSheet: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    /// Wird mit dem gefundenen Produkt aufgerufen; das Blatt schließt sich
    /// danach selbst.
    let onProduct: (Product) -> Void

    @State private var phase: ScanPhase = .checking

    /// Benannt als `ScanPhase`, nicht `State` -- ein verschachteltes `State`
    /// verdeckt SwiftUIs `@State`-Attribut in derselben Ansicht.
    enum ScanPhase {
        case checking
        case needsPermission
        case permissionDenied
        case unavailable(BarcodeScanning.Availability)
        case scanning
        case resolving(code: String)
        case notFound(code: String)
        case failed(message: String, code: String)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.ink.ignoresSafeArea()
                content
            }
            .navigationTitle("Barcode scannen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
            }
        }
        .task { await prepare() }
    }

    // MARK: - Ablauf

    private func prepare() async {
        let availability = BarcodeScanning.availability
        guard availability == .available else {
            phase = .unavailable(availability)
            return
        }

        switch BarcodeScanning.cameraAuthorization {
        case .authorized:
            phase = .scanning
        case .notDetermined:
            phase = .needsPermission
        case .denied, .restricted:
            phase = .permissionDenied
        @unknown default:
            phase = .needsPermission
        }
    }

    private func requestPermission() async {
        let granted = await BarcodeScanning.requestCameraAccess()
        phase = granted ? .scanning : .permissionDenied
    }

    private func resolve(code: String) async {
        phase = .resolving(code: code)
        do {
            let product = try await appEnvironment.products.product(barcode: code)
            onProduct(product)
            dismiss()
        } catch DataSourceError.notFound {
            phase = .notFound(code: code)
        } catch let error as DataSourceError {
            phase = .failed(message: error.userMessage, code: code)
        } catch {
            phase = .failed(message: "Der Barcode konnte nicht aufgelöst werden.", code: code)
        }
    }

    // MARK: - Darstellung

    @ViewBuilder
    private var content: some View {
        switch phase {

        case .checking:
            ProgressView().tint(Theme.accent)

        case .unavailable(let availability):
            EmptyState(symbol: "camera.metering.unknown",
                       title: "Scannen nicht möglich",
                       message: availability.explanation)

        case .needsPermission:
            EmptyState(
                symbol: "camera",
                title: "Kamera freigeben",
                message: "Zum Scannen von Barcodes braucht Preisfuchs Zugriff auf die "
                       + "Kamera. Die Bilder verlassen das Gerät nicht – es wird nur der "
                       + "Zahlencode ausgewertet.",
                actionTitle: "Kamera freigeben"
            ) {
                Task { await requestPermission() }
            }

        case .permissionDenied:
            EmptyState(
                symbol: "camera.slash",
                title: "Kamerazugriff ist aus",
                message: "Du kannst ihn in den Systemeinstellungen erlauben – oder das "
                       + "Produkt über die Suche finden.",
                actionTitle: "Einstellungen öffnen"
            ) {
                openSystemSettings()
            }

        case .scanning:
            scannerView

        case .resolving(let code):
            VStack(spacing: Theme.Spacing.m) {
                ProgressView().tint(Theme.accent)
                Text("Barcode \(code) wird gesucht …")
                    .font(.cardBody)
                    .foregroundStyle(Theme.textSecondary)
            }

        case .notFound(let code):
            EmptyState(
                symbol: "questionmark.circle",
                title: "Produkt unbekannt",
                message: "Zum Barcode \(code) gibt es in der Produktdatenbank keinen "
                       + "Eintrag. Die Datenbank wird von Menschen gepflegt – es wird "
                       + "hier bewusst kein Platzhalter erfunden.",
                actionTitle: "Nochmal scannen"
            ) {
                phase = .scanning
            }

        case .failed(let message, _):
            EmptyState(symbol: "exclamationmark.triangle",
                       title: "Abruf fehlgeschlagen",
                       message: message,
                       actionTitle: "Nochmal scannen") {
                phase = .scanning
            }
        }
    }

    @ViewBuilder
    private var scannerView: some View {
        #if !targetEnvironment(macCatalyst)
        ZStack(alignment: .bottom) {
            BarcodeScannerRepresentable { code in
                Task { await resolve(code: code) }
            }
            .ignoresSafeArea(edges: .bottom)

            Text("Halte den Strichcode in den Rahmen")
                .font(.cardBody)
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.l)
                .padding(.vertical, Theme.Spacing.m)
                .background(.black.opacity(0.55), in: Capsule())
                .padding(.bottom, Theme.Spacing.xl)
        }
        #else
        // Auf dem Mac kommt dieser Zweig nie zum Tragen; `availability`
        // meldet dort `.unsupportedPlatform`.
        EmptyState(symbol: "camera.metering.unknown",
                   title: "Scannen nicht möglich",
                   message: BarcodeScanning.Availability.unsupportedPlatform.explanation)
        #endif
    }

    private func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }
}
