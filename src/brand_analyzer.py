"""
Brand analyzer: reads brand.json + transcript, calls Claude to generate
motion graphic cues (timestamps + type + content) for the video.

Returns a BrandCues dict with the full list of graphic events to render.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

from src.transcription import WordTimestamp


_SYSTEM_PROMPT = """Você é um diretor de arte e editor de vídeo especialista em motion graphics para podcasts e conteúdo de marca.

Receberá:
1. O transcript completo de um vídeo/podcast com timestamps
2. A identidade visual da empresa (brand config)

Sua tarefa é gerar uma lista de "graphic cues" — momentos específicos no vídeo onde animações de motion graphics devem aparecer.

TIPOS DE CUE disponíveis:
- "lower_third": Card animado com nome/cargo. Use nos PRIMEIROS 5 segundos E ao apresentar convidados.
- "keyword_bubble": Palavra/frase-chave importante aparece animada na tela. Use para conceitos centrais, termos técnicos marcantes, números impactantes.
- "quote_card": Frase marcante/inspiradora aparece grande na tela. Use para 1-2 momentos de pico emocional ou insight poderoso.
- "intro_bumper": Tela de abertura com a marca. SEMPRE aos 0.0s, duração 3.5s.
- "outro_bumper": Tela de encerramento com a marca e CTA. SEMPRE nos últimos 5s do vídeo.
- "topic_title": Título de tópico/seção aparece brevemente. Use quando houver mudança clara de assunto.

REGRAS:
- Entre 8-18 cues no total (não exagere, não seja escasso)
- lower_third: duração entre 3.5s e 5s
- keyword_bubble: duração entre 1.5s e 3s
- quote_card: duração entre 4s e 7s
- topic_title: duração entre 2.5s e 4s
- Nunca sobreponha 2 cues do mesmo tipo no mesmo instante
- Para keyword_bubble, prefira palavras com impacto: dados, percentuais, conceitos únicos, marcas mencionadas
- Para quote_card, escolha APENAS as frases mais impactantes (máximo 2 por vídeo)

Responda SOMENTE com JSON válido neste formato exato:
{
  "cues": [
    {
      "type": "intro_bumper",
      "start_s": 0.0,
      "duration_s": 3.5,
      "content": {}
    },
    {
      "type": "lower_third",
      "start_s": 4.0,
      "duration_s": 4.5,
      "content": {
        "name": "Nome do apresentador",
        "title": "Cargo | Empresa"
      }
    }
  ]
}
"""


def analyze(
    words: list[WordTimestamp],
    brand: dict,
    video_duration: float,
) -> dict:
    """Generate graphic cues from transcript + brand identity using Claude."""
    api_key = os.getenv("ANTHROPIC_API_KEY")
    if not api_key:
        print("[brand] No ANTHROPIC_API_KEY — using default cues only")
        return _default_cues(brand, video_duration)

    try:
        return _call_claude(words, brand, video_duration, api_key)
    except Exception as e:
        print(f"[brand] Claude failed ({e}), using default cues")
        return _default_cues(brand, video_duration)


def _call_claude(
    words: list[WordTimestamp],
    brand: dict,
    video_duration: float,
    api_key: str,
) -> dict:
    import anthropic

    client = anthropic.Anthropic(api_key=api_key)

    transcript_lines = []
    for w in words:
        transcript_lines.append(f"[{w.start:.1f}s] {w.word}")
    transcript_text = "\n".join(transcript_lines)

    brand_summary = json.dumps(brand, ensure_ascii=False, indent=2)

    user_content = f"""BRAND CONFIG:
{brand_summary}

DURAÇÃO DO VÍDEO: {video_duration:.1f}s

TRANSCRIPT COM TIMESTAMPS:
{transcript_text}

Gere os graphic cues para este vídeo respeitando a identidade visual da marca acima."""

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=4096,
        system=_SYSTEM_PROMPT,
        messages=[{"role": "user", "content": user_content}],
    )

    raw = message.content[0].text.strip()
    json_match = re.search(r"\{.*\}", raw, re.DOTALL)
    if json_match:
        result = json.loads(json_match.group())
        result["cues"] = _validate_cues(result.get("cues", []), video_duration)
        print(f"[brand] {len(result['cues'])} graphic cues gerados pelo Claude")
        return result

    return _default_cues(brand, video_duration)


def _default_cues(brand: dict, video_duration: float) -> dict:
    """Fallback: basic cues without AI analysis."""
    host = brand.get("host", {})
    company = brand.get("company", "")
    cues = [
        {
            "type": "intro_bumper",
            "start_s": 0.0,
            "duration_s": 3.5,
            "content": {},
        },
    ]
    if host.get("name"):
        cues.append({
            "type": "lower_third",
            "start_s": 4.0,
            "duration_s": 4.5,
            "content": {
                "name": host["name"],
                "title": host.get("title", company),
            },
        })
    if video_duration > 10:
        cues.append({
            "type": "outro_bumper",
            "start_s": max(0, video_duration - 5.0),
            "duration_s": 5.0,
            "content": {},
        })
    return {"cues": cues}


def _validate_cues(cues: list[dict], video_duration: float) -> list[dict]:
    """Clean up and validate cues from Claude."""
    valid = []
    for cue in cues:
        start = float(cue.get("start_s", 0))
        duration = float(cue.get("duration_s", 3))
        if start < 0 or start >= video_duration:
            continue
        end = start + duration
        if end > video_duration:
            duration = video_duration - start
        cue["start_s"] = round(start, 2)
        cue["duration_s"] = round(duration, 2)
        if not cue.get("content"):
            cue["content"] = {}
        valid.append(cue)
    return sorted(valid, key=lambda c: c["start_s"])


def load_brand(brand_path: str | None) -> dict:
    """Load brand.json or return an empty brand config."""
    if not brand_path:
        default = Path.cwd() / "brand.json"
        if default.exists():
            brand_path = str(default)
        else:
            return {}
    with open(brand_path, "r", encoding="utf-8") as f:
        return json.load(f)
