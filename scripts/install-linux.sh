#!/usr/bin/env bash
# Murmur 一键安装 — Linux / WSL
# 装 ffmpeg / uv / pandoc / python3
#
# 用法：
#   bash scripts/install-linux.sh                 # 自动检测是否在中国大陆
#   bash scripts/install-linux.sh --cn            # 强制启用大陆安装/模型源偏好
#   bash scripts/install-linux.sh --no-cn         # 强制禁用大陆偏好

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { echo -e "${GREEN}✅${NC} $1"; }
warn() { echo -e "${YELLOW}⚠️ ${NC} $1"; }
err()  { echo -e "${RED}❌${NC} $1"; exit 1; }
info() { echo -e "${BLUE}ℹ️ ${NC} $1"; }

usage() {
  cat <<'EOF'
Murmur 一键安装 — Linux / WSL
装 ffmpeg / uv / pandoc / python3

用法：
  bash scripts/install-linux.sh                 # 自动检测是否在中国大陆
  bash scripts/install-linux.sh --cn            # 强制启用大陆安装/模型源偏好
  bash scripts/install-linux.sh --no-cn         # 强制禁用大陆偏好
EOF
}

CN_MODE=""
EXPLICIT_CN_FLAG=""
for arg in "$@"; do
  case "$arg" in
    --cn|--china)   CN_MODE="yes"; EXPLICIT_CN_FLAG="cn" ;;
    --no-cn)        CN_MODE="no";  EXPLICIT_CN_FLAG="no-cn" ;;
    -h|--help)
      usage
      exit 0
      ;;
    *) warn "忽略未知参数：$arg" ;;
  esac
done

detect_cn() {
  command -v python3 >/dev/null 2>&1 \
    && python3 "$SCRIPT_DIR/cn_env.py" --detect >/dev/null 2>&1
}

if [[ -z "$CN_MODE" ]]; then
  if detect_cn; then
    CN_MODE="yes"
    info "检测到中国大陆环境（时区/语言），将启用 PyPI 镜像安装 uv，并记住 HF/PyPI 镜像偏好"
    info "如需关闭：重跑时加 --no-cn"
  else
    CN_MODE="no"
  fi
fi

echo ""
echo "================================"
echo "  Murmur 一键安装 (Linux / WSL)"
echo "================================"
echo ""

OS="$(uname -s)"
if [[ "$OS" != "Linux" ]]; then
  err "这个脚本只能在 Linux / WSL 上跑；macOS 请用 scripts/install-mac.sh，Windows 请用 scripts/install-windows.ps1"
fi

# ---------- 包管理器检测 ----------
PKG_MGR=""
if command -v apt-get >/dev/null 2>&1; then
  PKG_MGR="apt"
elif command -v dnf >/dev/null 2>&1; then
  PKG_MGR="dnf"
elif command -v pacman >/dev/null 2>&1; then
  PKG_MGR="pacman"
else
  err "未检测到 apt / dnf / pacman。请手动安装 ffmpeg、uv、pandoc、python3 后跑 bash scripts/doctor.sh"
fi
ok "包管理器：$PKG_MGR"

install_pkg() {
  local pkg="$1"
  case "$PKG_MGR" in
    apt)
      sudo apt-get update -qq
      sudo apt-get install -y "$pkg"
      ;;
    dnf)
      sudo dnf install -y "$pkg"
      ;;
    pacman)
      sudo pacman -Sy --noconfirm "$pkg"
      ;;
  esac
}

# ---------- ffmpeg ----------
if command -v ffmpeg >/dev/null 2>&1; then
  ok "ffmpeg 已安装，跳过"
else
  info "安装 ffmpeg..."
  install_pkg ffmpeg
  ok "ffmpeg 安装完成"
fi

# ---------- pandoc ----------
if command -v pandoc >/dev/null 2>&1; then
  ok "pandoc 已安装，跳过"
else
  info "安装 pandoc（用于 md→docx 转换）..."
  install_pkg pandoc
  ok "pandoc 安装完成"
fi

# ---------- python3 ----------
if ! command -v python3 >/dev/null 2>&1; then
  info "安装 python3..."
  case "$PKG_MGR" in
    apt) install_pkg python3 python3-pip ;;
    dnf) install_pkg python3 python3-pip ;;
    pacman) install_pkg python python-pip ;;
  esac
fi
ok "python3 就绪：$(python3 --version)"

# ---------- uv ----------
if command -v uvx >/dev/null 2>&1; then
  ok "uv 已安装，跳过"
else
  info "安装 uv..."
  if [[ "$CN_MODE" == "yes" ]]; then
    info "大陆模式：用清华 PyPI 镜像 pip 安装 uv..."
    python3 -m pip install --user -i https://pypi.tuna.tsinghua.edu.cn/simple uv
  else
    if curl -LsSf https://astral.sh/uv/install.sh | sh; then
      ok "uv 已通过官方脚本安装"
    else
      warn "官方 uv 安装脚本失败，回退到 pip..."
      python3 -m pip install --user uv
    fi
  fi

  if ! command -v uvx >/dev/null 2>&1; then
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v uvx >/dev/null 2>&1; then
      err "uv 装完但 uvx 仍找不到。请把 \$HOME/.local/bin 加到 PATH 后重试。"
    fi
    if ! grep -q '\.local/bin' "$HOME/.bashrc" 2>/dev/null; then
      echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
      info "已把 \$HOME/.local/bin 写入 ~/.bashrc"
    fi
  fi
  ok "uv 安装完成"
fi

echo ""
echo "================================"
ok "Murmur 安装完成！"
echo "================================"
echo ""

# ---------- 持久化大陆模型/镜像偏好 ----------
if [[ "$CN_MODE" == "yes" ]]; then
  if python3 "$SCRIPT_DIR/transcribe.py" --set-default-cn on >/dev/null 2>&1; then
    ok "已记住偏好：以后 transcribe.py 默认启用大陆模型/镜像策略（关闭：python3 scripts/transcribe.py --set-default-cn off）"
  fi
elif [[ "$EXPLICIT_CN_FLAG" == "no-cn" ]]; then
  if python3 "$SCRIPT_DIR/transcribe.py" --set-default-cn off >/dev/null 2>&1; then
    ok "已记住偏好：以后 transcribe.py 默认走官方源（恢复自动：python3 scripts/transcribe.py --set-default-cn auto）"
  fi
fi

echo ""
echo "下一步："
echo "  1) 跑体检：    bash scripts/doctor.sh"
echo "  2) 第一次转录：python3 scripts/transcribe.py 你的录音.m4a"
echo ""
echo "首次转录会下载 ~1.5GB 的 Whisper large-v3-turbo 模型，喝杯咖啡。"
if [[ "$CN_MODE" == "yes" ]]; then
  echo ""
  echo "🇨🇳 大陆偏好已写入配置；转录模型优先走 ModelScope 已验证源，uv 拉包走清华 PyPI。"
else
  echo "国内网络慢可加："
  echo "  python3 scripts/transcribe.py --set-default-cn on"
fi
echo ""
