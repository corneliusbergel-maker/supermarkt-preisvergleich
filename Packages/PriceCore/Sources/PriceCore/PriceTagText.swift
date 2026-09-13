import Foundation

/// Findet den Verkaufspreis im erkannten Text eines Preisschilds.
///
/// Die Texterkennung selbst läuft in der App (Vision). Hier steht nur die
/// Auswahl – damit sie sich ohne Kamera testen lässt.
///
/// Das Ergebnis ist ein **Vorschlag**: Die App trägt ihn ins Formular ein, der
/// Mensch vor dem Regal bestätigt ihn. Übertragen wird nie automatisch.
public enum PriceTagText {

    /// Eine erkannte Textzeile. `height` ist die Höhe ihres Rahmens relativ zum
    /// Bild – auf Preisschildern steht der Verkaufspreis am größten.
    public struct Line: Hashable, Sendable {
        public let text: String
        public let height: Double

        public init(text: String, height: Double) {
            self.text = text
            self.height = height
        }
    }

    /// Preise außerhalb dieses Bereichs sind auf einem Supermarktschild
    /// unplausibel – eher eine Artikelnummer oder ein Lesefehler.
    static let plausibleRange: ClosedRange<Decimal> = Decimal(string: "0.05")!...Decimal(500)

    public static func bestPrice(in lines: [Line]) -> Decimal? {
        var withSeparator: [(amount: Decimal, height: Double)] = []
        var withoutSeparator: [(amount: Decimal, height: Double)] = []

        for line in lines where !isSecondaryLine(line.text) {
            for amount in separatedAmounts(in: line.text) {
                withSeparator.append((amount, line.height))
            }
            if let amount = splitAmount(in: line.text) {
                withoutSeparator.append((amount, line.height))
            }
        }

        // „1,79“ ist eindeutiger als „1 79“ – die zweite Form nur, wenn es
        // keine erste gibt.
        let pool = withSeparator.isEmpty ? withoutSeparator : withSeparator
        return pool.max { $0.height < $1.height }?.amount
    }

    /// Grundpreis („1 kg = 5,59 €“), Pfand und Mengenangaben sind nicht der
    /// Verkaufspreis.
    static func isSecondaryLine(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = ["=", "/", "pfand", "grundpreis", "kg", "100 g", "100g", "1 l ", "je l"]
        return markers.contains { lower.contains($0) }
    }

    /// „1,79“, „1.79 €“ – höchstens drei Stellen vor dem Komma, genau zwei danach.
    static func separatedAmounts(in text: String) -> [Decimal] {
        matches(of: "(?<!\\d)(\\d{1,3})[,.](\\d{2})(?!\\d)", in: text)
    }

    /// Schilder setzen die Cents oft hochgestellt, die Erkennung liest dann
    /// „1 79“. Nur als ganze Zeile akzeptiert.
    static func splitAmount(in text: String) -> Decimal? {
        matches(of: "^\\s*(\\d{1,2})\\s+(\\d{2})\\s*€?\\s*$", in: text).first
    }

    private static func matches(of pattern: String, in text: String) -> [Decimal] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let euros = Range(match.range(at: 1), in: text),
                  let cents = Range(match.range(at: 2), in: text),
                  let amount = Decimal(string: "\(text[euros]).\(text[cents])",
                                       locale: Locale(identifier: "en_US_POSIX")),
                  plausibleRange.contains(amount) else { return nil }
            return amount
        }
    }
}
