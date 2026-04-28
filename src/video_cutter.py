"""
Video cutter: cuts video to only the kept segments using ffmpeg concat demuxer.

This approach re-encodes as little as possible and handles arbitrary segments.
"""
from __future__ import annotations

import os
import subprocess
import tempfile
from pathlib import Path

from src.segment_planner import Segment


def cut_video(
    input_path: str,
    segments: list[Segment],
    output_path: str,
    video_codec: str = "libx264",
    audio_codec: str = "aac",
    crf: int = 18,
) -> str:
    """Cut input_path keeping only the given segments, write to output_path."""
    if not segments:
        raise ValueError("No segments to keep — nothing to cut.")

    with tempfile.TemporaryDirectory() as tmp_dir:
        segment_files = _extract_segments(input_path, segments, tmp_dir, video_codec, audio_codec, crf)
        _concat_segments(segment_files, output_path, tmp_dir, video_codec, audio_codec, crf)

    return output_path


def _extract_segments(
    input_path: str,
    segments: list[Segment],
    tmp_dir: str,
    video_codec: str,
    audio_codec: str,
    crf: int,
) -> list[str]:
    """Extract each segment as a separate file."""
    paths = []
    for i, seg in enumerate(segments):
        out_file = os.path.join(tmp_dir, f"seg_{i:04d}.mp4")
        cmd = [
            "ffmpeg", "-y",
            "-ss", str(seg.start),
            "-to", str(seg.end),
            "-i", input_path,
            "-c:v", video_codec,
            "-crf", str(crf),
            "-preset", "fast",
            "-c:a", audio_codec,
            "-b:a", "192k",
            "-avoid_negative_ts", "make_zero",
            out_file,
        ]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"ffmpeg segment extraction failed for seg {i}:\n{result.stderr}")
        paths.append(out_file)
    return paths


def _concat_segments(
    segment_files: list[str],
    output_path: str,
    tmp_dir: str,
    video_codec: str,
    audio_codec: str,
    crf: int,
) -> None:
    """Concatenate segments using ffmpeg concat demuxer."""
    concat_list = os.path.join(tmp_dir, "concat.txt")
    with open(concat_list, "w") as f:
        for seg_file in segment_files:
            f.write(f"file '{seg_file}'\n")

    os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)

    cmd = [
        "ffmpeg", "-y",
        "-f", "concat",
        "-safe", "0",
        "-i", concat_list,
        "-c", "copy",
        output_path,
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        raise RuntimeError(f"ffmpeg concat failed:\n{result.stderr}")


def cut_video_fast(
    input_path: str,
    segments: list[Segment],
    output_path: str,
) -> str:
    """
    Fast cut using stream copy (no re-encoding). May have slight imprecision
    at cut points due to keyframe alignment. Use for preview/draft mode.
    """
    if not segments:
        raise ValueError("No segments to keep.")

    with tempfile.TemporaryDirectory() as tmp_dir:
        segment_files = []
        for i, seg in enumerate(segments):
            out_file = os.path.join(tmp_dir, f"seg_{i:04d}.mp4")
            cmd = [
                "ffmpeg", "-y",
                "-ss", str(seg.start),
                "-to", str(seg.end),
                "-i", input_path,
                "-c", "copy",
                "-avoid_negative_ts", "make_zero",
                out_file,
            ]
            subprocess.run(cmd, capture_output=True, check=True)
            segment_files.append(out_file)

        concat_list = os.path.join(tmp_dir, "concat.txt")
        with open(concat_list, "w") as f:
            for sf in segment_files:
                f.write(f"file '{sf}'\n")

        os.makedirs(os.path.dirname(output_path) or ".", exist_ok=True)
        cmd = [
            "ffmpeg", "-y",
            "-f", "concat", "-safe", "0",
            "-i", concat_list,
            "-c", "copy",
            output_path,
        ]
        subprocess.run(cmd, capture_output=True, check=True)

    return output_path
