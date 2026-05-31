#!/usr/bin/env bash
# Murmur 一键安装 — macOS
# 装 ffmpeg / uv / pandoc
#
# 用法：
#   bash scripts/install-mac.sh                 # 自动检测是否在中国大陆，决定是否启用镜像
#   bash scripts/install-mac.sh --cn            # 强制启用大陆安装/模型源偏好
#   bash scripts/install-mac.sh --no-cn         # 强制禁用大陆偏好

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
Murmur 一键安装 — macOS
装 ffmpeg / uv / pandoc

用法：
  bash scripts/install-mac.sh                 # 自动检测是否在中国大陆，决定是否启用镜像
  bash scripts/install-mac.sh --cn            # 强制启用大陆安装/模型源偏好
  bash scripts/install-mac.sh --no-cn         # 强制禁用大陆偏好
EOF
}

persist_cn_shell_profile() {
  local marker="murmur cn mirror"
  local block='# >>> murmur cn mirror (managed by install-mac.sh) >>>
export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
export HOMEBREW_NO_AUTO_UPDATE=1
# <<< murmur cn mirror <<<'
  local rc
  for rc in "$HOME/.zshrc" "$HOME/.bash_profile"; do
    touch "$rc"
    if grep -q "$marker" "$rc" 2>/dev/null; then
      ok "Shell 镜像配置已存在于 $(basename "$rc")，跳过"
    else
      printf '\n%s\n' "$block" >> "$rc"
      ok "已写入 $(basename "$rc")：以后 brew install 默认走 USTC 镜像"
    fi
  done
}

# ---------- 解析参数 ----------
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

# ---------- 自动检测大陆环境（统一走 scripts/cn_env.py）----------
detect_cn() {
  command -v python3 >/dev/null 2>&1 \
    && python3 "$SCRIPT_DIR/cn_env.py" --detect >/dev/null 2>&1
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

# ---------- 启用 Homebrew 大陆镜像（当前 shell 会话）----------
if [[ "$CN_MODE" == "yes" ]]; then
  export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
  export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
  export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
  export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
  export HOMEBREW_NO_AUTO_UPDATE=1
  ok "已启用 Homebrew USTC 镜像（HOMEBREW_*_DOMAIN / *_GIT_REMOTE）"
fi

echo ""
echo "================================"
echo "  Murmur 一键安装 (macOS)"
echo "================================"
echo ""

if [[ "$(uname -s)" != "Darwin" ]]; then
  err "这个脚本只能在 macOS 上跑；Linux 请用 scripts/install-linux.sh，Windows 请用 scripts/install-windows.ps1"
fi

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

if command -v ffmpeg >/dev/null 2>&1; then
  ok "ffmpeg 已安装，跳过"
else
  info "安装 ffmpeg..."
  brew install ffmpeg
  ok "ffmpeg 安装完成"
fi

if command -v uvx >/dev/null 2>&1; then
  ok "uv 已安装，跳过"
else
  info "安装 uv..."
  brew install uv
  ok "uv 安装完成"
fi

if command -v pandoc >/dev/null 2>&1; then
  ok "pandoc 已安装，跳过"
else
  info "安装 pandoc（用于 md→docx 转换）..."
  brew install pandoc
  ok "pandoc 安装完成"
fi

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

# ---------- 持久化大陆模型/镜像偏好 + shell 配置 ----------
if [[ "$CN_MODE" == "yes" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 "$SCRIPT_DIR/transcribe.py" --set-default-cn on >/dev/null 2>&1 \
      && ok "已记住偏好：以后 transcribe.py 默认启用大陆模型/镜像策略（关闭：python3 scripts/transcribe.py --set-default-cn off）"
  fi
  persist_cn_shell_profile
elif [[ "$EXPLICIT_CN_FLAG" == "no-cn" ]]; then
  if command -v python3 >/dev/null 2>&1; then
    python3 "$SCRIPT_DIR/transcribe.py" --set-default-cn off >/dev/null 2>&1 \
      && ok "已记住偏好：以后 transcribe.py 默认走官方源（恢复自动：python3 scripts/transcribe.py --set-default-cn auto）"
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
  echo "🇨🇳 大陆偏好已写入配置；Homebrew USTC 镜像已写入 shell profile；转录模型优先走 ModelScope 已验证源。"
else
  echo "国内网络慢可加："
  echo "  python3 scripts/transcribe.py --set-default-cn on"
fi
echo ""
