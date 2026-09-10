import Foundation

/// Bildet Markennamen auf stabile Kennungen ab.
///
/// Notwendig, weil dieselbe Kette in den Rohdaten unterschiedlich geschrieben
/// wird -- in Open Prices und OpenStreetMap kommen "Rewe" und "REWE"
/// nebeneinander vor. Ohne Vereinheitlichung waeren das zwei Ketten, und der
/// Haendlerfilter der App wuerde die Haelfte der Treffer verschlucken.
///
/// Ebenso wichtig ist, was hier **nicht** passiert: aehnlich klingende Namen
/// werden nicht zusammengeworfen. "Netto" und "Netto Marken-Discount" sind
/// zwei verschiedene Unternehmen -- sie zu vereinen wuerde Preise zweier
/// Ketten vermischen.
public enum RetailerRegistry {

    /// Stabile Kennung einer Kette, z. B. "rewe" oder "netto-marken-discount".
    ///
    /// Gibt `nil` zurueck, wenn der Name nichts Verwertbares enthaelt --
    /// dann ist die Kette unbekannt und wird auch so behandelt.
    public static func identifier(forBrand name: String?) -> String? {
        guard let name else { return nil }

        var text = name.lowercased()
        for (from, to) in ["ä": "ae", "ö": "oe", "ü": "ue", "ß": "ss"] {
            text = text.replacingOccurrences(of: from, with: to)
        }
        text = text.folding(options: [.diacriticInsensitive],
                            locale: Locale(identifier: "de_DE"))

        let allowed = CharacterSet.alphanumerics
        text = String(text.unicodeScalars.map { allowed.contains($0) ? Character($0) : " " })

        let tokens = text.split(separator: " ").map(String.init)
        guard !tokens.isEmpty else { return nil }
        return tokens.joined(separator: "-")
    }

    /// Baut eine `Retailer` aus einem Rohnamen.
    ///
    /// Der Anzeigename bleibt der Originalwert der Quelle -- nur die Kennung
    /// wird vereinheitlicht. So steht in der Oberflaeche weiterhin das, was
    /// tatsaechlich in den Daten steht.
    public static func retailer(brandName: String?) -> Retailer? {
        guard let brandName,
              let id = identifier(forBrand: brandName) else { return nil }
        let displayName = brandName.trimmingCharacters(in: .whitespacesAndNewlines)
        return Retailer(id: id, name: displayName.isEmpty ? id : displayName)
    }

    /// Kennung aus einer Wikidata-ID, wie OpenStreetMap sie im Tag
    /// `brand:wikidata` fuehrt. Diese IDs sind die verlaesslichste Quelle --
    /// wo sie vorliegen, haben sie Vorrang vor dem Namen.
    public static func identifier(forWikidata id: String?) -> String? {
        guard let id else { return nil }
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard trimmed.count > 1, trimmed.hasPrefix("Q"),
              trimmed.dropFirst().allSatisfy(\.isNumber) else { return nil }
        return "wd:\(trimmed)"
    }
}
