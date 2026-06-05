import Cocoa

/// App container mínimo. Existe porque uma Share Extension precisa ser
/// distribuída dentro de um app host. A janela só mostra instruções de uso.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false)
        window.title = "Notion Export para Final Cut Pro"
        window.center()

        let text = NSTextField(wrappingLabelWithString: """
        Notion Export para Final Cut Pro

        Adiciona o destino "Enviar para o Notion" no menu Compartilhar.
        Ao compartilhar, o vídeo sobe no Cloudflare Stream e o link de
        aprovação é gravado no card do cliente no Notion (o arquivo também
        é anexado).

        Configuração inicial (uma vez):
        1. Notion: crie uma integração interna em notion.so/my-integrations
           e copie o "Internal Integration Secret".
        2. Notion: no banco desejado → ••• → Conexões → adicione a integração.
        3. Cloudflare: pegue seu Account ID e crie um API Token com a
           permissão Stream:Edit.
        4. No Final Cut Pro: Arquivo → Compartilhar → Enviar para o Notion.
           Na 1ª vez cole as credenciais; depois é só escolher o banco,
           o card (cliente) e as propriedades de link e de arquivo.

        Se o destino não aparecer, abra Ajustes do Sistema → Geral →
        Itens de Login e Extensões → Compartilhamento e marque
        "Enviar para o Notion".
        """)
        text.frame = NSRect(x: 24, y: 20, width: 472, height: 320)
        window.contentView?.addSubview(text)

        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
