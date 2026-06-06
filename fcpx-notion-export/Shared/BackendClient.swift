import Foundation

/// Cliente do backend da equipe (Vercel). Opcional: se a URL de ingest estiver
/// configurada, a extensão avisa o backend (UID do Cloudflare + card) para ele
/// montar o link de aprovação e disparar status/WhatsApp. Caso contrário, a
/// extensão segue gravando o link cru do Cloudflare no Notion.
struct IngestResult {
    /// Link da página de aprovação devolvido pelo backend (se houver).
    let approvalUrl: String?
}

enum BackendError: LocalizedError {
    case http(status: Int, body: String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case let .http(status, body): return "Backend retornou HTTP \(status): \(body)"
        case .invalidResponse: return "Resposta inesperada do backend."
        }
    }
}

final class BackendClient {
    private let ingestURL: URL
    private let apiKey: String
    private let session: URLSession

    init(ingestURL: URL, apiKey: String, session: URLSession = .shared) {
        self.ingestURL = ingestURL
        self.apiKey = apiKey
        self.session = session
    }

    /// Avisa o backend sobre um vídeo recém-enviado para aprovação.
    func ingest(
        notionPageId: String,
        cloudflareUid: String,
        clientName: String,
        projectName: String,
        version: Int = 1
    ) async throws -> IngestResult {
        var request = URLRequest(url: ingestURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "notionPageId": notionPageId,
            "cloudflareUid": cloudflareUid,
            "clientName": clientName,
            "projectName": projectName,
            "version": version
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BackendError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            throw BackendError.http(status: http.statusCode,
                                    body: String(data: data, encoding: .utf8) ?? "")
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        return IngestResult(approvalUrl: json?["approvalUrl"] as? String)
    }
}
