#!/usr/bin/env python3
"""Murmur — 跨平台本地音频转录主入口。

用法：
  python transcribe.py 录音.m4a                       # 用默认配置（首次会问）
  python transcribe.py 录音.m4a --format md           # 单次覆盖输出格式
  python transcribe.py 录音.m4a --format docx
  python transcribe.py 录音.m4a --lang en             # 改语言
  python transcribe.py 录音.m4a --output-dir out      # 改输出目录
  python transcribe.py --set-default md               # 改默认格式
  python transcribe.py --set-default docx
  python transcribe.py --show-config                  # 看当前配置
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
from pathlib import Path

# 让本脚本无论怎么跑都能 import config
sys.path.insert(0, str(Path(__file__).resolve().parent))
import config  # noqa: E402

# ---------- 引擎选择 ----------

def detect_engine() -> tuple[str, list[str]]:
    """根据平台/芯片返回 (引擎名, uvx 命令前缀)。"""
    system = platform.system()
    machine = platform.machine().lower()

    if system == "Darwin" and machine in ("arm64", "aarch64"):
        # Apple Silicon → mlx-whisper（GPU 加速）
        return "mlx-whisper", ["uvx", "--from", "mlx-whisper", "mlx_whisper"]
    # 其他全部走 whisper-ctranslate2（CPU 友好；有 CUDA 时自动用）
    return "whisper-ctranslate2", ["uvx", "whisper-ctranslate2"]


# ---------- 依赖检查 ----------

def check_prereqs() -> None:
    missing = []
    for cmd in ("ffmpeg", "uvx"):
        if shutil.which(cmd) is None:
            missing.append(cmd)
    if missing:
        sys.stderr.write(
            "❌ 缺少依赖：" + ", ".join(missing) + "\n"
            "   请先跑：\n"
            "     macOS:   bash scripts/install-mac.sh\n"
            "     Windows: powershell -ExecutionPolicy Bypass -File scripts\\install-windows.ps1\n"
            "   或参考 docs/install-mac.md / docs/install-windows.md\n"
        )
        sys.exit(2)


# ---------- 音频预处理 ----------

def preprocess_audio(src: Path, dst: Path) -> None:
    """把任意输入音频转成 16kHz 单声道 WAV。这是避免 Whisper 幻觉循环的关键。"""
    print(f"[1/3] 预处理音频：{src.name} → 16kHz 单声道 WAV ...")
    cmd = [
        "ffmpeg",
        "-y",
        "-i", str(src),
        "-ar", "16000",
        "-ac", "1",
        "-c:a", "pcm_s16le",
        str(dst),
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(f"❌ ffmpeg 失败：\n{result.stderr[-1500:]}\n")
        sys.exit(3)
    print(f"      → {dst.name}")


# ---------- 转录 ----------

def run_transcribe(wav: Path, output_dir: Path, language: str, engine: str, prefix: list[str]) -> None:
    """跑 mlx-whisper 或 whisper-ctranslate2，输出到 output_dir。"""
    print(f"[2/3] 转录中（引擎：{engine}）...")
    print("      首次跑会下载约 2.9GB 模型，请耐心等待。")
    print("      国内网络慢可设 HF_ENDPOINT=https://hf-mirror.com 后重跑。")

    if engine == "mlx-whisper":
        cmd = prefix + [
            str(wav),
            "--model", "mlx-community/whisper-large-v3-mlx",
            "--language", language,
            "--task", "transcribe",
            "--condition-on-previous-text", "False",  # 关键：避免幻觉循环
            "--output-format", "all",
            "--output-dir", str(output_dir),
        ]
    else:
        # whisper-ctranslate2 的 CLI 兼容 openai-whisper
        cmd = prefix + [
            str(wav),
            "--model", "large-v3",
            "--language", language,
            "--task", "transcribe",
            "--condition_on_previous_text", "False",  # 注意是下划线
            "--output_format", "all",
            "--output_dir", str(output_dir),
        ]

    # 实时输出
    result = subprocess.run(cmd)
    if result.returncode != 0:
        sys.stderr.write(
            "❌ 转录失败。常见原因：\n"
            "   - HuggingFace 下载失败 → 设 HF_ENDPOINT=https://hf-mirror.com 后重跑\n"
            "   - 显存/内存不足 → 关掉其他大型程序后重试\n"
            "   - 音频格式异常 → 看 docs/troubleshooting.md\n"
        )
        sys.exit(4)
    print("      转录完成 ✅")


# ---------- 输出整理 ----------

def organize_output(wav_stem: str, output_dir: Path) -> tuple[Path, Path]:
    """把 mlx/whisper 的默认输出 rename 成中文名，删多余格式。返回 (txt路径, srt路径)。"""
    print("[3/3] 整理输出文件 ...")

    txt_src = output_dir / f"{wav_stem}.txt"
    srt_src = output_dir / f"{wav_stem}.srt"

    txt_dst = output_dir / "转录原稿.txt"
    srt_dst = output_dir / "字幕.srt"

    if txt_src.exists():
        if txt_dst.exists():
            txt_dst.unlink()
        txt_src.rename(txt_dst)
    if srt_src.exists():
        if srt_dst.exists():
            srt_dst.unlink()
        srt_src.rename(srt_dst)

    # 清理多余格式
    for ext in (".vtt", ".tsv", ".json"):
        p = output_dir / f"{wav_stem}{ext}"
        if p.exists():
            p.unlink()

    return txt_dst, srt_dst


# ---------- 主流程 ----------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Murmur — 跨平台本地音频转录",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("audio", nargs="?", help="音频文件（m4a/mp3/wav/mp4/webm/flac/ogg）")
    parser.add_argument("--format", choices=["md", "docx"], help="本次输出格式（不改默认）")
    parser.add_argument("--lang", default="zh", help="音频语言（默认 zh，参考 Whisper 语言代码）")
    parser.add_argument("--output-dir", default=None, help="输出目录（默认与音频同目录）")
    parser.add_argument("--set-default", choices=["md", "docx"], help="设置永久默认格式后退出")
    parser.add_argument("--mirror", choices=["cn", "off"], help="设置下载镜像加速（cn=国内镜像，off=关闭）后退出")
    parser.add_argument("--show-config", action="store_true", help="显示当前配置后退出")

    args = parser.parse_args()

    # 配置管理子命令
    if args.show_config:
        cfg = config.load()
        print(f"配置文件：{config.config_path()}")
        print(f"内容：{cfg or '(空)'}")
        return 0

    if args.mirror:
        config.set_mirror(args.mirror)
        if args.mirror == "cn":
            print("✅ 已开启国内镜像加速（清华 PyPI + hf-mirror.com）")
            print("   PyPI:        https://pypi.tuna.tsinghua.edu.cn/simple/")
            print("   HuggingFace: https://hf-mirror.com")
        else:
            print("✅ 已关闭镜像加速，使用默认源")
        return 0

    if args.set_default:
        config.set_default_format(args.set_default)
        print(f"✅ 默认输出格式已改为：{args.set_default}")
        return 0

    # 转录主流程
    if not args.audio:
        parser.print_help()
        sys.stderr.write("\n❌ 缺少音频文件参数\n")
        return 1

    audio_path = Path(args.audio).expanduser().resolve()
    if not audio_path.exists():
        sys.stderr.write(f"❌ 找不到音频文件：{audio_path}\n")
        return 1

    check_prereqs()

    # 镜像加速：如果配置了 cn 镜像，注入环境变量
    if config.apply_mirror_env():
        print("ℹ️  已启用国内镜像加速（关闭：python transcribe.py --mirror off）")

    # 决定输出格式：CLI flag 优先 > config 默认 > 首次询问
    fmt = args.format
    if fmt is None:
        fmt = config.get_default_format()
        if fmt is None:
            fmt = config.prompt_for_default_format()
    print(f"本次输出格式：{fmt}（之后想改默认：python {Path(__file__).name} --set-default md|docx）")

    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else audio_path.parent
    output_dir.mkdir(parents=True, exist_ok=True)

    # 中间 WAV
    wav = output_dir / "audio_16k.wav"
    try:
        preprocess_audio(audio_path, wav)

        engine, prefix = detect_engine()
        run_transcribe(wav, output_dir, args.lang, engine, prefix)

        txt_path, srt_path = organize_output(wav.stem, output_dir)
    finally:
        if wav.exists():
            wav.unlink()

    print()
    print("================================")
    print("✅ 转录完成！")
    print("================================")
    print(f"   原稿：{txt_path}")
    print(f"   字幕：{srt_path}")
    print()
    print("下一步：让 AI 清洗成可读 Markdown")
    print("   1) 把 docs/prompts/clean-transcript.md 的内容连同 转录原稿.txt 一起喂给任意 LLM")
    print("   2) 它会输出 逐字稿-清洗版.md（带说话人 / 修字 / 分章节）")

    if fmt == "docx":
        print()
        print("拿到 逐字稿-清洗版.md 后，再跑：")
        script_dir = Path(__file__).resolve().parent
        print(f"   python {script_dir / 'md2docx.py'} {output_dir / '逐字稿-清洗版.md'}")
        print("→ 自动转出 逐字稿-清洗版.docx")

    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
