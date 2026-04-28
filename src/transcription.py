"""
Transcription module: ElevenLabs Scribe v2 (primary) + faster-whisper (fallback).

Returns a list of WordTimestamp dicts:
  [{"word": str, "start": float, "end": float}, ...]
"""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path
from typing import Any


@dataclass
class WordTimestamp:
    word: str
    start: float
    end: float

    def to_dict(self) -> dict:
        return {"word": self.word, "start": self.start, "end": self.end}


def transcribe(audio_path: str) -> list[WordTimestamp]:
    """Transcribe audio using ElevenLabs if API key present, else WhisperX."""
    api_key = os.getenv("ELEVENLABS_API_KEY")
    if api_key:
        try:
            return _transcribe_elevenlabs(audio_path, api_key)
        except Exception as e:
            print(f"[transcription] ElevenLabs failed ({e}), falling back to WhisperX")
    return _transcribe_whisperx(audio_path)


def _transcribe_elevenlabs(audio_path: str, api_key: str) -> list[WordTimestamp]:
    from elevenlabs import ElevenLabs

    client = ElevenLabs(api_key=api_key)

    with open(audio_path, "rb") as f:
        response = client.speech_to_text.convert(
            file=f,
            model_id="scribe_v2",
            language_code="pt",
            timestamps_granularity="word",
            tag_audio_events=False,
        )

    words: list[WordTimestamp] = []
    for word_data in response.words or []:
        if word_data.type == "word":
            words.append(WordTimestamp(
                word=word_data.text,
                start=float(word_data.start),
                end=float(word_data.end),
            ))
    return words


def _transcribe_whisperx(audio_path: str) -> list[WordTimestamp]:
    from faster_whisper import WhisperModel

    model_size = os.getenv("WHISPER_MODEL", "large-v2")
    device = "cuda" if _has_cuda() else "cpu"
    compute_type = "float16" if device == "cuda" else "int8"

    print(f"[transcription] Loading WhisperX model={model_size} device={device}")
    model = WhisperModel(model_size, device=device, compute_type=compute_type)

    segments, _ = model.transcribe(
        audio_path,
        language="pt",
        word_timestamps=True,
        vad_filter=True,
    )

    words: list[WordTimestamp] = []
    for segment in segments:
        for word in segment.words or []:
            words.append(WordTimestamp(
                word=word.word.strip(),
                start=word.start,
                end=word.end,
            ))
    return words


def _has_cuda() -> bool:
    try:
        import ctypes
        ctypes.cdll.LoadLibrary("libcuda.so.1")
        return True
    except Exception:
        return False


def words_to_full_transcript(words: list[WordTimestamp]) -> str:
    return " ".join(w.word for w in words)


def words_to_timed_segments(
    words: list[WordTimestamp],
    words_per_segment: int = 5,
) -> list[dict]:
    """Group words into caption segments of N words each."""
    segments = []
    for i in range(0, len(words), words_per_segment):
        chunk = words[i : i + words_per_segment]
        if chunk:
            segments.append({
                "words": [w.to_dict() for w in chunk],
                "start": chunk[0].start,
                "end": chunk[-1].end,
                "text": " ".join(w.word for w in chunk),
            })
    return segments
