import Foundation

enum CloudflareError: LocalizedError {
    case missingCredentials
    case http(status: Int, body: String)
    case noUploadURL
    case noMediaId
    case processingTimeout
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .missingCredentials: return "Account ID ou token do Cloudflare não configurados."
        case let .http(status, body): return "Cloudflare retornou HTTP \(status): \(body)"
        case .noUploadURL: return "Cloudflare não devolveu a URL de upload (header Location)."
        case .noMediaId: return "Cloudflare não devolveu o ID do vídeo (stream-media-id)."
        case .processingTimeout: return "O vídeo subiu, mas demorou demais para ficar pronto no Cloudflare."
        case .fileNotFound: return "Arquivo de vídeo não encontrado."
        }
    }
}

/// Sobe um vídeo para o Cloudflare Stream via tus (resumable) e devolve o link
/// de "assistir" público (https://customer-XXXX.cloudflarestream.com/<id>/watch).
final class CloudflareStreamClient {

    private let accountId: String
    private let apiToken: String
    private let session: URLSession

    /// 50 MiB — múltiplo de 256 KiB e acima do mínimo de 5 MiB exigido pelo tus do Cloudflare.
    private let chunkSize = 52_428_800
    private let apiBase = "https://api.cloudflare.com/client/v4"

    init(accountId: String, apiToken: String, session: URLSession = .shared) {
        self.accountId = accountId
        self.apiToken = apiToken
        self.session = session
    }

    /// Faz o upload completo e retorna o link de watch já pronto para tocar.
    /// `progress` 0.0–1.0; `status` reporta a etapa atual.
    func uploadAndGetWatchURL(
        fileURL: URL,
        progress: @escaping (Double) -> Void,
        status: @escaping (String) -> Void
    ) async throws -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { throw CloudflareError.fileNotFound }
        let fileSize = (try fm.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0

        status("Iniciando upload no Cloudflare…")
        let (uid, uploadURL) = try await createUpload(filename: fileURL.lastPathComponent, fileSize: fileSize)

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var offset = 0
        while offset < fileSize {
            let chunk = handle.readData(ofLength: chunkSize)
            if chunk.isEmpty { break }
            try await patchChunk(uploadURL: uploadURL, offset: offset, data: chunk)
            offset += chunk.count
            progress(Double(offset) / Double(max(fileSize, 1)) * 0.85)
            status("Enviando ao Cloudflare… \(Int(Double(offset) / Double(max(fileSize, 1)) * 100))%")
        }

        status("Processando o vídeo no Cloudflare…")
        let watchURL = try await waitUntilReady(uid: uid) { progress(0.85 + $0 * 0.15) }
        progress(1.0)
        return watchURL
    }

    // MARK: - tus

    private func createUpload(filename: String, fileSize: Int) async throws -> (uid: String, uploadURL: URL) {
        var request = URLRequest(url: URL(string: "\(apiBase)/accounts/\(accountId)/stream")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(fileSize), forHTTPHeaderField: "Upload-Length")
        let nameB64 = Data(filename.utf8).base64EncodedString()
        request.setValue("name \(nameB64)", forHTTPHeaderField: "Upload-Metadata")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudflareError.noUploadURL }
        guard (200...299).contains(http.statusCode) else {
            throw CloudflareError.http(status: http.statusCode,
                                       body: String(data: data, encoding: .utf8) ?? "")
        }
        guard let uid = http.value(forHTTPHeaderField: "stream-media-id") else {
            throw CloudflareError.noMediaId
        }
        guard let location = http.value(forHTTPHeaderField: "Location"),
              let url = URL(string: location, relativeTo: URL(string: apiBase)) else {
            throw CloudflareError.noUploadURL
        }
        return (uid, url)
    }

    private func patchChunk(uploadURL: URL, offset: Int, data: Data) async throws {
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "PATCH"
        request.setValue("1.0.0", forHTTPHeaderField: "Tus-Resumable")
        request.setValue(String(offset), forHTTPHeaderField: "Upload-Offset")
        request.setValue("application/offset+octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let (body, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CloudflareError.noUploadURL }
        guard (200...299).contains(http.statusCode) else {
            throw CloudflareError.http(status: http.statusCode,
                                       body: String(data: body, encoding: .utf8) ?? "")
        }
    }

    // MARK: - Status polling

    private func waitUntilReady(uid: String, progress: @escaping (Double) -> Void) async throws -> String {
        let maxAttempts = 200          // ~10 min com 3s de intervalo
        for attempt in 0..<maxAttempts {
            var request = URLRequest(url: URL(string: "\(apiBase)/accounts/\(accountId)/stream/\(uid)")!)
            request.setValue("Bearer \(apiToken)", forHTTPHeaderField: "Authorization")
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw CloudflareError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1,
                                           body: String(data: data, encoding: .utf8) ?? "")
            }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let result = json["result"] as? [String: Any] {
                let ready = result["readyToStream"] as? Bool ?? false
                let preview = result["preview"] as? String
                if ready {
                    return preview ?? "https://cloudflarestream.com/\(uid)/watch"
                }
                if let status = result["status"] as? [String: Any],
                   let pct = status["pctComplete"] as? String, let value = Double(pct) {
                    progress(min(value / 100.0, 0.99))
                }
            }
            try await Task.sleep(nanoseconds: 3 * 1_000_000_000)
            _ = attempt
        }
        throw CloudflareError.processingTimeout
    }
}
