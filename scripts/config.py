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

VALID_FORMATS = {"md", "docx"}


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
        return json.loads(p.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError):
        return {}


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


def prompt_for_default_format() -> str:
    """首次使用时交互式询问，并保存到 config。"""
    print()
    print("首次使用 Murmur 👋")
    print("以后默认输出格式选哪个？")
    print("  [1] markdown (.md)  — 程序员 / VS Code / Notion 友好")
    print("  [2] word (.docx)    — 通用，能直接发给同事")
    print()
    print(f"配置会存到：{config_path()}")
    print("（之后想改：python transcribe.py --set-default md  或  docx）")
    print()

    while True:
        try:
            choice = input("请输入 1 或 2：").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n已取消。")
            sys.exit(1)
        if choice in ("1", "md", "markdown"):
            fmt = "md"
            break
        if choice in ("2", "docx", "word"):
            fmt = "docx"
            break
        print("没听清，请输入 1 或 2。")

    set_default_format(fmt)
    print(f"已保存默认格式：{fmt}（之后随时可用 --set-default 切换）\n")
    return fmt
