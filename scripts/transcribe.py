#!/usr/bin/env python3
"""Murmur — 跨平台本地音频转录主入口。

用法：
  python transcribe.py 录音.m4a                       # 用默认配置（首次会问）
  python transcribe.py 录音.m4a --format md           # 单次覆盖输出格式
  python transcribe.py 录音.m4a --format docx
  python transcribe.py 录音.m4a --lang en             # 改语言
  python transcribe.py 录音.m4a --model medium        # 单次换模型（tiny/base/small/medium/large-v3...）
  python transcribe.py 录音.m4a --output-dir out      # 改输出目录
  python transcribe.py 录音.m4a --cn                  # 单次强制启用大陆镜像（HF / PyPI）
  python transcribe.py 录音.m4a --no-cn               # 单次强制禁用大陆镜像
  python transcribe.py --set-default md               # 改默认格式
  python transcribe.py --set-default docx
  python transcribe.py --set-default-model medium     # 改默认模型
  python transcribe.py --set-default-cn on            # 持久启用大陆镜像（每次自动注入）
  python transcribe.py --set-default-cn off           # 持久禁用
  python transcribe.py --set-default-cn auto          # 恢复默认：按时区/语言自动判断
  python transcribe.py --show-config                  # 看当前配置
"""

from __future__ import annotations

import argparse
import os
import platform
import shutil
import subprocess
import sys
import threading
import time
from pathlib import Path

# 让本脚本无论怎么跑都能 import 同目录模块
sys.path.insert(0, str(Path(__file__).resolve().parent))
import config  # noqa: E402
from cn_env import (  # noqa: E402
    CN_HF_ENDPOINT,
    CN_PYPI_INDEX,
    build_cn_env,
    detect_cn,
    resolve_cn_mode,
)


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


# ---------- 模型名解析 ----------

def model_download_size_hint(model: str) -> str:
    """根据模型名给用户一个大致的首次下载体积提示。"""
    m = model.lower()
    if "turbo" in m:
        return "约 1.5GB"
    if "large" in m:
        return "约 2.9GB"
    if "medium" in m:
        return "约 1GB"
    if "small" in m:
        return "约 500MB"
    if "tiny" in m or "base" in m:
        return "约 75–150MB"
    return "视模型而定"


def resolve_model(name: str | None, engine: str) -> str:
    """把用户给的模型名（或 None）按引擎映射成对应实参。

    规则：
      - None → 各引擎的内置 large-v3-turbo 默认
      - 已在 KNOWN_MODELS 里的短名 → 按引擎映射：
          mlx-whisper      → mlx-community/whisper-<name>-mlx
          whisper-ctranslate2 → 原样（large-v3-turbo / medium / ...）
      - 其它字符串 → 原样透传（高级用户用完整 HF repo 名时走这条）
    """
    if not name:
        default = config.DEFAULT_MODEL
        if engine == "mlx-whisper":
            return f"mlx-community/whisper-{default}-mlx"
        return default

    name = name.strip()
    if name in config.KNOWN_MODELS:
        if engine == "mlx-whisper":
            return f"mlx-community/whisper-{name}-mlx"
        return name

    # 透传：用户自己写了完整名（比如 mlx-community/whisper-small-mlx-q4）
    return name


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

