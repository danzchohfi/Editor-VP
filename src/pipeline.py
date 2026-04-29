"""
Main pipeline: orchestrates all steps from input video to final edited output.
"""
from __future__ import annotations

import json
import os
import tempfile
import time
from pathlib import Path

from src.audio_processor import extract_audio, extract_audio_for_analysis, get_video_duration, get_video_info
from src.transcription import transcribe, words_to_timed_segments
from src.silence_detector import detect_speech_intervals, detect_silence_intervals
from src.error_detector import detect_errors
from src.segment_planner import plan_segments, segments_to_cut_report
from src.video_cutter import cut_video
from src.subtitle_generator import remap_timestamps, generate_srt, generate_word_timing_json
from src.motion_overlay import add_word_highlight_captions
from src.remotion_renderer import render_with_remotion, is_remotion_available
from src.brand_analyzer import analyze as analyze_brand, load_brand
from src.hyperframes_renderer import (
    render_bumper,
    composite_with_bumpers,
    is_hyperframes_available,
)


def run(input_path: str, config: dict, output_dir: str = "output", brand_path: str | None = None) -> dict:
    """
    Full editing pipeline.

    Returns a dict with output file paths and the edit report.
    """
    start_time = time.time()
    Path(output_dir).mkdir(parents=True, exist_ok=True)

    stem = Path(input_path).stem

    print(f"\n{'='*60}")
    print(f"  Editor-VP | Vitamina Publicitária")
    print(f"  Input: {input_path}")
    print(f"{'='*60}\n")

    # --- Load brand identity ---
    brand = load_brand(brand_path)
    if brand:
        print(f"  Brand: {brand.get('company', 'desconhecida')} | {brand.get('primary_color', '')}")

    # --- Step 1: Video info ---
    print("[1/9] Analisando vídeo...")
    info = get_video_info(input_path)
    duration = info["duration"]
    print(f"      Duração: {duration:.1f}s | {info['width']}x{info['height']} @ {info['fps']:.1f}fps")

    with tempfile.TemporaryDirectory() as tmp_dir:
        # --- Step 2: Extract audio ---
        print("[2/9] Extraindo áudio...")
        audio_16k = extract_audio(input_path, tmp_dir)
        audio_hq = extract_audio_for_analysis(input_path, tmp_dir)

        # --- Step 3: Transcription ---
        print("[3/9] Transcrevendo com IA...")
        words = transcribe(audio_16k)
        print(f"      {len(words)} palavras transcritas")
        if not words:
            raise RuntimeError("Transcrição vazia — verifique o áudio do vídeo.")

        # --- Step 4: Silence detection ---
        print("[4/9] Detectando silêncios...")
        silence_cfg = config.get("silence", {})
        speech_intervals = detect_speech_intervals(
            audio_hq,
            threshold_db=silence_cfg.get("threshold_db", -40),
            min_silence_duration_s=silence_cfg.get("min_duration_s", 0.8),
            margin_s=silence_cfg.get("margin_s", 0.15),
        )
        silence_intervals = detect_silence_intervals(
            audio_hq,
            threshold_db=silence_cfg.get("threshold_db", -40),
            min_silence_duration_s=silence_cfg.get("min_duration_s", 0.8),
        )
        print(f"      {len(speech_intervals)} intervalos de fala | {len(silence_intervals)} silêncios")

        # --- Step 5: Error detection ---
        err_cfg = config.get("error_detection", {})
        error_result = {"cuts": [], "summary": "Desativado."}
        if err_cfg.get("enabled", True):
            print("[5/9] Detectando erros de gravação (Claude)...")
            error_result = detect_errors(
                words,
                aggressiveness=err_cfg.get("aggressiveness", "moderate"),
                filler_words=err_cfg.get("filler_words", []),
            )
            print(f"      {len(error_result['cuts'])} erros encontrados")
            if error_result.get("summary"):
                print(f"      → {error_result['summary']}")
        else:
            print("[5/9] Detecção de erros desativada.")

        # --- Step 6: Brand + motion graphics analysis ---
        graphic_cues: list[dict] = []
        if brand:
            print("[6/9] Analisando transcript para motion graphics (Claude)...")
            brand_result = analyze_brand(words, brand, duration)
            graphic_cues = brand_result.get("cues", [])
            print(f"      {len(graphic_cues)} graphic cues gerados")
        else:
            print("[6/9] Sem brand.json — pulando motion graphics de marca.")

        # --- Step 7: Segment planning ---
        print("[7/9] Planejando cortes...")
        segments = plan_segments(
            video_duration=duration,
            speech_intervals=speech_intervals,
            error_cuts=error_result["cuts"],
        )
        report = segments_to_cut_report(duration, segments, error_result["cuts"], silence_intervals)
        print(f"      Original: {report['original_duration_s']}s → Editado: {report['edited_duration_s']}s")
        print(f"      Removido: {report['removed_duration_s']}s ({report['removed_percent']}%)")

        # --- Step 8: Cut video ---
        print("[8/9] Cortando vídeo...")
        out_cfg = config.get("output", {})
        cut_path = os.path.join(tmp_dir, f"{stem}_cut.mp4")
        cut_video(
            input_path,
            segments,
            cut_path,
            video_codec=out_cfg.get("video_codec", "libx264"),
            audio_codec=out_cfg.get("audio_codec", "aac"),
            crf=out_cfg.get("crf", 18),
        )

        # --- Remap timestamps ---
        remapped_words = remap_timestamps(words, segments)

        # --- Generate SRT ---
        sub_cfg = config.get("subtitles", {})
        srt_path = os.path.join(output_dir, f"{stem}_subtitles.srt")
        generate_srt(remapped_words, srt_path, words_per_caption=sub_cfg.get("words_per_line", 5))

        word_timing_path = os.path.join(tmp_dir, f"{stem}_word_timing.json")
        word_timing = words_to_timed_segments(remapped_words, words_per_segment=sub_cfg.get("words_per_line", 5))
        with open(word_timing_path, "w") as f:
            import json as _json
            _json.dump(word_timing, f, ensure_ascii=False)

        # --- Step 8: Motion overlay ---
        final_path = os.path.join(output_dir, f"{stem}_editado.mp4")
        overlay_cfg = {
            "font_size": sub_cfg.get("font_size", 52),
            "highlight_color": sub_cfg.get("highlight_color", "#FFD700"),
            "text_color": sub_cfg.get("text_color", "#FFFFFF"),
            "margin_bottom": sub_cfg.get("margin_bottom", 80),
            "words_per_line": sub_cfg.get("words_per_line", 5),
            "video_codec": out_cfg.get("video_codec", "libx264"),
            "crf": out_cfg.get("crf", 18),
        }

        # Adjust graphic cue timestamps after silence cuts
        edited_duration = report["edited_duration_s"]
        adjusted_cues = _adjust_cues_for_edited_duration(graphic_cues, edited_duration)

        print("[9/9] Renderizando animações e motion graphics...")
        with_captions_path = os.path.join(tmp_dir, f"{stem}_captions.mp4")

        if sub_cfg.get("enabled", True) and sub_cfg.get("style") == "word_highlight":
            if is_remotion_available():
                print("      → Remotion: legendas + motion graphics overlays...")
                try:
                    render_with_remotion(
                        cut_path, word_timing, with_captions_path,
                        overlay_cfg, brand, adjusted_cues,
                    )
                except Exception as e:
                    print(f"      Remotion falhou ({e}), usando fallback ASS...")
                    add_word_highlight_captions(cut_path, word_timing, with_captions_path, overlay_cfg)
            else:
                print("      → ffmpeg ASS (fallback)...")
                add_word_highlight_captions(cut_path, word_timing, with_captions_path, overlay_cfg)
        else:
            import shutil as _shutil
            _shutil.copy2(cut_path, with_captions_path)

        # Render intro/outro bumpers with Hyperframes and stitch
        final_path = os.path.join(output_dir, f"{stem}_editado.mp4")
        if brand and is_hyperframes_available():
            intro_cue = next((c for c in adjusted_cues if c["type"] == "intro_bumper"), None)
            outro_cue = next((c for c in adjusted_cues if c["type"] == "outro_bumper"), None)

            intro_mp4, outro_mp4 = None, None
            if intro_cue:
                intro_mp4 = os.path.join(tmp_dir, "intro.mp4")
                try:
                    render_bumper("intro", brand, intro_mp4, intro_cue["duration_s"])
                except Exception as e:
                    print(f"      Hyperframes intro falhou ({e}), pulando.")
                    intro_mp4 = None
            if outro_cue:
                outro_mp4 = os.path.join(tmp_dir, "outro.mp4")
                try:
                    render_bumper("outro", brand, outro_mp4, outro_cue["duration_s"])
                except Exception as e:
                    print(f"      Hyperframes outro falhou ({e}), pulando.")
                    outro_mp4 = None

            if intro_mp4 or outro_mp4:
                print("      → ffmpeg: costurando intro + vídeo + outro...")
                composite_with_bumpers(with_captions_path, intro_mp4, outro_mp4, final_path)
            else:
                import shutil as _shutil
                _shutil.copy2(with_captions_path, final_path)
        else:
            import shutil as _shutil
            _shutil.copy2(with_captions_path, final_path)

    # --- Save report ---
    report_path = os.path.join(output_dir, f"{stem}_edit_report.json")
    elapsed = time.time() - start_time
    report["elapsed_seconds"] = round(elapsed, 1)
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    print(f"\n{'='*60}")
    print(f"  Concluído em {elapsed:.1f}s")
    print(f"  Vídeo final:  {final_path}")
    print(f"  Legendas:     {srt_path}")
    print(f"  Relatório:    {report_path}")
    print(f"{'='*60}\n")

    return {
        "video": final_path,
        "subtitles": srt_path,
        "report": report_path,
        "stats": report,
    }


