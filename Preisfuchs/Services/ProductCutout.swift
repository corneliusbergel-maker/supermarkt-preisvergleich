import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import Vision

/// Stellt ein Produktfoto frei: Übrig bleibt nur die Packung, ohne Tisch,
/// Regal oder Hand dahinter.
///
/// Läuft vollständig auf dem Gerät über Vision (seit iOS 17). Das kostet
/// nichts, und kein Bild verlässt das Gerät. Das Modell braucht GPU oder
/// Neural Engine – im Simulator gibt es keins von beiden, dort wirft Vision
/// einen Fehler, und die App zeigt das Originalfoto.
///
/// Bewusst ohne UIKit, damit die CI genau diese Datei auf dem Mac ausprobieren
/// kann (Schritt „Freistellen prüfen“ in `.github/workflows/ci.yml`).
enum ProductCutout {

    enum Outcome: Sendable {
        /// Freigestelltes Bild als PNG mit durchsichtigem Hintergrund.
        case cutout(Data)
        /// Kein eindeutiges Produkt gefunden. Das Originalfoto ist dann
        /// ehrlicher als ein halb abgeschnittenes.
        case noSubject
    }

    /// Längste Kante vor dem Freistellen. Angezeigt werden höchstens 84 pt,
    /// also 252 Pixel bei dreifacher Auflösung – mehr kostet nur Rechenzeit.
    static let workingSize = 512

    /// Unter diesem Flächenanteil gilt ein Fund als unsicher, etwa wenn nur
    /// ein Preisschild oder eine Hand erkannt wurde.
    static let minimumSubjectShare = 0.08

    static func cutout(imageData: Data) throws -> Outcome {
        guard let image = downsampled(imageData) else { return .noSubject }

        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])

        guard let observation = request.results?.first,
              !observation.allInstances.isEmpty else { return .noSubject }

        let masked = try observation.generateMaskedImage(
            ofInstances: observation.allInstances,
            from: handler,
            croppedToInstancesExtent: true
        )

        let subjectArea = Double(CVPixelBufferGetWidth(masked) * CVPixelBufferGetHeight(masked))
        let imageArea = Double(image.width * image.height)
        guard imageArea > 0, subjectArea / imageArea >= minimumSubjectShare else {
            return .noSubject
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let png = CIContext().pngRepresentation(of: CIImage(cvPixelBuffer: masked),
                                                      format: .RGBA8,
                                                      colorSpace: colorSpace)
        else { return .noSubject }

        return .cutout(png)
    }

    /// Verkleinert beim Dekodieren statt danach – ein Foto in voller Größe
    /// zu laden, nur um es zu verkleinern, kostet unnötig Speicher.
    private static func downsampled(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: workingSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
