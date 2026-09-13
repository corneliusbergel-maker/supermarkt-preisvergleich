import Foundation
import PriceCore

/// Angebote aus den Lidl-Aktionsprospekten, direkt von Lidl.
///
/// Geprüft am 2026-09-13: `lidl.de/robots.txt` erlaubt die Prospektübersicht,
/// der Prospektdienst `endpoints.leaflets.schwarz` hat keine `robots.txt`,
/// beide antworten einer App mit ehrlicher Preisfuchs-Kennung, und das
/// Impressum schränkt die Nutzung nicht ein.
///
/// **Einschränkung:** Strukturiert enthält der Prospekt nur die Artikel, die es
/// auch im Lidl-Onlineshop gibt – Non-Food sowie Wein, Bier und Spirituosen.
/// Lebensmittel stehen nur als Bild im Prospekt; die liest die App nicht.
public struct LidlOffersClient: Sendable {

    public static let retailerName = "Lidl"
    public static let pageURL = URL(string: "https://www.lidl.de/c/online-prospekte/s10005610")!
    static let flyerEndpoint = URL(string: "https://endpoints.leaflets.schwarz/v4/flyer")!

    /// Höchstens so viele Prospekte je Durchlauf: die laufende und die
    /// kommenden Wochen.
    static let maximumFlyers = 3

    private let runner: RequestRunner

    public init(transport: HTTPTransport = URLSessionTransport()) {
        self.runner = RequestRunner(transport: transport, maxAttempts: 2, baseDelay: 2)
    }

    public func offers() async throws -> [RetailerOffer] {
        let html = try await OfferFormatting.html(at: Self.pageURL, runner: runner)
        let identifiers = Array(LidlOfferParser.flyerIdentifiers(in: html).prefix(Self.maximumFlyers))
        guard !identifiers.isEmpty else {
            throw DataSourceError.decoding("Lidl: keine Aktionsprospekte gefunden")
        }

        var result: [RetailerOffer] = []
        var firstError: Error?
        for identifier in identifiers {
            do {
                let data = try await runner.run(Self.flyerRequest(identifier))
                result += try LidlOfferParser.parse(flyerJSON: data)
            } catch {
                // Fehlt ein Prospekt, bleiben die anderen sichtbar.
                if firstError == nil { firstError = error }
            }
        }

        if result.isEmpty, let firstError { throw firstError }
        var seen = Set<String>()
        return result.filter { seen.insert($0.id).inserted }
    }

    /// Ohne `region_id`: Die Angaben sind freiwillig, und der Prospekt kommt
    /// auch ohne sie vollständig.
    static func flyerRequest(_ identifier: String) -> URLRequest {
        var components = URLComponents(url: flyerEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "flyer_identifier", value: identifier)]
        var request = URLRequest(url: components?.url ?? flyerEndpoint)
        request.setValue(APIIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}

/// Liest Prospektkennungen aus der Übersichtsseite und Artikel aus dem Prospekt.
enum LidlOfferParser {

    /// Kennungen der Aktionsprospekte in der Reihenfolge der Seite, etwa
    /// `aktionsprospekt-14-09-2026-19-09-2026-aaacd7`.
    static func flyerIdentifiers(in html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: "/l/prospekte/(aktionsprospekt-\\d{2}-\\d{2}-\\d{4}-\\d{2}-\\d{2}-\\d{4}-[a-z0-9]+)/"
        ) else { return [] }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var seen = Set<String>()
        var result: [String] = []
        for match in regex.matches(in: html, range: range) {
            guard let found = Range(match.range(at: 1), in: html) else { continue }
            let identifier = String(html[found])
            if seen.insert(identifier).inserted {
                result.append(identifier)
            }
        }
        return result
    }

    static func parse(flyerJSON data: Data) throws -> [RetailerOffer] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let flyer = root["flyer"] as? [String: Any] else {
            throw DataSourceError.decoding("Lidl: Prospektdaten nicht lesbar")
        }

        let fromText = ((flyer["offerStartDate"] as? String) ?? (flyer["startDate"] as? String))
            .map { String($0.prefix(10)) }
        let toText = ((flyer["offerEndDate"] as? String) ?? (flyer["endDate"] as? String))
            .map { String($0.prefix(10)) }
        guard let fromText, let toText,
              let validFrom = RetailerOffer.day(from: fromText),
              let validTo = RetailerOffer.day(from: toText),
              validFrom <= validTo else {
            throw DataSourceError.decoding("Lidl: Gültigkeit des Prospekts fehlt")
        }

        let rawProducts: [Any]
        if let keyed = flyer["products"] as? [String: Any] {
            rawProducts = Array(keyed.values)
        } else {
            rawProducts = flyer["products"] as? [Any] ?? []
        }

        // Getränke zuerst – sie gehören am ehesten auf eine Einkaufsliste.
        var entries: [(group: Int, offer: RetailerOffer)] = []
        for case let product as [String: Any] in rawProducts {
            guard let offer = makeOffer(product, validFrom: validFrom, validTo: validTo,
                                        dayKey: fromText) else { continue }
            let category = product["wonCategoryPrimary"] as? String ?? ""
            entries.append((category.contains("Wein, Bier") ? 0 : 1, offer))
        }

