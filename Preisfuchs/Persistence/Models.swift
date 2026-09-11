import Foundation
import SwiftData
import PriceCore

/// Ein favorisiertes Produkt (#9).
///
/// Gespeichert wird eine **Abschrift** der Produktdaten, nicht nur der
/// Barcode. So bleibt die Favoritenliste auch ohne Netz lesbar -- die Preise
/// dazu sind dann natürlich nicht aktuell, und die App sagt das auch.
@Model
final class FavoriteProduct {

    /// Entspricht `Product.id`. Eindeutig, damit ein Produkt nicht doppelt
    /// in der Liste landen kann.
    @Attribute(.unique) var productID: String

    var barcode: String?
    var name: String
    var brand: String?

    /// Mengenangabe als Text, z. B. "750 g". Beim Laden wieder geparst.
    var quantityText: String?

    var imageURLString: String?
    var addedAt: Date

    init(productID: String,
         barcode: String?,
         name: String,
         brand: String?,
         quantityText: String?,
         imageURLString: String?,
         addedAt: Date = Date()) {
        self.productID = productID
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.quantityText = quantityText
        self.imageURLString = imageURLString
        self.addedAt = addedAt
    }

    convenience init(product: Product) {
        self.init(productID: product.id,
                  barcode: product.barcode,
                  name: product.name,
                  brand: product.brand,
                  quantityText: product.quantity?.formatted(),
                  imageURLString: product.imageURL?.absoluteString)
    }

    /// Zurück in das Modell der Rechenlogik.
    var product: Product {
        Product(barcode: barcode,
                name: name,
                brand: brand,
                quantity: quantityText.flatMap { Quantity.parse($0) },
                imageURL: imageURLString.flatMap(URL.init(string:)))
    }
}

/// Ein Posten auf der Einkaufsliste (#17).
@Model
final class ShoppingListEntry {

    @Attribute(.unique) var productID: String

    var barcode: String?
    var name: String
    var brand: String?
    var quantityText: String?
    var imageURLString: String?

    /// Wie oft der Posten gekauft werden soll.
    var count: Int

    /// Bereits im Wagen.
    var isChecked: Bool

    var addedAt: Date

    init(productID: String,
         barcode: String?,
         name: String,
         brand: String?,
         quantityText: String?,
         imageURLString: String?,
         count: Int = 1,
         isChecked: Bool = false,
         addedAt: Date = Date()) {
        self.productID = productID
        self.barcode = barcode
        self.name = name
        self.brand = brand
        self.quantityText = quantityText
        self.imageURLString = imageURLString
        self.count = max(1, count)
        self.isChecked = isChecked
        self.addedAt = addedAt
    }

    convenience init(product: Product, count: Int = 1) {
        self.init(productID: product.id,
                  barcode: product.barcode,
                  name: product.name,
                  brand: product.brand,
                  quantityText: product.quantity?.formatted(),
                  imageURLString: product.imageURL?.absoluteString,
                  count: count)
    }

    var product: Product {
        Product(barcode: barcode,
                name: name,
                brand: brand,
                quantity: quantityText.flatMap { Quantity.parse($0) },
                imageURL: imageURLString.flatMap(URL.init(string:)))
    }
}

/// Ein Preisalarm (#11).
///
/// Wichtig zur Erwartung: Die Prüfung läuft auf dem Gerät über
/// `BGAppRefreshTask`. iOS entscheidet selbst, wann das geschieht -- ein Alarm
/// kann deshalb verspätet oder gar nicht ausgelöst werden. Echter Push wäre
/// nur mit einem Apple-Entwicklerkonto möglich und damit nicht kostenlos.
@Model
final class PriceAlert {

    @Attribute(.unique) var productID: String

    var barcode: String?
    var name: String

    /// Zielpreis in der Währungseinheit, als Text gespeichert.
    ///
    /// `Decimal` wird von SwiftData nicht direkt geführt. Ein `Double` wäre
    /// hier falsch -- bei Geldbeträgen entstehen damit Rundungsfehler. Der
    /// Text ist verlustfrei.
    var thresholdText: String

    var currency: String
    var isEnabled: Bool
    var createdAt: Date

    /// Wann zuletzt geprüft wurde. `nil`, solange noch nie.
    var lastCheckedAt: Date?

    /// Preis, mit dem der Alarm zuletzt ausgelöst hat -- verhindert, dass
    /// derselbe Preis mehrfach meldet.
    var lastNotifiedPriceText: String?

    init(productID: String,
         barcode: String?,
         name: String,
         threshold: Money,
         isEnabled: Bool = true,
         createdAt: Date = Date()) {
        self.productID = productID
        self.barcode = barcode
        self.name = name
        self.thresholdText = "\(threshold.amount)"
        self.currency = threshold.currency
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    /// Zielpreis. `nil`, wenn der gespeicherte Text unlesbar ist -- dann löst
    /// der Alarm lieber gar nicht aus, als bei einem geratenen Wert.
    var threshold: Money? {
        guard let amount = DecimalParsing.decimal(from: thresholdText) else { return nil }
        return Money(amount: amount, currency: currency)
    }

    /// Ist dieser Preis ein Grund zu melden?
    func shouldNotify(about price: Money) -> Bool {
        guard isEnabled,
              let threshold,
              price.currency == threshold.currency,
              price.amount <= threshold.amount else { return false }

        // Nicht erneut für denselben oder einen höheren Preis melden.
        if let lastText = lastNotifiedPriceText,
           let last = DecimalParsing.decimal(from: lastText),
           price.amount >= last {
            return false
        }
        return true
    }
}
