import Foundation
import PriceCore

/// Wochenangebote von Kaufland, direkt von der Angebotsseite der Kette.
///
/// Warum Kaufland und keine andere Kette: Als einzige hat Kaufland am
/// 2026-09-12 alle Prüfungen bestanden. `robots.txt` erlaubt die
/// Übersichtsseite, die Seite antwortet einer App, die sich als Preisfuchs zu
/// erkennen gibt, weder Impressum noch Website schränken die Nutzung ein, und
/// die Angebote stehen strukturiert im Seitenquelltext. Die Gründe gegen die
/// übrigen Ketten stehen in `DATENQUELLEN-SUPERMAERKTE.md`.
///
/// Die Seite zeigt die Standardauswahl von kaufland.de, ohne gewählte Filiale.
/// Einzelne Filialen können abweichen – die Oberfläche sagt das dazu.
public struct KauflandOffersClient: Sendable {

    public static let retailerName = "Kaufland"
    public static let pageURL = URL(string: "https://filiale.kaufland.de/angebote/uebersicht.html")!

    private let runner: RequestRunner

    public init(transport: HTTPTransport = URLSessionTransport()) {
        // Sparsam wiederholen: Die Seite ist groß, und ein Händler soll von
        // dieser App nicht mehr Last bekommen als von einem Menschen.
        self.runner = RequestRunner(transport: transport, maxAttempts: 2, baseDelay: 2)
    }

    public func offers() async throws -> [RetailerOffer] {
        var request = URLRequest(url: Self.pageURL)
        request.setValue(APIIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")

        let data = try await runner.run(request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw DataSourceError.invalidResponse
        }
        return try KauflandOfferParser.parse(html: html, sourceURL: Self.pageURL)
    }
}

/// Liest die Angebote aus dem Quelltext der Kaufland-Angebotsseite.
///
/// Die Seite legt ihre Daten als `window.SSR['…'] = {…};` in ein Skript; der
/// Baustein mit `"component":"OfferTemplate"` enthält die Angebote. Einzelne
/// unlesbare Einträge werden übersprungen, statt die ganze Liste zu verwerfen.
enum KauflandOfferParser {

    static func parse(html: String, sourceURL: URL) throws -> [RetailerOffer] {
        guard let marker = html.range(of: "\"component\":\"OfferTemplate\""),
              let assignment = html.range(of: "= {", options: .backwards,
                                          range: html.startIndex..<marker.lowerBound),
              let scriptEnd = html.range(of: "</script>",
                                         range: marker.upperBound..<html.endIndex)
        else {
            throw DataSourceError.decoding("Kaufland: Angebotsdaten nicht gefunden")
        }

        let jsonStart = html.index(assignment.lowerBound, offsetBy: 2)
        var json = html[jsonStart..<scriptEnd.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if json.hasSuffix(";") { json.removeLast() }

        let template: Template
        do {
            template = try JSONDecoder().decode(Template.self, from: Data(json.utf8))
        } catch {
            throw DataSourceError.decoding("Kaufland: \(error)")
        }

        var seen = Set<String>()
        var result: [RetailerOffer] = []
        for cycle in template.props.offerData.cycles {
            for category in cycle.categories {
                for raw in category.offers {
                    guard let offer = raw.toOffer(sourceURL: sourceURL),
                          seen.insert(offer.id).inserted else { continue }
                    result.append(offer)
                }
            }
        }
        return result
    }

    // MARK: - Übertragungsformat

    private struct Template: Decodable {
        let props: Props
    }

    private struct Props: Decodable {
        let offerData: OfferData
    }

    private struct OfferData: Decodable {
        let cycles: [Cycle]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            cycles = try container.decodeIfPresent([Cycle].self, forKey: .cycles) ?? []
        }

        private enum CodingKeys: String, CodingKey { case cycles }
    }

    private struct Cycle: Decodable {
        let categories: [Category]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            categories = try container.decodeIfPresent([Category].self, forKey: .categories) ?? []
        }

        private enum CodingKeys: String, CodingKey { case categories }
    }

    private struct Category: Decodable {
        let offers: [RawOffer]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            guard container.contains(.offers) else {
                offers = []
                return
            }
            var list = try container.nestedUnkeyedContainer(forKey: .offers)
            var decoded: [RawOffer] = []
            while !list.isAtEnd {
                if let offer = try? list.decode(RawOffer.self) {
                    decoded.append(offer)
                } else if (try? list.decode(Skipped.self)) == nil {
                    // Weder Angebot noch Objekt: Ohne Fortschritt liefe die
                    // Schleife endlos.
                    break
                }
            }
            offers = decoded
        }

