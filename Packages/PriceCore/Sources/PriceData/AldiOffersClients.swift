import Foundation
import PriceCore

// Beide ALDI-Gesellschaften haben am 2026-09-12 dieselben Prüfungen bestanden
// wie Kaufland: `robots.txt` erlaubt die Angebotsseiten, die Seiten antworten
// einer App, die sich als Preisfuchs zu erkennen gibt, Impressum und
// Nutzungsbedingungen schränken die Nutzung der Seiten nicht ein, und die
// Angebote stehen maschinenlesbar im Quelltext. Einzelheiten:
// DATENQUELLEN-SUPERMAERKTE.md.

// MARK: - ALDI Nord

/// Wochenangebote von ALDI Nord – eine Seite, eingebettet als Next.js-Daten.
public struct AldiNordOffersClient: Sendable {

    public static let retailerName = "ALDI Nord"
    public static let pageURL = URL(string: "https://www.aldi-nord.de/angebote.html")!

    /// Vorschau auf die nächste Woche. Die Angebotsseite verweist selbst darauf
    /// (`weekIndicator` → `/angebote-vorschau`). Ohne sie stünde ALDI Nord
    /// sonntags leer da: Die laufende Woche endet samstags.
    public static let previewURL = URL(string: "https://www.aldi-nord.de/angebote-vorschau.html")!

    private let runner: RequestRunner

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.runner = RequestRunner(transport: transport, maxAttempts: 2, baseDelay: 2)
    }

    public func offers() async throws -> [RetailerOffer] {
        var result: [RetailerOffer] = []
        var firstError: Error?

        for url in [Self.pageURL, Self.previewURL] {
            do {
                let html = try await OfferFormatting.html(at: url, runner: runner)
                result += try AldiNordOfferParser.parse(html: html, sourceURL: url)
            } catch {
                // Fehlt eine der beiden Wochen, bleibt die andere sichtbar.
                if firstError == nil { firstError = error }
            }
        }

        if result.isEmpty, let firstError { throw firstError }
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }
}

enum AldiNordOfferParser {

    static func parse(html: String, sourceURL: URL) throws -> [RetailerOffer] {
        guard let json = PageScript.content(of: "__NEXT_DATA__", in: html),
              let root = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let props = root["props"] as? [String: Any],
              let pageProps = props["pageProps"] as? [String: Any],
              let apiText = pageProps["apiData"] as? String,
              let entries = try? JSONSerialization.jsonObject(with: Data(apiText.utf8)) as? [Any]
        else {
            throw DataSourceError.decoding("ALDI Nord: Seitendaten nicht gefunden")
        }

        let response = entries
            .compactMap { $0 as? [Any] }
            .first { ($0.first as? String) == "OFFER_GET" }
            .flatMap { $0.count > 1 ? $0[1] as? [String: Any] : nil }
            .flatMap { $0["res"] as? [String: Any] }

        guard let products = response?["algoliaDataMap"] as? [String: Any] else {
            throw DataSourceError.decoding("ALDI Nord: Angebotsdaten nicht gefunden")
        }

        // Reihenfolge wie auf der Seite: erst die Aktionsblöcke (Obst & Gemüse
        // vorn), dann alles Übrige. Die Produkte selbst liegen in einem
        // Wörterbuch ohne Reihenfolge.
        var order: [String] = []
        for category in (response?["categories"] as? [[String: Any]]) ?? [] {
            for block in (category["content"] as? [[String: Any]]) ?? [] {
                order.append(contentsOf: (block["productIds"] as? [String]) ?? [])
            }
        }
        order.append(contentsOf: products.keys.sorted())

        var seen = Set<String>()
        var result: [RetailerOffer] = []
        for key in order where seen.insert(key).inserted {
            guard let raw = products[key] as? [String: Any],
                  let offer = offer(from: raw, key: key, sourceURL: sourceURL) else { continue }
            result.append(offer)
        }
        return result
    }

