import Foundation

/// Ergebnis eines Produktvergleichs.
///
/// Die Trennung zwischen `identical` und `comparable` ist der Kern von
/// Anforderung #21: Nur `identical` darf Preise **zusammenfuehren**.
/// `comparable` erlaubt lediglich den Grundpreis-Vergleich zwischen
/// unterschiedlichen Packungsgroessen.
public enum ProductMatch: Hashable, Sendable {

    /// Sicher dasselbe Produkt in derselben Packung. Preise duerfen in einer
    /// gemeinsamen Vergleichsliste stehen.
    case identical(reason: String)

    /// Dasselbe Produkt, aber andere Packungsgroesse. Nur ueber den
    /// Grundpreis vergleichbar, niemals ueber den absoluten Preis.
    case comparable(reason: String)

    /// Nicht dasselbe Produkt. Darf nie zusammengefuehrt werden.
    case different(reason: String)

    public var allowsPriceMerging: Bool {
        if case .identical = self { return true }
        return false
    }

    public var allowsUnitPriceComparison: Bool {
        switch self {
        case .identical, .comparable: return true
        case .different: return false
        }
    }

    public var reason: String {
        switch self {
        case .identical(let reason), .comparable(let reason), .different(let reason):
            return reason
        }
    }
}

/// Entscheidet, ob zwei Produktdatensaetze dasselbe Produkt meinen.
///
/// Grundhaltung: Im Zweifel **trennen**. Ein faelschlich zusammengefuehrtes
/// Produkt erzeugt einen falschen Preisvergleich -- und ein falscher Preis ist
/// schlimmer als ein fehlender.
public enum ProductMatcher {

    /// Ab welcher Token-Uebereinstimmung zwei Namen als derselbe Artikel
    /// gelten, wenn beide Namen unterscheidende Tokens tragen.
    private static let minimumNameOverlap = 0.5

    public static func match(_ lhs: Product, _ rhs: Product) -> ProductMatch {

        // 1. Barcode ist die harte Identitaet.
        if let a = lhs.barcode, let b = rhs.barcode, !a.isEmpty, !b.isEmpty {
            if normalizeBarcode(a) == normalizeBarcode(b) {
                return .identical(reason: "Gleicher Barcode")
            }
            // Unterschiedliche Barcodes werden NICHT zusammengefuehrt, auch
            // wenn die Namen passen. Sie koennen dieselbe Ware in anderer
            // Aufmachung sein -- dafuer reicht der Grundpreis-Vergleich.
            return compareByAttributes(lhs, rhs, barcodesDiffer: true)
        }

        // 2. Ohne Barcode: ueber Merkmale vergleichen.
        return compareByAttributes(lhs, rhs, barcodesDiffer: false)
    }