        private enum CodingKeys: String, CodingKey { case offers }
    }

    private struct Skipped: Decodable {}

    private struct RawOffer: Decodable {
        let offerId: String?
        let dateFrom: String?
        let dateTo: String?
        let title: String?
        let detailTitle: String?
        let subtitle: String?
        let detailDescription: String?
        let unit: String?
        let discount: Double?
        let loyaltyDiscount: Double?
        let price: Double?
        let formattedPrice: String?
        let formattedOldPrice: String?
        let formattedBasePrice: String?
        let basePrice: String?
        let loyaltyFormattedPrice: String?
        let loyaltyFormattedOldPrice: String?
        let country: String?

        func toOffer(sourceURL: URL) -> RetailerOffer? {
            if let country, country.uppercased() != "DE" { return nil }

            // „*Mit Kaufland Card“ steht bei manchen Angeboten als Detailtitel –
            // das ist ein Hinweis, kein Artikelname.
            let fallbackTitle = Self.clean(detailTitle).flatMap { $0.hasPrefix("*") ? nil : $0 }

            guard let name = Self.clean(title) ?? fallbackTitle,
                  let fromText = dateFrom, let toText = dateTo,
                  let validFrom = RetailerOffer.day(from: fromText),
                  let validTo = RetailerOffer.day(from: toText),
                  validFrom <= validTo
            else { return nil }

            // `price` ist der Preis ohne Karte; bei Angeboten nur für
            // Karteninhaber steht dort 0. Der Kartenpreis kommt mit Sternchen
            // („2.22*“).
            let offerPrice = Self.positiveAmount(formattedPrice)
                ?? price.flatMap { Self.positiveAmount(String($0)) }
            let cardPrice = Self.positiveAmount(loyaltyFormattedPrice)
            guard let lowest = [offerPrice, cardPrice].compactMap({ $0 }).min() else { return nil }

            let regular = (Self.positiveAmount(formattedOldPrice)
                           ?? Self.positiveAmount(loyaltyFormattedOldPrice))
                .flatMap { $0 > lowest ? Money(amount: $0) : nil }

            return RetailerOffer(
                id: offerId ?? "\(name)|\(fromText)|\(lowest)",
                retailerName: KauflandOffersClient.retailerName,
                title: name,
                subtitle: Self.clean(subtitle),
                details: Self.clean(detailDescription),
                price: offerPrice.map { Money(amount: $0) },
                loyaltyPrice: cardPrice.map { Money(amount: $0) },
                regularPrice: regular,
                discountPercent: offerPrice == nil ? nil : Self.percent(discount),
                loyaltyDiscountPercent: cardPrice == nil ? nil : Self.percent(loyaltyDiscount),
                // Bei Non-Food steht als Einheit oft nur „je“ – ohne Angabe
                // dahinter ist das keine Information.
                unit: Self.clean(unit).flatMap { $0.lowercased() == "je" ? nil : $0 },
                basePriceText: Self.basePrice(Self.clean(formattedBasePrice) ?? Self.clean(basePrice)),
                validFrom: validFrom,
                validTo: validTo,
                sourceURL: sourceURL
            )
        }

        private static func clean(_ text: String?) -> String? {
            guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !trimmed.isEmpty else { return nil }
            return trimmed
        }

        private static func positiveAmount(_ text: String?) -> Decimal? {
            guard let text = clean(text?.replacingOccurrences(of: "*", with: "")),
                  let value = DecimalParsing.decimal(from: text),
                  value > 0 else { return nil }
            return value
        }

        private static func percent(_ value: Double?) -> Int? {
            guard let value, value > 0 else { return nil }
            return Int(value.rounded())
        }

        /// „(1 kg = 2.66)“ wird zu „1 kg = 2,66 €“ – mit geschütztem Leerzeichen
        /// vor dem Euro, sonst landet das Zeichen allein in der nächsten Zeile.
        private static func basePrice(_ text: String?) -> String? {
            guard var text else { return nil }
            text = text.trimmingCharacters(in: CharacterSet(charactersIn: "()* "))
            text = text.replacingOccurrences(of: "(\\d)\\.(\\d)", with: "$1,$2",
                                             options: .regularExpression)
            guard !text.isEmpty else { return nil }
            return text.hasSuffix("€") ? text : text + "\u{00A0}€"
        }
    }
}