def run_transcribe(
    wav: Path,
    output_dir: Path,
    language: str,
    engine: str,
    prefix: list[str],
    model: str,
    env: dict[str, str],
) -> None:
    """跑 mlx-whisper 或 whisper-ctranslate2，输出到 output_dir。"""
    print(f"[2/3] 转录中（引擎：{engine}，模型：{model}）...")
    print(f"      首次跑会下载{model_download_size_hint(model)}模型，请耐心等待。")
    if env.get("HF_ENDPOINT") == CN_HF_ENDPOINT:
        print(f"      已启用 HuggingFace 镜像：{CN_HF_ENDPOINT}")
    if env.get("UV_INDEX_URL") == CN_PYPI_INDEX:
        print(f"      已启用 PyPI 镜像（uv）：{CN_PYPI_INDEX}")
    if not env.get("HF_ENDPOINT") and not env.get("UV_INDEX_URL"):
        print("      国内网络慢可加 --cn 启用 HuggingFace / PyPI 镜像。")

    if engine == "mlx-whisper":
        cmd = prefix + [
            str(wav),
            "--model", model,
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
            "--model", model,
            "--language", language,
            "--task", "transcribe",
            "--condition_on_previous_text", "False",  # 注意是下划线
            "--output_format", "all",
            "--output_dir", str(output_dir),
        ]

    # 心跳线程：每 30 秒打印已用时间，让用户知道推理还在跑
    stop_heartbeat = threading.Event()
    def _heartbeat():
        t0 = time.monotonic()
        while not stop_heartbeat.wait(30):
            elapsed = int(time.monotonic() - t0)
            m, s = divmod(elapsed, 60)
            print(f"      ⏳ 推理中... 已用时 {m}:{s:02d}", flush=True)
    hb = threading.Thread(target=_heartbeat, daemon=True)
    hb.start()

    # 实时输出；env 传给子进程，承载 HF_ENDPOINT / UV_INDEX_URL 等
    result = subprocess.run(cmd, env=env)
    stop_heartbeat.set()
    hb.join(timeout=1)
    if result.returncode != 0:
        sys.stderr.write(
            "❌ 转录失败。常见原因：\n"
            "   - HuggingFace 下载失败 → 加 --cn 启用 hf-mirror.com 镜像后重跑\n"
            "   - uv 拉 mlx-whisper / whisper-ctranslate2 慢 → --cn 会同时启用清华 PyPI 镜像\n"
            "   - 显存/内存不足 → 关掉其他大型程序后重试，或 --model medium 换更小的模型\n"
            "   - 音频格式异常 → 看 docs/troubleshooting.md\n"
        )
        sys.exit(4)
    print("      转录完成 ✅")


# ---------- 输出整理 ----------

