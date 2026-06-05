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

1. **Quem é o dono da verdade do status** — Notion ou o sistema da Vercel?
2. **O sistema na Vercel tem backend/banco** capaz de hospedar a página de
   aprovação e receber webhooks? Quais tecnologias (Next.js? banco?)?
3. **A integração de WhatsApp** atual é disparável por API (oficial / Z-API /
   Twilio)? Dá pra acionar programaticamente a partir de um webhook?
4. **Feedback do cliente:** basta *Aprovar / Pedir ajustes + texto*, ou querem
   **comentários com timecode** (estilo Frame.io)?
5. **Privacidade:** os vídeos são sensíveis a vazamento? Vale signed URL +
   watermark?
```
