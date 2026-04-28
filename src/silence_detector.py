"""
Silence detector: finds silent intervals in audio using pydub amplitude analysis.

Returns list of (start_s, end_s) tuples for silent periods.
"""
from __future__ import annotations

from pydub import AudioSegment
from pydub.silence import detect_nonsilent


def detect_silence_intervals(
    audio_path: str,
    threshold_db: float = -40.0,
    min_silence_duration_s: float = 0.8,
) -> list[tuple[float, float]]:
    """Return list of (start_s, end_s) for silent regions in the audio."""
    audio = AudioSegment.from_file(audio_path)

    min_silence_ms = int(min_silence_duration_s * 1000)
    silence_thresh = audio.dBFS + threshold_db if threshold_db > 0 else threshold_db

    nonsilent = detect_nonsilent(
        audio,
        min_silence_len=min_silence_ms,
        silence_thresh=silence_thresh,
    )

    silent_intervals: list[tuple[float, float]] = []

    if not nonsilent:
        return [(0.0, len(audio) / 1000.0)]

    if nonsilent[0][0] > 0:
        silent_intervals.append((0.0, nonsilent[0][0] / 1000.0))

    for i in range(len(nonsilent) - 1):
        gap_start = nonsilent[i][1] / 1000.0
        gap_end = nonsilent[i + 1][0] / 1000.0
        if gap_end - gap_start >= min_silence_duration_s:
            silent_intervals.append((gap_start, gap_end))

    audio_duration = len(audio) / 1000.0
    if nonsilent[-1][1] / 1000.0 < audio_duration:
        silent_intervals.append((nonsilent[-1][1] / 1000.0, audio_duration))

    return silent_intervals


def detect_speech_intervals(
    audio_path: str,
    threshold_db: float = -40.0,
    min_silence_duration_s: float = 0.8,
    margin_s: float = 0.15,
) -> list[tuple[float, float]]:
    """Return list of (start_s, end_s) speech intervals, with margin padding removed."""
    audio = AudioSegment.from_file(audio_path)
    audio_duration = len(audio) / 1000.0

    min_silence_ms = int(min_silence_duration_s * 1000)
    silence_thresh = audio.dBFS + threshold_db if threshold_db > 0 else threshold_db

    nonsilent = detect_nonsilent(
        audio,
        min_silence_len=min_silence_ms,
        silence_thresh=silence_thresh,
    )

    speech_intervals: list[tuple[float, float]] = []
    for start_ms, end_ms in nonsilent:
        start_s = max(0.0, start_ms / 1000.0 - margin_s)
        end_s = min(audio_duration, end_ms / 1000.0 + margin_s)
        speech_intervals.append((start_s, end_s))

    return _merge_overlapping(speech_intervals)


def _merge_overlapping(
    intervals: list[tuple[float, float]],
) -> list[tuple[float, float]]:
    """Merge intervals that overlap or touch."""
    if not intervals:
        return []
    sorted_ivs = sorted(intervals, key=lambda x: x[0])
    merged = [sorted_ivs[0]]
    for start, end in sorted_ivs[1:]:
        if start <= merged[-1][1]:
            merged[-1] = (merged[-1][0], max(merged[-1][1], end))
        else:
            merged.append((start, end))
    return merged
