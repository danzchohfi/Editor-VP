# Guia: gerar o instalador (.dmg) no Mac — passo a passo

Feito para quem nunca usou Xcode/Terminal. Você faz isto **uma vez** e sai com
o arquivo `NotionExport.dmg` pronto para instalar.

> Você **não** precisa instalar "o Swift" separado — o Swift já vem dentro do
> Xcode. O script instala sozinho o resto (Homebrew e XcodeGen).

---

## Passo 1 — Instalar o Xcode (uma vez)

1. Abra a **App Store** no Mac.
2. Busque por **Xcode** e clique em **Obter / Instalar**.
   - É um download grande (vários GB) e demora bastante. Deixe baixando.
3. Quando terminar, **abra o Xcode uma vez**. Se aparecer uma janela pedindo
   para instalar componentes adicionais, clique em **Install** e digite sua
   senha do Mac. Depois pode **fechar o Xcode**.

---

## Passo 2 — Baixar o projeto

**Opção fácil (sem comandos):**
1. No GitHub, abra o repositório, troque para o branch
   `claude/fcpx-notion-export-extension-JvzOv`.
2. Clique no botão verde **Code → Download ZIP**.
3. O arquivo vai para **Downloads**. Dê dois cliques para descompactar.
   Vai virar uma pasta tipo `Editor-VP-claude-fcpx-...`.

---

## Passo 3 — Rodar o script

1. Abra o app **Terminal** (aperte `Cmd + Espaço`, digite `Terminal`, Enter).
2. No Terminal, digite `cd ` (com um espaço depois) **mas não aperte Enter**:
   ```
   cd 
   ```
3. Agora **arraste a pasta `fcpx-notion-export`** (de dentro da pasta que você
   descompactou) para dentro da janela do Terminal. Ele preenche o caminho
   sozinho. Aperte **Enter**.
4. Cole estes dois comandos, um de cada vez, apertando Enter em cada:
   ```bash
   chmod +x build_dmg.sh
   ./build_dmg.sh
   ```
5. Na primeira vez ele pode pedir a **senha do Mac** (para instalar o Homebrew)
   — é normal, digite e siga. A senha não aparece na tela enquanto você digita.
6. Espere. Quando terminar, vai aparecer:
   ```
   PRONTO! Seu instalador está em:
     .../fcpx-notion-export/dist/NotionExport.dmg
   ```

---

## Passo 4 — Instalar o app

1. Abra o arquivo **`dist/NotionExport.dmg`** (dois cliques).
2. **Arraste** o `NotionExport.app` para a pasta **Aplicativos**.
3. No **primeiro uso**, clique com o **botão direito** no app → **Abrir** →
   **Abrir**. (Isso libera o aviso de segurança do macOS, porque o app não tem
   assinatura paga da Apple. Só precisa fazer isto uma vez.)

---

## Passo 5 — Ativar no Final Cut Pro

Se o destino **"Enviar para o Notion"** não aparecer no menu *Compartilhar*:

1. Abra **Ajustes do Sistema → Geral → Itens de Login e Extensões**.
2. Em **Compartilhamento**, marque **"Enviar para o Notion"**.

Pronto. No Final Cut: **Arquivo → Compartilhar → Enviar para o Notion**.

---

## Se der algum erro

- **"o Xcode completo não está pronto"** → faltou abrir o Xcode uma vez, ou
  rode no Terminal:
  ```bash
  sudo xcodebuild -license accept
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  ```
  e rode `./build_dmg.sh` de novo.
- **Qualquer outra mensagem** → copie o texto que apareceu no Terminal e me
  mande; eu te digo o que fazer.
