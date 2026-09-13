import Foundation
import PriceCore
import UIKit
import Vision

/// Liest den Preis vom Foto eines Preisschilds – auf dem Gerät, ohne Upload.
///
/// Das beschleunigt „Preis beitragen“: Für REWE, EDEKA, PENNY, Netto und NORMA
/// ist das der einzige erlaubte Weg zu Preisen. Je weniger Tipparbeit, desto
/// mehr Preise kommen zusammen.
enum PriceTagReader {

    static func readPrice(from imageData: Data) async -> Decimal? {
        await Task.detached(priority: .userInitiated) { () -> Decimal? in
            // Das Foto ist bereits aufrecht neu gezeichnet (siehe
            // `ContributePriceSheet.compressImage`), die Ausrichtung stimmt also.
            guard let image = UIImage(data: imageData)?.cgImage else { return nil }

            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["de-DE"]
            // Keine Wortkorrektur: Sie „verbessert“ Ziffern gern zu Wörtern.
            request.usesLanguageCorrection = false

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            guard (try? handler.perform([request])) != nil else { return nil }

            let lines = (request.results ?? []).compactMap { observation -> PriceTagText.Line? in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                return PriceTagText.Line(text: text, height: Double(observation.boundingBox.height))
            }
            return PriceTagText.bestPrice(in: lines)
        }.value
    }
}
