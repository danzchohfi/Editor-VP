"""
Hyperframes renderer bridge: renders intro/outro bumper scenes (HTML/CSS/GSAP)
to MP4 using the Hyperframes CLI from HeyGen.

Hyperframes is installed on-demand via npx. No API key required — open source.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

_HYPERFRAMES_DIR = Path(__file__).parent.parent / "hyperframes"


def is_hyperframes_available() -> bool:
    return shutil.which("node") is not None


def render_bumper(
    scene: str,
    brand: dict,
    output_path: str,
    duration_s: float = 3.5,
) -> str:
    """
    Render an intro or outro bumper scene using Hyperframes.

    scene: "intro" | "outro"
    brand: brand config dict
    output_path: where to write the MP4
    Returns output_path on success, raises RuntimeError on failure.
    """
    if not is_hyperframes_available():
        raise RuntimeError("Node.js not found — cannot use Hyperframes renderer.")

    scene_file = _HYPERFRAMES_DIR / "scenes" / f"{scene}.html"
    if not scene_file.exists():
        raise RuntimeError(f"Hyperframes scene not found: {scene_file}")

    # Inject brand data into a temp copy of the HTML
    with open(scene_file, "r", encoding="utf-8") as f:
        html = f.read()

    brand_script = f"\n<script>window.__BRAND__ = {json.dumps(brand, ensure_ascii=False)};</script>\n"
    html = html.replace("</head>", brand_script + "</head>", 1)

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".html", dir=_HYPERFRAMES_DIR / "scenes",
        delete=False, encoding="utf-8"
    ) as tmp:
        tmp.write(html)
        tmp_path = tmp.name

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)

    try:
        cmd = [
            "npx", "--yes", "hyperframes", "render",
            tmp_path,
            "--output", os.path.abspath(output_path),
            "--non-interactive",
        ]
        print(f"[hyperframes] Rendering {scene} bumper...")
        result = subprocess.run(
            cmd,
            cwd=str(_HYPERFRAMES_DIR),
            capture_output=True,
            text=True,
            timeout=300,
        )
        if result.returncode != 0:
            raise RuntimeError(
                f"Hyperframes render failed:\n{result.stdout}\n{result.stderr}"
            )
        print(f"[hyperframes] {scene} bumper → {output_path}")
        return output_path
    finally:
        Path(tmp_path).unlink(missing_ok=True)


def composite_with_bumpers(
    main_video: str,
    intro_path: str | None,
    outro_path: str | None,
    output_path: str,
) -> str:
    """
    Use ffmpeg to concatenate: intro (opt) + main video + outro (opt).
    """
    parts = []
    if intro_path and Path(intro_path).exists():
        parts.append(intro_path)
    parts.append(main_video)
    if outro_path and Path(outro_path).exists():
        parts.append(outro_path)

    if len(parts) == 1:
        shutil.copy2(main_video, output_path)
        return output_path

    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False, encoding="utf-8"
    ) as f:
        for p in parts:
            f.write(f"file '{os.path.abspath(p)}'\n")
        concat_list = f.name

    try:
        cmd = [
            "ffmpeg", "-y",
            "-f", "concat", "-safe", "0",
            "-i", concat_list,
            "-c", "copy",
            output_path,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"ffmpeg composite failed:\n{result.stderr}")
    finally:
        Path(concat_list).unlink(missing_ok=True)

    return output_path
