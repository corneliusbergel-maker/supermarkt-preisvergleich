import Foundation
import PriceCore

/// Findet eingebettete Daten in Angebotsseiten.
enum PageScript {

    /// Inhalt des `<script>`-Elements mit dieser `id`.
    static func content(of id: String, in html: String) -> String? {
        guard let idRange = html.range(of: "id=\"\(id)\""),
              let tagEnd = html.range(of: ">", range: idRange.upperBound..<html.endIndex),
              let close = html.range(of: "</script>", range: tagEnd.upperBound..<html.endIndex)
        else { return nil }
        return String(html[tagEnd.upperBound..<close.lowerBound])
    }
}

/// Liest das Format, in dem Nuxt-Seiten ihren Zustand einbetten (`__NUXT_DATA__`).
///
/// Die Daten sind eine flache Liste. Objekte und Listen darin enthalten keine
/// Werte, sondern Positionen in dieser Liste; Einträge wie `["Reactive", 12]`
/// umhüllen einen Wert nur. Erst das Auflösen der Positionen ergibt die
/// eigentlichen Daten.
struct NuxtPayload {

    private let values: [Any]

    init?(html: String) {
        guard let json = PageScript.content(of: "__NUXT_DATA__", in: html),
              let values = try? JSONSerialization.jsonObject(with: Data(json.utf8),
                                                             options: [.fragmentsAllowed]) as? [Any]
        else { return nil }
        self.values = values
    }

    /// Alle Objekte mit mindestens diesen Schlüsseln, aufgelöst.
    ///
    /// Gesucht wird direkt in der flachen Liste statt über den ganzen Baum:
    /// Viele Objekte werden mehrfach referenziert, ein vollständiges Auflösen
    /// würde sie vervielfachen.
    func objects(withKeys keys: Set<String>, depth: Int = 12) -> [[String: Any]] {
        values
            .compactMap { $0 as? [String: Any] }
            .filter { keys.isSubset(of: Set($0.keys)) }
            .compactMap { resolve(object: $0, depth: depth) }
    }

    private func resolve(index: Int, depth: Int) -> Any? {
        guard depth > 0, index >= 0, index < values.count else { return nil }
        let value = values[index]

        if value is NSNull { return nil }
        if let object = value as? [String: Any] { return resolve(object: object, depth: depth) }
        if let array = value as? [Any] {
            if let tag = array.first as? String {
                switch tag {
                case "Reactive", "ShallowReactive", "Ref", "ShallowRef", "EmptyRef", "EmptyShallowRef":
                    return array.count > 1 ? resolve(reference: array[1], depth: depth - 1) : nil
                case "Date":
                    return array.count > 1 ? array[1] : nil
                case "Set", "Map":
                    return array.dropFirst().compactMap { resolve(reference: $0, depth: depth - 1) }
                default:
                    break
                }
            }
            return array.compactMap { resolve(reference: $0, depth: depth - 1) }
        }
        return value
    }

    private func resolve(reference: Any, depth: Int) -> Any? {
        guard let number = reference as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return resolve(index: number.intValue, depth: depth)
    }

    private func resolve(object: [String: Any], depth: Int) -> [String: Any]? {
        guard depth > 0 else { return nil }
        var result: [String: Any] = [:]
        for (key, reference) in object {
            if let resolved = resolve(reference: reference, depth: depth - 1) {
                result[key] = resolved
            }
        }
        return result
    }
}

/// Einheitliche Aufbereitung von Texten und Beträgen aus Angebotsseiten.
enum OfferFormatting {

    /// Entfernt doppelte und umgebende Leerzeichen; leer wird `nil`.
    static func clean(_ text: String?) -> String? {
        guard let text else { return nil }
        let collapsed = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    /// „5,29 €“, „2.22*“ oder „0.79“ als positiver Betrag.
    static func amount(_ text: String?) -> Decimal? {
        guard let text else { return nil }
        var digits = String(text.filter { $0.isNumber || $0 == "," || $0 == "." })
        if digits.contains(",") {
            digits = digits.replacingOccurrences(of: ".", with: "")
                .replacingOccurrences(of: ",", with: ".")
        }
        guard !digits.isEmpty,
              let value = Decimal(string: digits, locale: Locale(identifier: "en_US_POSIX")),
              value > 0 else { return nil }
        return value
    }

    /// Betrag aus einer JSON-Zahl, ohne Umweg über `Double`-Rundung.
    static func amount(number: Any?) -> Decimal? {
        guard let number = number as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        return amount(number.stringValue)
    }

    /// „-20 %“ oder „24 %“ als ganze Prozent. Texte ohne Prozentzeichen
    /// („2 für 1“) ergeben nichts.
    static func percent(_ text: String?) -> Int? {
        guard let text, let before = text.split(separator: "%").first, text.contains("%") else {
            return nil
        }
        guard let value = Int(before.filter(\.isNumber)), value > 0, value < 100 else { return nil }
        return value
    }

    /// Tag einer Zeitangabe in Sekunden seit 1970, nach deutschem Kalender.
    static func berlinDay(epoch: Any?) -> Date? {
        guard let number = epoch as? NSNumber, number.doubleValue > 0 else { return nil }
        return RetailerOffer.calendar.startOfDay(for: Date(timeIntervalSince1970: number.doubleValue))
    }

    /// „1 kg = 9,49 €“ – durchgehend mit geschützten Leerzeichen, damit der
    /// Grundpreis nur als Ganzes umbricht.
    static func basePrice(amount: Decimal, reference: String) -> String {
        nonBreaking("\(reference) = \(germanPrice(amount)) €")
    }

    static func germanPrice(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    static func nonBreaking(_ text: String) -> String {
        text.replacingOccurrences(of: " ", with: "\u{00A0}")
    }

    /// Lädt eine Seite mit ehrlicher Kennung.
    static func html(at url: URL, runner: RequestRunner) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(APIIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        let data = try await runner.run(request)
        guard let html = String(data: data, encoding: .utf8) else {
            throw DataSourceError.invalidResponse
        }
        return html
    }
}
