import Foundation
import PriceCore

/// Eine angemeldete Sitzung bei Open Prices.
public struct OpenPricesSession: Sendable, Equatable {
    public let accessToken: String
    public let userID: String
    public let isModerator: Bool

    public init(accessToken: String, userID: String, isModerator: Bool) {
        self.accessToken = accessToken
        self.userID = userID
        self.isModerator = isModerator
    }
}

/// Trägt Preise zu Open Prices bei (#3, Abschnitt „Preis beitragen").
///
/// Das ist die Antwort auf die dünne Datenlage in Deutschland: Wer einen Preis
/// im Markt sieht, kann ihn mit einem Foto des Preisschilds hinterlegen. Damit
/// wächst genau der Teil der Datenbank, den man selbst braucht -- und er bleibt
/// unter ODbL für alle offen.
///
/// **Schreibvorgänge werden nicht wiederholt.** Anders als beim Lesen wäre ein
/// zweiter Versuch hier gefährlich: Kommt die erste Anfrage durch und geht nur
/// die Antwort verloren, entstünde ein Doppeleintrag in einer öffentlichen
/// Datenbank.
public struct OpenPricesContributionClient: Sendable {

    private let transport: HTTPTransport
    private let host: String

    public init(transport: HTTPTransport = URLSessionTransport(timeout: 60),
                host: String = "prices.openfoodfacts.org") {
        self.transport = transport
        self.host = host
    }

    // MARK: - Anmeldung

    /// Meldet mit den Zugangsdaten eines Open-Food-Facts-Kontos an.
    ///
    /// - Important: Der Benutzername ist die **Open-Food-Facts-Benutzerkennung**,
    ///   nicht die E-Mail-Adresse. Das Kennwort wird nur zum Abholen des Tokens
    ///   gesendet und **nirgends gespeichert** -- gespeichert wird allein der
    ///   zurückgegebene Token, und der gehört in den Schlüsselbund.
    public func signIn(username: String, password: String) async throws -> OpenPricesSession {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v1/auth"

        guard let url = components.url else { throw DataSourceError.invalidResponse }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(APIIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(
            "username=\(Self.escape(username))&password=\(Self.escape(password))".utf8
        )

        let response = try await send(request)
        do {
            let session = try JSONDecoder().decode(SessionDTO.self, from: response)
            return OpenPricesSession(accessToken: session.accessToken,
                                     userID: session.userID,
                                     isModerator: session.isModerator)
        } catch {
            throw DataSourceError.decoding(String(describing: error))
        }
    }

    // MARK: - Beleg hochladen

    /// Lädt ein Foto des Preisschilds hoch und gibt die Belegnummer zurück.
    ///
    /// Ohne Beleg nimmt Open Prices zwar Preise an, sie gelten dann aber als
    /// weniger verlässlich. Diese App lädt deshalb immer einen Beleg mit --
    /// das ist dieselbe Anforderung, die sie an fremde Daten stellt.
    public func uploadPriceTag(imageData: Data,
                               store: Store,
                               currency: String,
                               date: Date,
                               token: String) async throws -> Int {

        guard let osmType = store.osmType, let osmID = store.osmID else {
            throw DataSourceError.invalidResponse
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v1/proofs/upload"
        guard let url = components.url else { throw DataSourceError.invalidResponse }

        let boundary = "preisfuchs-\(UUID().uuidString)"
        var body = Data()

        func appendField(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(Data("\(value)\r\n".utf8))
        }

        appendField("type", "PRICE_TAG")
        appendField("location_osm_id", String(osmID))
        appendField("location_osm_type", osmType)
        appendField("currency", currency)
        appendField("date", Self.dayFormatter.string(from: date))

        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"file\"; "
                         + "filename=\"preisschild.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(imageData)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(APIIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        let response = try await send(request)
        do {
            return try JSONDecoder().decode(ProofDTO.self, from: response).id
        } catch {
            throw DataSourceError.decoding(String(describing: error))
        }
    }

    // MARK: - Preis melden

    /// Meldet den Preis. Setzt eine zuvor hochgeladene Belegnummer voraus.
    public func submitPrice(barcode: String,
                            price: Money,
                            date: Date,
                            store: Store,
                            proofID: Int,
                            isDiscounted: Bool,
                            priceWithoutDiscount: Money?,
                            token: String) async throws {

        guard let osmType = store.osmType, let osmID = store.osmID else {
            throw DataSourceError.invalidResponse
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = "/api/v1/prices"
        guard let url = components.url else { throw DataSourceError.invalidResponse }

        var payload: [String: Any] = [
            "product_code": barcode.filter(\.isNumber),
            "price": NSDecimalNumber(decimal: price.amount).doubleValue,
            "currency": price.currency,
            "date": Self.dayFormatter.string(from: date),
            "location_osm_id": osmID,
            "location_osm_type": osmType,
            "proof_id": proofID,
            "price_is_discounted": isDiscounted
        ]

        // Den Ursprungspreis nur mitsenden, wenn er wirklich bekannt ist.
        if isDiscounted, let priceWithoutDiscount {
            payload["price_without_discount"] =
                NSDecimalNumber(decimal: priceWithoutDiscount.amount).doubleValue
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else {
            throw DataSourceError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(APIIdentity.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body

        _ = try await send(request)
    }

    // MARK: - Innereien

    /// Ein Versuch, keine Wiederholung. Siehe Klassenkommentar.
    private func send(_ request: URLRequest) async throws -> Data {
        let response = try await transport.send(request)
        guard response.isSuccess else {
            throw DataSourceError.from(status: response.status,
                                       retryAfter: response.retryAfterSeconds)
        }
        return response.body
    }

    private static func escape(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Uebertragungsformate

private struct SessionDTO: Decodable {
    let accessToken: String
    let userID: String
    let isModerator: Bool

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case userID = "user_id"
        case isModerator = "is_moderator"
    }
}

private struct ProofDTO: Decodable {
    let id: Int
}
