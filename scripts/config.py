"""Murmur 的小型配置管理 —— 只管一件事：默认输出格式（md / docx）。

存储位置：
  - macOS / Linux: $XDG_CONFIG_HOME/murmur/config.json （默认 ~/.config/murmur/config.json）
  - Windows:       %APPDATA%\\Murmur\\config.json

设计原则：
  - 跨项目通用，不污染当前工作目录
  - 用户可以随时通过 `transcribe.py --set-default md|docx` 覆盖
  - 单次跑用 `--format md|docx` 临时覆盖，不动 config
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

from models import DEFAULT_MODEL, KNOWN_MODELS, ONBOARDING_MODEL_CHOICES, is_valid_default_model

VALID_FORMATS = {"md", "docx"}

# 大陆镜像偏好的三种取值：
#   on   = 每次转录都强制启用 HF/PyPI 镜像
#   off  = 每次转录都强制走官方源
#   auto = 由 transcribe.py 按时区/语言自动判断（默认）
VALID_CN_MODES = {"on", "off", "auto"}

ONBOARDING_FORMAT_CHOICES: tuple[dict[str, str], ...] = (
    {
        "id": "md",
        "label": "Markdown (.md)",
        "description": "程序员 / VS Code / Notion 友好",
    },
    {
        "id": "docx",
        "label": "Word (.docx)",
        "description": "通用，能直接发给同事",
    },
)


def _config_dir() -> Path:
    if sys.platform == "win32":
        base = os.environ.get("APPDATA")
        if not base:
            base = str(Path.home() / "AppData" / "Roaming")
        return Path(base) / "Murmur"
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "murmur"


def config_path() -> Path:
    return _config_dir() / "config.json"


def load() -> dict:
    p = config_path()
    if not p.exists():
        return {}
    try:
        cfg = json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}
    if not isinstance(cfg, dict):
        return {}
    # 迁移：把已废弃的 mirror=cn/off 平迁到 cn_mode=on/off；之后剥离 mirror key
    if "mirror" in cfg:
        old = cfg.pop("mirror")
        if "cn_mode" not in cfg:
            if old == "cn":
                cfg["cn_mode"] = "on"
            elif old == "off":
                cfg["cn_mode"] = "off"
        try:
            save(cfg)
        except OSError:
            pass  # 迁移失败不阻塞读取
    # 不再把旧配置（只有 default_format）自动视为完成；必须补选 default_model。
    return cfg


def save(cfg: dict) -> None:
    p = config_path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(cfg, indent=2, ensure_ascii=False), encoding="utf-8")


def get_default_format() -> str | None:
    cfg = load()
    fmt = cfg.get("default_format")
    return fmt if fmt in VALID_FORMATS else None


def set_default_format(fmt: str) -> None:
    if fmt not in VALID_FORMATS:
        raise ValueError(f"格式必须是 {VALID_FORMATS} 之一，收到：{fmt!r}")
    cfg = load()
    cfg["default_format"] = fmt
    save(cfg)


def get_default_model() -> str | None:
    """读出用户设置的默认模型；返回 None 表示用代码里的内置默认（large-v3-turbo）。"""
    cfg = load()
    model = cfg.get("default_model")
    if isinstance(model, str) and model.strip():
        return model.strip()
    return None


def set_default_model(model: str) -> None:
    """写入默认模型。允许任意非空字符串：短名（large-v3）或完整 HF repo 名都行。"""
    if not isinstance(model, str) or not model.strip():
        raise ValueError(f"模型名不能为空，收到：{model!r}")
    cfg = load()
    cfg["default_model"] = model.strip()
    save(cfg)


def needs_onboarding() -> bool:
    """是否尚未完成首次 onboarding（默认格式 + 默认模型）。"""
    cfg = load()
    fmt = cfg.get("default_format")
    model = cfg.get("default_model")
    return not (
        cfg.get("onboarding_complete") is True
        and fmt in VALID_FORMATS
        and isinstance(model, str)
        and is_valid_default_model(model)
    )


def _onboarding_model_ids() -> set[str]:
    return {choice["id"] for choice in ONBOARDING_MODEL_CHOICES}


def onboarding_payload() -> dict:
    """给 agent 候选框用的结构化 onboarding 描述（可 JSON 序列化）。"""
    format_options = []
    for opt in ONBOARDING_FORMAT_CHOICES:
        item = dict(opt)
        item["recommended"] = opt["id"] == "md"
        format_options.append(item)
    model_options = []
    for opt in ONBOARDING_MODEL_CHOICES:
        item = dict(opt)
        item["recommended"] = opt["id"] == DEFAULT_MODEL
        model_options.append(item)
    return {
        "needs_onboarding": needs_onboarding(),
        "must_ask_user": True,
        "do_not_choose_for_user": True,
        "do_not_run_example_without_user_choice": True,
        "config_path": str(config_path()),
        "agent_instructions": (
            "Use your AskQuestion / 候选框 tool to let the user pick default_format "
            "and default_model. Do NOT choose for the user. Do NOT run the example "
            "without an explicit user choice. Then run apply.command."
        ),
        "questions": [
            {
                "id": "default_format",
                "prompt": "以后默认输出格式选哪个？",
                "type": "single_select",
                "options": format_options,
            },
            {
                "id": "default_model",
                "prompt": "以后默认离线 Whisper 模型选哪个？（首次转录会下载到 HuggingFace 缓存）",
                "type": "single_select",
                "options": model_options,
            },
        ],
        "apply": {
            "command": (
                "python scripts/transcribe.py --init-defaults "
                "--format <md|docx> --set-default-model <model>"
            ),
            "example_is_not_a_default_answer": True,
            "example": (
                f"python scripts/transcribe.py --init-defaults "
                f"--format md --set-default-model {DEFAULT_MODEL}"
            ),
        },
    }


def apply_onboarding(fmt: str, model: str) -> None:
    """写入首次 onboarding 选择（格式 + 模型）并标记完成。"""
    if fmt not in VALID_FORMATS:
        raise ValueError(f"格式必须是 {VALID_FORMATS} 之一，收到：{fmt!r}")
    model = model.strip()
    if not model:
        raise ValueError("模型名不能为空")
    allowed = _onboarding_model_ids() | KNOWN_MODELS
    if model not in allowed:
        raise ValueError(f"模型必须是 {sorted(allowed)} 之一，收到：{model!r}")
    cfg = load()
    cfg["default_format"] = fmt
    cfg["default_model"] = model
    cfg["onboarding_complete"] = True
    save(cfg)


def emit_onboarding_required() -> None:
    """非交互环境缺少 onboarding 时：stderr 人话 + stdout JSON，exit 10。"""
    payload = onboarding_payload()
    sys.stderr.write(
        "❌ 首次使用 Murmur：请先完成 onboarding（默认格式 + 默认离线模型）。\n"
        "   Agent：必须用 AskQuestion / 候选框让用户选择，再运行 apply.command；不要直接跑 example。\n"
        "   或单独查看：python scripts/transcribe.py --onboarding\n"
    )
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    sys.exit(10)


def prompt_for_onboarding_tty() -> tuple[str, str]:
    """TTY 下交互式首次 onboarding（格式 + 模型）。"""
    print()
    print("首次使用 Murmur 👋")
    print("先选两个默认值（之后随时可改）。")
    print()
    print("【1/2】以后默认输出格式？")
    for i, opt in enumerate(ONBOARDING_FORMAT_CHOICES, 1):
        print(f"  [{i}] {opt['label']}  — {opt['description']}")
    print()
    print(f"配置会存到：{config_path()}")
    print()

    fmt: str | None = None
    while fmt is None:
        try:
            choice = input("格式请输入 1 或 2：").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(1)
        if choice in ("1", "md", "markdown"):
            fmt = "md"
        elif choice in ("2", "docx", "word"):
            fmt = "docx"
        else:
            print("没听清，请输入 1 或 2。")

    print()
    print("【2/2】以后默认离线 Whisper 模型？（首次会下载到 ~/.cache/huggingface/hub）")
    for i, opt in enumerate(ONBOARDING_MODEL_CHOICES, 1):
        rec = " ← 推荐" if opt["id"] == DEFAULT_MODEL else ""
        print(f"  [{i}] {opt['label']}  — {opt['description']}{rec}")
    print()

    model: str | None = None
    while model is None:
        try:
            choice = input(f"模型请输入 1–{len(ONBOARDING_MODEL_CHOICES)}：").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(1)
        if choice.isdigit():
            idx = int(choice)
            if 1 <= idx <= len(ONBOARDING_MODEL_CHOICES):
                model = ONBOARDING_MODEL_CHOICES[idx - 1]["id"]
                continue
        lowered = choice.lower()
        for opt in ONBOARDING_MODEL_CHOICES:
            if lowered == opt["id"]:
                model = opt["id"]
                break
        if model is None:
            print(f"没听清，请输入 1–{len(ONBOARDING_MODEL_CHOICES)} 或模型短名。")

    apply_onboarding(fmt, model)
    print(f"\n已保存默认格式：{fmt}，默认模型：{model}\n")
    return fmt, model


def prompt_for_default_format() -> str:
    """兼容旧调用：TTY 走完整 onboarding；非 TTY 抛给 agent 流程。"""
    if sys.stdin.isatty() and sys.stdout.isatty():
        fmt, _model = prompt_for_onboarding_tty()
        return fmt
    emit_onboarding_required()


# ---------- 大陆镜像偏好（cn_mode） ----------

def get_cn_mode() -> str:
    """读取持久化的大陆镜像偏好。返回 'on' / 'off' / 'auto'（默认 'auto'）。

    决策语义（在 transcribe.py 里实现）：
      - on   → 每次都启用 HF/PyPI 镜像
      - off  → 每次都走官方源
      - auto → 调 detect_cn() 按时区/语言判断
    """
    cfg = load()
    mode = cfg.get("cn_mode")
    return mode if mode in VALID_CN_MODES else "auto"


def set_cn_mode(mode: str) -> None:
    if mode not in VALID_CN_MODES:
        raise ValueError(f"cn_mode 必须是 {VALID_CN_MODES} 之一，收到：{mode!r}")
    cfg = load()
    cfg["cn_mode"] = mode
    save(cfg)