def organize_output(wav_stem: str, output_dir: Path) -> tuple[Path, Path]:
    """把 mlx/whisper 的默认输出 rename 成中文名，删多余格式。返回 (txt路径, srt路径)。

    若源文件不存在（说明转录子进程虽 exit 0 但没产文件），抛 RuntimeError，
    避免"转录完成 ✅"的虚假成功。
    """
    print("[3/3] 整理输出文件 ...")

    txt_src = output_dir / f"{wav_stem}.txt"
    srt_src = output_dir / f"{wav_stem}.srt"

    txt_dst = output_dir / "转录原稿.txt"
    srt_dst = output_dir / "字幕.srt"

    if not txt_src.exists() and not srt_src.exists():
        # 列一下实际产物，方便排查
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
    parser.add_argument(
        "--model",
        default=None,
        help=(
            "本次使用的模型（短名 tiny/base/small/medium/large-v2/large-v3/large-v3-turbo，"
            "或完整 HF repo 名）。不传则用 --set-default-model 的值，再不行用内置默认 large-v3-turbo"
        ),
    )
    parser.add_argument("--output-dir", default=None, help="输出目录（默认与音频同目录）")
    parser.add_argument(
        "--cn", dest="cn", action="store_true", default=None,
        help="本次强制启用大陆镜像：给子进程注入 HF_ENDPOINT=hf-mirror.com 和 UV_INDEX_URL=清华 PyPI",
    )
    parser.add_argument(
        "--no-cn", dest="cn", action="store_false",
        help="本次强制禁用大陆镜像（覆盖 cn_mode 配置 / 自动检测）",
    )
    parser.add_argument("--set-default", choices=["md", "docx"], help="设置永久默认格式后退出")
    parser.add_argument("--set-default-model", help="设置永久默认模型后退出（清空：传空串 ''）")
    parser.add_argument(
        "--set-default-cn",
        choices=["on", "off", "auto"],
        help=(
            "设置持久化的大陆镜像偏好后退出。on=每次自动启用 / off=每次禁用 / "
            "auto=按时区/语言自动判断（默认）"
        ),
    )
    parser.add_argument("--show-config", action="store_true", help="显示当前配置后退出")

    args = parser.parse_args()

    # 配置管理子命令
    if args.show_config:
        cfg = config.load()
        cn_mode = config.get_cn_mode()
        print(f"配置文件：{config.config_path()}")
        print(f"内容：{cfg or '(空)'}")
        print()
        print(f"大陆镜像偏好（cn_mode）：{cn_mode}")
        if cn_mode == "auto":
            detected = detect_cn()
            print(f"  └ 当前自动检测结果：{'命中（启用）' if detected else '未命中（禁用）'}")
        elif cn_mode == "on":
            print("  └ 每次转录都会注入 HF_ENDPOINT=hf-mirror.com / 清华 PyPI")
        else:
            print("  └ 每次转录都走官方源；如需单次启用：加 --cn")
        return 0

    if getattr(args, "mirror", None):
        config.set_mirror(args.mirror)
        if args.mirror == "cn":
            print("✅ 已开启国内镜像加速（清华 PyPI + hf-mirror.com）")
            print("   PyPI:        https://pypi.tuna.tsinghua.edu.cn/simple/")
            print("   HuggingFace: https://hf-mirror.com")
        else:
            print("  └ 每次转录都走官方源；如需单次启用：加 --cn")
        return 0

    if args.set_default:
        config.set_default_format(args.set_default)
        print(f"✅ 默认输出格式已改为：{args.set_default}")
        return 0

    if args.set_default_model is not None:
        if args.set_default_model == "":
            cfg = config.load()
            cfg.pop("default_model", None)
            config.save(cfg)
            print(f"✅ 已清除默认模型（恢复使用内置默认 {config.DEFAULT_MODEL}）")
        else:
            config.set_default_model(args.set_default_model)
            print(f"✅ 默认模型已改为：{args.set_default_model}")
        return 0

    if args.set_default_cn:
        config.set_cn_mode(args.set_default_cn)
        print(f"✅ 大陆镜像偏好已改为：{args.set_default_cn}")
        if args.set_default_cn == "on":
            print("   每次转录都会自动注入 HF_ENDPOINT=hf-mirror.com / 清华 PyPI")
        elif args.set_default_cn == "off":
            print("   每次转录都走官方源；如需单次启用：加 --cn")
        else:
            print("   每次转录会按时区/语言自动判断；如需强制：加 --cn 或 --no-cn")
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

    # 决定输出格式：CLI flag 优先 > config 默认 > 首次询问
    fmt = args.format
    if fmt is None:
        fmt = config.get_default_format()
        if fmt is None:
            fmt = config.prompt_for_default_format()
    print(f"本次输出格式：{fmt}（之后想改默认：python {Path(__file__).name} --set-default md|docx）")

    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else audio_path.parent
    output_dir.mkdir(parents=True, exist_ok=True)

    # 决定是否启用大陆镜像：CLI flag > config.cn_mode > 自动检测
    cn_mode, cn_reason = resolve_cn_mode(args.cn)
    if cn_mode:
        print(f"ℹ️  本次启用大陆镜像（{cn_reason}）")
        print("   持久化偏好：python transcribe.py --set-default-cn on|off|auto")
    elif cn_reason.startswith("auto"):
        # auto 模式且未命中：低调提示，让国内用户知道有这个选项
        print(f"ℹ️  本次走官方源（{cn_reason}）；如需启用：--cn 或 --set-default-cn on")

    # 子进程的 env：从当前 env 继承；CN 模式下注入镜像（不覆盖用户已设值）
    child_env = dict(os.environ)
    if cn_mode:
        child_env = build_cn_env(child_env)

    # 决定模型：CLI > config > None（None 在 resolve_model 里走内置默认）
    model_name = args.model or config.get_default_model()

    # 中间 WAV
    wav = output_dir / "audio_16k.wav"
    try:
        preprocess_audio(audio_path, wav)

        engine, prefix = detect_engine()
        resolved_model = resolve_model(model_name, engine)
        run_transcribe(wav, output_dir, args.lang, engine, prefix, resolved_model, child_env)

        try:
            txt_path, srt_path = organize_output(wav.stem, output_dir)
        except RuntimeError as e:
            sys.stderr.write(f"❌ {e}\n")
            return 5
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
