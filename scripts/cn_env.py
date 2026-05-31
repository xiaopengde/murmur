#!/usr/bin/env python3
"""Murmur 大陆环境检测与模型/镜像 env 构建 —— 供 transcribe / install / doctor 共用。

CLI（给 shell 脚本调用）：
  python3 cn_env.py --detect          # exit 0=大陆环境，1=否
  python3 cn_env.py --should-mirror   # exit 0=本次应启用镜像（含 cn_mode 配置）
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

# 与 install 脚本保持一致
CN_HF_ENDPOINT = "https://hf-mirror.com"
CN_PYPI_INDEX = "https://pypi.tuna.tsinghua.edu.cn/simple"


def detect_cn() -> bool:
    """根据时区/语言/系统区域判断是否在中国大陆。

    任一命中即返回 True：
      1. LANG / LC_ALL 是 zh_CN.*
      2. macOS: 系统区域偏好 AppleLocale 为 zh_CN
      3. macOS/Linux: /etc/localtime 链接到 Asia/Shanghai 等
      4. Windows: tzutil 显示 China Standard Time
      5. 兜底：UTC+8 时区且 tzname 含 CST/China/中国
    """
    for var in ("LANG", "LC_ALL"):
        val = os.environ.get(var, "").lower()
        if val.startswith("zh_cn") or val.startswith("zh-cn"):
            return True

    if sys.platform == "darwin":
        try:
            loc = subprocess.run(
                ["defaults", "read", "-g", "AppleLocale"],
                capture_output=True,
                text=True,
                timeout=3,
            ).stdout.strip()
            if loc.startswith("zh_CN"):
                return True
        except (OSError, subprocess.SubprocessError):
            pass

    localtime = Path("/etc/localtime")
    if localtime.is_symlink():
        try:
            target = os.readlink(localtime)
        except OSError:
            target = ""
        for keyword in ("Shanghai", "Chongqing", "Urumqi", "Harbin"):
            if keyword in target:
                return True

    if sys.platform == "win32":
        try:
            tz = subprocess.run(
                ["tzutil", "/g"], capture_output=True, text=True, timeout=3
            ).stdout.strip()
            if "China Standard Time" in tz:
                return True
        except (OSError, subprocess.SubprocessError):
            pass

    try:
        from datetime import datetime, timezone as _tz
        import time as _time

        local_tz = datetime.now(_tz.utc).astimezone().tzinfo
        offset = local_tz.utcoffset(datetime.now()) if local_tz else None
        if offset and int(offset.total_seconds()) == 8 * 3600:
            tz_names = " ".join(name for name in _time.tzname if name).lower()
            if "china" in tz_names or "cst" in tz_names or "中国" in tz_names:
                return True
    except Exception:
        pass

    return False


def resolve_cn_mode(cli_flag: bool | None) -> tuple[bool, str]:
    """决定本次是否启用大陆模型/镜像策略。优先级：CLI flag > config.cn_mode > 自动检测。"""
    if cli_flag is True:
        return True, "--cn"
    if cli_flag is False:
        return False, "--no-cn"

    sys.path.insert(0, str(Path(__file__).resolve().parent))
    import config  # noqa: WPS433

    pref = config.get_cn_mode()
    if pref == "on":
        return True, "配置 cn_mode=on（持久启用）"
    if pref == "off":
        return False, "配置 cn_mode=off（持久禁用）"

    if detect_cn():
        return True, "auto：检测到中国大陆环境（时区/语言/区域）"
    return False, "auto：未检测到中国大陆环境"


def should_use_cn_mirror() -> bool:
    """转录 / smoke 测试是否应启用大陆模型/镜像策略（读配置 + 自动检测）。"""
    return resolve_cn_mode(None)[0]


def build_cn_env(base_env: dict[str, str]) -> dict[str, str]:
    """在 base_env 基础上注入大陆兜底镜像变量；用户已显式设置的不覆盖。"""
    env = dict(base_env)
    if not env.get("HF_ENDPOINT"):
        env["HF_ENDPOINT"] = CN_HF_ENDPOINT
    if not env.get("UV_INDEX_URL") and not env.get("UV_DEFAULT_INDEX"):
        env["UV_INDEX_URL"] = CN_PYPI_INDEX
    env.setdefault("UV_HTTP_TIMEOUT", "120")
    return env


def main() -> int:
    parser = argparse.ArgumentParser(description="Murmur 大陆环境检测")
    parser.add_argument(
        "--detect",
        action="store_true",
        help="检测是否在中国大陆环境（exit 0=是，1=否）",
    )
    parser.add_argument(
        "--should-mirror",
        action="store_true",
        help="是否应启用 HF/PyPI 镜像（exit 0=是，1=否）",
    )
    args = parser.parse_args()

    if args.detect:
        return 0 if detect_cn() else 1
    if args.should_mirror:
        return 0 if should_use_cn_mirror() else 1

    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
