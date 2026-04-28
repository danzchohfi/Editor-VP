"""
Editor-VP CLI — Vitamina Publicitária
"""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path

import click
from dotenv import load_dotenv

load_dotenv()

SUPPORTED_FORMATS = (".mp4", ".mov", ".mkv", ".avi", ".webm")


@click.group()
@click.version_option("1.0.0", prog_name="editor-vp")
def cli():
    """Editor-VP: AI video editor para podcasts da Vitamina Publicitária."""
    pass


@cli.command()
@click.option("--input", "-i", "input_path", required=True, type=click.Path(exists=True), help="Arquivo de vídeo de entrada")
@click.option("--config", "-c", "config_path", default=None, type=click.Path(), help="Arquivo de configuração JSON (padrão: config/default.json)")
@click.option("--output", "-o", "output_dir", default="output", show_default=True, help="Diretório de saída")
@click.option("--no-subtitles", is_flag=True, default=False, help="Pular geração de legendas animadas")
@click.option("--no-error-detection", is_flag=True, default=False, help="Pular detecção de erros com Claude")
@click.option("--aggressiveness", type=click.Choice(["conservative", "moderate", "aggressive"]), default=None, help="Nível de agressividade dos cortes")
def edit(input_path, config_path, output_dir, no_subtitles, no_error_detection, aggressiveness):
    """Editar vídeo: cortar silêncios, detectar erros, adicionar legendas animadas."""
    _check_input(input_path)
    config = _load_config(config_path)

    if no_subtitles:
        config.setdefault("subtitles", {})["enabled"] = False
    if no_error_detection:
        config.setdefault("error_detection", {})["enabled"] = False
    if aggressiveness:
        config.setdefault("error_detection", {})["aggressiveness"] = aggressiveness

    from src.pipeline import run
    try:
        result = run(input_path, config, output_dir)
        click.echo(click.style("\nEdição concluída com sucesso!", fg="green", bold=True))
        _print_results(result)
    except Exception as e:
        click.echo(click.style(f"\nErro: {e}", fg="red"), err=True)
        sys.exit(1)


@cli.command()
@click.option("--input", "-i", "input_path", required=True, type=click.Path(exists=True), help="Arquivo de vídeo de entrada")
@click.option("--output", "-o", "output_dir", default="output", show_default=True, help="Diretório de saída")
def transcribe(input_path, output_dir):
    """Somente transcrever vídeo e gerar arquivo .srt (sem cortes)."""
    _check_input(input_path)
    from src.pipeline import run_transcribe_only
    try:
        result = run_transcribe_only(input_path, output_dir)
        click.echo(click.style("\nTranscrição concluída!", fg="green", bold=True))
        _print_results(result)
    except Exception as e:
        click.echo(click.style(f"\nErro: {e}", fg="red"), err=True)
        sys.exit(1)


@cli.command()
@click.option("--input", "-i", "input_path", required=True, type=click.Path(exists=True), help="Arquivo de vídeo de entrada")
@click.option("--config", "-c", "config_path", default=None, type=click.Path(), help="Arquivo de configuração JSON")
@click.option("--output", "-o", "output_dir", default="output", show_default=True)
def cut_silence(input_path, config_path, output_dir):
    """Cortar apenas os silêncios, sem detecção de erros nem legendas."""
    _check_input(input_path)
    config = _load_config(config_path)
    config.setdefault("error_detection", {})["enabled"] = False
    config.setdefault("subtitles", {})["enabled"] = False

    from src.pipeline import run
    try:
        result = run(input_path, config, output_dir)
        click.echo(click.style("\nCorte de silêncios concluído!", fg="green", bold=True))
        _print_results(result)
    except Exception as e:
        click.echo(click.style(f"\nErro: {e}", fg="red"), err=True)
        sys.exit(1)


@cli.command()
def check_deps():
    """Verificar dependências instaladas e API keys configuradas."""
    click.echo("Verificando dependências...\n")

    deps = [
        ("ffmpeg", "ffmpeg -version"),
        ("ffprobe", "ffprobe -version"),
    ]
    import subprocess
    for name, cmd in deps:
        try:
            subprocess.run(cmd.split(), capture_output=True, check=True)
            click.echo(click.style(f"  ✓ {name}", fg="green"))
        except Exception:
            click.echo(click.style(f"  ✗ {name} — não encontrado!", fg="red"))

    py_deps = ["elevenlabs", "faster_whisper", "moviepy", "pydub", "anthropic", "PIL", "click", "dotenv"]
    for dep in py_deps:
        try:
            __import__(dep)
            click.echo(click.style(f"  ✓ {dep}", fg="green"))
        except ImportError:
            click.echo(click.style(f"  ✗ {dep} — não instalado (pip install {dep})", fg="yellow"))

    click.echo("\nVariáveis de ambiente:")
    for key in ["ELEVENLABS_API_KEY", "ANTHROPIC_API_KEY", "HF_TOKEN"]:
        val = os.getenv(key)
        if val:
            click.echo(click.style(f"  ✓ {key} = {val[:8]}...", fg="green"))
        else:
            click.echo(click.style(f"  ✗ {key} — não configurada", fg="yellow"))


def _check_input(path: str) -> None:
    ext = Path(path).suffix.lower()
    if ext not in SUPPORTED_FORMATS:
        click.echo(
            click.style(f"Formato não suportado: {ext}. Use: {', '.join(SUPPORTED_FORMATS)}", fg="red"),
            err=True,
        )
        sys.exit(1)


def _load_config(config_path: str | None) -> dict:
    if config_path is None:
        default = Path(__file__).parent.parent / "config" / "default.json"
        config_path = str(default)
    if not Path(config_path).exists():
        return {}
    with open(config_path, "r", encoding="utf-8") as f:
        return json.load(f)


def _print_results(result: dict) -> None:
    click.echo("\nArquivos gerados:")
    for key, path in result.items():
        if key == "stats":
            continue
        if path and Path(path).exists():
            size = Path(path).stat().st_size / (1024 * 1024)
            click.echo(f"  {key:12s} → {path} ({size:.1f} MB)")
    if "stats" in result:
        s = result["stats"]
        if "original_duration_s" in s:
            click.echo(f"\n  Original:  {s['original_duration_s']}s")
            click.echo(f"  Editado:   {s['edited_duration_s']}s")
            click.echo(f"  Removido:  {s['removed_duration_s']}s ({s['removed_percent']}%)")


if __name__ == "__main__":
    cli()
