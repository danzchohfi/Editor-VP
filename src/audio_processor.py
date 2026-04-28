import os
import subprocess
import tempfile
from pathlib import Path


def extract_audio(video_path: str, output_dir: str | None = None) -> str:
    """Extract audio from video as 16kHz mono WAV for transcription."""
    video_path = Path(video_path)
    if output_dir:
        out_path = Path(output_dir) / f"{video_path.stem}_audio.wav"
    else:
        out_path = video_path.parent / f"{video_path.stem}_audio.wav"

    cmd = [
        "ffmpeg", "-y",
        "-i", str(video_path),
        "-vn",
        "-acodec", "pcm_s16le",
        "-ar", "16000",
        "-ac", "1",
        str(out_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg audio extraction failed:\n{result.stderr}")
    return str(out_path)


def extract_audio_for_analysis(video_path: str, output_dir: str | None = None) -> str:
    """Extract audio as high-quality WAV for amplitude analysis."""
    video_path = Path(video_path)
    if output_dir:
        out_path = Path(output_dir) / f"{video_path.stem}_analysis.wav"
    else:
        out_path = video_path.parent / f"{video_path.stem}_analysis.wav"

    cmd = [
        "ffmpeg", "-y",
        "-i", str(video_path),
        "-vn",
        "-acodec", "pcm_s16le",
        "-ar", "44100",
        "-ac", "2",
        str(out_path),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg audio extraction failed:\n{result.stderr}")
    return str(out_path)


def get_video_duration(video_path: str) -> float:
    """Return video duration in seconds using ffprobe."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_format",
        video_path,
    ]
    import json
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed:\n{result.stderr}")
    data = json.loads(result.stdout)
    return float(data["format"]["duration"])


def get_video_info(video_path: str) -> dict:
    """Return video metadata: duration, fps, width, height."""
    cmd = [
        "ffprobe", "-v", "quiet",
        "-print_format", "json",
        "-show_streams",
        "-show_format",
        video_path,
    ]
    import json
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffprobe failed:\n{result.stderr}")
    data = json.loads(result.stdout)

    video_stream = next(
        (s for s in data.get("streams", []) if s["codec_type"] == "video"), {}
    )
    fps_str = video_stream.get("r_frame_rate", "30/1")
    num, den = fps_str.split("/")
    fps = float(num) / float(den) if float(den) else 30.0

    return {
        "duration": float(data["format"].get("duration", 0)),
        "fps": fps,
        "width": int(video_stream.get("width", 1920)),
        "height": int(video_stream.get("height", 1080)),
        "codec": video_stream.get("codec_name", "h264"),
    }
