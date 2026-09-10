import SwiftUI

/// Farb- und Massvorgaben der App.
///
/// Farbdisziplin, abgeleitet aus den Referenzbildern:
/// - **Cyan** ist die funktionale Akzentfarbe: Ersparnis, Bestpreis, aktive
///   Bedienelemente.
/// - **Rot/Orange** ist ausschliesslich fuer Angebote reserviert. Wird es auch
///   fuer Knoepfe verwendet, verliert das Angebots-Signal seine Wirkung.
/// - Der Bordeaux-Anteil erscheint nur im Verlauf, nie als Bedienelement.
enum Theme {

    // MARK: - Flaechen

    /// Grundfarbe der App. Nicht reines Schwarz -- das wirkt auf OLED hart und
    /// laesst die Karten nicht mehr abheben.
    static let ink = Color(red: 0.039, green: 0.039, blue: 0.047)

    /// Kartenfuellung. Sehr leicht aufgehellt statt eigener Farbwert, damit
    /// Karten auf jedem Untergrund funktionieren.
    static let surface = Color.white.opacity(0.06)
    static let surfaceRaised = Color.white.opacity(0.10)
    static let surfaceStroke = Color.white.opacity(0.10)

    // MARK: - Text

    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.62)
    static let textTertiary = Color.white.opacity(0.38)

    // MARK: - Signalfarben

    /// Funktionale Akzentfarbe.
    static let accent = Color(red: 0.16, green: 0.83, blue: 0.78)

    /// Nur fuer Angebote.
    static let deal = Color(red: 1.0, green: 0.35, blue: 0.24)

    /// Nur fuer Preissteigerungen.
    static let priceUp = Color(red: 1.0, green: 0.45, blue: 0.42)

    /// Nur fuer Preissenkungen.
    static let priceDown = Color(red: 0.35, green: 0.88, blue: 0.62)

    // MARK: - Verlaeufe

    /// Der Hero-Verlauf: Bordeaux nach Tuerkis, wie in den Referenzbildern.
    static let hero = LinearGradient(
        colors: [
            Color(red: 0.48, green: 0.07, blue: 0.19),
            Color(red: 0.24, green: 0.07, blue: 0.16),
            Color(red: 0.06, green: 0.33, blue: 0.38)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Abgeschwaechte Fassung fuer grosse Flaechen auf iPad und Mac, damit der
    /// Verlauf dort nicht erdrueckend wirkt.
    static let heroWide = LinearGradient(
        colors: [
            Color(red: 0.38, green: 0.06, blue: 0.16),
            Color(red: 0.10, green: 0.05, blue: 0.10),
            Color(red: 0.05, green: 0.26, blue: 0.31)
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    /// Verlauf fuer den Bestpreis-Hinweis.
    static let accentFill = LinearGradient(
        colors: [Color(red: 0.16, green: 0.83, blue: 0.78),
                 Color(red: 0.10, green: 0.66, blue: 0.72)],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: - Masse

    enum Radius {
        static let card: CGFloat = 26
        static let tile: CGFloat = 20
        static let chip: CGFloat = 14
        static let pill: CGFloat = 999
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 14
        static let l: CGFloat = 20
        static let xl: CGFloat = 28
        static let xxl: CGFloat = 40
    }
}

// MARK: - Schrift

extension Font {

    /// Grosse Preis- und Kennzahlen. Abgerundet und mit gleich breiten
    /// Ziffern, damit Betraege beim Aktualisieren nicht springen.
    static func priceDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .semibold, design: .rounded)
            .monospacedDigit()
    }

    static let sectionTitle = Font.system(size: 19, weight: .semibold, design: .rounded)
    static let cardTitle = Font.system(size: 16, weight: .semibold)
    static let cardBody = Font.system(size: 14, weight: .regular)
    static let caption = Font.system(size: 12, weight: .medium)
}
