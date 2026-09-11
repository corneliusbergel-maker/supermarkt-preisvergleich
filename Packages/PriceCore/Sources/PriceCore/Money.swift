import Foundation

/// Ein Geldbetrag.
///
/// Verwendet `Decimal` statt `Double`. Das ist keine Stilfrage: `Double` kann
/// 0,01 nicht exakt darstellen, wodurch sich bei Summen ueber eine
/// Einkaufsliste Cent-Fehler aufaddieren. `Decimal` rechnet dezimal exakt.
public struct Money: Hashable, Sendable, Comparable {

    /// Der Betrag in der Waehrungseinheit (also Euro, nicht Cent).
    public let amount: Decimal

    /// ISO-4217-Code, z. B. "EUR".
    public let currency: String

    public init(amount: Decimal, currency: String = "EUR") {
        self.amount = amount
        self.currency = currency
    }

    /// Erzeugt einen Betrag aus einem String, wie ihn APIs liefern ("1.49").
    ///
    /// Gibt `nil` zurueck, wenn der String kein gueltiger Betrag ist -- es wird
    /// bewusst NICHT auf 0 zurueckgefallen, damit fehlende Daten sichtbar
    /// bleiben statt sich als "kostenlos" zu tarnen.
    public init?(string: String, currency: String = "EUR") {
        guard let value = DecimalParsing.decimal(from: string) else { return nil }
        self.init(amount: value, currency: currency)
    }

    /// Kaufmaennisch auf Cent gerundeter Betrag -- nur fuer die Anzeige.
    public var roundedToCents: Money {
        Money(amount: DecimalParsing.round(amount, scale: 2), currency: currency)
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        precondition(lhs.currency == rhs.currency,
                     "Betraege in unterschiedlichen Waehrungen sind nicht vergleichbar.")
        return lhs.amount < rhs.amount
    }
}

// MARK: - Rechnen

public extension Money {

    /// Summiert Betraege. Gibt `nil` zurueck, sobald Waehrungen gemischt sind
    /// oder die Liste leer ist -- eine "0 EUR"-Summe waere hier eine Luege.
    static func sum(_ values: [Money]) -> Money? {
        guard let first = values.first else { return nil }
        guard values.allSatisfy({ $0.currency == first.currency }) else { return nil }
        let total = values.reduce(Decimal(0)) { $0 + $1.amount }
        return Money(amount: total, currency: first.currency)
    }

    static func + (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Waehrungen muessen uebereinstimmen.")
        return Money(amount: lhs.amount + rhs.amount, currency: lhs.currency)
    }

    static func - (lhs: Money, rhs: Money) -> Money {
        precondition(lhs.currency == rhs.currency, "Waehrungen muessen uebereinstimmen.")
        return Money(amount: lhs.amount - rhs.amount, currency: lhs.currency)
    }

    static func * (lhs: Money, rhs: Int) -> Money {
        Money(amount: lhs.amount * Decimal(rhs), currency: lhs.currency)
    }

    /// Relative Aenderung von `self` zu `other`, z. B. -0.178 fuer -17,8 %.
    /// `nil`, wenn der Ausgangswert 0 ist (Division waere undefiniert).
    func relativeChange(from other: Money) -> Decimal? {
        guard other.amount != 0, currency == other.currency else { return nil }
        return (amount - other.amount) / other.amount
    }
}

// MARK: - Formatierung

public extension Money {

    /// Formatiert als "1,49 EUR" im uebergebenen Gebietsschema.
    func formatted(locale: Locale = Locale(identifier: "de_DE")) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        formatter.locale = locale
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: amount))
            ?? "\(amount) \(currency)"
    }
}

// MARK: - Dezimal-Hilfen

public enum DecimalParsing {

    /// Rundet kaufmaennisch (half-up) auf `scale` Nachkommastellen.
    public static func round(_ value: Decimal, scale: Int) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, scale, .plain)
        return result
    }

    /// Parst eine Zahl aus einem String und beherrscht dabei deutsche wie
    /// englische Schreibweise.
    ///
    /// Regeln -- bewusst explizit, weil "1.500" mehrdeutig ist:
    /// 1. Kommen Punkt UND Komma vor, ist das **rechtere** das Dezimaltrennzeichen.
    /// 2. Kommt nur ein Trennzeichen vor und folgen ihm **genau drei** Ziffern,
    ///    gilt es als Tausendertrennzeichen ("1.500 ml" = 1500 ml) -- ausser
    ///    der Teil davor ist "0" ("0,500 kg" = 0,5 kg).
    /// 3. Sonst ist es ein Dezimaltrennzeichen.
    public static func decimal(from raw: String) -> Decimal? {
        // Alle Arten von Zwischenraum entfernen, nicht nur das gewoehnliche
        // Leerzeichen. `NumberFormatter` setzt im Deutschen ein **schmales
        // geschuetztes** Leerzeichen (U+202F) vor das Waehrungszeichen; andere
        // Gebietsschemata nutzen es als Tausendertrennzeichen. Wer einen
        // formatierten Betrag einfuegt, soll damit nicht scheitern.
        var text = String(raw.unicodeScalars.filter {
            !CharacterSet.whitespacesAndNewlines.contains($0)
        })
        guard !text.isEmpty else { return nil }

        let hasDot = text.contains(".")
        let hasComma = text.contains(",")

        if hasDot && hasComma {
            let lastDot = text.lastIndex(of: ".")!
            let lastComma = text.lastIndex(of: ",")!
            if lastComma > lastDot {
                text = text.replacingOccurrences(of: ".", with: "")
                text = text.replacingOccurrences(of: ",", with: ".")
            } else {
                text = text.replacingOccurrences(of: ",", with: "")
            }
        } else if hasDot || hasComma {
            let separator: Character = hasDot ? "." : ","
            let parts = text.split(separator: separator, omittingEmptySubsequences: false)
            if parts.count == 2,
               parts[1].count == 3,
               parts[1].allSatisfy(\.isNumber),
               parts[0] != "0" {
                // Tausendertrennzeichen
                text = parts.joined()
            } else {
                text = text.replacingOccurrences(of: String(separator), with: ".")
            }
        }

        guard text.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) else { return nil }
        return Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))
    }
}
