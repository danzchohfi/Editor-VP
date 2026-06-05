import Foundation
import Security

/// Guarda o token interno do Notion no Keychain (sandbox da própria extensão).
/// Sem App Group / access-group explícito — usa o keychain padrão do bundle,
/// o que funciona sem conta paga do Apple Developer.
enum KeychainTokenStore {

    private static let service = "com.vitaminapublicitaria.NotionExport"
    private static let account = "notion_internal_token"

    static func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Remove o existente antes de inserir o novo.
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
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

/// Preferências lembradas entre exportações (banco e propriedade padrão).
enum AppConfig {
    private static let defaults = UserDefaults.standard
    private static let kDatabaseId = "default_database_id"
    private static let kPropertyName = "default_property_name"

    static var databaseId: String? {
        get { defaults.string(forKey: kDatabaseId) }
        set { defaults.set(newValue, forKey: kDatabaseId) }
    }

    static var propertyName: String? {
        get { defaults.string(forKey: kPropertyName) }
        set { defaults.set(newValue, forKey: kPropertyName) }
    }
}
