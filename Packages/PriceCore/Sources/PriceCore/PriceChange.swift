import Foundation

/// Die Veränderung eines Preises gegenüber einer früheren Beobachtung (#25).
///
/// Wichtig für die Ehrlichkeit: Eine Veränderung entsteht nur aus **zwei
/// tatsächlich beobachteten** Preisen. Fehlt die Vorgeschichte, gibt es keine
/// Aussage -- und die App zeigt dann auch keinen Pfeil.
public struct PriceChange: Hashable, Sendable {

    public enum Direction: Hashable, Sendable {
        case down
        case up
        case unchanged
    }

    /// Der ältere der beiden Preise.
    public let previous: Money

    /// Der aktuelle Preis.
    public let current: Money

    /// Tag der älteren Beobachtung.
    public let previousDate: Date

    /// Tag der aktuellen Beobachtung.
    public let currentDate: Date

    public init?(previous: Money, previousDate: Date, current: Money, currentDate: Date) {
        // Unterschiedliche Waehrungen sind nicht vergleichbar.
        guard previous.currency == current.currency else { return nil }
        // Die Reihenfolge muss stimmen, sonst waere das Vorzeichen verkehrt.
        guard previousDate <= currentDate else { return nil }

        self.previous = previous
        self.currentDate = currentDate
        self.current = current
        self.previousDate = previousDate
    }

    /// Absoluter Unterschied, immer positiv.
    public var absolute: Money {
        let difference = current.amount - previous.amount
        return Money(amount: difference < 0 ? -difference : difference,
                     currency: current.currency)
    }

    /// Relative Veränderung, z. B. -0.178 für -17,8 %.
    /// `nil`, wenn der Ausgangspreis 0 war.
    public var relative: Decimal? {
        current.relativeChange(from: previous)
    }

    public var direction: Direction {
        if current.amount < previous.amount { return .down }
        if current.amount > previous.amount { return .up }
        return .unchanged
    }

    /// Anzahl Tage zwischen den beiden Beobachtungen.
    public var dayCount: Int {
        let calendar = Calendar(identifier: .gregorian)
        let from = calendar.startOfDay(for: previousDate)
        let to = calendar.startOfDay(for: currentDate)
        return calendar.dateComponents([.day], from: from, to: to).day ?? 0
    }

    /// Ist der Unterschied groß genug, um ihn überhaupt zu erwähnen?
    ///
    /// Unter einem Cent ist er für den Nutzer bedeutungslos; ihn anzuzeigen
    /// wäre Scheingenauigkeit.
    public var isWorthShowing: Bool {
        direction != .unchanged && absolute.amount >= Decimal(string: "0.01")!
    }

    /// Text für die Oberfläche, z. B. „0,30 € günstiger als vor 14 Tagen".
    public func summary(locale: Locale = Locale(identifier: "de_DE")) -> String? {
        guard isWorthShowing else { return nil }

        let amount = absolute.roundedToCents.formatted(locale: locale)
        let word = direction == .down ? "günstiger" : "teurer"

        switch dayCount {
        case 0: return "\(amount) \(word) als zuletzt"
        case 1: return "\(amount) \(word) als gestern"
        default: return "\(amount) \(word) als vor \(dayCount) Tagen"
        }
    }

    /// Prozentangabe für die Oberfläche, z. B. „−17,8 %".
    /// `nil`, wenn sie nicht berechenbar oder zu klein ist.
    public func percentText(locale: Locale = Locale(identifier: "de_DE")) -> String? {
        guard isWorthShowing, let relative else { return nil }

        let percent = DecimalParsing.round(relative * 100, scale: 1)
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1

        let magnitude = percent < 0 ? -percent : percent
        guard let text = formatter.string(from: NSDecimalNumber(decimal: magnitude)) else {
            return nil
        }
        return direction == .down ? "−\(text) %" : "+\(text) %"
    }
}

// MARK: - Aus einer Beobachtungsreihe ableiten

public extension PriceChange {

    /// Bildet die Veränderung aus einer Reihe von Beobachtungen.
    ///
    /// Verglichen wird der neueste Preis mit der jüngsten **davorliegenden
    /// Beobachtung derselben Filiale, die einen anderen Betrag hat** -- nach
    /// denselben Regeln wie `forPrice(_:history:)`.
    ///
    /// Gibt `nil` zurück, wenn es keine verwertbare Vorgeschichte gibt.
    static func fromObservations(_ observations: [PriceObservation]) -> PriceChange? {
        guard let latest = observations.max(by: { $0.observedOn < $1.observedOn }) else {
            return nil
        }
        return forPrice(latest, history: observations)
    }

    /// Veränderung eines bestimmten Preises gegenüber seiner Vorgeschichte.
    ///
    /// Zählt nur, was **in derselben Filiale** vorher beobachtet wurde.
    /// 1,39 € bei Lidl gegen 1,69 € bei Rewe ist ein Unterschied zwischen zwei
    /// Märkten, keine Preisänderung -- so gemeldet wäre die Aussage erfunden.
    /// Ohne bekannte Filiale gibt es deshalb keine Aussage.
    ///
    /// Zwei identische Messungen hintereinander sind ebenfalls keine
    /// Veränderung; gesucht wird die jüngste mit einem **anderen** Betrag.
    static func forPrice(_ current: PriceObservation,
                         history: [PriceObservation]) -> PriceChange? {
        guard let storeID = current.store?.id else { return nil }

        let earlier = history
            .filter {
                $0.id != current.id
                && $0.store?.id == storeID
                && $0.observedOn <= current.observedOn
                && $0.price.currency == current.price.currency
                && $0.price.amount != current.price.amount
            }
            .max { $0.observedOn < $1.observedOn }
        guard let earlier else { return nil }

        return PriceChange(previous: earlier.price,
                           previousDate: earlier.observedOn,
                           current: current.price,
                           currentDate: current.observedOn)
    }
}
