import Cocoa

/// Painel que aparece DENTRO do Final Cut Pro (Janela → Extensões), no estilo
/// Frame.io. Aqui o editor faz login, escolhe o banco padrão, navega pelos
/// cards e define as propriedades. A exportação do vídeo final continua pelo
/// menu Compartilhar (a Share Extension faz o upload).
///
/// Esta classe é AppKit puro (não depende do SDK do Final Cut). Quem a conecta
/// ao FCPX é a "principal class" gerada pelo template oficial da Apple — veja
/// GUIA-PAINEL-FCPX.md.
final class WorkflowPanelViewController: NSViewController,
    NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate {

    // Estado
    private var notion: NotionClient?
    private var databases: [NotionDatabase] = []
    private var pages: [NotionPage] = []
    private var urlProperties: [NotionProperty] = []
    private var fileProperties: [NotionProperty] = []
    private var titleProperty = ""
    private var searchWorkItem: DispatchWorkItem?

    // Credenciais
    private let notionTokenField = Brand.field(placeholder: "Token interno do Notion (ntn_… / secret_…)", secure: true)
    private let cfAccountField = Brand.field(placeholder: "Cloudflare Account ID")
    private let cfTokenField = Brand.field(placeholder: "Cloudflare API Token (Stream:Edit)", secure: true)

    // Seleção
    private let databasePopup = NSPopUpButton()
    private let searchField = NSSearchField()
    private let cardsTable = NSTableView()
    private let urlPropertyPopup = NSPopUpButton()
    private let filePropertyPopup = NSPopUpButton()
    private let statusLabel = Brand.label("", font: Brand.body(12), color: Brand.textMuted)

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 360, height: 640))
        root.wantsLayer = true
        root.layer?.backgroundColor = Brand.background.cgColor
        root.appearance = NSAppearance(named: .darkAqua)
        view = root
        buildUI()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        loadCredentials()
        if Credentials.isComplete {
            notion = NotionClient(token: Credentials.notionToken!)
            Task { await reloadDatabases() }
        } else {
            statusLabel.stringValue = "Preencha as credenciais e toque em Salvar."
        }
    }

    // MARK: - UI

    private func buildUI() {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 18),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -18)
        ])
        func fullWidth(_ v: NSView) {
            v.translatesAutoresizingMaskIntoConstraints = false
            v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        stack.addArrangedSubview(Brand.wordmark(size: 22))
        stack.addArrangedSubview(Brand.label("Aprovação · Notion + Cloudflare",
                                             font: Brand.body(12), color: Brand.textMuted))

        // Credenciais
        stack.addArrangedSubview(Brand.label("Conexão", font: Brand.semibold(13), color: Brand.textPrimary))
        [notionTokenField, cfAccountField, cfTokenField].forEach { fullWidth($0); stack.addArrangedSubview($0) }
        let credButtons = NSStackView(views: [
            Brand.primaryButton("Salvar", target: self, action: #selector(saveCreds)),
            Brand.ghostButton("Testar conexão", target: self, action: #selector(testConnection))
        ])
        credButtons.orientation = .horizontal
        credButtons.spacing = 8
        stack.addArrangedSubview(credButtons)

        // Banco
        databasePopup.target = self
        databasePopup.action = #selector(databaseChanged)
        stack.addArrangedSubview(Brand.label("Banco de dados", font: Brand.semibold(13), color: Brand.textPrimary))
        fullWidth(databasePopup); stack.addArrangedSubview(databasePopup)

        // Busca de card
        stack.addArrangedSubview(Brand.label("Clientes / cards", font: Brand.semibold(13), color: Brand.textPrimary))
        searchField.placeholderString = "Buscar cliente…"
        searchField.delegate = self
        fullWidth(searchField); stack.addArrangedSubview(searchField)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        cardsTable.headerView = nil
        cardsTable.backgroundColor = .clear
        cardsTable.rowHeight = 34
        cardsTable.intercellSpacing = NSSize(width: 0, height: 2)
        cardsTable.dataSource = self
        cardsTable.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("card"))
        cardsTable.addTableColumn(column)
        scroll.documentView = cardsTable
        let listCard = Brand.cardContainer(scroll, padding: 6)
        fullWidth(listCard)
        listCard.heightAnchor.constraint(equalToConstant: 150).isActive = true
        stack.addArrangedSubview(listCard)

        // Propriedades
        stack.addArrangedSubview(Brand.label("Propriedade do link (URL)", font: Brand.body(12), color: Brand.textMuted))
        fullWidth(urlPropertyPopup); stack.addArrangedSubview(urlPropertyPopup)
        stack.addArrangedSubview(Brand.label("Propriedade do arquivo", font: Brand.body(12), color: Brand.textMuted))
        fullWidth(filePropertyPopup); stack.addArrangedSubview(filePropertyPopup)

        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 3
        fullWidth(statusLabel)
        stack.addArrangedSubview(statusLabel)

        let note = Brand.label("Para exportar: selecione o projeto e use Arquivo → Compartilhar → Enviar para o Notion.",
                               font: Brand.body(11), color: Brand.textMuted)
        note.lineBreakMode = .byWordWrapping
        note.maximumNumberOfLines = 3
        fullWidth(note)
        stack.addArrangedSubview(note)
    }

    private func loadCredentials() {
        notionTokenField.stringValue = Credentials.notionToken ?? ""
        cfAccountField.stringValue = Credentials.cloudflareAccountId ?? ""
        cfTokenField.stringValue = Credentials.cloudflareToken ?? ""
    }

    // MARK: - Ações

    @objc private func saveCreds() {
        let token = notionTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let account = cfAccountField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let cfToken = cfTokenField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !account.isEmpty, !cfToken.isEmpty else {
            return setStatus("Preencha as três credenciais.", error: true)
        }
        Credentials.notionToken = token
        Credentials.cloudflareAccountId = account
        Credentials.cloudflareToken = cfToken
        notion = NotionClient(token: token)
        Task { await reloadDatabases() }
        setStatus("Credenciais salvas.")
    }

    @objc private func testConnection() {
        guard let notion = notion else { return setStatus("Salve as credenciais primeiro.", error: true) }
        setStatus("Testando…")
        Task {
            do {
                let dbs = try await notion.listDatabases()
                await MainActor.run { self.setStatus("Conectado! \(dbs.count) banco(s) acessível(is).") }
            } catch {
                await MainActor.run { self.setStatus("Falha: \(error.localizedDescription)", error: true) }
            }
        }
    }

    @objc private func databaseChanged() {
        guard let db = selected(databasePopup, databases) else { return }
        AppConfig.databaseId = db.id
        Task { await reloadDatabaseDetails(db.id) }
    }

    // MARK: - Busca

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

    // MARK: - Tabela

    func numberOfRows(in tableView: NSTableView) -> Int { pages.count }
    func tableView(_ t: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { BrandRowView() }

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
            field.font = Brand.body(13)
            field.textColor = Brand.textPrimary
            field.lineBreakMode = .byTruncatingTail
            cell.addSubview(field)
            cell.textField = field
            NSLayoutConstraint.activate([
                field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 10),
                field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -10),
                field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = pages[row].title
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = cardsTable.selectedRow
        guard row >= 0, row < pages.count else { return }
        AppConfig.preferredCardId = pages[row].id
        AppConfig.preferredCardTitle = pages[row].title
        setStatus("Card padrão: \(pages[row].title)")
    }

    // MARK: - Carregamento

    private func selected<T>(_ popup: NSPopUpButton, _ items: [T]) -> T? {
        let idx = popup.indexOfSelectedItem
        guard idx >= 0, idx < items.count else { return nil }
        return items[idx]
    }

    private func reloadDatabases() async {
        guard let notion = notion else { return }
        do {
            let dbs = try await notion.listDatabases()
            await MainActor.run {
                self.databases = dbs
                self.databasePopup.removeAllItems()
                self.databasePopup.addItems(withTitles: dbs.map { $0.title })
                if let saved = AppConfig.databaseId, let idx = dbs.firstIndex(where: { $0.id == saved }) {
                    self.databasePopup.selectItem(at: idx)
                }
            }
            if let db = selected(databasePopup, databases) { await reloadDatabaseDetails(db.id) }
        } catch {
            await MainActor.run { self.setStatus("Erro: \(error.localizedDescription)", error: true) }
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
            }
            await reloadPages(databaseId: databaseId, query: searchField.stringValue)
        } catch {
            await MainActor.run { self.setStatus("Erro: \(error.localizedDescription)", error: true) }
        }
    }

    private func reloadPages(databaseId: String, query: String) async {
        guard let notion = notion else { return }
        do {
            let result = try await notion.listPages(databaseId: databaseId, titleProperty: titleProperty, query: query)
            await MainActor.run { self.pages = result; self.cardsTable.reloadData() }
        } catch {
            await MainActor.run { self.setStatus("Erro: \(error.localizedDescription)", error: true) }
        }
    }

    private func setStatus(_ text: String, error: Bool = false) {
        statusLabel.stringValue = text
        statusLabel.textColor = error ? Brand.danger : Brand.textMuted
    }
}
