#!/usr/bin/env python3
"""把 Murmur 清洗后的 Markdown 转成 Word (.docx)，依赖 pandoc。

用法：
  python md2docx.py 逐字稿-清洗版.md                    # 输出同目录 同名 .docx
  python md2docx.py 逐字稿-清洗版.md -o 自定义.docx     # 指定输出
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description="Murmur — Markdown → Word")
    parser.add_argument("md", help="输入 markdown 文件")
    parser.add_argument("-o", "--output", help="输出 .docx 文件（默认与 md 同名）")
    args = parser.parse_args()

    if shutil.which("pandoc") is None:
        sys.stderr.write(
            "❌ 未检测到 pandoc。请先安装：\n"
            "   macOS:   brew install pandoc\n"
            "   Windows: winget install JohnMacFarlane.Pandoc\n"
            "   Linux:   sudo apt install pandoc  /  sudo dnf install pandoc\n"
        )
        return 2

    src = Path(args.md).expanduser().resolve()
    if not src.exists():
        sys.stderr.write(f"❌ 找不到输入文件：{src}\n")
        return 1

    dst = Path(args.output).expanduser().resolve() if args.output else src.with_suffix(".docx")

    print(f"转换：{src.name} → {dst.name}")
    cmd = [
        "pandoc",
        str(src),
        "-o", str(dst),
        "--from", "markdown",
        "--to", "docx",
        "--standalone",
    ]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.stderr.write(f"❌ pandoc 失败：\n{result.stderr[-1500:]}\n")
        return 3

    print(f"✅ 已生成：{dst}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
