import Foundation

/// Erros possíveis ao falar com a API do Notion.
enum NotionError: LocalizedError {
    case noToken
    case http(status: Int, body: String)
    case invalidResponse
    case missingTitleProperty
    case fileNotFound

    var errorDescription: String? {
        switch self {
        case .noToken:
            return "Token do Notion não configurado."
        case let .http(status, body):
            return "Notion retornou HTTP \(status): \(body)"
        case .invalidResponse:
            return "Resposta inesperada da API do Notion."
        case .missingTitleProperty:
            return "O banco de dados não tem propriedade de título."
        case .fileNotFound:
            return "Arquivo de vídeo não encontrado."
        }
    }
}

/// Representa um banco de dados do Notion (apenas id + nome para exibição).
struct NotionDatabase: Identifiable, Hashable {
    let id: String
    let title: String
}

/// Representa um registro (página) dentro de um banco de dados.
struct NotionPage: Identifiable, Hashable {
    let id: String
    let title: String
    var status: String? = nil
}

/// Um comentário de uma página do Notion (usado para o "pedir ajustes").
struct NotionComment: Identifiable, Hashable {
    var id: String { createdTime + text }
    let text: String
    let createdTime: String
}

/// Uma propriedade do banco de dados (nome + tipo Notion, ex.: "files", "title").
struct NotionProperty: Identifiable, Hashable {
    var id: String { name }
    let name: String
    let type: String
}

/// Cliente mínimo da API do Notion focado no fluxo:
/// listar bancos -> listar registros -> upload de arquivo -> anexar na propriedade.
final class NotionClient {

    private let token: String
    private let session: URLSession
    private let apiBase = URL(string: "https://api.notion.com/v1/")!
    private let notionVersion = "2022-06-28"

    /// Tamanho de cada parte em uploads multipart (10 MB — dentro da faixa 5–20 MB do Notion).
    private let partSize = 10 * 1024 * 1024
    /// Limite do Notion para upload em parte única (20 MB).
    private let singlePartLimit = 20 * 1024 * 1024

    init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    // MARK: - Request helpers

    private func makeRequest(path: String, method: String, json: [String: Any]? = nil) throws -> URLRequest {
        var request = URLRequest(url: URL(string: path, relativeTo: apiBase)!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(notionVersion, forHTTPHeaderField: "Notion-Version")
        if let json = json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        return request
    }

    @discardableResult
    private func send(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NotionError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "<sem corpo>"
            throw NotionError.http(status: http.statusCode, body: body)
        }
        let obj = try JSONSerialization.jsonObject(with: data)
        guard let dict = obj as? [String: Any] else { throw NotionError.invalidResponse }
        return dict
    }

    // MARK: - Discovery

    /// Lista os bancos de dados aos quais a integração tem acesso.
    func listDatabases() async throws -> [NotionDatabase] {
        let body: [String: Any] = [
            "filter": ["value": "database", "property": "object"],
            "page_size": 100
        ]
        let request = try makeRequest(path: "search", method: "POST", json: body)
        let response = try await send(request)
        let results = response["results"] as? [[String: Any]] ?? []
        return results.compactMap { item in
            guard let id = item["id"] as? String else { return nil }
            let title = Self.plainText(from: item["title"]) ?? "(sem título)"
            return NotionDatabase(id: id, title: title)
        }
    }

    /// Busca o schema do banco para descobrir título e propriedades de arquivo.
    func databaseProperties(databaseId: String) async throws -> (titleName: String, properties: [NotionProperty]) {
        let request = try makeRequest(path: "databases/\(databaseId)", method: "GET")
        let response = try await send(request)
        guard let props = response["properties"] as? [String: Any] else {
            throw NotionError.invalidResponse
        }
        var all: [NotionProperty] = []
        var titleName: String?
        for (name, value) in props {
            guard let dict = value as? [String: Any], let type = dict["type"] as? String else { continue }
            all.append(NotionProperty(name: name, type: type))
            if type == "title" { titleName = name }
        }
        guard let title = titleName else { throw NotionError.missingTitleProperty }
        return (title, all.sorted { $0.name < $1.name })
    }

