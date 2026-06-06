# Arquitetura da solução de aprovação de vídeos — mapa e melhorias

> Documento de arquitetura. Objetivo do produto: **fazer o cliente aprovar
> nossos vídeos** com o mínimo de atrito, e **facilitar a entrega** dos
> materiais para nossas plataformas (Notion, Cloudflare Stream e o nosso
> sistema/site na Vercel), que hoje dispara o link por WhatsApp para o cliente.

## 1. Atores e sistemas

| Sistema | Papel hoje | Papel recomendado |
|---|---|---|
| **Final Cut Pro** | Edição e exportação | Ponto de ingestão (Share + Painel) |
| **Cloudflare Stream** | Hospeda e faz streaming do vídeo | Storage/CDN + segurança (signed URL, watermark) |
| **Notion** | Card do cliente recebe link/arquivo | Sistema operacional editorial (cards + **status**) |
| **Sistema/site (Vercel)** | Envia o link por WhatsApp | **Orquestrador** + **página de aprovação** do cliente |
| **WhatsApp** | Canal de aprovação | Canal (mantido), disparado automaticamente |
| **Cliente** | Recebe link, responde no WhatsApp | Aprova/pede ajustes numa página rastreável |

## 2. Fluxo atual (como entendo hoje)

```
[Final Cut Pro]
   │ Compartilhar (Share Extension)
   ▼
[Cloudflare Stream] ──link──► [Notion: card do cliente]
                                   │ (manual: copiar link)
                                   ▼
                            [Sistema Vercel] ──► [WhatsApp] ──► [Cliente]
                                                                   │ responde "ok" / "muda X" (texto)
                                                                   ▼
                                                         (volta manual para o editor)
```

### Riscos e lacunas
- **Sem dono único da verdade do status.** O "aprovado?" vive no WhatsApp (texto
  solto), não num campo estruturado. Difícil auditar e automatizar.
- **Passos manuais** (copiar link, mandar WhatsApp, reportar de volta ao editor).
- **Feedback não estruturado.** "Muda o corte aos 0:42" chega como texto no
  WhatsApp, sem timecode, sem histórico, sem vínculo com a versão.
- **Versionamento frágil.** v1, v2, v3 do mesmo vídeo tendem a se sobrescrever
  ou se perder no card.
- **Segurança/custo do link.** Link público pode circular; versões antigas no
  Cloudflare acumulam custo (cobra por minuto armazenado + entregue).
- **Sem visibilidade.** Não se sabe se o cliente abriu/assistiu antes de cobrar.

## 3. Arquitetura-alvo recomendada

```
[Final Cut Pro]  (Share Extension + Painel)
   │ upload (tus) + metadados: cliente, projeto, versão, editor, data
   ▼
[Cloudflare Stream]  ──webhook "readyToStream"──►  [Backend (Vercel) = ORQUESTRADOR]
   (storage/CDN, signed URL,                              │
    watermark, allowedOrigins)                            ├─► grava no [Notion]:
                                                          │     link, versão, status = "Aguardando aprovação"
                                                          ├─► dispara [WhatsApp] com o link da
                                                          │     PÁGINA DE APROVAÇÃO (domínio nosso)
                                                          ▼
                                          [Página /aprovar/:id  (Vercel)]
                                          player + [Aprovar] [Pedir ajustes]
                                          (+ comentários com timecode, opcional)
                                                          │ ação do cliente
                                                          ▼
                                          [Backend] grava status no Notion
                                                    + notifica o editor (Notion/Slack/WhatsApp)
```

**Princípios:**
- **Notion = camada de dados editorial** (cards, status, versões).
- **Backend na Vercel = orquestrador e glue** (webhooks, automações, página do
  cliente). É quem tira os passos manuais.
- **Cloudflare = só storage/entrega/segurança.**
- **O link enviado ao cliente aponta para a NOSSA página**, não para o `/watch`
  cru do Cloudflare. Isso dá marca, rastreio, segurança e botões de ação.

## 4. Melhorias priorizadas