    private static func compareByAttributes(_ lhs: Product,
                                            _ rhs: Product,
                                            barcodesDiffer: Bool) -> ProductMatch {

        // Marke muss sich ueberschneiden. "Coca-Cola" vs. "Pepsi" ist raus.
        let brandA = ProductTextNormalizer.brandTokens(lhs.brand)
        let brandB = ProductTextNormalizer.brandTokens(rhs.brand)
        if !brandA.isEmpty && !brandB.isEmpty && brandA.isDisjoint(with: brandB) {
            return .different(reason: "Unterschiedliche Marke")
        }

        // Beide Seiten werden gegen dieselbe Markenwortliste gemessen.
        // Quellen fuehren Marken unterschiedlich vollstaendig ("Ferrero,
        // Nutella" gegen "Ferrero"); ohne gemeinsame Liste wuerde dasselbe
        // Wort einmal als Marke und einmal als Bedeutungswort gewertet.
        let brands = brandA.union(brandB)

        // Varianten muessen exakt uebereinstimmen.
        // Das ist die Regel, die Cola Zero von Cola Original trennt.
        let variantsA = ProductTextNormalizer.variantTokens(name: lhs.name, brandTokens: brands)
        let variantsB = ProductTextNormalizer.variantTokens(name: rhs.name, brandTokens: brands)
        if variantsA != variantsB {
            let difference = variantsA.symmetricDifference(variantsB).sorted().joined(separator: ", ")
            return .different(reason: "Unterschiedliche Variante: \(difference)")
        }

        // Restliche Namensbestandteile muessen zusammenpassen -- aber nur,
        // wenn beide Seiten ueberhaupt welche haben. "Coca Cola" (leer) gegen
        // "Coca-Cola Original Taste" (leer nach Normalisierung) faellt hier
        // korrekt durch.
        let coreA = ProductTextNormalizer.coreTokens(name: lhs.name, brandTokens: brands)
        let coreB = ProductTextNormalizer.coreTokens(name: rhs.name, brandTokens: brands)
        if !coreA.isEmpty && !coreB.isEmpty {
            let overlap = jaccard(coreA, coreB)
            if overlap < minimumNameOverlap {
                return .different(reason: "Produktnamen zu unterschiedlich")
            }
        }

        // Menge entscheidet ueber identisch vs. nur vergleichbar.
        guard let quantityA = lhs.quantity, let quantityB = rhs.quantity else {
            return .different(reason: "Menge unbekannt - kein sicherer Vergleich moeglich")
        }

        guard quantityA.isComparable(with: quantityB) else {
            return .different(reason: "Nicht vergleichbare Einheiten "
                              + "(\(quantityA.baseUnit.symbol) vs. \(quantityB.baseUnit.symbol))")
        }

        guard quantityA.hasSameTotal(as: quantityB) else {
            return .comparable(reason: "Gleiches Produkt, andere Gesamtmenge "
                               + "(\(quantityA.formatted()) vs. \(quantityB.formatted())) "
                               + "- nur ueber den Grundpreis vergleichbar")
        }

        // Gleiche Gesamtmenge, aber andere Aufteilung: 4 x 250 g ist ein
        // anderer Artikel als 1 x 1 kg, auch wenn beide 1 kg ergeben.
        guard quantityA.packCount == quantityB.packCount else {
            return .comparable(reason: "Gleiche Gesamtmenge, andere Packungsaufteilung "
                               + "(\(quantityA.formatted()) vs. \(quantityB.formatted()))")
        }

        if barcodesDiffer {
            return .comparable(reason: "Merkmale stimmen ueberein, "
                               + "aber unterschiedliche Barcodes")
        }

        return .identical(reason: "Marke, Variante und Menge stimmen ueberein")
    }

    /// EAN-13 und die 12-stellige UPC-Variante bezeichnen dieselbe Ware;
    /// fuehrende Nullen werden deshalb ignoriert.
    private static func normalizeBarcode(_ code: String) -> String {
        let digits = code.filter(\.isNumber)
        let trimmed = String(digits.drop(while: { $0 == "0" }))
        return trimmed.isEmpty ? digits : trimmed
    }

    private static func jaccard(_ lhs: Set<String>, _ rhs: Set<String>) -> Double {
        let union = lhs.union(rhs)
        guard !union.isEmpty else { return 1 }
        return Double(lhs.intersection(rhs).count) / Double(union.count)
    }
}

// MARK: - Gruppieren

public extension ProductMatcher {

    /// Fasst eine Trefferliste zu Gruppen zusammen, in denen alle Eintraege
    /// **identisch** sind. Ergebnis: eine Gruppe pro echtem Artikel.
    ///
    /// Wird fuer die Suchergebnisliste gebraucht (#6): Coca-Cola Original 1,5 l,
    /// Coca-Cola Zero 1,5 l und Coca-Cola Original 6 x 1,5 l bleiben getrennt.
    static func group(_ products: [Product]) -> [[Product]] {
        var groups: [[Product]] = []
        for product in products {
            if let index = groups.firstIndex(where: { group in
                group.allSatisfy { match($0, product).allowsPriceMerging }
            }) {
                groups[index].append(product)
            } else {
                groups.append([product])
            }
        }
        return groups
    }
}
