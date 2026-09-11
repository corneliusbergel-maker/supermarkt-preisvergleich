import AVFoundation
import SwiftUI

#if !targetEnvironment(macCatalyst)
import VisionKit
// Die Symbologien (.ean13, .ean8, ...) sind `VNBarcodeSymbology` und kommen
// aus Vision, nicht aus VisionKit.
import Vision
#endif

/// Kapselt, was auf der jeweiligen Plattform überhaupt möglich ist.
///
/// `DataScannerViewController` aus VisionKit gibt es auf Mac Catalyst nicht,
/// und selbst auf iOS setzt er eine Neural Engine voraus. Beides wird hier
/// geprüft, statt einen Knopf anzubieten, der dann nichts tut.
enum BarcodeScanning {

    enum Availability: Equatable {
        case available
        /// Das Gerät kann es grundsätzlich nicht.
        case unsupportedDevice
        /// Auf dieser Plattform gibt es die Funktion nicht.
        case unsupportedPlatform
        /// Kamera ist gesperrt oder gerade nicht nutzbar.
        case cameraUnavailable

        var explanation: String {
            switch self {
            case .available:
                return ""
            case .unsupportedPlatform:
                return "Barcode-Scannen gibt es nur auf iPhone und iPad. "
                     + "Auf dem Mac kannst du stattdessen nach dem Produktnamen suchen."
            case .unsupportedDevice:
                return "Dieses Gerät unterstützt das Scannen von Barcodes nicht. "
                     + "Du kannst stattdessen nach dem Produktnamen suchen."
            case .cameraUnavailable:
                return "Die Kamera ist gerade nicht verfügbar."
            }
        }
    }

    /// An den Hauptaktor gebunden, weil `DataScannerViewController.isSupported`
    /// und `.isAvailable` es sind.
    @MainActor
    static var availability: Availability {
        #if targetEnvironment(macCatalyst)
        return .unsupportedPlatform
        #else
        guard DataScannerViewController.isSupported else { return .unsupportedDevice }
        guard DataScannerViewController.isAvailable else { return .cameraUnavailable }
        return .available
        #endif
    }

    /// Zustand der Kameraberechtigung.
    static var cameraAuthorization: AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .video)
    }

    /// Fragt die Kameraberechtigung an. Ohne Zustimmung wird nicht gescannt --
    /// es gibt keinen Umweg daran vorbei.
    static func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }
}

#if !targetEnvironment(macCatalyst)

/// Die Kameraansicht mit Barcode-Erkennung.
struct BarcodeScannerRepresentable: UIViewControllerRepresentable {

    /// Wird genau einmal je erkanntem Code aufgerufen.
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            // Die in Deutschland üblichen Symbologien auf Lebensmitteln.
            recognizedDataTypes: [
                .barcode(symbologies: [.ean13, .ean8, .upce, .code128])
            ],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        if scanner.isScanning == false {
            try? scanner.startScanning()
        }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController,
                                          coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {

        private let onScan: (String) -> Void

        /// Verhindert, dass derselbe Code mehrfach gemeldet wird, solange die
        /// Kamera ihn im Bild behält.
        private var handledPayloads: Set<String> = []

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController,
                         didAdd addedItems: [RecognizedItem],
                         allItems: [RecognizedItem]) {
            for item in addedItems {
                guard case .barcode(let barcode) = item,
                      let payload = barcode.payloadStringValue else { continue }

                let digits = payload.filter(\.isNumber)
                guard !digits.isEmpty, handledPayloads.insert(digits).inserted else { continue }

                onScan(digits)
                return
            }
        }
    }
}

#endif
