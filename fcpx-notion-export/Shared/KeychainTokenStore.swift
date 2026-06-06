import Foundation
import Security

/// Guarda segredos no Keychain (sandbox da própria extensão), sem App Group /
/// access-group explícito — funciona sem conta paga do Apple Developer.
enum KeychainStore {

    private static let service = "com.vitaminapublicitaria.NotionExport"

    static func save(_ value: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = Data(value.utf8)
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func clear(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Credenciais necessárias para o fluxo Cloudflare Stream + Notion.
enum Credentials {
    static var notionToken: String? {
        get { KeychainStore.load(account: "notion_token") }
        set { newValue.map { KeychainStore.save($0, account: "notion_token") } }
    }
    static var cloudflareToken: String? {
        get { KeychainStore.load(account: "cloudflare_token") }
        set { newValue.map { KeychainStore.save($0, account: "cloudflare_token") } }
    }

    /// O Account ID do Cloudflare não é segredo; fica em UserDefaults.
    static var cloudflareAccountId: String? {
        get { UserDefaults.standard.string(forKey: "cloudflare_account_id") }
        set { UserDefaults.standard.set(newValue, forKey: "cloudflare_account_id") }
    }

    /// Há tudo o que é preciso para operar?
    static var isComplete: Bool {
        [notionToken, cloudflareToken, cloudflareAccountId].allSatisfy { ($0?.isEmpty == false) }
    }
}

/// Preferências lembradas entre exportações (banco e propriedades padrão).
enum AppConfig {
    private static let defaults = UserDefaults.standard

    static var databaseId: String? {
        get { defaults.string(forKey: "default_database_id") }
        set { defaults.set(newValue, forKey: "default_database_id") }
    }
    static var urlPropertyName: String? {
        get { defaults.string(forKey: "default_url_property") }
        set { defaults.set(newValue, forKey: "default_url_property") }
    }
    static var filePropertyName: String? {
        get { defaults.string(forKey: "default_file_property") }
        set { defaults.set(newValue, forKey: "default_file_property") }
    }

    /// Propriedade que guarda o status de aprovação (tipo Status/Select).
    static var statusPropertyName: String? {
        get { defaults.string(forKey: "default_status_property") }
        set { defaults.set(newValue, forKey: "default_status_property") }
    }

    /// Card pré-selecionado no painel (usado para pré-marcar no Compartilhar).
    static var preferredCardId: String? {
        get { defaults.string(forKey: "preferred_card_id") }
        set { defaults.set(newValue, forKey: "preferred_card_id") }
    }
    static var preferredCardTitle: String? {
        get { defaults.string(forKey: "preferred_card_title") }
        set { defaults.set(newValue, forKey: "preferred_card_title") }
    }
}
