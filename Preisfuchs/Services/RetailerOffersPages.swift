import Foundation

/// Offizielle Angebotsseiten der Ketten.
///
/// Nur Links: Preisfuchs liest diese Seiten nicht aus. Keine Kette bietet dafür
/// eine Schnittstelle an, und mehrere untersagen oder blockieren automatische
/// Abrufe – Einzelheiten in `DATENQUELLEN-SUPERMAERKTE.md`.
///
/// Jede Adresse wurde am 2026-09-12 geprüft; der Kommentar nennt, worauf sie
/// führte. Ändert eine Kette ihre Adresse, landet der Link schlimmstenfalls
/// auf ihrer Startseite.
enum RetailerOffersPages {

    struct Page: Identifiable, Hashable {
        /// Name wie in der Auswahlliste der Einstellungen.
        let name: String
        /// Kürzere Beschriftung, falls der volle Name nicht in die Kachel passt.
        var shortName: String?
        let url: URL
        var id: String { name }
    }

    static let all: [Page] = [
        // Seitentitel „Angebote in deinem REWE Markt“
        page("REWE", "https://www.rewe.de/angebote/nationale-angebote/"),
        // Seitentitel „EDEKA: Angebote der Woche“
        page("EDEKA", "https://www.edeka.de/angebote/"),
        // Seitentitel „Aktuelle Angebote im Überblick | Kaufland“
        page("Kaufland", "https://filiale.kaufland.de/angebote/uebersicht.html"),
        // Seitentitel „Prospekte bei Lidl: Unsere Aktionsprospekte jetzt online“
        page("Lidl", "https://www.lidl.de/c/online-prospekte/s10005610"),
        // Seitentitel „Aktuelle Angebote & Werbung | ALDI SÜD“
        page("Aldi Süd", "https://www.aldi-sued.de/angebote"),
        // Seitentitel „Aktuelle Angebote von ALDI Nord zum ALDI Preis“
        page("Aldi Nord", "https://www.aldi-nord.de/angebote.html"),
        // Seitentitel „Angebote & Prospekt der Woche | PENNY.de“
        page("Penny", "https://www.penny.de/angebote"),
        // Seitentitel „Aktuelle Filial-Angebote & Prospekte | Netto Marken-Discount“
        page("Netto Marken-Discount", "https://www.netto-online.de/filialangebote", short: "Netto"),
        // Seitentitel „NORMA - Ihr Lebensmittel-Discounter | Angebote“
        page("Norma", "https://www.norma-online.de/de/angebote/")
    ]

    private static func page(_ name: String, _ address: String, short: String? = nil) -> Page {
        // Feste, geprüfte Adressen – ein Tippfehler fiele beim ersten Start auf.
        Page(name: name, shortName: short, url: URL(string: address)!)
    }
}
