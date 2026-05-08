import path from "path";
import fs from "fs";
import { execSync } from "child_process";
import { transcribeAudio } from "./transcribe";

const PUBLIC = path.join(process.cwd(), "public");
const AUDIO_OUT = path.join(PUBLIC, "dialogue.wav");
const COVER_OUT = path.join(PUBLIC, "podcast-cover.jpeg");
const ROOT_TSX = path.join(process.cwd(), "src", "Root.tsx");

async function main() {
  const [inputFile, title, coverFile] = process.argv.slice(2);

  if (!inputFile) {
    console.log(
      'Uso: npm run setup -- <video.mp4> ["Título do episódio"] [capa.jpg]',
    );
    process.exit(1);
  }

  const absInput = path.resolve(inputFile);
  if (!fs.existsSync(absInput)) {
    console.error(`❌ Arquivo não encontrado: ${absInput}`);
    process.exit(1);
  }

  console.log("🎵 Extraindo áudio...");
  execSync(
    `npx remotion ffmpeg -i "${absInput}" -vn -ar 44100 -ac 2 "${AUDIO_OUT}" -y`,
    { stdio: "inherit" },
  );
  console.log("✅ Áudio extraído.");

  if (coverFile) {
    const absCover = path.resolve(coverFile);
    if (fs.existsSync(absCover)) {
      fs.copyFileSync(absCover, COVER_OUT);
      console.log("✅ Capa copiada.");
    } else {
      console.warn(`⚠️  Capa não encontrada: ${coverFile}`);
    }
  }

  if (title) {
    const root = fs.readFileSync(ROOT_TSX, "utf-8");
    const escaped = title.replace(/\\/g, "\\\\").replace(/"/g, '\\"');
    const updated = root.replace(/titleText: ".*?"/, `titleText: "${escaped}"`);
    fs.writeFileSync(ROOT_TSX, updated);
    console.log(`✅ Título: "${title}"`);
  }

  console.log(
    "🎙️  Transcrevendo (pode demorar alguns minutos na primeira vez)...",
  );
  await transcribeAudio({ audioPath: absInput, speechStartsAtSecond: 0 });

  console.log("\n🎬 Pronto! Execute: npm run dev");
}

main().catch((e: Error) => {
  console.error("❌ Erro:", e.message);
  process.exit(1);
});
