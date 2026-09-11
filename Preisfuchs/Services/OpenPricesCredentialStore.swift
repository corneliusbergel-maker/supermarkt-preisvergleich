import Foundation
import Security
import PriceData

/// Bewahrt den Open-Prices-Token im Schlüsselbund auf.
///
/// **Nicht** in `UserDefaults`: Die liegen unverschlüsselt im App-Container
/// und landen in Backups im Klartext. Ein Zugangstoken gehört in den
/// Schlüsselbund, der ihn an das Gerät und dessen Entsperrung bindet.
///
/// Das **Kennwort** wird nie gespeichert – es dient einmalig dazu, den Token
/// abzuholen, und wird danach verworfen.
enum OpenPricesCredentialStore {

    private static let service = "de.preisfuchs.openprices"
    private static let account = "session"

    private struct StoredSession: Codable {
        let accessToken: String
        let userID: String
        let isModerator: Bool
    }

    // MARK: - Lesen

    static func load() -> OpenPricesSession? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let stored = try? JSONDecoder().decode(StoredSession.self, from: data)
        else { return nil }

        return OpenPricesSession(accessToken: stored.accessToken,
                                 userID: stored.userID,
                                 isModerator: stored.isModerator)
    }

    // MARK: - Schreiben

    @discardableResult
    static func save(_ session: OpenPricesSession) -> Bool {
        let stored = StoredSession(accessToken: session.accessToken,
                                   userID: session.userID,
                                   isModerator: session.isModerator)
        guard let data = try? JSONEncoder().encode(stored) else { return false }

        // Vorhandenen Eintrag ersetzen statt zu ergänzen.
        clear()

        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            // Nur nach der ersten Entsperrung lesbar und nicht in Backups --
            // ein Token nützt auf einem anderen Gerät niemandem.
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
