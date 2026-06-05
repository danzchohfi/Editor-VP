# Guia: adicionar o painel dentro do Final Cut Pro (Workflow Extension)

Este painel é o que aparece em **Janela → Extensões** do Final Cut Pro (igual
ao Frame.io). Diferente da Share Extension (que o `build_dmg.sh` compila
sozinho), o painel usa o **SDK/template oficial da Apple**, que é licenciado e
**não pode ser embutido neste repositório**. Por isso ele é adicionado com
alguns passos no Xcode, **uma vez**.

> Você só precisa fazer isto se quiser o painel encaixado no FCPX. A exportação
> em si funciona sem ele, pelo menu **Compartilhar**.

## 1. Pegar o SDK / template da Apple

1. Acesse os downloads do Apple Developer e baixe o **Final Cut Pro –
   Workflow Extensions SDK** (também chamado "Workflow Extensions SDK").
   - Procure por "Workflow Extensions" em developer.apple.com/download.
2. Instale-o seguindo o README do SDK. Isso adiciona o template
   **"Final Cut Pro Workflow Extension"** ao Xcode.

## 2. Criar o alvo a partir do template

1. Abra o projeto gerado pelo `build_dmg.sh` (`NotionExport.xcodeproj`) no Xcode
   — ou rode `xcodegen generate` e abra.
2. **File → New → Target…**, escolha **Final Cut Pro Workflow Extension**,
   nomeie por exemplo `WorkflowExtension`. O template já cria:
   - o `Info.plist` com o `NSExtensionPointIdentifier` correto;
   - a `ProExtensionPrincipalClass` (a classe que o FCPX carrega);
   - o vínculo com o framework `ProExtension`.

## 3. Trazer o nosso código para o alvo

1. Adicione ao alvo `WorkflowExtension` (marque a caixa "Target Membership"):
   - `WorkflowExtension/WorkflowPanelViewController.swift`
   - `Shared/Theme.swift`
   - `Shared/NotionClient.swift`
   - `Shared/CloudflareStreamClient.swift`
   - `Shared/KeychainTokenStore.swift`
2. Em **Signing & Capabilities** do alvo, ative **App Sandbox** com
   **Outgoing Connections (Client)** e marque **Disable Library Validation**
   (necessário para o painel carregar sem assinatura paga).

## 4. Fazer a principal class apresentar o nosso painel

O template gera uma `ProExtensionPrincipalClass`. Faça ela devolver o nosso
`WorkflowPanelViewController`. O formato exato vem do SDK; o trecho abaixo é o
padrão (ajuste o nome do protocolo/propriedade ao que o template trouxe):

```swift
import Cocoa
import ProExtension   // vem do SDK da Apple

class ProExtensionPrincipalClass: NSObject, ProExtensionPrincipalClassProtocol {

    // Preenchido pelo host (Final Cut Pro). Guarde se precisar acessar o
    // projeto/biblioteca no futuro.
    var hostInfo: ProExtensionHostInterface!

    // O FCPX pede a view do painel. Devolvemos o nosso controller AppKit.
    private lazy var panel = WorkflowPanelViewController()

    func viewController() -> NSViewController { panel }
}
```

> Se o template usar um Storyboard em vez de `viewController()`, basta trocar a
> classe do view controller do storyboard por `WorkflowPanelViewController` (ou
> instanciá-lo no `viewDidLoad`).

## 5. Compilar e testar

1. Selecione o esquema do app `NotionExport` e **Run** (isso instala o app e a
   extensão).
2. Abra o Final Cut Pro → **Janela → Extensões → Enviar para o Notion**.
3. Se não aparecer, verifique em **Ajustes do Sistema → Geral → Itens de Login
   e Extensões** se a extensão está ativada.

## Observações honestas

- **Não testei a compilação** (escrevi fora do Mac e o SDK é da Apple). O
  `WorkflowPanelViewController` é AppKit puro e independente do SDK; a única
  parte que toca o SDK é a `ProExtensionPrincipalClass` acima, que o template
  fornece — então o ajuste no Mac é pequeno.
- **Sem conta paga**, o painel e a Share Extension **não compartilham as
  credenciais automaticamente** (isso exigiria App Group / assinatura paga).
  Na prática: configure o token uma vez no painel e uma vez no primeiro
  Compartilhar. Com conta paga, dá para unificar via App Group.
- O painel serve para **login, escolher banco, navegar pelos cards e definir as
  propriedades**. O **upload do vídeo final** acontece pelo **Compartilhar**.
```
