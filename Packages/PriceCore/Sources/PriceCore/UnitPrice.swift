import Foundation

/// Der Grundpreis: Preis bezogen auf eine Referenzmenge.
///
/// Beispiel: 1,49 EUR fuer 1,5 l ergibt 0,9933... EUR pro Liter.
/// Der ungerundete Wert wird aufbewahrt; gerundet wird ausschliesslich fuer
/// die Anzeige. So entstehen beim Sortieren keine Gleichstaende, die es
/// rechnerisch gar nicht gibt.
public struct UnitPrice: Hashable, Sendable, Comparable {

    /// Preis fuer `referenceAmount` mal `referenceUnit`.
    public let price: Money

    /// Bezugsmenge -- 1 (l, kg, Stk) oder 100 (ml, g).
    public let referenceAmount: Decimal

    /// Bezugseinheit.
    public let referenceUnit: MeasurementUnit

    public init(price: Money, referenceAmount: Decimal, referenceUnit: MeasurementUnit) {
        self.price = price
        self.referenceAmount = referenceAmount
        self.referenceUnit = referenceUnit
    }

    /// Bezugsgroesse fuer den Grundpreis.
    public enum Basis: Hashable, Sendable {
        /// Immer auf 1 l / 1 kg / 1 Stueck.
        case perBaseUnit
        /// Bei Nennfuellmengen unter 250 g bzw. 250 ml auf 100 g / 100 ml --
        /// so wie es die Preisangabenverordnung zulaesst und der Handel es
        /// ueblicherweise ausweist.
        case automatic
    }

    /// Berechnet den Grundpreis.
    ///
    /// Gibt `nil` zurueck, wenn die Menge unbrauchbar ist. Es wird nichts
    /// geschaetzt -- ohne verlaessliche Menge zeigt die App keinen Grundpreis.
    public static func calculate(price: Money,
                                 quantity: Quantity,
                                 basis: Basis = .automatic) -> UnitPrice? {
        let totalBase = quantity.totalInBaseUnit
        guard totalBase > 0 else { return nil }

        let pricePerBaseUnit = price.amount / totalBase
        let baseUnit = quantity.baseUnit

        guard basis == .automatic, quantity.dimension != .count else {
            return UnitPrice(
                price: Money(amount: pricePerBaseUnit, currency: price.currency),
                referenceAmount: 1,
                referenceUnit: baseUnit
            )
        }

        let smallThreshold = Decimal(string: "0.25")!
        if totalBase < smallThreshold {
            // Auf 100 ml bzw. 100 g umrechnen.
            let smallUnit: MeasurementUnit = (quantity.dimension == .volume) ? .milliliter : .gram
            let pricePer100 = pricePerBaseUnit * smallUnit.factorToBase * 100
            return UnitPrice(
                price: Money(amount: pricePer100, currency: price.currency),
                referenceAmount: 100,
                referenceUnit: smallUnit
            )
        }

        return UnitPrice(
            price: Money(amount: pricePerBaseUnit, currency: price.currency),
            referenceAmount: 1,
            referenceUnit: baseUnit
        )
    }

    /// Auf eine gemeinsame Basiseinheit normierter Wert -- nur so duerfen
    /// zwei Grundpreise verglichen werden (0,50 EUR/100 g vs. 4,80 EUR/kg).
    public var normalizedPerBaseUnit: Decimal {
        let amountInBase = referenceAmount * referenceUnit.factorToBase
        guard amountInBase > 0 else { return 0 }
        return price.amount / amountInBase
    }

    /// Anzeige wie "0,99 EUR/l" oder "1,25 EUR/100 g".
    public func formatted(locale: Locale = Locale(identifier: "de_DE")) -> String {
        let rounded = Money(amount: DecimalParsing.round(price.amount, scale: 2),
                            currency: price.currency)
        let reference = referenceAmount == 1
            ? referenceUnit.symbol
            : "\(referenceAmount) \(referenceUnit.symbol)"
        return "\(rounded.formatted(locale: locale))/\(reference)"
    }

    public static func < (lhs: UnitPrice, rhs: UnitPrice) -> Bool {
        lhs.normalizedPerBaseUnit < rhs.normalizedPerBaseUnit
    }
}

// MARK: - Packungsgroessen vergleichen

public extension UnitPrice {

    /// Wie viel guenstiger ist `self` gegenueber `other`, relativ?
    ///
    /// -0.18 bedeutet: 18 % guenstiger. Ergibt `nil`, wenn die Messgroessen
    /// nicht zusammenpassen (Liter gegen Kilogramm) oder `other` 0 ist.
    func relativeAdvantage(over other: UnitPrice) -> Decimal? {
        guard referenceUnit.dimension == other.referenceUnit.dimension else { return nil }
        let mine = normalizedPerBaseUnit
        let theirs = other.normalizedPerBaseUnit
        guard theirs > 0 else { return nil }
        return (mine - theirs) / theirs
    }
}
