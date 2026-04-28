# Editor-VP — AI Video Editor

Editor de vídeo automatizado com IA para podcasts da Vitamina Publicitária.

## Setup

```bash
pip install -r requirements.txt
cp .env.example .env
# Edite .env com suas API keys
```

## Uso

```bash
# Editar vídeo com configuração padrão
python -m src.main edit --input video.mp4

# Editar com configuração customizada
python -m src.main edit --input video.mp4 --config minha_config.json

# Só transcrever (sem editar)
python -m src.main transcribe --input video.mp4

# Ver opções
python -m src.main --help
```

## Variáveis de Ambiente

- `ELEVENLABS_API_KEY` — Chave da API ElevenLabs (transcrição primária)
- `ANTHROPIC_API_KEY` — Chave da API Anthropic Claude (detecção de erros)
- `HF_TOKEN` — Token Hugging Face (opcional, para WhisperX diarization)

## Output

Todos os arquivos são salvos em `output/`:
- `video_editado.mp4` — vídeo final com legendas animadas
- `subtitles.srt` — arquivo de legendas externo
- `edit_report.json` — relatório completo do que foi cortado e por quê

## Pipeline

```
Input → Extração áudio → Transcrição → Detecção silêncio
      → Detecção erros (Claude) → Planejamento segmentos
      → Corte do vídeo → Legendas animadas → Output
```

## Stack

- `elevenlabs` — Transcrição primária (Scribe v2)
- `faster-whisper` — Transcrição fallback local
- `moviepy` v2 + `ffmpeg-python` — Processamento de vídeo
- `pydub` — Análise de áudio
- `anthropic` — Detecção de erros com Claude
- `Pillow` — Renderização de legendas animadas
- `click` — CLI