    /// Lista registros do banco. `query` filtra pelo texto do título (client-side).
    /// Se `statusProperty` for informado, traz também o status de cada registro.
    func listPages(databaseId: String, titleProperty: String, query: String = "",
                   statusProperty: String? = nil) async throws -> [NotionPage] {
        var body: [String: Any] = ["page_size": 100]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            body["filter"] = ["property": titleProperty, "title": ["contains": trimmed]]
        }
        let request = try makeRequest(path: "databases/\(databaseId)/query", method: "POST", json: body)
        let response = try await send(request)
        let results = response["results"] as? [[String: Any]] ?? []
        return results.compactMap { page in
            guard let id = page["id"] as? String,
                  let props = page["properties"] as? [String: Any],
                  let titleProp = props[titleProperty] as? [String: Any] else { return nil }
            let title = Self.plainText(from: titleProp["title"]) ?? "(sem título)"
            var status: String?
            if let statusProperty = statusProperty, let sp = props[statusProperty] as? [String: Any] {
                status = Self.statusName(from: sp)
            }
            return NotionPage(id: id, title: title.isEmpty ? "(sem título)" : title, status: status)
        }
    }

    /// Lê os comentários de uma página (usado para mostrar o "pedir ajustes").
    /// Requer a capability "Read comments" habilitada na integração.
    func comments(pageId: String) async throws -> [NotionComment] {
        let request = try makeRequest(path: "comments?block_id=\(pageId)", method: "GET")
        let response = try await send(request)
        let results = response["results"] as? [[String: Any]] ?? []
        return results.compactMap { comment in
            let text = Self.plainText(from: comment["rich_text"]) ?? ""
            let created = comment["created_time"] as? String ?? ""
            return text.isEmpty ? nil : NotionComment(text: text, createdTime: created)
        }
    }

    // MARK: - File upload

    /// Sobe o vídeo para o Notion e devolve o `file_upload` id (sem anexar a nada).
    /// `progress` reporta de 0.0 a 1.0.
    func uploadFile(fileURL: URL, progress: @escaping (Double) -> Void) async throws -> (uploadId: String, filename: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { throw NotionError.fileNotFound }
        let attrs = try fm.attributesOfItem(atPath: fileURL.path)
        let fileSize = (attrs[.size] as? Int) ?? 0
        let filename = fileURL.lastPathComponent
        let contentType = Self.contentType(for: fileURL)

        let uploadId: String
        if fileSize <= singlePartLimit {
            uploadId = try await createFileUpload(filename: filename, contentType: contentType, parts: nil)
            let data = try Data(contentsOf: fileURL)
            try await sendPart(uploadId: uploadId, partNumber: nil, data: data,
                               filename: filename, contentType: contentType)
            progress(1.0)
        } else {
            let numberOfParts = Int(ceil(Double(fileSize) / Double(partSize)))
            uploadId = try await createFileUpload(filename: filename, contentType: contentType, parts: numberOfParts)
            let handle = try FileHandle(forReadingFrom: fileURL)
            defer { try? handle.close() }
            for part in 1...numberOfParts {
                let chunk = handle.readData(ofLength: partSize)
                try await sendPart(uploadId: uploadId, partNumber: part, data: chunk,
                                   filename: filename, contentType: contentType)
                progress(Double(part) / Double(numberOfParts))
            }
            try await completeFileUpload(uploadId: uploadId)
        }
        return (uploadId, filename)
    }

    /// Atualiza um registro gravando (opcionalmente) o link numa propriedade URL
    /// e/ou o arquivo enviado numa propriedade "Arquivos e mídia", numa só chamada.
    func updatePage(
        pageId: String,
        urlProperty: String? = nil,
        url: String? = nil,
        fileProperty: String? = nil,
        fileUploadId: String? = nil,
        fileName: String? = nil
    ) async throws {
        var properties: [String: Any] = [:]
        if let urlProperty = urlProperty, let url = url {
            properties[urlProperty] = ["url": url]
        }
        if let fileProperty = fileProperty, let fileUploadId = fileUploadId {
            properties[fileProperty] = [
                "files": [[
                    "type": "file_upload",
                    "name": fileName ?? "video",
                    "file_upload": ["id": fileUploadId]
                ]]
            ]
        }
        guard !properties.isEmpty else { return }
        let request = try makeRequest(path: "pages/\(pageId)", method: "PATCH",
                                      json: ["properties": properties])
        try await send(request)
    }

    private func createFileUpload(filename: String, contentType: String, parts: Int?) async throws -> String {
        var body: [String: Any] = ["filename": filename, "content_type": contentType]
        if let parts = parts {
            body["mode"] = "multi_part"
            body["number_of_parts"] = parts
        }
        let request = try makeRequest(path: "file_uploads", method: "POST", json: body)
        let response = try await send(request)
        guard let id = response["id"] as? String else { throw NotionError.invalidResponse }
        return id
    }

    private func sendPart(uploadId: String, partNumber: Int?, data: Data,
                          filename: String, contentType: String) async throws {
        var request = try makeRequest(path: "file_uploads/\(uploadId)/send", method: "POST")
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        func append(_ string: String) { body.append(string.data(using: .utf8)!) }

        if let partNumber = partNumber {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"part_number\"\r\n\r\n")
            append("\(partNumber)\r\n")
        }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(contentType)\r\n\r\n")
        body.append(data)
        append("\r\n--\(boundary)--\r\n")
        request.httpBody = body
        try await send(request)
    }

    private func completeFileUpload(uploadId: String) async throws {
        let request = try makeRequest(path: "file_uploads/\(uploadId)/complete", method: "POST", json: [:])
        try await send(request)
    }

    // MARK: - Helpers

    /// Extrai texto plano de um array de rich text do Notion (usado para títulos).
    private static func plainText(from value: Any?) -> String? {
        guard let array = value as? [[String: Any]] else { return nil }
        let text = array.compactMap { $0["plain_text"] as? String }.joined()
        return text.isEmpty ? nil : text
    }

    /// Lê o nome do status de uma propriedade do tipo "status" ou "select".
    private static func statusName(from dict: [String: Any]) -> String? {
        if let s = dict["status"] as? [String: Any] { return s["name"] as? String }
        if let s = dict["select"] as? [String: Any] { return s["name"] as? String }
        return nil
    }

    /// Mapeia a extensão do arquivo para um content-type de vídeo.
    private static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mov": return "video/quicktime"
        case "mp4", "m4v": return "video/mp4"
        case "avi": return "video/x-msvideo"
        case "mkv": return "video/x-matroska"
        default: return "application/octet-stream"
        }
    }
}
