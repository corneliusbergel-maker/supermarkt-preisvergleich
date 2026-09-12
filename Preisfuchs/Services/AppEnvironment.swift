import Foundation
import Observation
import PriceCore
import PriceData

/// Haelt die Dienste zusammen, die die ganze App braucht.
///
/// Eine Instanz, von der Wurzelansicht nach unten gereicht. Kein globaler
/// Singleton -- so laesst sich in Vorschauen und Tests eine andere Umgebung
/// einsetzen.
@MainActor
@Observable
final class AppEnvironment {

    let settings: AppSettings
    let location: LocationService
    let notifications: NotificationService

    /// Sagt der Oberflaeche, ob gerade zwischengespeicherte Daten gezeigt
    /// werden (#32).
    let freshness: DataFreshness

    let products: OpenFoodFactsClient
    let prices: OpenPricesClient
    let stores: OverpassClient

    /// Angebote direkt von den Ketten (Kaufland, ALDI Nord, ALDI SÜD).
    let marketOffers: MarketOffersStore

    /// Zeitpunkt der zuletzt angestoßenen Aktualisierung. Startseite und
    /// Favoriten hängen ihr Neuladen daran.
    private(set) var refreshTick = Date()

    /// Solange die App offen ist, werden Preise und Angebote stündlich neu
    /// geholt – und beim Zurückkehren in die App, wenn der letzte Stand älter
    /// ist.
    static let refreshInterval: TimeInterval = 60 * 60

    /// `settings`, `location` und `notifications` sind an den Hauptaktor
    /// gebunden. Sie duerfen deshalb **nicht** als Standardwert eines
    /// Parameters entstehen: Standardausdruecke werden ausserhalb der
    /// Isolierung ausgewertet, auch wenn der Initialisierer selbst
    /// `@MainActor` ist. Sie werden hier im Rumpf erzeugt; die Clients sind
    /// einfache Wertetypen ohne Isolierung und koennen als Vorgabe stehen
    /// bleiben.
    init(settings: AppSettings? = nil,
         location: LocationService? = nil,
         notifications: NotificationService? = nil,
         products: OpenFoodFactsClient? = nil,
         prices: OpenPricesClient? = nil,
         stores: OverpassClient? = nil) {

        self.settings = settings ?? AppSettings()
        self.location = location ?? LocationService()
        self.notifications = notifications ?? NotificationService()

        let freshness = DataFreshness()
        self.freshness = freshness

        // Ein gemeinsamer Transport fuer alle Leseabfragen. Er legt Antworten
        // ab und liefert sie bei Netzproblemen wieder aus -- und meldet der
        // Oberflaeche, dass sie nicht mehr frisch sind.
        let transport = CachingTransport(
            wrapping: URLSessionTransport(),
            onCacheHit: { date in
                Task { @MainActor in freshness.noteCacheHit(at: date) }
            },
            onFreshResponse: {
                Task { @MainActor in freshness.noteFreshResponse() }
            }
        )

        self.products = products ?? OpenFoodFactsClient(transport: transport)
        self.prices = prices ?? OpenPricesClient(transport: transport)

        // Über denselben Transport: Ohne Netz zeigt die Liste den letzten Stand
        // und das Banner sagt, von wann er ist.
        self.marketOffers = MarketOffersStore.standard(transport: transport)

        // Overpass bleibt beim einfachen Transport: Es fragt per POST ab, und
        // POST wird bewusst nicht auf Platte gelegt. Die Filialen haben
        // stattdessen einen eigenen Zwischenspeicher im Arbeitsspeicher --
        // der ueberlebt allerdings keinen Neustart der App. Ohne Netz und nach
        // einem Neustart bleibt die Filialliste deshalb leer und sagt das auch.
        self.stores = stores ?? OverpassClient()
    }

    /// Der Ort, mit dem gerechnet wird.
    ///
    /// Ein von Hand gewaehlter Ort hat Vorrang vor der Ortung: Wer ihn setzt,
    /// hat sich bewusst dafuer entschieden.
    var activeCoordinate: Coordinate? {
        settings.manualCoordinate ?? location.coordinate
    }

    /// Beschreibt fuer die Oberflaeche, worauf sich Entfernungen beziehen.
    var activeLocationDescription: String? {
        if let name = settings.manualPlaceName, settings.manualCoordinate != nil {
            return name
        }
        if location.coordinate != nil { return "Dein Standort" }
        return nil
    }

    /// Kann die App gerade Entfernungen ausweisen?
    var hasLocation: Bool { activeCoordinate != nil }

    // MARK: - Aktualisieren

    /// Stößt ein Neuladen an, wenn der letzte Stand älter als eine Stunde ist.
    func refreshIfStale(now: Date = Date()) {
        guard now.timeIntervalSince(refreshTick) >= Self.refreshInterval else { return }
        refreshTick = now
    }

    /// Neuladen auf Wunsch, etwa beim Herunterziehen der Startseite.
    func refreshNow() {
        refreshTick = Date()
    }

    /// Läuft, solange die Oberfläche besteht, und stößt stündlich ein Neuladen an.
    func runHourlyRefresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(Self.refreshInterval))
            guard !Task.isCancelled else { return }
            refreshTick = Date()
        }
    }
}