### Quick wins (alto impacto, esforço baixo/médio)
1. **Máquina de estados no Notion** — propriedade *Status* (`Em edição →
   Aguardando aprovação → Aprovado / Ajustes solicitados → Publicado`). A
   extensão já grava `Aguardando aprovação` ao subir. Vira o gatilho de tudo.
2. **Automatizar o WhatsApp** — em vez de copiar link à mão, o backend observa o
   card entrar em "Aguardando aprovação" (webhook do Notion ou polling) e dispara
   o WhatsApp. (Vocês já têm a integração; aqui é só ligar o gatilho.)
3. **Página de aprovação branded** (`/aprovar/:id`) — player do vídeo + botões
   **Aprovar** / **Pedir ajustes** + campo de comentário. Substitui o link cru.
4. **Versionamento** — cada export = nova versão no card (v1, v2…), preservando
   histórico; a página sempre mostra a versão mais recente.
5. **Metadados automáticos** — a **Workflow Extension lê o nome do projeto no
   FCPX** e pré-preenche cliente/projeto/versão (menos digitação, menos erro).

### Alto impacto, esforço maior
6. **Webhook do Cloudflare ("ready")** → orquestração server-side, em vez de a
   extensão ficar esperando o processamento. Mais robusto.
7. **Loop de feedback fechado** — aprovação/ajuste grava status no Notion e
   **notifica o editor** (sem depender de alguém ler o WhatsApp e avisar).
8. **Comentários com timecode (estilo Frame.io)** na página de aprovação — o
   padrão-ouro de revisão de vídeo. Mais caro de construir; ótimo diferencial.

### Segurança e custo
9. **Signed URLs + `allowedOrigins`** — o vídeo só toca embedado na nossa página,
   não no link cru (evita vazamento se o link circular).
10. **Watermark** com nome/e-mail do cliente + data — desencoraja vazar material
    pré-aprovação.
11. **Lifecycle/limpeza** — apagar versões antigas após aprovação ou após N dias
    (controle de custo do Cloudflare Stream).

### Confiabilidade e operação
12. **Convenção de nomes** no export (`cliente_projeto_v3_AAAA-MM-DD`) — busca e
    organização.
13. **Analytics de visualização** — saber se o cliente abriu e quanto assistiu
    antes de cobrar.
14. **Observabilidade/auditoria** — quem aprovou, quando, qual versão.

## 5. Roadmap sugerido em fases

- **Fase 0 (feito):** export do FCPX → Cloudflare → link + arquivo no card do Notion.
- **Fase 1 — Tirar o trabalho manual:** Status no Notion + disparo automático do
  WhatsApp + página de aprovação simples (Aprovar / Pedir ajustes) que grava de
  volta no Notion.
- **Fase 2 — Fechar o loop:** notificação ao editor na aprovação/ajuste;
  versionamento no card; metadados automáticos vindos do FCPX.
- **Fase 3 — Profissionalizar:** comentários com timecode na página; signed URLs
  + watermark + allowedOrigins; analytics; limpeza automática de versões.

## 6. Decisões em aberto (para afinar o plano)

> **Status (informado pela equipe):** os itens 1, 2 e 3 (status como fonte da
> verdade, backend na Vercel e WhatsApp disparável por API) **já estão em
> produção**. O foco passa a ser **4 (feedback com timecode)** e
> **5 (segurança/watermark)**, detalhados abaixo.

## 7. Item 4 — Comentários com timecode (revisão estilo Frame.io)

**Objetivo:** o cliente deixa feedback preso a um momento do vídeo
("aos 0:42, tira essa cartela"), rastreável, ligado à versão, e o editor
consome isso no fluxo dele.

**Como encaixa na nossa stack (sem ferramenta externa):**
- O **Stream Player do Cloudflare** expõe API JS (`player.currentTime`,
  `play/pause`, `seek`, eventos). Então na **página de aprovação (Vercel)**:
  - botão **"Comentar neste ponto"** captura o `currentTime`;
  - salva `{versão, timecode_seg, texto, autor, criado_em, status}`;
  - lista de comentários abaixo do player, cada um **clicável para saltar** ao
    timecode.
