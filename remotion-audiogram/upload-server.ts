import http from "node:http";
import path from "node:path";
import fs from "node:fs";
import os from "node:os";
import { execSync } from "node:child_process";
import busboy from "busboy";
import {
  downloadWhisperModel,
  installWhisperCpp,
  transcribe,
  toCaptions,
  type WhisperModel,
} from "@remotion/install-whisper-cpp";

const PORT = 3003;
const PUBLIC = path.join(process.cwd(), "public");
const ROOT_TSX = path.join(process.cwd(), "src", "Root.tsx");
const AUDIO_OUT = path.join(PUBLIC, "dialogue.wav");
const WHISPER_VERSION = process.platform === "win32" ? "1.6.0" : "1.7.4";
const WHISPER_MODEL: WhisperModel = "medium";
const WHISPER_PATH = path.join(process.cwd(), "whisper.cpp");

const PAGE = `<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>VP Audiogram</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: -apple-system, BlinkMacSystemFont, sans-serif; background: #0f0f0f; color: #f0f0f0; min-height: 100vh; display: flex; align-items: center; justify-content: center; }
    .card { background: #1a1a1a; border-radius: 16px; padding: 40px; width: 100%; max-width: 480px; }
    h1 { font-size: 24px; margin-bottom: 8px; }
    .sub { color: #888; margin-bottom: 32px; font-size: 15px; }
    .drop-zone { border: 2px dashed #333; border-radius: 12px; padding: 48px 24px; text-align: center; cursor: pointer; transition: all 0.2s; }
    .drop-zone:hover, .drop-zone.over { border-color: #0A84FF; background: rgba(10,132,255,0.07); }
    .drop-zone p { color: #888; margin-top: 8px; font-size: 14px; }
    .icon { font-size: 40px; }
    #fileName { color: #0A84FF; font-weight: 500; margin-top: 12px; min-height: 20px; font-size: 14px; }
    input[type="file"] { display: none; }
    input[type="text"] { width: 100%; padding: 12px 16px; margin-top: 16px; background: #262626; border: 1px solid #333; border-radius: 10px; color: #f0f0f0; font-size: 15px; outline: none; }
    input[type="text"]::placeholder { color: #555; }
    input[type="text"]:focus { border-color: #0A84FF; }
    button { margin-top: 16px; width: 100%; padding: 14px; background: #0A84FF; color: white; border: none; border-radius: 10px; cursor: pointer; font-size: 16px; font-weight: 600; transition: background 0.2s; }
    button:hover:not(:disabled) { background: #0068CC; }
    button:disabled { background: #2a2a2a; color: #555; cursor: not-allowed; }
    #log { margin-top: 24px; background: #0a0a0a; border: 1px solid #222; padding: 16px; border-radius: 10px; font-family: monospace; font-size: 13px; white-space: pre-wrap; line-height: 1.7; max-height: 260px; overflow-y: auto; display: none; }
  </style>
</head>
<body>
  <div class="card">
    <h1>🎙️ VP Audiogram</h1>
    <p class="sub">Carregue seu episódio para gerar o audiograma automaticamente</p>

    <div class="drop-zone" id="drop" onclick="document.getElementById('fi').click()">
      <div class="icon">🎬</div>
      <p>Arraste o vídeo aqui ou clique para selecionar</p>
      <div id="fileName"></div>
      <input type="file" id="fi" accept="video/*,audio/*">
    </div>

    <input type="text" id="title" placeholder="Título do episódio (opcional)">
    <button id="btn" onclick="go()">Processar</button>
    <div id="log"></div>
  </div>

  <script>
    let file = null;
    const drop = document.getElementById('drop');
    const fi = document.getElementById('fi');
    const logEl = document.getElementById('log');
    const btn = document.getElementById('btn');

    drop.addEventListener('dragover', e => { e.preventDefault(); drop.classList.add('over'); });
    drop.addEventListener('dragleave', () => drop.classList.remove('over'));
    drop.addEventListener('drop', e => {
      e.preventDefault(); drop.classList.remove('over');
      setFile(e.dataTransfer.files[0]);
    });
    fi.addEventListener('change', () => setFile(fi.files[0]));

    function setFile(f) {
      file = f;
      document.getElementById('fileName').textContent = '📁 ' + f.name;
    }

    async function go() {
      if (!file) { alert('Selecione um arquivo primeiro.'); return; }
      btn.disabled = true;
      btn.textContent = 'Processando...';
      logEl.style.display = 'block';
      logEl.textContent = '';

      const fd = new FormData();
      fd.append('video', file);
      fd.append('title', document.getElementById('title').value);

      try {
        const res = await fetch('/upload', { method: 'POST', body: fd });
        const reader = res.body.getReader();
        const dec = new TextDecoder();
        while (true) {
          const { done, value } = await reader.read();
          if (done) break;
          logEl.textContent += dec.decode(value);
          logEl.scrollTop = logEl.scrollHeight;
        }
      } catch (e) {
        logEl.textContent += '\\n❌ Erro de conexão: ' + e.message;
      }

      btn.disabled = false;
      btn.textContent = 'Processar outro';
    }
  </script>
</body>
</html>`;

