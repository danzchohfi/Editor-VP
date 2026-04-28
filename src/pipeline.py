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


def run(input_path: str, config: dict, output_dir: str = "output") -> dict:
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

    # --- Step 1: Video info ---
    print("[1/8] Analisando vídeo...")
    info = get_video_info(input_path)
    duration = info["duration"]
    print(f"      Duração: {duration:.1f}s | {info['width']}x{info['height']} @ {info['fps']:.1f}fps")

    with tempfile.TemporaryDirectory() as tmp_dir:
        # --- Step 2: Extract audio ---
        print("[2/8] Extraindo áudio...")
        audio_16k = extract_audio(input_path, tmp_dir)
        audio_hq = extract_audio_for_analysis(input_path, tmp_dir)

        # --- Step 3: Transcription ---
        print("[3/8] Transcrevendo com IA...")
        words = transcribe(audio_16k)
        print(f"      {len(words)} palavras transcritas")
        if not words:
            raise RuntimeError("Transcrição vazia — verifique o áudio do vídeo.")

        # --- Step 4: Silence detection ---
        print("[4/8] Detectando silêncios...")
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
            print("[5/8] Detectando erros de gravação (Claude)...")
            error_result = detect_errors(
                words,
                aggressiveness=err_cfg.get("aggressiveness", "moderate"),
                filler_words=err_cfg.get("filler_words", []),
            )
            print(f"      {len(error_result['cuts'])} erros encontrados")
            if error_result.get("summary"):
                print(f"      → {error_result['summary']}")
        else:
            print("[5/8] Detecção de erros desativada.")

        # --- Step 6: Segment planning ---
        print("[6/8] Planejando cortes...")
        segments = plan_segments(
            video_duration=duration,
            speech_intervals=speech_intervals,
            error_cuts=error_result["cuts"],
        )
        report = segments_to_cut_report(duration, segments, error_result["cuts"], silence_intervals)
        print(f"      Original: {report['original_duration_s']}s → Editado: {report['edited_duration_s']}s")
        print(f"      Removido: {report['removed_duration_s']}s ({report['removed_percent']}%)")

        # --- Step 7: Cut video ---
        print("[7/8] Cortando vídeo...")
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
        if sub_cfg.get("enabled", True) and sub_cfg.get("style") == "word_highlight":
            print("[8/8] Renderizando legendas animadas...")
            overlay_cfg = {
                "font_size": sub_cfg.get("font_size", 52),
                "highlight_color": sub_cfg.get("highlight_color", "#FFD700"),
                "text_color": sub_cfg.get("text_color", "#FFFFFF"),
                "margin_bottom": sub_cfg.get("margin_bottom", 80),
                "video_codec": out_cfg.get("video_codec", "libx264"),
                "crf": out_cfg.get("crf", 18),
            }
            add_word_highlight_captions(cut_path, word_timing, final_path, overlay_cfg)
        else:
            print("[8/8] Copiando vídeo final (legendas externas)...")
            import shutil
            shutil.copy2(cut_path, final_path)

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
