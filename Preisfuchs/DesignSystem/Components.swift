import SwiftUI

// MARK: - Karten

/// Die Grundkarte der App: leicht aufgehellte Flaeche mit feiner Kontur.
struct GlassCard<Content: View>: View {

    var padding: CGFloat = Theme.Spacing.l
    var radius: CGFloat = Theme.Radius.card
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
            )
    }
}

/// Ueberschrift einer Abschnittsgruppe, optional mit Aktion rechts.
struct SectionHeader: View {

    let title: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.sectionTitle)
                .foregroundStyle(Theme.textPrimary)
            Spacer(minLength: Theme.Spacing.s)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
            }
        }
        .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Zustandsanzeigen

/// Wie verlaesslich ein angezeigter Preis ist.
///
/// Es gibt bewusst keine Darstellung "kein Preis" als 0,00 EUR -- fehlende
/// Daten bekommen `EmptyState`, keinen Betrag.
struct ConfidenceBadge: View {

    enum Level {
        case confirmed      // frisch und belegt
        case current        // aktuell genug
        case stale          // moeglicherweise veraltet

        var text: String {
            switch self {
            case .confirmed: return "Bestätigt"
            case .current: return "Aktuell"
            case .stale: return "Evtl. veraltet"
            }
        }

        var color: Color {
            switch self {
            case .confirmed: return Theme.accent
            case .current: return Theme.textSecondary
            case .stale: return Theme.textTertiary
            }
        }

        var symbol: String {
            switch self {
            case .confirmed: return "checkmark.seal.fill"
            case .current: return "clock"
            case .stale: return "exclamationmark.triangle"
            }
        }
    }

    let level: Level
    /// Wann der Preis beobachtet wurde, z. B. "vor 2 Tagen".
    let freshness: String

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: level.symbol)
                .font(.system(size: 10, weight: .semibold))
            Text("\(level.text) · \(freshness)")
                .font(.caption)
        }
        .foregroundStyle(level.color)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(level.color.opacity(0.12), in: Capsule())
        .accessibilityLabel("Preisstand: \(level.text), \(freshness)")
    }
}

/// Angebots-Kennzeichnung. Die einzige Stelle, an der Rot verwendet wird.
struct DealBadge: View {

    /// Rabatt als ganze Prozent, z. B. 22 fuer -22 %.
    let percentOff: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
            Text("Angebot −\(percentOff) %")
                .font(.caption)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.s)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.deal, in: Capsule())
        .accessibilityLabel("Angebot, \(percentOff) Prozent günstiger")
    }
}

// MARK: - Leerzustaende

/// Wird immer dann gezeigt, wenn keine Daten vorliegen.
///
/// Das ist die sichtbare Umsetzung der wichtigsten Projektregel: lieber
/// "keine Daten" sagen als eine Zahl erfinden.
struct EmptyState: View {

    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(Theme.textTertiary)

            Text(title)
                .font(.cardTitle)
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            Text(message)
                .font(.cardBody)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.cardTitle)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, Theme.Spacing.l)
                        .padding(.vertical, Theme.Spacing.m)
                        .background(Theme.accentFill, in: Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, Theme.Spacing.xs)
            }
        }
        .frame(maxWidth: 420)
        .padding(Theme.Spacing.xl)
    }
}

/// Kennzeichnet Bereiche, deren echte Datenquelle noch nicht angebunden ist.
///
/// Anforderung #38: Es darf nie so aussehen, als zeige die App echte Daten,
/// solange die Quelle fehlt. Statt Beispielinhalten steht hier der
/// Entwicklungsstand.
struct DevelopmentNotice: View {

    let feature: String
    let dataSource: String

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: "hammer.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("\(feature) ist noch nicht angebunden")
                    .font(.cardTitle)
                    .foregroundStyle(Theme.textPrimary)
                Text("Sobald \(dataSource) angebunden ist, stehen hier echte Daten. "
                     + "Bis dahin werden hier bewusst keine Beispielwerte angezeigt.")
                    .font(.cardBody)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(Theme.Spacing.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }
}

// MARK: - Kacheln

/// Die Schnellaktionen aus dem Referenzbild: Symbol oben links, Titel unten.
struct ActionTile: View {

    let symbol: String
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Image(systemName: symbol)
                    .font(.system(size: 19, weight: .medium))
                    .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textTertiary)
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(isEnabled ? Theme.textPrimary : Theme.textTertiary)
            }
            .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
            .padding(Theme.Spacing.l)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.tile, style: .continuous)
                    .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