    private static func offer(from raw: [String: Any], key: String, sourceURL: URL) -> RetailerOffer? {
        if raw["isRecall"] as? Bool == true { return nil }
        if raw["isAvailable"] as? Bool == false { return nil }

        guard let name = OfferFormatting.clean(raw["name"] as? String),
              let current = raw["currentPrice"] as? [String: Any],
              let price = OfferFormatting.amount(number: current["priceValue"])
        else { return nil }

        let promotion = (raw["promotionPrices"] as? [[String: Any]])?.first
        guard let validFrom = (promotion?["validFromLocalDate"] as? String).flatMap(RetailerOffer.day(from:))
                ?? OfferFormatting.berlinDay(epoch: current["validFrom"])
        else { return nil }
        let validTo = (promotion?["validUntilLocalDate"] as? String).flatMap(RetailerOffer.day(from:))
            ?? OfferFormatting.berlinDay(epoch: current["validUntil"])
        if let validTo, validTo < validFrom { return nil }

        let strike = current["strikePrice"] as? [String: Any]
        let regular = OfferFormatting.amount(number: strike?["strikePriceValue"])
            .flatMap { $0 > price ? Money(amount: $0) : nil }
        let labels = current["priceTagLabels"] as? [String: Any]
        let brand = OfferFormatting.clean(raw["brandName"] as? String)

        let basePrice = (current["basePrice"] as? [[String: Any]])?.first.flatMap { entry -> String? in
            guard let value = OfferFormatting.amount(number: entry["basePriceValue"]),
                  let scale = OfferFormatting.clean(entry["basePriceScale"] as? String) else { return nil }
            return OfferFormatting.basePrice(amount: value, reference: "1 " + scaleLabel(scale))
        }

        let identifier = (raw["objectID"] as? String)
            ?? (raw["objectID"] as? NSNumber)?.stringValue
            ?? key

        return RetailerOffer(
            // Mit Aktionsbeginn: Dieselbe Ware kann in zwei Wochen im Angebot sein.
            id: "aldi-nord:\(identifier)@\(dayKey(validFrom))",
            retailerName: AldiNordOffersClient.retailerName,
            title: brand ?? name,
            subtitle: brand == nil ? nil : name,
            details: OfferFormatting.clean(raw["shortDescription"] as? String),
            price: Money(amount: price),
            regularPrice: regular,
            regularPriceLabel: regular == nil ? nil : OfferFormatting.clean(strike?["strikePriceLabel"] as? String),
            discountPercent: OfferFormatting.percent(labels?["promoText1"] as? String),
            unit: OfferFormatting.clean(raw["salesUnit"] as? String),
            basePriceText: basePrice,
            deposit: OfferFormatting.amount(number: raw["depositValue"]).map { Money(amount: $0) },
            validFrom: validFrom,
            validTo: validTo,
            sourceURL: sourceURL
        )
    }

    /// Kalendertag als „2026-09-07“.
    private static func dayKey(_ date: Date) -> String {
        let parts = RetailerOffer.calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// „Liter“ wird „l“, „kg (ATG)“ wird „kg Abtropfgewicht“.
    private static func scaleLabel(_ scale: String) -> String {
        switch scale.lowercased() {
        case "liter": return "l"
        case "kg (atg)": return "kg Abtropfgewicht"
        default: return scale
        }
    }
}

// MARK: - ALDI SÜD

/// Angebote von ALDI SÜD.
///
/// Die Übersicht verlinkt je Aktionstag eine eigene Seite
/// (`/angebote/2026-09-11`), jede mit bis zu 30 Produkten und weiteren Seiten
/// über `?page=2`. Beides erlaubt `robots.txt` ausdrücklich. ALDI SÜD nennt
/// kein Enddatum, nur „verfügbar seit“.
public struct AldiSuedOffersClient: Sendable {

    public static let retailerName = "ALDI SÜD"
    public static let pageURL = URL(string: "https://www.aldi-sued.de/angebote")!

    /// Aktionstage höchstens so weit vor und zurück.
    static let dayWindow = 7

    /// Obergrenze je Aktionstag – schützt vor einer Endlosschleife, falls die
    /// Seitenangabe einmal nicht stimmt.
    static let maximumPagesPerDay = 6

    private let runner: RequestRunner

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.runner = RequestRunner(transport: transport, maxAttempts: 2, baseDelay: 2)
    }

