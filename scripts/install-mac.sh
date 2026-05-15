#!/usr/bin/env bash
# Murmur 一键安装 — macOS
# 装 ffmpeg / uv / pandoc

set -e

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️ ${NC} $1"; }
err()  { echo -e "${RED}❌${NC} $1"; exit 1; }
info() { echo -e "${BLUE}ℹ️ ${NC} $1"; }

echo ""
echo "================================"
echo "  Murmur 一键安装 (macOS)"
echo "================================"
echo ""

# ---------- 检查 macOS ----------
if [[ "$(uname -s)" != "Darwin" ]]; then
  err "这个脚本只能在 macOS 上跑；Linux 请看 docs/install-windows.md 末尾的 Linux 章节，Windows 请用 scripts/install-windows.ps1"
fi

# ---------- 检查 Homebrew ----------
if ! command -v brew >/dev/null 2>&1; then
  warn "未检测到 Homebrew —— Murmur 需要 brew 来装 ffmpeg/uv/pandoc"
  echo ""
  echo "请先手动安装 Homebrew（一行命令）："
  echo ""
  echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  echo ""
  echo "装完后重新跑这个脚本。"
  exit 1
fi
ok "Homebrew 已安装：$(brew --version | head -n1)"

# ---------- ffmpeg ----------
if command -v ffmpeg >/dev/null 2>&1; then
  ok "ffmpeg 已安装，跳过"
else
  info "安装 ffmpeg..."
  brew install ffmpeg
  ok "ffmpeg 安装完成"
fi

# ---------- uv ----------
if command -v uvx >/dev/null 2>&1; then
  ok "uv 已安装，跳过"
else
  info "安装 uv..."
  brew install uv
  ok "uv 安装完成"
fi

# ---------- pandoc ----------
if command -v pandoc >/dev/null 2>&1; then
  ok "pandoc 已安装，跳过"
else
  info "安装 pandoc（用于 md→docx 转换）..."
  brew install pandoc
  ok "pandoc 安装完成"
fi

# ---------- python3 检查 ----------
if ! command -v python3 >/dev/null 2>&1; then
  warn "python3 未检测到（macOS 通常自带），尝试装 python@3.11..."
  brew install python@3.11
fi
ok "python3 就绪：$(python3 --version)"

echo ""
echo "================================"
ok "Murmur 安装完成！"
echo "================================"
echo ""
echo "下一步："
echo "  1) 跑体检：    bash scripts/doctor.sh"
echo "  2) 第一次转录：python3 scripts/transcribe.py 你的录音.m4a"
echo ""
echo "首次转录会下载 ~2.9GB 的 Whisper large-v3 模型，喝杯咖啡。"
echo "国内用户强烈建议先开镜像加速（一次设置永久生效）："
echo "  python3 scripts/transcribe.py --mirror cn"
echo ""
