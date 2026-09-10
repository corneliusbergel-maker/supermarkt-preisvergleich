import Foundation

/// Messgroesse einer Menge.
public enum UnitDimension: String, Hashable, Sendable {
    case volume
    case mass
    case count
}

/// Eine Mengeneinheit inklusive Umrechnung in ihre Basiseinheit.
///
/// Basiseinheiten sind Liter, Kilogramm und Stueck -- das sind die Bezugs-
/// groessen, auf die die deutsche Preisangabenverordnung den Grundpreis
/// bezieht.
public enum MeasurementUnit: String, Hashable, Sendable, CaseIterable {
    case milliliter
    case centiliter
    case liter
    case milligram
    case gram
    case kilogram
    case piece

    public var dimension: UnitDimension {
        switch self {
        case .milliliter, .centiliter, .liter: return .volume
        case .milligram, .gram, .kilogram: return .mass
        case .piece: return .count
        }
    }

    public var baseUnit: MeasurementUnit {
        switch dimension {
        case .volume: return .liter
        case .mass: return .kilogram
        case .count: return .piece
        }
    }

    /// Faktor zur Umrechnung in die Basiseinheit.
    public var factorToBase: Decimal {
        switch self {
        case .milliliter: return Decimal(string: "0.001")!
        case .centiliter: return Decimal(string: "0.01")!
        case .liter: return 1
        case .milligram: return Decimal(string: "0.000001")!
        case .gram: return Decimal(string: "0.001")!
        case .kilogram: return 1
        case .piece: return 1
        }
    }

    /// Kurzform fuer die Anzeige.
    public var symbol: String {
        switch self {
        case .milliliter: return "ml"
        case .centiliter: return "cl"
        case .liter: return "l"
        case .milligram: return "mg"
        case .gram: return "g"
        case .kilogram: return "kg"
        case .piece: return "Stk"
        }
    }

    /// Erkennt eine Einheit aus dem Text einer Produktangabe.
    /// Gibt `nil` zurueck, wenn das Token keine bekannte Einheit ist --
    /// es wird bewusst nicht geraten.
    public static func parse(_ token: String) -> MeasurementUnit? {
        let key = token
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ".", with: "")
        switch key {
        case "ml", "milliliter", "millilitre", "millilitres", "milliliters":
            return .milliliter
        case "cl", "centiliter", "centilitre":
            return .centiliter
        case "l", "lt", "ltr", "liter", "litre", "liters", "litres":
            return .liter
        case "mg", "milligramm", "milligram":
            return .milligram
        case "g", "gr", "gramm", "gram", "grams", "gramme", "grammes":
            return .gram
        case "kg", "kilo", "kilos", "kilogramm", "kilogram", "kilograms":
            return .kilogram
        case "stk", "st", "stueck", "stück", "stuck", "piece", "pieces",
             "pcs", "pc", "portionen", "portion", "beutel", "kapseln":
            return .piece
        default:
            return nil
        }
    }
}

/// Eine geparste Produktmenge, z. B. "6 x 1,5 l".
///
/// Wichtig fuer den Preisvergleich: `totalInBaseUnit` ist die einzige Groesse,
/// die zwischen unterschiedlichen Packungen verglichen werden darf.
public struct Quantity: Hashable, Sendable {

    /// Anzahl der Einzelpackungen. 1 bei Einzelprodukten, 6 bei "6 x 1,5 l".
    public let packCount: Int

    /// Menge pro Einzelpackung.
    public let unitAmount: Decimal

    /// Einheit der Einzelpackung.
    public let unit: MeasurementUnit

    public init?(packCount: Int, unitAmount: Decimal, unit: MeasurementUnit) {
        // Eine Menge <= 0 ist keine gueltige Angabe, kein Grund zum Raten.
        guard packCount > 0, unitAmount > 0 else { return nil }
        self.packCount = packCount
        self.unitAmount = unitAmount
        self.unit = unit
    }

    public var isMultipack: Bool { packCount > 1 }

    /// Gesamtmenge in der angegebenen Einheit (6 x 1,5 l -> 9 l).
    public var totalAmount: Decimal { Decimal(packCount) * unitAmount }

    /// Gesamtmenge in der Basiseinheit -- die Vergleichsgroesse.
    public var totalInBaseUnit: Decimal { totalAmount * unit.factorToBase }

    public var baseUnit: MeasurementUnit { unit.baseUnit }

    public var dimension: UnitDimension { unit.dimension }

