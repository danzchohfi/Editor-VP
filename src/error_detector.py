"""
Error detector: uses Claude API to analyze transcript and identify recording mistakes.

Returns list of ErrorSegment dicts marking time ranges to cut.
"""
from __future__ import annotations

import json
import os
import re
from typing import Any

from src.transcription import WordTimestamp


_SYSTEM_PROMPT = """Você é um editor de vídeo/podcast especialista. Analise o transcript a seguir e identifique todos os trechos que devem ser CORTADOS na edição.

Corte os seguintes tipos de erros:
1. Gagueiras e repetições de palavras (ex: "e e e então", "eu eu queria")
2. Recomeços de frase (ex: "então, quando — então quando eu fui")
3. Palavras de preenchimento em excesso (uh, um, né, tipo, assim, eh, ahn)
4. Erros de raciocínio com recomeço imediato
5. Pausas com ruído (tosse, barulho, risada involuntária no meio de frase)

NÃO corte:
- Pausas naturais e dramáticas para ênfase
- "né?" usado como pergunta retórica intencional
- Risos intencionais que fazem parte do conteúdo
- Hesitações curtas que soam naturais (1-2 ocorrências por minuto)

Responda APENAS com JSON válido neste formato:
{
  "cuts": [
    {
      "start": 12.4,
      "end": 13.8,
      "reason": "repetição: 'e e então'",
      "severity": "high"
    }
  ],
  "summary": "Encontrados X erros. Descrição geral."
}

severity pode ser: "high" (cortar sempre), "medium" (cortar se agressividade >= moderate), "low" (cortar apenas se agressividade = aggressive)
"""


def detect_errors(
    words: list[WordTimestamp],
    aggressiveness: str = "moderate",
    filler_words: list[str] | None = None,
) -> dict:
    """Analyze transcript with Claude and return cuts + filler word detections."""
    api_key = os.getenv("ANTHROPIC_API_KEY")

    rule_cuts = _detect_filler_words(words, filler_words or [])

    if not api_key:
        print("[error_detector] No ANTHROPIC_API_KEY — using rule-based detection only")
        return _filter_by_aggressiveness({"cuts": rule_cuts, "summary": "Rule-based detection only."}, aggressiveness)

    try:
        ai_cuts = _detect_with_claude(words, api_key)
        all_cuts = _merge_cuts(rule_cuts, ai_cuts.get("cuts", []))
        return _filter_by_aggressiveness(
            {"cuts": all_cuts, "summary": ai_cuts.get("summary", "")},
            aggressiveness,
        )
    except Exception as e:
        print(f"[error_detector] Claude API failed ({e}), using rule-based only")
        return _filter_by_aggressiveness({"cuts": rule_cuts, "summary": "Rule-based detection only."}, aggressiveness)


def _detect_with_claude(words: list[WordTimestamp], api_key: str) -> dict:
    import anthropic

    client = anthropic.Anthropic(api_key=api_key)

    transcript_lines = []
    for w in words:
        transcript_lines.append(f"[{w.start:.2f}s] {w.word}")
    transcript_text = "\n".join(transcript_lines)

    message = client.messages.create(
        model="claude-sonnet-4-6",
        max_tokens=4096,
        system=_SYSTEM_PROMPT,
        messages=[
            {
                "role": "user",
                "content": f"Transcript com timestamps:\n\n{transcript_text}",
            }
        ],
    )

    raw = message.content[0].text.strip()
    json_match = re.search(r"\{.*\}", raw, re.DOTALL)
    if json_match:
        return json.loads(json_match.group())
    return {"cuts": [], "summary": "Parsing error."}


def _detect_filler_words(
    words: list[WordTimestamp],
    filler_words: list[str],
) -> list[dict]:
    """Detect consecutive repeated words and filler words via rules."""
    cuts: list[dict] = []
    filler_set = {w.lower() for w in filler_words}

    for i, word in enumerate(words):
        clean = re.sub(r"[^\w]", "", word.word.lower())
        if clean in filler_set:
            cuts.append({
                "start": word.start,
                "end": word.end,
                "reason": f"filler word: '{word.word}'",
                "severity": "medium",
            })
        if i > 0:
            prev_clean = re.sub(r"[^\w]", "", words[i - 1].word.lower())
            if clean == prev_clean and clean:
                cuts.append({
                    "start": words[i - 1].start,
                    "end": word.end,
                    "reason": f"word repetition: '{word.word}'",
                    "severity": "high",
                })

    return cuts


def _merge_cuts(cuts_a: list[dict], cuts_b: list[dict]) -> list[dict]:
    seen: set[tuple] = set()
    merged = []
    for cut in cuts_a + cuts_b:
        key = (round(cut["start"], 1), round(cut["end"], 1))
        if key not in seen:
            seen.add(key)
            merged.append(cut)
    return sorted(merged, key=lambda x: x["start"])


def _filter_by_aggressiveness(result: dict, aggressiveness: str) -> dict:
    severity_map = {"conservative": ["high"], "moderate": ["high", "medium"], "aggressive": ["high", "medium", "low"]}
    allowed = set(severity_map.get(aggressiveness, ["high", "medium"]))
    result["cuts"] = [c for c in result["cuts"] if c.get("severity", "high") in allowed]
    return result
