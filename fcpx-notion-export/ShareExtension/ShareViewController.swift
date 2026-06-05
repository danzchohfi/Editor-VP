import Cocoa
import UniformTypeIdentifiers

/// View controller exibido pelo Final Cut Pro ao compartilhar um vídeo.
/// Fluxo: (token uma vez) -> banco -> registro/cliente -> propriedade -> enviar.
final class ShareViewController: NSViewController {

    // Estado
    private var videoURL: URL?
    private var client: NotionClient?
    private var databases: [NotionDatabase] = []
    private var pages: [NotionPage] = []
    private var fileProperties: [NotionProperty] = []
    private var titleProperty: String = ""

    // UI
    private let tokenField = NSSecureTextField()
    private let saveTokenButton = NSButton()
    private let databasePopup = NSPopUpButton()
    private let searchField = NSSearchField()
    private let pagePopup = NSPopUpButton()
    private let propertyPopup = NSPopUpButton()
    private let statusLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let sendButton = NSButton()
    private let cancelButton = NSButton()
    private let tokenRow = NSStackView()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 430))
        buildUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadVideoFromContext()
        bootstrap()
    }

    // MARK: - UI

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])

        let titleLabel = NSTextField(labelWithString: "Exportar para o Notion")
        titleLabel.font = .boldSystemFont(ofSize: 15)
        stack.addArrangedSubview(titleLabel)

        // Token (mostrado só quando não há token salvo)
        tokenField.placeholderString = "Token interno do Notion (secret_...)"
        saveTokenButton.title = "Salvar"
        saveTokenButton.bezelStyle = .rounded
        saveTokenButton.target = self
        saveTokenButton.action = #selector(saveToken)
        tokenRow.orientation = .horizontal
        tokenRow.spacing = 8
        tokenRow.addArrangedSubview(tokenField)
        tokenRow.addArrangedSubview(saveTokenButton)
        tokenField.widthAnchor.constraint(equalToConstant: 300).isActive = true
        stack.addArrangedSubview(labeled("Conta", tokenRow))

        databasePopup.target = self
        databasePopup.action = #selector(databaseChanged)
        stack.addArrangedSubview(labeled("Banco de dados", fill(databasePopup)))

        searchField.placeholderString = "Buscar cliente / registro…"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = false
        stack.addArrangedSubview(labeled("Filtrar", fill(searchField)))

        stack.addArrangedSubview(labeled("Registro (card)", fill(pagePopup)))
        stack.addArrangedSubview(labeled("Propriedade de arquivo", fill(propertyPopup)))

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 420).isActive = true
        stack.addArrangedSubview(progress)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        statusLabel.preferredMaxLayoutWidth = 420
        stack.addArrangedSubview(statusLabel)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        cancelButton.title = "Cancelar"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        sendButton.title = "Enviar para o Notion"
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        sendButton.target = self
        sendButton.action = #selector(send)
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(sendButton)
        stack.addArrangedSubview(buttons)
    }

    /// Linha com rótulo à esquerda e controle preenchendo o restante.
    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 110).isActive = true
        row.addArrangedSubview(label)
        row.addArrangedSubview(control)
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }

    private func fill(_ control: NSView) -> NSView {
        control.translatesAutoresizingMaskIntoConstraints = false
        control.widthAnchor.constraint(equalToConstant: 300).isActive = true
        return control
    }

    // MARK: - Bootstrap

    private func loadVideoFromContext() {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else { return }
        let types = [UTType.movie.identifier, UTType.quickTimeMovie.identifier,
                     UTType.mpeg4Movie.identifier, UTType.fileURL.identifier]
        for provider in attachments {
            for type in types where provider.hasItemConformingToTypeIdentifier(type) {
                provider.loadItem(forTypeIdentifier: type, options: nil) { [weak self] data, _ in
                    var url: URL?
                    if let u = data as? URL { url = u }
                    else if let d = data as? Data { url = URL(dataRepresentation: d, relativeTo: nil) }
                    if let url = url {
                        DispatchQueue.main.async {
                            self?.videoURL = url
                            self?.refreshStatus()
                        }
                    }
                }
                return
            }
        }
    }

    private func bootstrap() {
        if let token = KeychainTokenStore.load(), !token.isEmpty {
            tokenField.stringValue = token
            tokenRow.isHidden = true
            client = NotionClient(token: token)
            Task { await reloadDatabases() }
        } else {
            setControlsEnabled(false)
            statusLabel.stringValue = "Cole seu token interno do Notion e clique em Salvar."
        }
    }

    private func setControlsEnabled(_ enabled: Bool) {
        [databasePopup, searchField, pagePopup, propertyPopup, sendButton].forEach { $0.isEnabled = enabled }
    }

    // MARK: - Actions

    @objc private func saveToken() {
        let token = tokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        KeychainTokenStore.save(token)
        client = NotionClient(token: token)
        tokenRow.isHidden = true
        Task { await reloadDatabases() }
    }

    @objc private func databaseChanged() {
        guard databasePopup.indexOfSelectedItem >= 0,
              databasePopup.indexOfSelectedItem < databases.count else { return }
        let db = databases[databasePopup.indexOfSelectedItem]
        AppConfig.databaseId = db.id
        Task { await reloadDatabaseDetails(db.id) }
    }

    @objc private func searchChanged() {
        guard let db = selectedDatabase() else { return }
        Task { await reloadPages(databaseId: db.id, query: searchField.stringValue) }
    }

    @objc private func cancel() {
        extensionContext?.cancelRequest(withError: NSError(domain: "NotionExport", code: -1))
    }

    @objc private func send() {
        guard let client = client else { return }
        guard let videoURL = videoURL else {
            statusLabel.stringValue = "Aguardando o vídeo do Final Cut…"
            return
        }
        guard pagePopup.indexOfSelectedItem >= 0, pagePopup.indexOfSelectedItem < pages.count else {
            statusLabel.stringValue = "Selecione o registro de destino."
            return
        }
        guard propertyPopup.indexOfSelectedItem >= 0,
              propertyPopup.indexOfSelectedItem < fileProperties.count else {
            statusLabel.stringValue = "Selecione a propriedade de arquivo."
            return
        }
        let page = pages[pagePopup.indexOfSelectedItem]
        let property = fileProperties[propertyPopup.indexOfSelectedItem]
        AppConfig.propertyName = property.name

        setControlsEnabled(false)
        progress.isHidden = false
        progress.doubleValue = 0
        statusLabel.stringValue = "Enviando \(videoURL.lastPathComponent)…"

        Task {
            do {
                try await client.uploadVideo(
                    fileURL: videoURL,
                    pageId: page.id,
                    propertyName: property.name
                ) { fraction in
                    DispatchQueue.main.async { self.progress.doubleValue = fraction }
                }
                await MainActor.run {
                    self.statusLabel.stringValue = "Concluído! Vídeo anexado em \(page.title)."
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                }
            } catch {
                await MainActor.run {
                    self.progress.isHidden = true
                    self.setControlsEnabled(true)
                    self.statusLabel.stringValue = "Erro: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Data loading

    private func selectedDatabase() -> NotionDatabase? {
        let idx = databasePopup.indexOfSelectedItem
        guard idx >= 0, idx < databases.count else { return nil }
        return databases[idx]
    }

    private func reloadDatabases() async {
        guard let client = client else { return }
        await setStatus("Carregando bancos de dados…")
        do {
            let dbs = try await client.listDatabases()
            await MainActor.run {
                self.databases = dbs
                self.databasePopup.removeAllItems()
                self.databasePopup.addItems(withTitles: dbs.map { $0.title })
                if dbs.isEmpty {
                    self.statusLabel.stringValue = "Nenhum banco compartilhado com a integração. Em Notion, abra o banco → ••• → Conexões → adicione a integração."
                    return
                }
                // Restaura o banco padrão salvo, se existir.
                if let saved = AppConfig.databaseId,
                   let idx = dbs.firstIndex(where: { $0.id == saved }) {
                    self.databasePopup.selectItem(at: idx)
                }
                self.setControlsEnabled(true)
            }
            if let db = selectedDatabase() { await reloadDatabaseDetails(db.id) }
        } catch {
            await setStatus("Erro ao listar bancos: \(error.localizedDescription)")
        }
    }

    private func reloadDatabaseDetails(_ databaseId: String) async {
        guard let client = client else { return }
        do {
            let (title, props) = try await client.databaseProperties(databaseId: databaseId)
            await MainActor.run {
                self.titleProperty = title
                self.fileProperties = props.filter { $0.type == "files" }
                self.propertyPopup.removeAllItems()
                self.propertyPopup.addItems(withTitles: self.fileProperties.map { $0.name })
                if self.fileProperties.isEmpty {
                    self.statusLabel.stringValue = "Este banco não tem propriedade do tipo 'Arquivos e mídia'."
                } else if let saved = AppConfig.propertyName,
                          let idx = self.fileProperties.firstIndex(where: { $0.name == saved }) {
                    self.propertyPopup.selectItem(at: idx)
                }
            }
            await reloadPages(databaseId: databaseId, query: searchField.stringValue)
        } catch {
            await setStatus("Erro ao ler propriedades: \(error.localizedDescription)")
        }
    }

    private func reloadPages(databaseId: String, query: String) async {
        guard let client = client else { return }
        do {
            let result = try await client.listPages(
                databaseId: databaseId, titleProperty: titleProperty, query: query)
            await MainActor.run {
                self.pages = result
                self.pagePopup.removeAllItems()
                self.pagePopup.addItems(withTitles: result.map { $0.title })
                self.refreshStatus()
            }
        } catch {
            await setStatus("Erro ao listar registros: \(error.localizedDescription)")
        }
    }

    private func refreshStatus() {
        if let url = videoURL {
            statusLabel.stringValue = "Pronto para enviar: \(url.lastPathComponent)"
        } else {
            statusLabel.stringValue = "Aguardando o vídeo do Final Cut…"
        }
    }

    private func setStatus(_ text: String) async {
        await MainActor.run { self.statusLabel.stringValue = text }
    }
}
