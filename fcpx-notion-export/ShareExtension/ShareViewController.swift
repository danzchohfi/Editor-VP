import Cocoa
import UniformTypeIdentifiers

/// Tela exibida pelo Final Cut ao compartilhar. O protagonista é a busca do
/// card: o editor digita o cliente e clica na lista. Banco/propriedades e
/// credenciais ficam num painel de Configurações que raramente é tocado.
final class ShareViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    // Estado
    private var videoURL: URL?
    private var notion: NotionClient?
    private var databases: [NotionDatabase] = []
    private var pages: [NotionPage] = []
    private var selectedPage: NotionPage?
    private var urlProperties: [NotionProperty] = []
    private var fileProperties: [NotionProperty] = []
    private var titleProperty: String = ""
    private var searchWorkItem: DispatchWorkItem?

    // Cabeçalho / hero
    private let videoChip = Brand.label("Aguardando vídeo do Final Cut…", font: Brand.body(13), color: Brand.textMuted)
    private let searchField = NSSearchField()
    private let cardsTable = NSTableView()
    private let selectionLabel = Brand.label("Nenhum card selecionado", font: Brand.semibold(13), color: Brand.textMuted)
    private lazy var sendButton = Brand.primaryButton("Enviar para o Notion", target: self, action: #selector(send))

    // Configurações
    private let databasePopup = NSPopUpButton()
    private let urlPropertyPopup = NSPopUpButton()
    private let filePropertyPopup = NSPopUpButton()
    private let notionTokenField = Brand.field(placeholder: "Token interno do Notion (ntn_… / secret_…)", secure: true)
    private let cfAccountField = Brand.field(placeholder: "Cloudflare Account ID")
    private let cfTokenField = Brand.field(placeholder: "Cloudflare API Token (Stream:Edit)", secure: true)
    private lazy var settingsPanel = NSStackView()
    private lazy var settingsToggle = Brand.ghostButton("⚙  Configurações", target: self, action: #selector(toggleSettings))

    // Feedback
    private let progress = NSProgressIndicator()
    private let statusLabel = Brand.label("", font: Brand.body(12), color: Brand.textMuted)

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 640))
        root.wantsLayer = true
        root.layer?.backgroundColor = Brand.background.cgColor
        root.appearance = NSAppearance(named: .darkAqua)
        view = root
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
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -22)
        ])
        func fullWidth(_ v: NSView) {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        // Cabeçalho (wordmark + subtítulo)
        let wordmark = Brand.label("Produção", font: Brand.display(22), color: Brand.textPrimary)
        let subtitle = Brand.label("Exportar vídeo para aprovação", font: Brand.body(13), color: Brand.textMuted)
        let header = NSStackView(views: [wordmark, subtitle])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 2
        stack.addArrangedSubview(header)

        // Chip do vídeo
        let chipContent = NSStackView(views: [Brand.label("🎬", font: Brand.body(14), color: Brand.textPrimary), videoChip])
        chipContent.orientation = .horizontal
        chipContent.spacing = 8
        let chip = Brand.cardContainer(chipContent, padding: 12)
        fullWidth(chip)
        stack.addArrangedSubview(chip)

        // HERO — busca do cliente
        let heroLabel = Brand.label("Para qual cliente?", font: Brand.semibold(15), color: Brand.textPrimary)
        stack.addArrangedSubview(heroLabel)

        searchField.placeholderString = "Digite o nome do cliente / card…"
        searchField.delegate = self
        searchField.font = Brand.body(14)
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.heightAnchor.constraint(equalToConstant: 38).isActive = true
        fullWidth(searchField)
        stack.addArrangedSubview(searchField)

        // Lista de cards
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        cardsTable.headerView = nil
        cardsTable.backgroundColor = .clear
        cardsTable.rowHeight = 38
        cardsTable.intercellSpacing = NSSize(width: 0, height: 2)
        cardsTable.selectionHighlightStyle = .regular
        cardsTable.dataSource = self
        cardsTable.delegate = self
        cardsTable.target = self
        cardsTable.doubleAction = #selector(send)
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("card"))
        column.resizingMask = .autoresizingMask
        cardsTable.addTableColumn(column)
        scroll.documentView = cardsTable
        let listCard = Brand.cardContainer(scroll, padding: 6)
        fullWidth(listCard)
        listCard.heightAnchor.constraint(equalToConstant: 190).isActive = true
        stack.addArrangedSubview(listCard)

        stack.addArrangedSubview(selectionLabel)

        // Ação principal
        fullWidth(sendButton)
        stack.addArrangedSubview(sendButton)

        // Progresso + status
        progress.style = .bar
        progress.isIndeterminate = false
        progress.minValue = 0
        progress.maxValue = 1
        progress.isHidden = true
        progress.translatesAutoresizingMaskIntoConstraints = false
        fullWidth(progress)
        stack.addArrangedSubview(progress)

        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.maximumNumberOfLines = 2
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        fullWidth(statusLabel)
        stack.addArrangedSubview(statusLabel)

        // Configurações (recolhível)
        fullWidth(settingsToggle)
        stack.addArrangedSubview(settingsToggle)
        buildSettingsPanel()
        fullWidth(settingsPanel)
        stack.addArrangedSubview(settingsPanel)
    }

    private func buildSettingsPanel() {
        settingsPanel.orientation = .vertical
        settingsPanel.alignment = .leading
        settingsPanel.spacing = 8
        settingsPanel.isHidden = true

        func row(_ title: String, _ control: NSView) -> NSView {
            let label = Brand.label(title, font: Brand.body(12), color: Brand.textMuted)
            let r = NSStackView(views: [label, control])
            r.orientation = .vertical
            r.alignment = .leading
            r.spacing = 3
            control.translatesAutoresizingMaskIntoConstraints = false
            control.widthAnchor.constraint(equalToConstant: 432).isActive = true
            return r
        }

        databasePopup.target = self
        databasePopup.action = #selector(databaseChanged)
        settingsPanel.addArrangedSubview(row("Banco de dados", databasePopup))
        settingsPanel.addArrangedSubview(row("Propriedade do link (URL)", urlPropertyPopup))
        settingsPanel.addArrangedSubview(row("Propriedade do arquivo", filePropertyPopup))

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        divider.widthAnchor.constraint(equalToConstant: 432).isActive = true
        settingsPanel.addArrangedSubview(divider)

        settingsPanel.addArrangedSubview(row("Token do Notion", notionTokenField))
        settingsPanel.addArrangedSubview(row("Cloudflare Account ID", cfAccountField))
        settingsPanel.addArrangedSubview(row("Cloudflare API Token", cfTokenField))
        let save = Brand.primaryButton("Salvar credenciais", target: self, action: #selector(saveCreds))
        save.widthAnchor.constraint(equalToConstant: 200).isActive = true
        settingsPanel.addArrangedSubview(save)
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
                            self?.videoChip.stringValue = url.lastPathComponent
                            self?.videoChip.textColor = Brand.textPrimary
                        }
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
            notion = NotionClient(token: Credentials.notionToken!)
            Task { await reloadDatabases() }
        } else {
            settingsPanel.isHidden = false
            statusLabel.stringValue = "Configure as credenciais do Notion e do Cloudflare em Configurações."
            statusLabel.textColor = Brand.danger
        }
    }

    // MARK: - Actions

    @objc private func toggleSettings() {
        settingsPanel.isHidden.toggle()
    }

    @objc private func saveCreds() {
        let notionToken = notionTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfAccount = cfAccountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfToken = cfTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !notionToken.isEmpty, !cfAccount.isEmpty, !cfToken.isEmpty else {
            statusLabel.stringValue = "Preencha as três credenciais."
            statusLabel.textColor = Brand.danger
            return
        }
        Credentials.notionToken = notionToken
        Credentials.cloudflareAccountId = cfAccount
        Credentials.cloudflareToken = cfToken
        notion = NotionClient(token: notionToken)
        settingsPanel.isHidden = true
        statusLabel.stringValue = ""
        Task { await reloadDatabases() }
    }

    @objc private func databaseChanged() {
        guard let db = selected(databasePopup, databases) else { return }
        AppConfig.databaseId = db.id
        Task { await reloadDatabaseDetails(db.id) }
    }

    @objc private func send() {
        guard let notion = notion,
              let accountId = Credentials.cloudflareAccountId,
              let cfToken = Credentials.cloudflareToken else { return }
        guard let videoURL = videoURL else { return fail("Aguardando o vídeo do Final Cut…") }
        guard let page = selectedPage else { return fail("Escolha o card do cliente na lista.") }
        guard let urlProp = selected(urlPropertyPopup, urlProperties) else {
            return fail("Defina a propriedade do link em Configurações.")
        }
        guard let fileProp = selected(filePropertyPopup, fileProperties) else {
            return fail("Defina a propriedade do arquivo em Configurações.")
        }
        AppConfig.urlPropertyName = urlProp.name
        AppConfig.filePropertyName = fileProp.name

        sendButton.isEnabled = false
        progress.isHidden = false
        progress.doubleValue = 0
        statusLabel.textColor = Brand.textMuted

        let cloudflare = CloudflareStreamClient(accountId: accountId, apiToken: cfToken)
        Task {
            do {
                let watchURL = try await cloudflare.uploadAndGetWatchURL(
                    fileURL: videoURL,
                    progress: { f in DispatchQueue.main.async { self.progress.doubleValue = f * 0.6 } },
                    status: { s in DispatchQueue.main.async { self.statusLabel.stringValue = s } })

                await self.setStatus("Anexando o arquivo no Notion…")
                let upload = try await notion.uploadFile(fileURL: videoURL) { f in
                    DispatchQueue.main.async { self.progress.doubleValue = 0.6 + f * 0.35 }
                }

                await self.setStatus("Gravando link e arquivo no card…")
                try await notion.updatePage(
                    pageId: page.id,
                    urlProperty: urlProp.name, url: watchURL,
                    fileProperty: fileProp.name, fileUploadId: upload.uploadId, fileName: upload.filename)

                await MainActor.run {
                    self.progress.doubleValue = 1.0
                    self.statusLabel.textColor = Brand.success
                    self.statusLabel.stringValue = "Pronto! Enviado para \(page.title)."
                    self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
                }
            } catch {
                await MainActor.run {
                    self.progress.isHidden = true
                    self.sendButton.isEnabled = true
                    self.statusLabel.textColor = Brand.danger
                    self.statusLabel.stringValue = "Erro: \(error.localizedDescription)"
                }
            }
        }
    }

    private func fail(_ message: String) {
        statusLabel.stringValue = message
        statusLabel.textColor = Brand.danger
    }

    // MARK: - Busca (debounce)

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === searchField else { return }
        searchWorkItem?.cancel()
        let text = searchField.stringValue
        let work = DispatchWorkItem { [weak self] in
            guard let self = self, let db = self.selected(self.databasePopup, self.databases) else { return }
            Task { await self.reloadPages(databaseId: db.id, query: text) }
        }
        searchWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
    }

    // MARK: - NSTableView

    func numberOfRows(in tableView: NSTableView) -> Int { pages.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { BrandRowView() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cardCell")
        let cell: NSTableCellView
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            cell = reused
        } else {
            cell = NSTableCellView()
            cell.identifier = id
            let field = NSTextField(labelWithString: "")
            field.translatesAutoresizingMaskIntoConstraints = false
            field.font = Brand.body(14)
            field.textColor = Brand.textPrimary
            field.lineBreakMode = .byTruncatingTail
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = pages[row].title
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = cardsTable.selectedRow
        if row >= 0, row < pages.count {
            selectedPage = pages[row]
            selectionLabel.stringValue = "✓  \(pages[row].title)"
            selectionLabel.textColor = Brand.success
        } else {
            selectedPage = nil
            selectionLabel.stringValue = "Nenhum card selecionado"
            selectionLabel.textColor = Brand.textMuted
        }
    }

    // MARK: - Data loading

    private func selected<T>(_ popup: NSPopUpButton, _ items: [T]) -> T? {
        let idx = popup.indexOfSelectedItem
        guard idx >= 0, idx < items.count else { return nil }
        return items[idx]
    }

    private func reloadDatabases() async {
        guard let notion = notion else { return }
        await setStatus("Carregando…")
        do {
            let dbs = try await notion.listDatabases()
            await MainActor.run {
                self.databases = dbs
                self.databasePopup.removeAllItems()
                self.databasePopup.addItems(withTitles: dbs.map { $0.title })
                guard !dbs.isEmpty else {
                    self.fail("Nenhum banco compartilhado com a integração (Notion: banco → ••• → Conexões).")
                    return
                }
                if let saved = AppConfig.databaseId, let idx = dbs.firstIndex(where: { $0.id == saved }) {
                    self.databasePopup.selectItem(at: idx)
                }
                self.statusLabel.stringValue = ""
            }
            if let db = selected(databasePopup, databases) { await reloadDatabaseDetails(db.id) }
        } catch {
            await MainActor.run { self.fail("Erro ao listar bancos: \(error.localizedDescription)") }
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
            }
            await reloadPages(databaseId: databaseId, query: searchField.stringValue)
        } catch {
            await MainActor.run { self.fail("Erro ao ler propriedades: \(error.localizedDescription)") }
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
                self.selectedPage = nil
                self.cardsTable.reloadData()
                self.cardsTable.deselectAll(nil)
                self.tableViewSelectionDidChange(Notification(name: NSTableView.selectionDidChangeNotification))
            }
        } catch {
            await MainActor.run { self.fail("Erro ao listar registros: \(error.localizedDescription)") }
        }
    }

    private func setStatus(_ text: String) async {
        await MainActor.run {
            self.statusLabel.textColor = Brand.textMuted
            self.statusLabel.stringValue = text
        }
    }
}
