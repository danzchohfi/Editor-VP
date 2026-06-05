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

        Esta extensão adiciona um destino "Enviar para o Notion" no menu
        Compartilhar do Final Cut Pro.

        Configuração inicial (uma vez):
        1. No Notion, crie uma integração interna em
           notion.so/my-integrations e copie o "Internal Integration Secret".
        2. Abra o banco de dados desejado → menu ••• → Conexões →
           adicione a sua integração (assim ela enxerga o banco).
        3. No Final Cut Pro, selecione um clipe/projeto e use
           Arquivo → Compartilhar → Enviar para o Notion.
        4. Cole o token na primeira vez. Depois é só escolher o banco,
           o registro (cliente/card) e a propriedade de arquivo.

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
