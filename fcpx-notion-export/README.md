# Notion Export — extensão de Compartilhamento para Final Cut Pro

Adiciona um destino **"Enviar para o Notion"** no menu *Compartilhar* do Final
Cut Pro. Ao compartilhar um vídeo, abre uma janela para você escolher o **banco
de dados**, o **registro (cliente/card)** e a **propriedade de arquivo** onde o
vídeo será anexado. O upload usa a *File Upload API* do Notion (com multipart
automático para vídeos grandes).

> **Importante:** este é um app **macOS nativo**. A compilação e a geração do
> `.dmg` precisam ser feitas **num Mac com Xcode** — não há como gerar o `.dmg`
> em Linux/CI sem macOS. O código completo está aqui; você roda um comando e o
> `.dmg` sai pronto.

## Estrutura

```
fcpx-notion-export/
├── App/                  App container (host da extensão + tela de instruções)
├── ShareExtension/       A extensão que aparece no menu Compartilhar
│   └── ShareViewController.swift   UI: banco → registro → propriedade → enviar
├── Shared/
│   ├── NotionClient.swift          Cliente da API (listar, upload, anexar)
│   └── KeychainTokenStore.swift    Token no Keychain + preferências
├── project.yml           Definição do projeto (XcodeGen)
└── build_dmg.sh          Compila e empacota o .dmg
```

## Pré-requisitos no Mac

- macOS 12 ou superior
- Xcode (App Store) + `xcode-select --install`
- [Homebrew](https://brew.sh) (o script instala o XcodeGen via `brew` se faltar)

## Como gerar o `.dmg`

```bash
cd fcpx-notion-export
chmod +x build_dmg.sh
./build_dmg.sh
```

O `.dmg` final fica em `fcpx-notion-export/dist/NotionExport.dmg`.

> Sem conta paga do Apple Developer, o app é assinado **ad-hoc**. No primeiro
> uso o macOS bloqueia (Gatekeeper): **clique com o botão direito no app →
> Abrir → Abrir**. Só precisa fazer isso uma vez.

## Instalação

1. Abra o `.dmg` e arraste **NotionExport.app** para **Aplicativos**.
2. Abra o app uma vez (botão direito → Abrir).
3. Se o destino não aparecer no Final Cut, ative em **Ajustes do Sistema →
   Geral → Itens de Login e Extensões → Compartilhamento** e marque
   **"Enviar para o Notion"**.

## Configuração do Notion (uma vez)

1. Crie uma **integração interna** em <https://www.notion.so/my-integrations>
   e copie o **Internal Integration Secret** (`secret_...` / `ntn_...`).
2. Abra o banco de dados desejado no Notion → menu **•••** → **Conexões** →
   adicione a sua integração. (Sem isso a integração não enxerga o banco.)
3. Garanta que o banco tenha uma propriedade do tipo **"Arquivos e mídia"** —
   é nela que o vídeo será anexado.

## Uso no Final Cut Pro

1. Selecione um clipe ou projeto.
2. **Arquivo → Compartilhar → Enviar para o Notion**.
3. Na primeira vez, cole o token e clique em **Salvar** (fica guardado no
   Keychain; não pede de novo).
4. Escolha o **banco**, busque/escolha o **registro (cliente/card)** e a
   **propriedade de arquivo**, e clique em **Enviar para o Notion**.

O banco e a propriedade escolhidos ficam lembrados como padrão para as próximas
exportações.

## Notas técnicas

- **Sem App Groups:** como não há conta paga, a configuração (token + padrões)
  vive no sandbox da própria extensão (Keychain + UserDefaults), evitando
  *entitlements* que exigiriam provisionamento pago.
- **Upload:** arquivos ≤ 20 MB vão em parte única; acima disso, em partes de
  10 MB via *multi-part upload*, finalizando com `/complete`.
- **Versão da API:** `Notion-Version: 2022-06-28`.
- O código pode pedir pequenos ajustes ao abrir no Xcode (APIs AppKit), já que
  foi escrito fora do Mac. Os pontos de extensão e o fluxo estão completos.
```