    /// Anzeige wie "6 x 1,5 l" bzw. "500 g".
    public func formatted(locale: Locale = Locale(identifier: "de_DE")) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        let amount = formatter.string(from: NSDecimalNumber(decimal: unitAmount))
            ?? "\(unitAmount)"
        return isMultipack
            ? "\(packCount) x \(amount) \(unit.symbol)"
            : "\(amount) \(unit.symbol)"
    }

    /// Zwei Mengen sind vergleichbar, wenn sie dieselbe Messgroesse haben.
    /// 500 g und 1 kg sind vergleichbar, 1 l und 500 g nicht.
    public func isComparable(with other: Quantity) -> Bool {
        dimension == other.dimension
    }

    /// Exakt gleiche Gesamtmenge in der Basiseinheit.
    public func hasSameTotal(as other: Quantity) -> Bool {
        isComparable(with: other) && totalInBaseUnit == other.totalInBaseUnit
    }
}

// MARK: - Parsing

public extension Quantity {

    /// Bevorzugter Weg: aus den **strukturierten** Feldern von Open Food Facts.
    ///
    /// `product_quantity` ist dort bereits normalisiert (in g oder ml) und
    /// damit deutlich verlaesslicher als der freie Text in `quantity`.
    /// Der Text wird nur noch herangezogen, um eine Multipack-Aufteilung zu
    /// erkennen -- die Gesamtmenge bleibt immer die strukturierte Zahl.
    static func fromOpenFoodFacts(productQuantity: Decimal?,
                                  productQuantityUnit: String?,
                                  quantityText: String?) -> Quantity? {
        if let value = productQuantity,
           let unitToken = productQuantityUnit,
           let unit = MeasurementUnit.parse(unitToken),
           value > 0 {

            // Multipack nur uebernehmen, wenn er zur strukturierten Menge passt.
            if let text = quantityText,
               let parsed = parse(text),
               parsed.isMultipack,
               parsed.unit.dimension == unit.dimension,
               parsed.totalInBaseUnit == value * unit.factorToBase {
                return parsed
            }
            return Quantity(packCount: 1, unitAmount: value, unit: unit)
        }

        // Fallback: freien Text parsen.
        if let text = quantityText { return parse(text) }
        return nil
    }

    /// Parst Freitext wie "1,5 L", "500g", "6 x 1,5 l", "4 × 250 g".
    /// Gibt `nil` zurueck, wenn nichts eindeutig erkennbar ist.
    static func parse(_ raw: String) -> Quantity? {
        var text = raw.lowercased()
            .replacingOccurrences(of: "\u{00D7}", with: "x")   // ×
            .replacingOccurrences(of: "\u{00A0}", with: " ")   // NBSP
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        // "500 g (2 x 250 g)" -> zuerst den Klammerinhalt versuchen, weil er
        // die praezisere Aufteilung enthaelt.
        if let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")"),
           open < close {
            let inner = String(text[text.index(after: open)..<close])
            if let fromInner = parseSingle(inner), fromInner.isMultipack {
                return fromInner
            }
            text = String(text[text.startIndex..<open])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return parseSingle(text)
    }

    private static func parseSingle(_ text: String) -> Quantity? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Multipack: "6 x 1,5 l", "6x1,5l", "4 x 250 g"
        if let match = firstMatch(pattern: "^([0-9]+)\\s*[x*]\\s*(.+)$", in: trimmed),
           match.count == 3,
           let count = Int(match[1]), count > 0,
           let inner = parseAmountAndUnit(match[2]) {
            return Quantity(packCount: count, unitAmount: inner.0, unit: inner.1)
        }

        // "6er Pack" ohne Einzelmenge ist nicht eindeutig -> kein Rateversuch.
        guard let single = parseAmountAndUnit(trimmed) else { return nil }
        return Quantity(packCount: 1, unitAmount: single.0, unit: single.1)
    }

    /// Zerlegt "1,5 l" in (1.5, .liter).
    private static func parseAmountAndUnit(_ text: String) -> (Decimal, MeasurementUnit)? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let match = firstMatch(
            pattern: "^([0-9]+(?:[.,][0-9]+)?)\\s*([a-zäöüß]+)\\.?$",
            in: trimmed
        ), match.count == 3 else { return nil }

        guard let amount = DecimalParsing.decimal(from: match[1]), amount > 0,
              let unit = MeasurementUnit.parse(match[2]) else { return nil }
        return (amount, unit)
    }

    /// Kleiner Regex-Helfer. Gibt die Gruppen des ersten Treffers zurueck,
    /// Index 0 ist der Gesamttreffer.
    private static func firstMatch(pattern: String, in text: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range) else {
            return nil
        }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            guard let sub = Range(match.range(at: index), in: text) else {
                groups.append("")
                continue
            }
            groups.append(String(text[sub]))
        }
        return groups
    }
}
