"""
Remotion renderer bridge: calls Remotion (React/Node.js) from Python to render
animated word-by-word captions onto the edited video.

Falls back to ASS subtitle method if Node.js / npm is not available.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

_REMOTION_DIR = Path(__file__).parent.parent / "remotion"


def is_remotion_available() -> bool:
    """Check if Node.js and npm are available."""
    return shutil.which("node") is not None and shutil.which("npm") is not None


def ensure_remotion_installed() -> bool:
    """Install Remotion npm packages if not already installed."""
    node_modules = _REMOTION_DIR / "node_modules"
    if node_modules.exists():
        return True

    print("[remotion] Installing npm packages (first run only)...")
    result = subprocess.run(
        ["npm", "install"],
        cwd=str(_REMOTION_DIR),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        print(f"[remotion] npm install failed:\n{result.stderr}")
        return False
    print("[remotion] npm packages installed.")
    return True


def render_with_remotion(
    video_path: str,
    word_timing: list[dict],
    output_path: str,
    config: dict | None = None,
) -> str:
    """
    Render animated captions using Remotion.

    word_timing: list of caption segments from subtitle_generator
    Returns output_path on success, raises RuntimeError on failure.
    """
    if not is_remotion_available():
        raise RuntimeError("Node.js not found — cannot use Remotion renderer.")

    if not ensure_remotion_installed():
        raise RuntimeError("Failed to install Remotion npm packages.")

    cfg = _merge_config(config)

    import ffmpeg as _ffmpeg
    video_info = _get_video_info(video_path)
    duration_s = video_info["duration"]
    fps = video_info["fps"]
    width = video_info["width"]
    height = video_info["height"]
    duration_frames = max(1, int(duration_s * fps))

    video_abs = str(Path(video_path).resolve())

    props = {
        "videoSrc": video_abs,
        "wordTiming": word_timing,
        "durationInFrames": duration_frames,
        "fps": fps,
        "width": width,
        "height": height,
        "highlightColor": cfg["highlight_color"],
        "textColor": cfg["text_color"],
        "fontSize": cfg["font_size"],
        "wordsPerLine": cfg.get("words_per_line", 5),
        "marginBottom": cfg["margin_bottom"],
    }

    props_json = json.dumps(props)

    output_abs = str(Path(output_path).resolve())
    os.makedirs(os.path.dirname(output_abs) or ".", exist_ok=True)

    cmd = [
        "npx", "remotion", "render",
        "src/index.ts",
        "CaptionedVideo",
        output_abs,
        "--props", props_json,
        "--frames", f"0-{duration_frames - 1}",
        "--overwrite",
        "--log", "error",
    ]

    print(f"[remotion] Rendering {duration_frames} frames at {fps}fps...")
    result = subprocess.run(
        cmd,
        cwd=str(_REMOTION_DIR),
        capture_output=True,
        text=True,
        timeout=3600,
    )

    if result.returncode != 0:
        raise RuntimeError(
            f"Remotion render failed:\n{result.stdout}\n{result.stderr}"
        )

    print(f"[remotion] Render complete → {output_path}")
    return output_path


def _get_video_info(video_path: str) -> dict:
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_streams",
        "-show_format",
        video_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        return {"duration": 60.0, "fps": 30.0, "width": 1920, "height": 1080}

    data = json.loads(result.stdout)
    video_stream = next(
        (s for s in data.get("streams", []) if s["codec_type"] == "video"), {}
    )
    fps_str = video_stream.get("r_frame_rate", "30/1")
    num, den = fps_str.split("/")
    fps = float(num) / float(den) if float(den) else 30.0

    return {
        "duration": float(data["format"].get("duration", 60.0)),
        "fps": fps,
        "width": int(video_stream.get("width", 1920)),
        "height": int(video_stream.get("height", 1080)),
    }


def _merge_config(config: dict | None) -> dict:
    defaults = {
        "font_size": 52,
        "highlight_color": "#FFD700",
        "text_color": "#FFFFFF",
        "margin_bottom": 80,
        "words_per_line": 5,
    }
    if config:
        defaults.update(config)
    return defaults
