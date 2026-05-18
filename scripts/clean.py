#!/usr/bin/env python3
"""Murmur · 清洗 prompt 组装工具

把 docs/prompts/clean-transcript.md 里的完整 prompt 与转录原稿拼好，输出到 stdout。
复制粘贴到任意 LLM 对话框，或 pipe 给支持 stdin 的 CLI LLM 工具。

用法：
  python scripts/clean.py 转录原稿.txt
  python scripts/clean.py 转录原稿.txt --scene interview   # 在 prompt 开头加面试场景提示
  python scripts/clean.py 转录原稿.txt --scene meeting
  python scripts/clean.py 转录原稿.txt --scene podcast

  # macOS：直接复制到剪贴板
  python scripts/clean.py 转录原稿.txt | pbcopy

  # Linux（需装 xclip）
  python scripts/clean.py 转录原稿.txt | xclip -selection clipboard
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

SCENE_HINTS: dict[str, str] = {
    "interview": """这是一段中文面试录音，面试官代称"面试官"，应试者代称"我"。""",
    "meeting":   """这是一段工作会议录音。如果你能从上下文识别出参与者姓名或角色，请用真实名字/角色标注说话人。""",
    "podcast":   """这是一段播客/访谈录音，主持人代称"主持人"，嘉宾代称"嘉宾"（多位嘉宾时用"嘉宾 A / 嘉宾 B"）。""",
}

PROMPT_START_MARKER = "## === PROMPT 开始 ==="
PROMPT_END_MARKER   = "## === PROMPT 结束 ==="
TRANSCRIPT_PLACEHOLDER = "（在这里贴 `转录原稿.txt` 的全部内容）"


def find_prompt_file() -> Path:
    """从脚本所在目录向上找 docs/prompts/clean-transcript.md。"""
    script_dir = Path(__file__).resolve().parent
    candidates = [
        script_dir.parent / "docs" / "prompts" / "clean-transcript.md",
        Path("docs") / "prompts" / "clean-transcript.md",
    ]
    for p in candidates:
        if p.exists():
            return p
    sys.stderr.write(
        "❌ 找不到 docs/prompts/clean-transcript.md\n"
        "   请在 Murmur 仓库根目录下运行，或检查文件是否存在。\n"
    )
    sys.exit(2)


def extract_prompt(prompt_file: Path) -> str:
    """提取 PROMPT 开始/结束 标记之间的内容（不含标记行本身）。"""
    text = prompt_file.read_text(encoding="utf-8")
    lines = text.splitlines()

    inside = False
    collected: list[str] = []
    for line in lines:
        if line.strip() == PROMPT_START_MARKER.strip():
            inside = True
            continue
        if line.strip() == PROMPT_END_MARKER.strip():
            break
        if inside:
            collected.append(line)

    if not collected:
        sys.stderr.write(
            f"❌ 在 {prompt_file} 中找不到 PROMPT 开始/结束 标记。\n"
            f"   期望找到：\n"
            f"   {PROMPT_START_MARKER}\n"
            f"   {PROMPT_END_MARKER}\n"
        )
        sys.exit(2)

    # 去掉头尾多余空行
    return "\n".join(collected).strip()


def assemble(transcript_path: Path, scene: str | None) -> str:
    prompt_file = find_prompt_file()
    prompt = extract_prompt(prompt_file)
    transcript = transcript_path.read_text(encoding="utf-8")

    # 把占位符替换成真实内容
    if TRANSCRIPT_PLACEHOLDER in prompt:
        prompt = prompt.replace(TRANSCRIPT_PLACEHOLDER, transcript)
    else:
        # 兜底：直接追加到末尾
        prompt = prompt + "\n\n" + transcript

    # 场景描述插到 prompt 最开头
    if scene:
        hint = SCENE_HINTS.get(scene, "")
        if hint:
            prompt = hint + "\n\n" + prompt

    return prompt


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Murmur · 清洗 prompt 组装工具",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("transcript", help="转录原稿路径（转录原稿.txt）")
    parser.add_argument(
        "--scene",
        choices=list(SCENE_HINTS.keys()),
        default=None,
        help="场景提示（interview / meeting / podcast）；不传则不加",
    )
    args = parser.parse_args()

    transcript_path = Path(args.transcript).expanduser().resolve()
    if not transcript_path.exists():
        sys.stderr.write(f"❌ 找不到转录原稿：{transcript_path}\n")
        return 1

    result = assemble(transcript_path, args.scene)
    sys.stdout.write(result)
    if not result.endswith("\n"):
        sys.stdout.write("\n")

    # 字数提示写到 stderr，不污染 stdout（pipe 场景）
    word_count = len(result)
    sys.stderr.write(f"\n✅ 已组装 prompt（{word_count:,} 字符）\n")
    sys.stderr.write("   复制到 LLM 对话框，或加 | pbcopy (macOS) / | xclip (Linux)\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
