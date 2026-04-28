"""
Subtitle generator: converts word timestamps to .srt files and timed caption data.

Also handles timestamp remapping after video cuts (since the edited video has
different timestamps than the original).
"""
from __future__ import annotations

import math
from pathlib import Path

from src.transcription import WordTimestamp
from src.segment_planner import Segment


def remap_timestamps(
    words: list[WordTimestamp],
    kept_segments: list[Segment],
) -> list[WordTimestamp]:
    """
    Remap word timestamps from original video time to edited video time.

    Words that fall inside cut regions are discarded.
    Words in kept regions have their timestamps shifted to match the new timeline.
    """
    remapped: list[WordTimestamp] = []
    time_offset = 0.0
    seg_idx = 0

    for word in words:
        word_mid = (word.start + word.end) / 2.0

        while seg_idx < len(kept_segments) and kept_segments[seg_idx].end <= word_mid:
            seg = kept_segments[seg_idx]
            next_start = kept_segments[seg_idx + 1].start if seg_idx + 1 < len(kept_segments) else seg.end
            time_offset += next_start - seg.end
            seg_idx += 1

        if seg_idx >= len(kept_segments):
            break

        seg = kept_segments[seg_idx]
        if seg.start <= word_mid <= seg.end:
            remapped.append(WordTimestamp(
                word=word.word,
                start=max(0.0, word.start - time_offset),
                end=max(0.0, word.end - time_offset),
            ))

    return remapped


def generate_srt(
    words: list[WordTimestamp],
    output_path: str,
    words_per_caption: int = 5,
) -> str:
    """Generate .srt subtitle file from word timestamps."""
    captions = _group_into_captions(words, words_per_caption)
    srt_content = _captions_to_srt(captions)
    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write(srt_content)
    return output_path


def generate_word_timing_json(
    words: list[WordTimestamp],
    output_path: str,
    words_per_line: int = 5,
) -> str:
    """Generate JSON with word-level timing for animated subtitle rendering."""
    import json

    lines = _group_into_captions(words, words_per_line)
    output = []
    for line in lines:
        output.append({
            "start": line["start"],
            "end": line["end"],
            "text": line["text"],
            "words": line["words"],
        })

    Path(output_path).parent.mkdir(parents=True, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, indent=2)
    return output_path


def _group_into_captions(
    words: list[WordTimestamp],
    words_per_caption: int,
) -> list[dict]:
    captions = []
    for i in range(0, len(words), words_per_caption):
        chunk = words[i : i + words_per_caption]
        if not chunk:
            continue
        captions.append({
            "start": chunk[0].start,
            "end": chunk[-1].end,
            "text": " ".join(w.word for w in chunk),
            "words": [{"word": w.word, "start": w.start, "end": w.end} for w in chunk],
        })
    return captions


def _captions_to_srt(captions: list[dict]) -> str:
    lines = []
    for i, cap in enumerate(captions, 1):
        lines.append(str(i))
        lines.append(f"{_format_srt_time(cap['start'])} --> {_format_srt_time(cap['end'])}")
        lines.append(cap["text"])
        lines.append("")
    return "\n".join(lines)


def _format_srt_time(seconds: float) -> str:
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    millis = int((seconds % 1) * 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d},{millis:03d}"
