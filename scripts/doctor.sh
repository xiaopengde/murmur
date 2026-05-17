#!/usr/bin/env bash
# Murmur env doctor — macOS / Linux
# 检查 ffmpeg / uv / pandoc / python3 / 平台 / HuggingFace 缓存
# 故意不开 set -e/-u —— 体检脚本就是要把所有问题报完，而不是遇到第一个就退

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️ ${NC} $1"; }
err()  { echo -e "${RED}❌${NC} $1"; }
info() { echo -e "${BLUE}ℹ️ ${NC} $1"; }

echo ""
echo "================================"
echo "  Murmur 环境体检"
echo "================================"
echo ""

# ---------- OS / Arch ----------
OS="$(uname -s)"
ARCH="$(uname -m)"
info "操作系统：$OS"
info "芯片架构：$ARCH"

if [[ "$OS" == "Darwin" ]]; then
  if [[ "$ARCH" == "arm64" ]]; then
    ok "Apple Silicon Mac → 将使用 mlx-whisper（GPU 加速最快）"
    ENGINE="mlx-whisper"
  else
    warn "Intel Mac → 将使用 whisper-ctranslate2（CPU，速度较慢）"
    ENGINE="whisper-ctranslate2"
  fi
elif [[ "$OS" == "Linux" ]]; then
  warn "Linux → 将使用 whisper-ctranslate2（CPU 或 CUDA 加速）"
  ENGINE="whisper-ctranslate2"
else
  err "不支持的操作系统：$OS"
  exit 1
fi
echo ""

# ---------- ffmpeg ----------
if command -v ffmpeg >/dev/null 2>&1; then
  VER=$(ffmpeg -version 2>&1 | head -n1 | awk '{print $3}')
  ok "ffmpeg 已安装（$VER）"
else
  err "ffmpeg 未安装"
  if [[ "$OS" == "Darwin" ]]; then
    echo "    → 安装：brew install ffmpeg（如无 brew：先装 https://brew.sh）"
  else
    echo "    → Ubuntu/Debian: sudo apt install ffmpeg"
    echo "    → Fedora/RHEL:   sudo dnf install ffmpeg"
    echo "    → Arch:          sudo pacman -S ffmpeg"
  fi
fi

# ---------- uv / uvx ----------
if command -v uvx >/dev/null 2>&1; then
  VER=$(uvx --version 2>&1 | awk '{print $2}')
  ok "uv 已安装（$VER）"
else
  err "uv 未安装"
  if [[ "$OS" == "Darwin" ]]; then
    echo "    → 安装：brew install uv  （或 curl -LsSf https://astral.sh/uv/install.sh | sh）"
  else
    echo "    → 安装：curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi
fi

# ---------- pandoc ----------
if command -v pandoc >/dev/null 2>&1; then
  VER=$(pandoc --version 2>&1 | head -n1 | awk '{print $2}')
  ok "pandoc 已安装（$VER）—— md→docx 转换可用"
else
  warn "pandoc 未安装（仅当默认输出 docx 时需要）"
  if [[ "$OS" == "Darwin" ]]; then
    echo "    → 安装：brew install pandoc"
  else
    echo "    → Ubuntu/Debian: sudo apt install pandoc"
    echo "    → Fedora/RHEL:   sudo dnf install pandoc"
  fi
fi

# ---------- python3 ----------
if command -v python3 >/dev/null 2>&1; then
  VER=$(python3 --version 2>&1 | awk '{print $2}')
  MAJOR=$(echo "$VER" | cut -d. -f1)
  MINOR=$(echo "$VER" | cut -d. -f2)
  if [[ "$MAJOR" -ge 3 ]] && [[ "$MINOR" -ge 9 ]]; then
    ok "python3 已安装（$VER）"
  else
    warn "python3 版本偏低（$VER），建议 3.9+"
  fi
else
  err "python3 未安装"
  if [[ "$OS" == "Darwin" ]]; then
    echo "    → macOS 自带 python3；如缺失：brew install python@3.11"
  else
    echo "    → Ubuntu/Debian: sudo apt install python3"
  fi
fi

# ---------- HuggingFace 缓存 ----------
HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}/hub"
if [[ -d "$HF_CACHE" ]]; then
  SIZE=$(du -sh "$HF_CACHE" 2>/dev/null | awk '{print $1}')
  if find "$HF_CACHE" -name "*whisper*large-v3*" 2>/dev/null | grep -q .; then
    ok "HuggingFace 缓存已含 whisper-large-v3 模型（$SIZE）"
  else
    info "HuggingFace 缓存目录存在但未含 large-v3，首次转录会下载约 2.9GB"
  fi
else
  info "HuggingFace 缓存尚未建立，首次转录会下载约 2.9GB 模型"
  info "国内网络慢可设：export HF_ENDPOINT=https://hf-mirror.com"
fi

# ---------- Murmur 配置 ----------
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/murmur"
CONFIG_FILE="$CONFIG_DIR/config.json"
if [[ -f "$CONFIG_FILE" ]]; then
  FORMAT=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('default_format','?'))" 2>/dev/null || echo "?")
  CN_MODE=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('cn_mode','auto'))" 2>/dev/null || echo "auto")
  ok "Murmur 配置已存在（默认输出格式：$FORMAT）"
  case "$CN_MODE" in
    on)
      ok "大陆镜像偏好：on（每次转录自动启用 HF/PyPI 镜像）"
      ;;
    off)
      info "大陆镜像偏好：off（每次转录走官方源；国内慢可改：python3 scripts/transcribe.py --set-default-cn on）"
      ;;
    *)
      info "大陆镜像偏好：auto（按时区/语言自动判断；强制开：python3 scripts/transcribe.py --set-default-cn on）"
      ;;
  esac
else
  info "Murmur 还未初始化，首次跑 transcribe.py 时会问你 md/docx 默认值"
  info "国内用户建议先跑：python3 scripts/transcribe.py --set-default-cn on"
fi

echo ""
echo "================================"
if command -v ffmpeg >/dev/null 2>&1 && command -v uvx >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
  ok "核心环境就绪，可以开始转录！"
  echo "    试试：python3 scripts/transcribe.py 你的录音.m4a"
else
  err "缺少核心依赖，请按上方提示安装；或一键跑：bash scripts/install-mac.sh"
fi
echo "================================"
echo ""