    public func offers(now: Date = Date()) async throws -> [RetailerOffer] {
        let landing = try await OfferFormatting.html(at: Self.pageURL, runner: runner)

        let calendar = RetailerOffer.calendar
        let today = calendar.startOfDay(for: now)
        let days: [(path: String, day: Date)] = AldiSuedOfferParser.dayPaths(inLanding: landing).compactMap { path in
            guard let day = RetailerOffer.day(from: String(path.dropFirst("/angebote/".count))),
                  let distance = calendar.dateComponents([.day], from: today, to: day).day,
                  abs(distance) <= Self.dayWindow else { return nil }
            return (path, day)
        }
        guard !days.isEmpty else {
            throw DataSourceError.decoding("ALDI SÜD: keine Aktionstage gefunden")
        }

        var seen = Set<String>()
        var result: [RetailerOffer] = []
        var firstError: Error?

        for entry in days {
            guard let dayURL = URL(string: "https://www.aldi-sued.de\(entry.path)") else { continue }
            do {
                var page = 1
                while page <= Self.maximumPagesPerDay {
                    let pageURL = page == 1 ? dayURL : URL(string: dayURL.absoluteString + "?page=\(page)") ?? dayURL
                    let html = try await OfferFormatting.html(at: pageURL, runner: runner)
                    let parsed = try AldiSuedOfferParser.parseDay(html: html, day: entry.day, sourceURL: dayURL)
                    for offer in parsed.offers where seen.insert(offer.id).inserted {
                        result.append(offer)
                    }
                    guard !parsed.offers.isEmpty,
                          let total = parsed.totalCount, let size = parsed.pageSize, size > 0,
                          page * size < total else { break }
                    page += 1
                }
            } catch {
                // Ein fehlender Aktionstag soll nicht alle anderen verwerfen.
                if firstError == nil { firstError = error }
            }
        }

        if result.isEmpty, let firstError { throw firstError }
        return result
    }
}

enum AldiSuedOfferParser {

    struct DayPage {
        let offers: [RetailerOffer]
        let totalCount: Int?
        let pageSize: Int?
    }

    /// Tagesseiten, auf die die Übersicht verlinkt – ohne Themenfilter.
    static func dayPaths(inLanding html: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"href="(/angebote/\d{4}-\d{2}-\d{2})""#) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        let paths = regex.matches(in: html, range: range).compactMap { match -> String? in
            guard let found = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[found])
        }
        return Array(Set(paths)).sorted()
    }

    static func parseDay(html: String, day: Date, sourceURL: URL) throws -> DayPage {
        guard let payload = NuxtPayload(html: html) else {
            throw DataSourceError.decoding("ALDI SÜD: Seitendaten nicht gefunden")
        }
        let offers = payload.objects(withKeys: ["sku", "name", "price"])
            .compactMap { offer(from: $0, day: day, sourceURL: sourceURL) }
        let pagination = payload.objects(withKeys: ["offset", "limit", "totalCount"]).first
        return DayPage(offers: offers,
                       totalCount: (pagination?["totalCount"] as? NSNumber)?.intValue,
                       pageSize: (pagination?["limit"] as? NSNumber)?.intValue)
    }

    private static func offer(from raw: [String: Any], day: Date, sourceURL: URL) -> RetailerOffer? {
        guard let sku = OfferFormatting.clean(raw["sku"] as? String),
              let name = OfferFormatting.clean(raw["name"] as? String),
              let price = raw["price"] as? [String: Any],
              let cents = (price["amountRelevant"] as? NSNumber) ?? (price["amount"] as? NSNumber),
              cents.intValue > 0
        else { return nil }
        if let currency = price["currencyCode"] as? String, currency != "EUR" { return nil }

        let amount = Decimal(cents.intValue) / 100
        let brand = OfferFormatting.clean(raw["brandName"] as? String)
        let regular = OfferFormatting.amount(price["wasPriceDisplay"] as? String)
            .flatMap { $0 > amount ? Money(amount: $0) : nil }
        let depositCents = (price["bottleDeposit"] as? NSNumber)?.intValue ?? 0

        return RetailerOffer(
            id: "aldi-sued:\(sku)",
            retailerName: AldiSuedOffersClient.retailerName,
            title: brand ?? name,
            subtitle: brand == nil ? nil : name,
            price: Money(amount: amount),
            regularPrice: regular,
            discountPercent: OfferFormatting.percent(price["savingsDisplay"] as? String),
            unit: OfferFormatting.clean(raw["sellingSize"] as? String),
            basePriceText: comparison(price["comparisonDisplay"] as? String),
            deposit: depositCents > 0 ? Money(amount: Decimal(depositCents) / 100) : nil,
            validFrom: (raw["onSaleDate"] as? String).flatMap(RetailerOffer.day(from:)) ?? day,
            validTo: nil,
            sourceURL: sourceURL
        )
    }

    /// „6,58 €/1 kg“ wird „1 kg = 6,58 €“ – im selben Stil wie bei den
    /// anderen Ketten.
    static func comparison(_ text: String?) -> String? {
        guard let text = OfferFormatting.clean(text) else { return nil }
        let parts = text.split(separator: "/", maxSplits: 1).map(String.init)
        guard parts.count == 2,
              let amount = OfferFormatting.amount(parts[0]),
              let reference = OfferFormatting.clean(parts[1]) else {
            return OfferFormatting.nonBreaking(text)
        }
        return OfferFormatting.basePrice(amount: amount, reference: reference)
    }
}