        return entries
            .sorted { $0.group != $1.group ? $0.group < $1.group : $0.offer.title < $1.offer.title }
            .map { $0.offer }
    }

    static func makeOffer(_ product: [String: Any],
                          validFrom: Date,
                          validTo: Date,
                          dayKey: String) -> RetailerOffer? {
        if let currency = product["currencyText"] as? String, currency.uppercased() != "EUR" {
            return nil
        }

        let identifier = (product["productId"] as? String)
            ?? (product["productId"] as? NSNumber)?.stringValue
        guard let identifier,
              let title = OfferFormatting.clean(withoutMarks(plainText(product["title"] as? String))),
              let amount = OfferFormatting.amount(product["price"] as? String)
                ?? OfferFormatting.amount(number: product["price"])
        else { return nil }

        // Lidl setzt die Marke vor den Artikel („KILBEGGAN Berry Selection“).
        let brand = OfferFormatting.clean(withoutMarks(product["brand"] as? String))
        var article: String?
        if let brand {
            let rest = title.range(of: brand, options: [.caseInsensitive, .anchored])
                .map { String(title[$0.upperBound...]) }
            article = OfferFormatting.clean(rest ?? title)
        }

        let description = OfferFormatting.clean(plainText(product["description"] as? String))
        let sourceURL = (product["canonicalUrl"] as? String)
            .flatMap { $0.hasPrefix("/") ? URL(string: "https://www.lidl.de" + $0) : URL(string: $0) }
            ?? LidlOffersClient.pageURL

        return RetailerOffer(
            id: "lidl:\(identifier)@\(dayKey)",
            retailerName: LidlOffersClient.retailerName,
            title: brand ?? title,
            subtitle: brand == nil ? nil : (article ?? title),
            details: description.map { shortened($0, limit: 140) },
            price: Money(amount: amount),
            unit: packagePhrase(in: [title, description].compactMap { $0 }),
            validFrom: validFrom,
            validTo: validTo,
            sourceURL: sourceURL
        )
    }

    // MARK: - Texte

    /// HTML-Text ohne Tags, mit aufgelösten Entitäten und gewöhnlichen
    /// Bindestrichen statt geschützter (U+2011).
    static func plainText(_ html: String?) -> String? {
        guard let html else { return nil }
        let withoutTags = html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        return decodeEntities(withoutTags).replacingOccurrences(of: "\u{2011}", with: "-")
    }

    static func withoutMarks(_ text: String?) -> String? {
        text.map { $0.replacingOccurrences(of: "®", with: "")
                    .replacingOccurrences(of: "™", with: "")
                    .replacingOccurrences(of: "©", with: "") }
    }

    private static let namedEntities: [String: String] = [
        "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&lt;": "<", "&gt;": ">",
        "&auml;": "ä", "&ouml;": "ö", "&uuml;": "ü", "&Auml;": "Ä", "&Ouml;": "Ö", "&Uuml;": "Ü",
        "&szlig;": "ß", "&eacute;": "é", "&egrave;": "è", "&ecirc;": "ê", "&agrave;": "à",
        "&ocirc;": "ô", "&ccedil;": "ç", "&reg;": "®", "&trade;": "™", "&ndash;": "–",
        "&bdquo;": "„", "&ldquo;": "“", "&rdquo;": "”"
    ]

    static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, character) in namedEntities {
            result = result.replacingOccurrences(of: entity, with: character)
        }

        // Numerische Entitäten wie „&#8211;“.
        if let regex = try? NSRegularExpression(pattern: "&#(\\d{2,6});") {
            let matches = regex.matches(in: result, range: NSRange(result.startIndex..<result.endIndex, in: result))
            for match in matches.reversed() {
                guard let whole = Range(match.range, in: result),
                      let digits = Range(match.range(at: 1), in: result),
                      let code = UInt32(result[digits]),
                      let scalar = Unicode.Scalar(code) else { continue }
                result.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }

        // Zuletzt, damit „&amp;uuml;“ nicht doppelt aufgelöst wird.
        return result.replacingOccurrences(of: "&amp;", with: "&")
    }

    /// Erste Packungsangabe wie „0,7-l-Flasche“ oder „0,75 l“.
    static func packagePhrase(in texts: [String]) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "\\d+(?:[.,]\\d+)?\\s*-?\\s*(?:kg|g|ml|cl|l)(?:-[a-zäöüß]+\\.?)?(?![a-zäöüß])",
            options: [.caseInsensitive]
        ) else { return nil }

        for text in texts {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            if let match = regex.firstMatch(in: text, range: range),
               let found = Range(match.range, in: text) {
                return String(text[found])
            }
        }
        return nil
    }

    /// Kürzt lange Werbetexte an einer Wortgrenze.
    static func shortened(_ text: String, limit: Int) -> String {
        guard text.count > limit else { return text }
        let prefix = text.prefix(limit)
        let cut = prefix.lastIndex(of: " ").map { prefix[..<$0] } ?? prefix
        return cut.trimmingCharacters(in: .whitespaces) + " …"
    }
}
