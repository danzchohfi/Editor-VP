import Cocoa
import UniformTypeIdentifiers

/// View controller exibido pelo Final Cut Pro ao compartilhar um vídeo.
/// Fluxo: (credenciais uma vez) -> banco -> registro/cliente -> propriedades ->
/// sobe no Cloudflare Stream, grava o link e anexa o arquivo no card do Notion.
final class ShareViewController: NSViewController {

    // Estado
    private var videoURL: URL?
    private var notion: NotionClient?
    private var databases: [NotionDatabase] = []
    private var pages: [NotionPage] = []
    private var urlProperties: [NotionProperty] = []
    private var fileProperties: [NotionProperty] = []
    private var titleProperty: String = ""

    // Credenciais
    private let notionTokenField = NSSecureTextField()
    private let cfAccountField = NSTextField()
    private let cfTokenField = NSSecureTextField()
    private let saveCredsButton = NSButton()
    private let settingsBox = NSStackView()

    // Seleção
    private let databasePopup = NSPopUpButton()
    private let searchField = NSSearchField()
    private let pagePopup = NSPopUpButton()
    private let urlPropertyPopup = NSPopUpButton()
    private let filePropertyPopup = NSPopUpButton()

    // Feedback
    private let statusLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()
    private let sendButton = NSButton()
    private let cancelButton = NSButton()

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 540))
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
        stack.spacing = 9
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -20)
        ])

        let titleLabel = NSTextField(labelWithString: "Exportar para aprovação (Cloudflare + Notion)")
        titleLabel.font = .boldSystemFont(ofSize: 15)
        stack.addArrangedSubview(titleLabel)

        // Credenciais (escondidas quando já configuradas)
        settingsBox.orientation = .vertical
        settingsBox.alignment = .leading
        settingsBox.spacing = 6
        notionTokenField.placeholderString = "Token interno do Notion (ntn_… / secret_…)"
        cfAccountField.placeholderString = "Cloudflare Account ID"
        cfTokenField.placeholderString = "Cloudflare API Token (Stream:Edit)"
        saveCredsButton.title = "Salvar credenciais"
        saveCredsButton.bezelStyle = .rounded
        saveCredsButton.target = self
        saveCredsButton.action = #selector(saveCreds)
        [notionTokenField, cfAccountField, cfTokenField].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            $0.widthAnchor.constraint(equalToConstant: 420).isActive = true
            settingsBox.addArrangedSubview($0)
        }
        settingsBox.addArrangedSubview(saveCredsButton)
        stack.addArrangedSubview(settingsBox)

        databasePopup.target = self
        databasePopup.action = #selector(databaseChanged)
        stack.addArrangedSubview(labeled("Banco de dados", fill(databasePopup)))

        searchField.placeholderString = "Buscar cliente / registro…"
        searchField.target = self
        searchField.action = #selector(searchChanged)
        searchField.sendsSearchStringImmediately = false
        stack.addArrangedSubview(labeled("Filtrar", fill(searchField)))

        stack.addArrangedSubview(labeled("Registro (card)", fill(pagePopup)))
        stack.addArrangedSubview(labeled("Propriedade do link", fill(urlPropertyPopup)))
        stack.addArrangedSubview(labeled("Propriedade do arquivo", fill(filePropertyPopup)))

        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        progress.widthAnchor.constraint(equalToConstant: 440).isActive = true
        stack.addArrangedSubview(progress)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        statusLabel.preferredMaxLayoutWidth = 440
        stack.addArrangedSubview(statusLabel)

        let buttons = NSStackView()
        buttons.orientation = .horizontal
        buttons.spacing = 10
        cancelButton.title = "Cancelar"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel)
        sendButton.title = "Enviar"
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r"
        sendButton.target = self
        sendButton.action = #selector(send)
        buttons.addArrangedSubview(cancelButton)
        buttons.addArrangedSubview(sendButton)
        stack.addArrangedSubview(buttons)
    }

    private func labeled(_ title: String, _ control: NSView) -> NSView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 8
        let label = NSTextField(labelWithString: title)
        label.alignment = .right
        label.widthAnchor.constraint(equalToConstant: 130).isActive = true
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
                        DispatchQueue.main.async { self?.videoURL = url; self?.refreshStatus() }
                    }
                }
                return
            }
        }
    }

    private func bootstrap() {
        notionTokenField.stringValue = Credentials.notionToken ?? ""
        cfAccountField.stringValue = Credentials.cloudflareAccountId ?? ""
        cfTokenField.stringValue = Credentials.cloudflareToken ?? ""

        if Credentials.isComplete {
            settingsBox.isHidden = true
            notion = NotionClient(token: Credentials.notionToken!)
            Task { await reloadDatabases() }
        } else {
            setSelectionEnabled(false)
            statusLabel.stringValue = "Preencha as credenciais do Notion e do Cloudflare e salve."
        }
    }

    private func setSelectionEnabled(_ enabled: Bool) {
        [databasePopup, searchField, pagePopup, urlPropertyPopup, filePropertyPopup, sendButton]
            .forEach { $0.isEnabled = enabled }
    }

    // MARK: - Actions

    @objc private func saveCreds() {
        let notionToken = notionTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfAccount = cfAccountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfToken = cfTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notionToken.isEmpty, !cfAccount.isEmpty, !cfToken.isEmpty else {
            statusLabel.stringValue = "Preencha as três credenciais."
            return
        }
        Credentials.notionToken = notionToken
        Credentials.cloudflareAccountId = cfAccount
        Credentials.cloudflareToken = cfToken
        notion = NotionClient(token: notionToken)
        settingsBox.isHidden = true
        Task { await reloadDatabases() }
    }

    @objc private func databaseChanged() {
        guard let db = selectedDatabase() else { return }
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
        guard let notion = notion,
              let accountId = Credentials.cloudflareAccountId,
              let cfToken = Credentials.cloudflareToken else { return }
        guard let videoURL = videoURL else {
            statusLabel.stringValue = "Aguardando o vídeo do Final Cut…"; return
        }
        guard let page = selected(pagePopup, pages) else {
            statusLabel.stringValue = "Selecione o registro de destino."; return
        }
        guard let urlProp = selected(urlPropertyPopup, urlProperties) else {
            statusLabel.stringValue = "Selecione a propriedade do link (URL)."; return
        }
        guard let fileProp = selected(filePropertyPopup, fileProperties) else {
            statusLabel.stringValue = "Selecione a propriedade do arquivo."; return
        }
        AppConfig.urlPropertyName = urlProp.name
        AppConfig.filePropertyName = fileProp.name

        setSelectionEnabled(false)
        progress.isHidden = false
        progress.doubleValue = 0

        let cloudflare = CloudflareStreamClient(accountId: accountId, apiToken: cfToken)
        Task {
            do {
                // 1) Cloudflare Stream (0–60% do progresso total)
                let watchURL = try await cloudflare.uploadAndGetWatchURL(
                    fileURL: videoURL,
                    progress: { f in DispatchQueue.main.async { self.progress.doubleValue = f * 0.6 } },
                    status: { s in DispatchQueue.main.async { self.statusLabel.stringValue = s } })

                // 2) Upload do arquivo para o Notion (60–95%)
                await self.setStatus("Anexando o arquivo no Notion…")
                let upload = try await notion.uploadFile(fileURL: videoURL) { f in
                    DispatchQueue.main.async { self.progress.doubleValue = 0.6 + f * 0.35 }
                }

                // 3) Grava link + arquivo no card (95–100%)
                await self.setStatus("Gravando link e arquivo no card…")
                try await notion.updatePage(
                    pageId: page.id,
                    urlProperty: urlProp.name, url: watchURL,
                    fileProperty: fileProp.name, fileUploadId: upload.uploadId, fileName: upload.filename)

                await MainActor.run {
                    self.progress.doubleValue = 1.0
                    self.statusLabel.stringValue = "Concluído! Link no card \(page.title): \(watchURL)"
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                }
            } catch {
                await MainActor.run {
                    self.progress.isHidden = true
                    self.setSelectionEnabled(true)
                    self.statusLabel.stringValue = "Erro: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: - Data loading

    private func selectedDatabase() -> NotionDatabase? { selected(databasePopup, databases) }

    private func selected<T>(_ popup: NSPopUpButton, _ items: [T]) -> T? {
        let idx = popup.indexOfSelectedItem
        guard idx >= 0, idx < items.count else { return nil }
        return items[idx]
    }

    private func reloadDatabases() async {
        guard let notion = notion else { return }
        await setStatus("Carregando bancos de dados…")
        do {
            let dbs = try await notion.listDatabases()
            await MainActor.run {
                self.databases = dbs
                self.databasePopup.removeAllItems()
                self.databasePopup.addItems(withTitles: dbs.map { $0.title })
                guard !dbs.isEmpty else {
                    self.statusLabel.stringValue = "Nenhum banco compartilhado com a integração. No Notion: abra o banco → ••• → Conexões → adicione a integração."
                    return
                }
                if let saved = AppConfig.databaseId,
                   let idx = dbs.firstIndex(where: { $0.id == saved }) {
                    self.databasePopup.selectItem(at: idx)
                }
                self.setSelectionEnabled(true)
            }
            if let db = selectedDatabase() { await reloadDatabaseDetails(db.id) }
        } catch {
            await setStatus("Erro ao listar bancos: \(error.localizedDescription)")
        }
    }

    private func reloadDatabaseDetails(_ databaseId: String) async {
        guard let notion = notion else { return }
        do {
            let (title, props) = try await notion.databaseProperties(databaseId: databaseId)
            await MainActor.run {
                self.titleProperty = title
                self.urlProperties = props.filter { $0.type == "url" }
                self.fileProperties = props.filter { $0.type == "files" }
                self.urlPropertyPopup.removeAllItems()
                self.urlPropertyPopup.addItems(withTitles: self.urlProperties.map { $0.name })
                self.filePropertyPopup.removeAllItems()
                self.filePropertyPopup.addItems(withTitles: self.fileProperties.map { $0.name })
                self.selectSaved(self.urlPropertyPopup, self.urlProperties, AppConfig.urlPropertyName)
                self.selectSaved(self.filePropertyPopup, self.fileProperties, AppConfig.filePropertyName)
                if self.urlProperties.isEmpty {
                    self.statusLabel.stringValue = "Este banco não tem propriedade do tipo 'URL' para o link."
                } else if self.fileProperties.isEmpty {
                    self.statusLabel.stringValue = "Este banco não tem propriedade do tipo 'Arquivos e mídia'."
                }
            }
            await reloadPages(databaseId: databaseId, query: searchField.stringValue)
        } catch {
            await setStatus("Erro ao ler propriedades: \(error.localizedDescription)")
        }
    }

    private func selectSaved(_ popup: NSPopUpButton, _ items: [NotionProperty], _ saved: String?) {
        if let saved = saved, let idx = items.firstIndex(where: { $0.name == saved }) {
            popup.selectItem(at: idx)
        }
    }

    private func reloadPages(databaseId: String, query: String) async {
        guard let notion = notion else { return }
        do {
            let result = try await notion.listPages(databaseId: databaseId, titleProperty: titleProperty, query: query)
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
        statusLabel.stringValue = videoURL.map { "Pronto para enviar: \($0.lastPathComponent)" }
            ?? "Aguardando o vídeo do Final Cut…"
    }

    private func setStatus(_ text: String) async {
        await MainActor.run { self.statusLabel.stringValue = text }
    }
}
