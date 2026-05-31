#!/usr/bin/env python3
"""Murmur — 跨平台本地音频转录主入口。

用法：
  python transcribe.py 录音.m4a                       # 用默认配置（首次需先 --onboarding）
  python transcribe.py 录音.m4a --format md           # 单次覆盖输出格式
  python transcribe.py 录音.m4a --format docx
  python transcribe.py 录音.m4a --lang en             # 改语言
  python transcribe.py 录音.m4a --model medium        # 单次换模型（tiny/base/small/medium/large-v3...）
  python transcribe.py 录音.m4a --model-source modelscope  # 强制从 ModelScope 准备已验证模型
  python transcribe.py 录音.m4a --output-dir out      # 改输出目录
  python transcribe.py 录音.m4a --cn                  # 单次强制启用大陆模型/镜像策略（ModelScope / HF / PyPI）
  python transcribe.py 录音.m4a --no-cn               # 单次强制禁用大陆模型/镜像策略
  python transcribe.py --set-default md               # 改默认格式
  python transcribe.py --set-default docx
  python transcribe.py --set-default-model medium     # 改默认模型
  python transcribe.py --set-default-cn on            # 持久启用大陆模型/镜像策略
  python transcribe.py --set-default-cn off           # 持久禁用
  python transcribe.py --set-default-cn auto          # 恢复默认：按时区/语言自动判断
  python transcribe.py --show-config                  # 看当前配置
  python transcribe.py --onboarding                   # 输出首次 onboarding 候选 JSON（agent 候选框）
  python transcribe.py --init-defaults --format md --set-default-model large-v3-turbo
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

# 让本脚本无论怎么跑都能 import 同目录模块
sys.path.insert(0, str(Path(__file__).resolve().parent))
import config  # noqa: E402
from cn_env import build_cn_env, detect_cn, resolve_cn_mode  # noqa: E402
from model_sources import maybe_prepare_model_source  # noqa: E402
from models import resolve_model  # noqa: E402
from pipeline import (  # noqa: E402
    check_prereqs,
    detect_engine,
    organize_output,
    preprocess_audio,
    run_transcribe,
)


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
        "--model-source",
        choices=["auto", "hf", "modelscope"],
        default="auto",
        help=(
            "模型下载来源：auto=大陆模式优先 ModelScope 已验证映射，否则原 HuggingFace/引擎默认；"
            "hf=强制原模型源；modelscope=强制 ModelScope（无映射则报错）"
        ),
    )
    parser.add_argument(
        "--cn", dest="cn", action="store_true", default=None,
        help="本次强制启用大陆模型/镜像策略：优先 ModelScope 已验证模型，无映射时再注入 HF/PyPI 镜像",
    )
    parser.add_argument(
        "--no-cn", dest="cn", action="store_false",
        help="本次强制禁用大陆模型/镜像策略（覆盖 cn_mode 配置 / 自动检测）",
    )
    parser.add_argument("--set-default", choices=["md", "docx"], help="设置永久默认格式后退出")
    parser.add_argument("--set-default-model", help="设置永久默认模型后退出（清空：传空串 ''）")
    parser.add_argument(
        "--set-default-cn",
        choices=["on", "off", "auto"],
        help=(
            "设置持久化的大陆模型/镜像偏好后退出。on=每次自动启用 / off=每次禁用 / "
            "auto=按时区/语言自动判断（默认）"
        ),
    )
    parser.add_argument("--show-config", action="store_true", help="显示当前配置后退出")
    parser.add_argument(
        "--onboarding",
        action="store_true",
        help="输出首次 onboarding 候选 JSON（供 agent AskQuestion / 候选框使用）",
    )
    parser.add_argument(
        "--init-defaults",
        action="store_true",
        help="写入首次默认格式+模型后退出（需同时 --format 与 --set-default-model）",
    )

    args = parser.parse_args()

    # 配置管理子命令
    if args.show_config:
        cfg = config.load()
        cn_mode = config.get_cn_mode()
        print(f"配置文件：{config.config_path()}")
        print(f"内容：{cfg or '(空)'}")
        print()
        print(f"大陆模型/镜像偏好（cn_mode）：{cn_mode}")
        if cn_mode == "auto":
            detected = detect_cn()
            print(f"  └ 当前自动检测结果：{'命中（启用）' if detected else '未命中（禁用）'}")
        elif cn_mode == "on":
            print("  └ 每次转录会优先使用 ModelScope 已验证模型；无映射时注入 HF_ENDPOINT=hf-mirror.com / 清华 PyPI")
        else:
            print("  └ 每次转录都走官方源；如需单次启用：加 --cn")
        onboard = "已完成" if not config.needs_onboarding() else "未完成（跑 --onboarding 查看候选）"
        print(f"首次 onboarding：{onboard}")
        return 0

    if args.onboarding:
        import json
        print(json.dumps(config.onboarding_payload(), ensure_ascii=False, indent=2))
        return 0

    if args.init_defaults:
        if not args.format:
            sys.stderr.write("❌ --init-defaults 需要同时指定 --format md|docx\n")
            return 2
        if args.set_default_model is None:
            sys.stderr.write(
                "❌ --init-defaults 需要同时指定 --set-default-model <模型短名>\n"
                "   例：python transcribe.py --init-defaults --format md --set-default-model large-v3-turbo\n"
            )
            return 2
        try:
            config.apply_onboarding(args.format, args.set_default_model)
        except ValueError as e:
            sys.stderr.write(f"❌ {e}\n")
            return 2
        print(f"✅ 首次 onboarding 完成：默认格式 {args.format}，默认模型 {args.set_default_model}")
        print(f"   配置已写入：{config.config_path()}")
        return 0

    if getattr(args, "mirror", None):
        config.set_mirror(args.mirror)
        if args.mirror == "cn":
            print("✅ 已开启国内模型/镜像加速（ModelScope 优先 + 清华 PyPI + hf-mirror.com 兜底）")
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
            config.set_default_model(config.DEFAULT_MODEL)
            print(f"✅ 默认模型已恢复为内置默认：{config.DEFAULT_MODEL}")
        else:
            config.set_default_model(args.set_default_model)
            print(f"✅ 默认模型已改为：{args.set_default_model}")
        return 0

    if args.set_default_cn:
        config.set_cn_mode(args.set_default_cn)
        print(f"✅ 大陆模型/镜像偏好已改为：{args.set_default_cn}")
        if args.set_default_cn == "on":
            print("   每次转录都会优先使用 ModelScope 已验证模型；无映射时注入 HF_ENDPOINT=hf-mirror.com / 清华 PyPI")
        elif args.set_default_cn == "off":
            print("   每次转录都走官方源；如需单次启用：加 --cn")
        else:
            print("   每次转录会按时区/语言自动判断；如需强制：加 --cn 或 --no-cn")
        return 0

    # 转录主流程：首次 onboarding 是硬门禁，--format/--model 不能绕过。
    if config.needs_onboarding():
        config.emit_onboarding_required()

    if not args.audio:
        parser.print_help()
        sys.stderr.write("\n❌ 缺少音频文件参数\n")
        return 1

    audio_path = Path(args.audio).expanduser().resolve()
    if not audio_path.exists():
        sys.stderr.write(f"❌ 找不到音频文件：{audio_path}\n")
        return 1

    check_prereqs()

    # 决定输出格式：CLI > config。onboarding 已在上方硬门禁。
    fmt = args.format or config.get_default_format()
    if fmt is None:
        sys.stderr.write(
            "❌ 配置缺少 default_format。请运行："
            f"python {Path(__file__).name} --onboarding\n"
        )
        return 2
    print(f"本次输出格式：{fmt}（之后想改默认：python {Path(__file__).name} --set-default md|docx）")

    output_dir = Path(args.output_dir).expanduser().resolve() if args.output_dir else audio_path.parent
    output_dir.mkdir(parents=True, exist_ok=True)

    # 决定是否启用大陆模型/镜像策略：CLI flag > config.cn_mode > 自动检测
    cn_mode, cn_reason = resolve_cn_mode(args.cn)
    if cn_mode:
        print(f"ℹ️  本次启用大陆模型/镜像策略（{cn_reason}）")
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
        resolved_model, model_source_label = maybe_prepare_model_source(
            model_name,
            resolved_model,
            engine,
            child_env,
            args.model_source,
            cn_mode,
        )
        if model_source_label == "modelscope":
            print(f"ℹ️  本次使用 ModelScope 本地模型：{resolved_model}")
            print("   💡 ModelScope 是国内源，直连最快；如开了全局 VPN/代理，建议先临时关闭再下载，否则反而更慢。")
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
