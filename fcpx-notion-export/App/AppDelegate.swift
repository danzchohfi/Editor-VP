import Cocoa

/// App container mínimo. Existe porque uma Share Extension precisa ser
/// distribuída dentro de um app host. A janela mostra instruções, no visual
/// da marca (Produção.app).
@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered, defer: false)
        window.title = "Produção · Exportar para o Notion"
        window.center()
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = Brand.background

        let content = NSView(frame: window.contentLayoutRect)
        content.autoresizingMask = [.width, .height]

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -32),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 28)
        ])

        stack.addArrangedSubview(Brand.label("Produção", font: Brand.display(26), color: Brand.textPrimary))
        stack.addArrangedSubview(Brand.label("Exportar do Final Cut Pro para aprovação",
                                             font: Brand.body(14), color: Brand.textMuted))

        let steps = """
        Adiciona o destino “Enviar para o Notion” no menu Compartilhar do
        Final Cut Pro. O vídeo sobe no Cloudflare Stream e o link de aprovação
        é gravado no card do cliente no Notion (com o arquivo anexado).

        Configuração (uma vez):
        1.  Notion — crie uma integração interna em notion.so/my-integrations
            e copie o Internal Integration Secret.
        2.  Notion — no banco desejado: •••  →  Conexões  →  adicione a integração.
        3.  Cloudflare — pegue o Account ID e crie um API Token com Stream:Edit.
        4.  Final Cut — Arquivo → Compartilhar → Enviar para o Notion.
            Na 1ª vez, abra Configurações e cole as credenciais.

        Uso no dia a dia:
        •  Compartilhe o vídeo, digite o nome do cliente e clique no card.
        •  Confirme e toque em Enviar.

        O destino não apareceu? Ajustes do Sistema → Geral → Itens de Login e
        Extensões → Compartilhamento → marque “Enviar para o Notion”.
        """
        let body = Brand.label(steps, font: Brand.body(13), color: Brand.textPrimary)
        body.lineBreakMode = .byWordWrapping
        body.maximumNumberOfLines = 0
        body.preferredMaxLayoutWidth = 496
        stack.addArrangedSubview(body)

        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