const server = http.createServer(async (req, res) => {
  if (req.method === "GET") {
    res.writeHead(200, { "Content-Type": "text/html; charset=utf-8" });
    res.end(PAGE);
    return;
  }

  if (req.method === "POST" && req.url === "/upload") {
    res.writeHead(200, {
      "Content-Type": "text/plain; charset=utf-8",
      "Transfer-Encoding": "chunked",
      "Cache-Control": "no-cache",
    });

    const log = (msg: string) => {
      process.stdout.write(msg + "\n");
      res.write(msg + "\n");
    };

    let inputPath = "";
    let title = "";

    try {
      await new Promise<void>((resolve, reject) => {
        const bb = busboy({ headers: req.headers });
        bb.on("file", (_name, file, info) => {
          inputPath = path.join(
            os.tmpdir(),
            `vp-${Date.now()}-${info.filename}`,
          );
          log(`📥 Recebendo: ${info.filename}...`);
          const ws = fs.createWriteStream(inputPath);
          file.pipe(ws);
          ws.on("close", resolve);
          ws.on("error", reject);
        });
        bb.on("field", (name, val) => {
          if (name === "title") title = val;
        });
        bb.on("error", reject);
        req.pipe(bb);
      });

      log("🎵 Extraindo áudio...");
      execSync(
        `npx remotion ffmpeg -i "${inputPath}" -vn -ar 44100 -ac 2 "${AUDIO_OUT}" -y`,
        { stdio: "pipe" },
      );
      log("✅ Áudio extraído.");

      if (title) {
        const root = fs.readFileSync(ROOT_TSX, "utf-8");
        const escaped = title.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
        const updated = root.replace(
          /titleText: ".*?"/,
          `titleText: "${escaped}"`,
        );
        fs.writeFileSync(ROOT_TSX, updated);
        log(`✅ Título: "${title}"`);
      }

      log("⬇️  Preparando Whisper (só na primeira vez pode demorar)...");
      await installWhisperCpp({ to: WHISPER_PATH, version: WHISPER_VERSION });
      await downloadWhisperModel({ model: WHISPER_MODEL, folder: WHISPER_PATH });

      log("🎙️  Transcrevendo...");
      const tempWav = path.join(os.tmpdir(), `whisper-${Date.now()}.wav`);
      execSync(
        `npx remotion ffmpeg -i "${inputPath}" -ar 16000 -ac 1 "${tempWav}" -y`,
        { stdio: "pipe" },
      );

      const output = await transcribe({
        model: WHISPER_MODEL,
        whisperPath: WHISPER_PATH,
        inputPath: tempWav,
        tokenLevelTimestamps: true,
        language: "pt",
        whisperCppVersion: WHISPER_VERSION,
      });

      const { captions } = toCaptions({ whisperCppOutput: output });
      fs.writeFileSync(
        path.join(PUBLIC, "captions.json"),
        JSON.stringify(captions, null, 2),
      );

      fs.unlinkSync(tempWav);
      fs.unlinkSync(inputPath);

      log("✅ Transcrição concluída.");
      log("\n🎬 Pronto! Abra o Remotion Studio para ver o resultado.");
    } catch (e: unknown) {
      const msg = e instanceof Error ? e.message : String(e);
      log(`\n❌ Erro: ${msg}`);
      if (inputPath && fs.existsSync(inputPath)) fs.unlinkSync(inputPath);
    }

    res.end();
    return;
  }

  res.writeHead(404);
  res.end();
});

server.listen(PORT, () => {
  console.log(`\n🎙️  Abra no navegador → http://localhost:${PORT}\n`);
});
