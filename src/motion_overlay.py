"""
Motion overlay: renders word-by-word highlight captions onto video.

Implements the modern podcast caption style (Flow Podcast / Lex Fridman):
- 5 words shown per line
- Current word has a colored highlight background
- Smooth fade-in per caption line
- Rendered using Pillow + moviepy
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path
from typing import Any

import numpy as np
from PIL import Image, ImageDraw, ImageFont


_FONT_FALLBACKS = [
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
    "/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf",
    "/usr/share/fonts/truetype/freefont/FreeSansBold.ttf",
    "/System/Library/Fonts/Helvetica.ttc",
    "/Library/Fonts/Arial Bold.ttf",
    "C:/Windows/Fonts/arialbd.ttf",
]


def add_word_highlight_captions(
    video_path: str,
    word_timing: list[dict],
    output_path: str,
    config: dict | None = None,
) -> str:
    """
    Burn word-by-word highlight captions into video.

    word_timing: list of caption segments from subtitle_generator.generate_word_timing_json
    Each segment: {"start": float, "end": float, "text": str, "words": [{"word", "start", "end"}]}
    """
    cfg = _merge_config(config)
    font = _load_font(cfg["font_size"])

    video_info = _get_video_info(video_path)
    width, height = video_info["width"], video_info["height"]

    with tempfile.TemporaryDirectory() as tmp_dir:
        filter_script = _build_drawtext_filter(word_timing, cfg, width, height, font, tmp_dir)
        _apply_filter(video_path, filter_script, output_path, cfg)

    return output_path


def _build_drawtext_filter(
    word_timing: list[dict],
    cfg: dict,
    width: int,
    height: int,
    font: ImageFont.FreeTypeFont,
    tmp_dir: str,
) -> str:
    """Build ffmpeg filter_complex for word-by-word highlights using subtitle overlay."""
    ass_path = os.path.join(tmp_dir, "captions.ass")
    _generate_ass_subtitles(word_timing, cfg, width, height, ass_path)
    return ass_path


def _generate_ass_subtitles(
    word_timing: list[dict],
    cfg: dict,
    width: int,
    height: int,
    output_path: str,
) -> None:
    """Generate ASS subtitle file with word highlighting via karaoke tags."""
    font_size = cfg["font_size"]
    highlight_color = _hex_to_ass_color(cfg["highlight_color"])
    text_color = _hex_to_ass_color(cfg["text_color"])
    margin_v = cfg["margin_bottom"]

    lines = []
    lines.append("[Script Info]")
    lines.append("ScriptType: v4.00+")
    lines.append(f"PlayResX: {width}")
    lines.append(f"PlayResY: {height}")
    lines.append("WrapStyle: 0")
    lines.append("")
    lines.append("[V4+ Styles]")
    lines.append(
        "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, "
        "OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, "
        "ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, "
        "Alignment, MarginL, MarginR, MarginV, Encoding"
    )
    lines.append(
        f"Style: Default,Arial,{font_size},{text_color},&H00FFFFFF,&H00000000,"
        f"&H80000000,-1,0,0,0,100,100,0,0,1,2,1,2,10,10,{margin_v},1"
    )
    lines.append("")
    lines.append("[Events]")
    lines.append("Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text")
    lines.append("")

    for segment in word_timing:
        seg_start = segment["start"]
        seg_end = segment["end"]
        words = segment["words"]

        for w_idx, word_info in enumerate(words):
            w_start = word_info["start"]
            w_end = word_info["end"]
            w_dur_cs = max(1, int((w_end - w_start) * 100))

            text_parts = []
            for i, w in enumerate(words):
                word_text = w["word"].replace("{", "\\{").replace("}", "\\}")
                if i < w_idx:
                    text_parts.append(f"{{\\c{text_color}}}{word_text}")
                elif i == w_idx:
                    text_parts.append(
                        f"{{\\c{highlight_color}\\3c&H000000&\\bord3}}{word_text}"
                        f"{{\\c{text_color}\\3c&H000000&\\bord2}}"
                    )
                else:
                    text_parts.append(f"{{\\c{text_color}}}{word_text}")
            full_text = " ".join(text_parts)

            start_str = _format_ass_time(w_start)
            end_str = _format_ass_time(w_end if w_idx < len(words) - 1 else seg_end)
            lines.append(
                f"Dialogue: 0,{start_str},{end_str},Default,,0,0,0,,{full_text}"
            )

    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))


def _apply_filter(
    video_path: str,
    ass_path: str,
    output_path: str,
    cfg: dict,
) -> None:
    """Burn ASS subtitles into video with ffmpeg."""
    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)

    safe_ass_path = ass_path.replace("\\", "/").replace(":", "\\:")

    cmd = [
        "ffmpeg", "-y",
        "-i", video_path,
        "-vf", f"ass={safe_ass_path}",
        "-c:v", cfg.get("video_codec", "libx264"),
        "-crf", str(cfg.get("crf", 18)),
        "-preset", "fast",
        "-c:a", "copy",
        output_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg subtitle burn failed:\n{result.stderr}")


def _get_video_info(video_path: str) -> dict:
    import json
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_streams",
        video_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return {"width": 1920, "height": 1080}
    data = json.loads(result.stdout)
    video_stream = next(
        (s for s in data.get("streams", []) if s["codec_type"] == "video"), {}
    )
    return {
        "width": int(video_stream.get("width", 1920)),
        "height": int(video_stream.get("height", 1080)),
    }


def _load_font(font_size: int) -> ImageFont.FreeTypeFont | None:
    for path in _FONT_FALLBACKS:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, font_size)
            except Exception:
                continue
    return None


def _hex_to_ass_color(hex_color: str) -> str:
    """Convert #RRGGBB to ASS &H00BBGGRR format."""
    hex_color = hex_color.lstrip("#")
    r = int(hex_color[0:2], 16)
    g = int(hex_color[2:4], 16)
    b = int(hex_color[4:6], 16)
    return f"&H00{b:02X}{g:02X}{r:02X}"


def _format_ass_time(seconds: float) -> str:
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    secs = int(seconds % 60)
    centisecs = int((seconds % 1) * 100)
    return f"{hours}:{minutes:02d}:{secs:02d}.{centisecs:02d}"


def _merge_config(config: dict | None) -> dict:
    defaults = {
        "font_size": 52,
        "highlight_color": "#FFD700",
        "text_color": "#FFFFFF",
        "margin_bottom": 80,
        "video_codec": "libx264",
        "crf": 18,
    }
    if config:
        defaults.update(config)
    return defaults
