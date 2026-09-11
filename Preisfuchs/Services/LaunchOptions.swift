import Foundation

/// Startparameter, mit denen die CI die App in einen bestimmten Zustand
/// bringt, um Bildschirmfotos aufzunehmen.
///
/// Bewusst hinter `#if DEBUG`: In einem Release-Build existiert dieser Code
/// nicht. Die Auslieferungsfassung hat damit keinen zusätzlichen Einstiegspunkt.
///
/// Aufruf im Simulator:
/// ```
/// xcrun simctl launch <udid> de.preisfuchs.app -uiTab search -uiQuery nutella
/// ```
enum LaunchOptions {

    #if DEBUG
    /// Bereich, der beim Start angezeigt werden soll.
    static var initialDestination: Destination? {
        guard let raw = value(for: "-uiTab") else { return nil }
        switch raw.lowercased() {
        case "home", "start": return .home
        case "search", "suche": return .search
        case "list", "liste": return .shoppingList
        case "favorites", "favoriten": return .favorites
        case "settings", "einstellungen": return .settings
        default: return nil
        }
    }

    /// Suchbegriff, der beim Start eingetragen wird.
    ///
    /// Die Suche läuft danach ganz normal gegen die echte API -- es werden
    /// keine Ergebnisse untergeschoben.
    static var initialSearchQuery: String? {
        value(for: "-uiQuery")
    }

    private static func value(for key: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: key),
              arguments.index(after: index) < arguments.endIndex else { return nil }
        let value = arguments[arguments.index(after: index)]
        return value.isEmpty ? nil : value
    }
    #else
    static var initialDestination: Destination? { nil }
    static var initialSearchQuery: String? { nil }
    #endif
}
