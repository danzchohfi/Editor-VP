"""
Segment planner: combines silence intervals and error cuts into a final
keep-list of (start_s, end_s) segments to include in the edited video.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Segment:
    start: float
    end: float
    reason: str = ""

    @property
    def duration(self) -> float:
        return self.end - self.start

    def to_dict(self) -> dict:
        return {"start": self.start, "end": self.end, "duration": self.duration, "reason": self.reason}


def plan_segments(
    video_duration: float,
    speech_intervals: list[tuple[float, float]],
    error_cuts: list[dict],
    min_segment_duration: float = 0.3,
) -> list[Segment]:
    """
    Build the list of video segments to KEEP.

    speech_intervals: result from silence_detector (already the keep regions)
    error_cuts: list of {start, end, reason} from error_detector
    """
    cut_intervals = [(c["start"], c["end"]) for c in error_cuts]
    segments: list[Segment] = []

    for speech_start, speech_end in speech_intervals:
        sub_segments = _subtract_cuts(speech_start, speech_end, cut_intervals)
        for start, end in sub_segments:
            if end - start >= min_segment_duration:
                segments.append(Segment(start=start, end=end))

    return _merge_adjacent(segments, gap_threshold=0.05)


def _subtract_cuts(
    start: float,
    end: float,
    cuts: list[tuple[float, float]],
) -> list[tuple[float, float]]:
    """Remove cut intervals from a speech interval, returning remaining pieces."""
    remaining = [(start, end)]
    for cut_start, cut_end in cuts:
        new_remaining = []
        for seg_start, seg_end in remaining:
            if cut_end <= seg_start or cut_start >= seg_end:
                new_remaining.append((seg_start, seg_end))
            else:
                if cut_start > seg_start:
                    new_remaining.append((seg_start, cut_start))
                if cut_end < seg_end:
                    new_remaining.append((cut_end, seg_end))
        remaining = new_remaining
    return remaining


def _merge_adjacent(
    segments: list[Segment],
    gap_threshold: float = 0.05,
) -> list[Segment]:
    """Merge segments that are very close together (gap < threshold)."""
    if not segments:
        return []
    sorted_segs = sorted(segments, key=lambda s: s.start)
    merged = [Segment(sorted_segs[0].start, sorted_segs[0].end)]
    for seg in sorted_segs[1:]:
        if seg.start - merged[-1].end <= gap_threshold:
            merged[-1] = Segment(merged[-1].start, max(merged[-1].end, seg.end))
        else:
            merged.append(Segment(seg.start, seg.end))
    return merged


def segments_to_cut_report(
    original_duration: float,
    kept_segments: list[Segment],
    error_cuts: list[dict],
    silence_intervals: list[tuple[float, float]],
) -> dict:
    kept_duration = sum(s.duration for s in kept_segments)
    removed_duration = original_duration - kept_duration

    return {
        "original_duration_s": round(original_duration, 2),
        "edited_duration_s": round(kept_duration, 2),
        "removed_duration_s": round(removed_duration, 2),
        "removed_percent": round((removed_duration / original_duration) * 100, 1) if original_duration else 0,
        "silence_cuts": len(silence_intervals),
        "error_cuts": len(error_cuts),
        "kept_segments": len(kept_segments),
        "segments": [s.to_dict() for s in kept_segments],
        "error_details": error_cuts,
    }
