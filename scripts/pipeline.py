"""Audio preprocessing, engine execution, and output organization for Murmur."""

from __future__ import annotations

import platform
import shutil
import subprocess
import sys
from pathlib import Path

from cn_env import CN_HF_ENDPOINT, CN_PYPI_INDEX
from models import model_download_bytes_hint, model_download_size_hint, transcribe_failure_hint
from progress import run_subprocess_with_progress


def detect_engine() -> tuple[str, list[str]]:
    system = platform.system()
    machine = platform.machine().lower()
    if system == "Darwin" and machine in ("arm64", "aarch64"):
        return "mlx-whisper", ["uvx", "--from", "mlx-whisper", "mlx_whisper"]
    return "whisper-ctranslate2", ["uvx", "whisper-ctranslate2"]


def check_prereqs() -> None:
    missing = [cmd for cmd in ("ffmpeg", "uvx") if shutil.which(cmd) is None]
    if missing:
        sys.stderr.write(
            "❌ 缺少依赖：" + ", ".join(missing) + "\n"
            "   请先跑：\n"
            "     macOS:   bash scripts/install-mac.sh\n"
            "     Windows: powershell -ExecutionPolicy Bypass -File scripts\\install-windows.ps1\n"
            "   或参考 docs/install-mac.md / docs/install-windows.md\n"
        )
        sys.exit(2)


def preprocess_audio(src: Path, dst: Path) -> None:
    print(f"[1/3] 预处理音频：{src.name} → 16kHz 单声道 WAV ...")
    cmd = ["ffmpeg", "-y", "-i", str(src), "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(dst)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(f"❌ ffmpeg 失败：\n{result.stderr[-1500:]}\n")
        sys.exit(3)
    print(f"      → {dst.name}")


def run_transcribe(wav: Path, output_dir: Path, language: str, engine: str, prefix: list[str], model: str, env: dict[str, str]) -> None:
    print(f"[2/3] 转录中（引擎：{engine}，模型：{model}）...")
    print(f"      首次跑会下载{model_download_size_hint(model)}模型，请耐心等待。")
    print("      下载与推理过程中会持续打印进度（📥 下载 / ⏳ 推理），无需另开终端查询。")
    if env.get("HF_ENDPOINT") == CN_HF_ENDPOINT:
        print(f"      已启用 HuggingFace 镜像：{CN_HF_ENDPOINT}")
    if env.get("UV_INDEX_URL") == CN_PYPI_INDEX:
        print(f"      已启用 PyPI 镜像（uv）：{CN_PYPI_INDEX}")
    if not env.get("HF_ENDPOINT") and not env.get("UV_INDEX_URL"):
        print("      国内网络慢可加 --cn 启用 HuggingFace / PyPI 镜像。")

    if engine == "mlx-whisper":
        cmd = prefix + [
            str(wav), "--model", model, "--language", language, "--task", "transcribe",
            "--condition-on-previous-text", "False", "--output-format", "all", "--output-dir", str(output_dir),
        ]
    else:
        cmd = prefix + [
            str(wav), "--model", model, "--language", language, "--task", "transcribe",
            "--condition_on_previous_text", "False", "--output_format", "all", "--output_dir", str(output_dir),
        ]

    returncode, output_tail = run_subprocess_with_progress(cmd, env, model_download_bytes_hint(model))
    if returncode != 0:
        sys.stderr.write(transcribe_failure_hint(model, output_tail))
        sys.exit(4)
    print("      转录完成 ✅")


def organize_output(wav_stem: str, output_dir: Path) -> tuple[Path, Path]:
    print("[3/3] 整理输出文件 ...")
    txt_src = output_dir / f"{wav_stem}.txt"
    srt_src = output_dir / f"{wav_stem}.srt"
    txt_dst = output_dir / "转录原稿.txt"
    srt_dst = output_dir / "字幕.srt"
    if not txt_src.exists() and not srt_src.exists():
        actual = sorted(p.name for p in output_dir.iterdir()) if output_dir.exists() else []
        raise RuntimeError(
            f"转录子进程退出码 0，但找不到预期输出：{txt_src.name} / {srt_src.name}\n"
            f"   输出目录实际内容：{actual}\n"
            "   常见原因：mlx-whisper / whisper-ctranslate2 把文件写到了别的位置；"
            "请用 --output-dir 显式指定，或检查脚本日志。"
        )
    if txt_src.exists():
        if txt_dst.exists():
            txt_dst.unlink()
        txt_src.rename(txt_dst)
    else:
        print(f"      ⚠️  缺少 {txt_src.name}（只产出了 srt？）")
    if srt_src.exists():
        if srt_dst.exists():
            srt_dst.unlink()
        srt_src.rename(srt_dst)
    else:
        print(f"      ⚠️  缺少 {srt_src.name}（只产出了 txt？）")
    for ext in (".vtt", ".tsv", ".json"):
        p = output_dir / f"{wav_stem}{ext}"
        if p.exists():
            p.unlink()
    return txt_dst, srt_dst
