#!/usr/bin/env bash
# Murmur 一键安装 — macOS
# 装 ffmpeg / uv / pandoc
#
# 用法：
#   bash scripts/install-mac.sh                 # 自动检测是否在中国大陆，决定是否启用镜像
#   bash scripts/install-mac.sh --cn            # 强制启用大陆镜像（USTC Homebrew）
#   bash scripts/install-mac.sh --no-cn         # 强制禁用镜像

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

usage() {
  cat <<'EOF'
Murmur 一键安装 — macOS
装 ffmpeg / uv / pandoc

用法：
  bash scripts/install-mac.sh                 # 自动检测是否在中国大陆，决定是否启用镜像
  bash scripts/install-mac.sh --cn            # 强制启用大陆镜像（USTC Homebrew）
  bash scripts/install-mac.sh --no-cn         # 强制禁用镜像
EOF
}

# ---------- 解析参数 ----------
CN_MODE=""           # "", "yes", "no"  — 本次安装是否启用大陆镜像（含 auto-detect 结果）
EXPLICIT_CN_FLAG=""  # "", "cn", "no-cn" — 用户是否显式传了 --cn / --no-cn
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

# ---------- 自动检测大陆环境 ----------
# 仅在用户没显式指定时检测；命中任一就建议启用镜像
detect_cn() {
  # 时区
  if [[ -L /etc/localtime ]]; then
    local tz
    tz=$(readlink /etc/localtime 2>/dev/null || true)
    case "$tz" in
      *Shanghai*|*Chongqing*|*Urumqi*|*Harbin*) return 0 ;;
    esac
  fi
  # locale / 语言
  case "${LANG:-}${LC_ALL:-}" in
    zh_CN*|zh-CN*) return 0 ;;
  esac
  # 系统偏好设置（macOS）
  if command -v defaults >/dev/null 2>&1; then
    local loc
    loc=$(defaults read -g AppleLocale 2>/dev/null || true)
    case "$loc" in
      zh_CN*) return 0 ;;
    esac
  fi
  return 1
}

if [[ -z "$CN_MODE" ]]; then
  if detect_cn; then
    CN_MODE="yes"
    info "检测到中国大陆环境（时区/语言），将自动启用 Homebrew 大陆镜像（USTC）"
    info "如需关闭：重跑时加 --no-cn"
  else
    CN_MODE="no"
  fi
fi

# ---------- 启用 Homebrew 大陆镜像 ----------
# 参考 USTC 镜像：https://mirrors.ustc.edu.cn/help/brew.git.html
# 这些环境变量对子进程 brew 生效；HOMEBREW_API_DOMAIN / BOTTLE_DOMAIN 影响 bottle 下载速度
if [[ "$CN_MODE" == "yes" ]]; then
  export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
  export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
  export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
  export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
  export HOMEBREW_NO_AUTO_UPDATE=1   # 避免每次 brew install 都同步 tap，国内常卡
  ok "已启用 Homebrew USTC 镜像（HOMEBREW_*_DOMAIN / *_GIT_REMOTE）"
fi

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
  if [[ "$CN_MODE" == "yes" ]]; then
    echo "国内推荐用 USTC 镜像一键装（一行命令）："
    echo ""
    echo '  /bin/bash -c "$(curl -fsSL https://mirrors.ustc.edu.cn/misc/brew-install.sh)"'
    echo ""
    echo "或者用清华源："
    echo ""
    echo '  /bin/bash -c "$(curl -fsSL https://mirrors.tuna.tsinghua.edu.cn/homebrew/install.sh)"'
    echo ""
    echo "都可以；如果网络畅通也可以用官方："
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
  else
    echo "请先手动安装 Homebrew（一行命令）："
    echo ""
    echo '  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
    echo ""
    echo "国内网络慢的话用 USTC 镜像："
    echo '  /bin/bash -c "$(curl -fsSL https://mirrors.ustc.edu.cn/misc/brew-install.sh)"'
  fi
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

# ---------- 持久化大陆镜像偏好（仅当用户显式 --cn / --no-cn 时）----------
# auto-detect 的结果不写入配置——把"自动判断"的决策权留给 transcribe.py 每次跑时再决定，
# 避免一次旅行到海外用 install 时的判断把偏好锁死。
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
case "$EXPLICIT_CN_FLAG" in
  cn)
    if command -v python3 >/dev/null 2>&1; then
      python3 "$SCRIPT_DIR/transcribe.py" --set-default-cn on >/dev/null 2>&1 \
        && ok "已记住偏好：以后 transcribe.py 默认启用大陆镜像（关闭：python3 scripts/transcribe.py --set-default-cn off）"
    fi
    ;;
  no-cn)
    if command -v python3 >/dev/null 2>&1; then
      python3 "$SCRIPT_DIR/transcribe.py" --set-default-cn off >/dev/null 2>&1 \
        && ok "已记住偏好：以后 transcribe.py 默认走官方源（恢复自动：python3 scripts/transcribe.py --set-default-cn auto）"
    fi
    ;;
esac

echo ""
echo "下一步："
echo "  1) 跑体检：    bash scripts/doctor.sh"
echo "  2) 第一次转录：python3 scripts/transcribe.py 你的录音.m4a"
echo ""
echo "首次转录会下载 ~2.9GB 的 Whisper large-v3 模型，喝杯咖啡。"
if [[ "$CN_MODE" == "yes" ]]; then
  echo ""
  echo "🇨🇳 大陆用户：模型下载也建议走镜像，把下面这行加到 ~/.zshrc 让以后所有终端生效（已存在则跳过）："
  echo "  grep -q '^export HF_ENDPOINT=' ~/.zshrc 2>/dev/null || echo 'export HF_ENDPOINT=https://hf-mirror.com' >> ~/.zshrc"
else
  echo "国内网络慢可加："
  echo "  export HF_ENDPOINT=https://hf-mirror.com"
fi
echo ""