def _adjust_cues_for_edited_duration(
    cues: list[dict], edited_duration: float
) -> list[dict]:
    """Clamp cue timestamps to the edited video duration and fix outro position."""
    adjusted = []
    for cue in cues:
        c = dict(cue)
        if c["type"] == "outro_bumper":
            c["start_s"] = max(0, edited_duration - c["duration_s"])
        if c["start_s"] >= edited_duration:
            continue
        c["end_s"] = min(c["start_s"] + c["duration_s"], edited_duration)
        c["duration_s"] = round(c["end_s"] - c["start_s"], 2)
        adjusted.append(c)
    return adjusted


def run_transcribe_only(input_path: str, output_dir: str = "output") -> dict:
    """Transcribe video and generate SRT + word timing JSON, without editing."""
    Path(output_dir).mkdir(parents=True, exist_ok=True)
    stem = Path(input_path).stem

    with tempfile.TemporaryDirectory() as tmp_dir:
        print("[1/2] Extraindo áudio...")
        audio_16k = extract_audio(input_path, tmp_dir)

        print("[2/2] Transcrevendo...")
        words = transcribe(audio_16k)

    srt_path = os.path.join(output_dir, f"{stem}_subtitles.srt")
    generate_srt(words, srt_path)

    timing_path = os.path.join(output_dir, f"{stem}_word_timing.json")
    generate_word_timing_json(words, timing_path)

    print(f"SRT salvo em: {srt_path}")
    print(f"Word timing salvo em: {timing_path}")

    return {"subtitles": srt_path, "word_timing": timing_path}