- **Onde guardar:** no banco de vocês (Vercel) como dono do dado, **espelhando
  um resumo no Notion** (uma base "Feedback" com relação ao card + Número
  `timecode` + Texto + Status `Aberto/Resolvido`). Assim o editor vê no hub
  (Notion) e o histórico fica por versão.
- **Bônus de alto valor:** o **painel dentro do Final Cut** (a Workflow Extension
  que já criamos) pode **listar os comentários do projeto atual** — o editor lê
  o feedback do cliente sem sair do FCPX.

**Níveis (faseável):**
1. **Timecode + texto** (recomendado p/ v1) — cobre ~90% do valor.
2. **+ Desenho no frame** (anotação sobre a imagem) — Frame.io completo; bem mais
   caro (overlay em canvas + coordenadas). Só se houver demanda real.

**O que muda na extensão do FCPX:** nada. É trabalho de backend + página.

## 8. Item 5 — Segurança e watermark (anti-vazamento)

**Objetivo:** material pré-aprovação não vaza; se o link circular, não toca; e
desencorajar gravação de tela com identificação do espectador.

**Mecanismos do Cloudflare Stream:**
- **`requireSignedURLs: true`** — playback exige um token (JWT) assinado no
  backend, curto (com `exp`). O link cru `/watch` deixa de tocar.
- **`allowedOrigins`** — o vídeo só toca **embedado no nosso domínio** (a página
  de aprovação), não em qualquer lugar.
- **Watermark fixa** (perfil de watermark do Cloudflare) — queima a **logo
  vitamina** no vídeo. É estática (mesma para todos).
- **Watermark dinâmica por espectador** (nome/e-mail/data do cliente) — feita
  como **overlay no player** (DOM/CSS) na página. Desencoraja e identifica a
  sessão; **não** é forense (um técnico remove). Burn-in forense por espectador
  exigiria transcode por viewer → **caro**, normalmente não vale.
- **Download desligado** (sem MP4 baixável) — dificulta ripar.
- **Expiração** do link de aprovação (após aprovar ou após N dias) — opcional.

**Regra de ouro de segurança:** a **chave de assinatura / token com poder de
assinar fica SÓ no backend**, nunca no app do Mac. A extensão só tem
`Stream:Edit` para subir.

**O que muda na extensão do FCPX (pequeno):**
- Subir o vídeo já **privado** (`requiresignedurls = true` na criação do upload).
- Gravar no Notion **o UID do vídeo no Cloudflare** (além/no lugar do link cru),
  para o backend assinar o token e montar a página de aprovação.
- O link enviado ao cliente passa a ser a **página de aprovação** (montada pelo
  backend), não o `/watch`.

> Resumo da separação de responsabilidades: a **extensão** termina em
> "vídeo privado no Cloudflare + UID/card no Notion + status = Aguardando
> aprovação". O **backend** cuida de assinar URL, watermark dinâmica,
> `allowedOrigins`, página e WhatsApp.

## 9. Decisões tomadas (itens 4 e 5)

- **Item 4 — feedback:** **sem** comentários com timecode. Mantém-se apenas
  **Aprovar / Pedir ajustes + texto livre** (já coberto pelo fluxo atual).
- **Onde o editor vê:** **Notion + painel dentro do Final Cut** (ambos).
- **Item 5 — watermark/segurança:** **não é necessário** por enquanto (sem
  signed URLs, sem watermark, sem expiração). Vídeos seguem com link direto.

### Escopo resultante (a única peça nova)

Trazer para o **painel da Workflow Extension** (dentro do FCPX) o **status de
aprovação** e o **texto de "pedir ajustes"** de cada card, lidos do Notion —
fechando o loop para o editor sem sair do Final Cut. Nada muda no item de
segurança nem na página do cliente.

**Precisa definir:** em quais propriedades do Notion vivem o **status** e o
**texto de ajustes** (ou se o texto fica como **comentário** da página — o que
muda a forma de ler via API).
```
