# Notion Export — extensão de Compartilhamento para Final Cut Pro

Adiciona um destino **"Enviar para o Notion"** no menu *Compartilhar* do Final
Cut Pro, voltado ao **fluxo de aprovação do cliente**:

1. O editor compartilha o vídeo no Final Cut.
2. A extensão **sobe o vídeo no Cloudflare Stream** (upload resumável `tus`,
   aguenta arquivos grandes) e aguarda o processamento.
3. Pega o **link público de "assistir"**
   (`https://customer-XXXX.cloudflarestream.com/<id>/watch`).
4. No **card do cliente** escolhido no Notion, grava o **link numa propriedade
   URL** e **anexa o arquivo numa propriedade "Arquivos e mídia"**.
5. Você copia o link do card e manda no WhatsApp para o cliente aprovar.

> **Importante:** é um app **macOS nativo**. Compilar e gerar o `.dmg` precisa
> ser feito **num Mac com Xcode** — não há como gerar o `.dmg` em Linux/CI. O
> código completo está aqui; você roda um comando e o `.dmg` sai pronto.

## Estrutura

```
fcpx-notion-export/
├── App/                  App container (host da extensão + tela de instruções)
├── ShareExtension/       A extensão que aparece no menu Compartilhar
│   └── ShareViewController.swift   UI: banco → card → link/arquivo → enviar
├── Shared/
│   ├── CloudflareStreamClient.swift  Upload tus + polling + link de watch
│   ├── NotionClient.swift            Listar bancos/registros, upload e propriedades
│   └── KeychainTokenStore.swift      Credenciais no Keychain + preferências
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
> uso o macOS bloqueia (Gatekeeper): **botão direito no app → Abrir → Abrir**.
> Só precisa fazer isso uma vez.

## Instalação

1. Abra o `.dmg` e arraste **NotionExport.app** para **Aplicativos**.
2. Abra o app uma vez (botão direito → Abrir).
3. Se o destino não aparecer no Final Cut, ative em **Ajustes do Sistema →
   Geral → Itens de Login e Extensões → Compartilhamento** e marque
   **"Enviar para o Notion"**.

## Configuração (uma vez)

### Notion
1. Crie uma **integração interna** em <https://www.notion.so/my-integrations>
   e copie o **Internal Integration Secret** (`ntn_...` / `secret_...`).
2. No banco de dados desejado → **•••** → **Conexões** → adicione a integração.
3. O banco precisa ter uma propriedade do tipo **URL** (para o link) e uma do
   tipo **Arquivos e mídia** (para o arquivo).

### Cloudflare Stream
1. Pegue o seu **Account ID** (no painel da Cloudflare).
2. Crie um **API Token** com a permissão **Stream:Edit**
   (<https://dash.cloudflare.com/profile/api-tokens>).

Na primeira exportação a extensão pede essas 3 credenciais (token do Notion,
Account ID e token do Cloudflare) e guarda no Keychain — não pede de novo.

## Uso no Final Cut Pro

1. Selecione um clipe ou projeto.
2. **Arquivo → Compartilhar → Enviar para o Notion**.
3. (1ª vez) cole as credenciais e **Salvar**.
4. Escolha o **banco**, busque/escolha o **card (cliente)**, confirme as
   **propriedades de link e de arquivo** e clique em **Enviar**.

A barra mostra: upload no Cloudflare → processamento → upload do arquivo no
Notion → gravação no card. O banco e as propriedades ficam lembrados como
padrão para as próximas exportações.

## Notas técnicas

- **Cloudflare tus:** `POST /accounts/{id}/stream` cria o upload (ID no header
  `stream-media-id`, URL no header `Location`); chunks de 50 MiB via `PATCH`;
  *polling* de `readyToStream` antes de devolver o link `preview`.
- **Notion:** *File Upload API* (parte única ≤ 20 MB, senão multi-part de
  10 MB); o link vai numa propriedade `url` e o arquivo numa `files`, gravados
  numa única chamada `PATCH /pages/{id}`. `Notion-Version: 2022-06-28`.
- **Vídeos públicos:** o link de watch abre sem login. Se um dia quiser links
  privados/assinados, dá para evoluir para *signed URLs* do Cloudflare.
- **Sem App Groups:** as credenciais ficam no sandbox da própria extensão
  (Keychain + UserDefaults), evitando *entitlements* que exigiriam conta paga.
- O código pode pedir pequenos ajustes ao abrir no Xcode (APIs AppKit), já que
  foi escrito fora do Mac. O fluxo e os pontos de extensão estão completos.

## Próximos passos possíveis

- Automatizar o envio do link no **WhatsApp** (via WhatsApp Business API) após
  a gravação no card.
- **Signed URLs** do Cloudflare para vídeos privados com expiração.
