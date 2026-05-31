#!/usr/bin/env bash
# Murmur env doctor — macOS / Linux
# 检查 ffmpeg / uv / pandoc / python3 / 平台 / 模型缓存
# 故意不开 set -e/-u —— 体检脚本就是要把所有问题报完，而不是遇到第一个就退
#
# 用法：
#   bash scripts/doctor.sh              # 只跑依赖体检
#   bash scripts/doctor.sh --smoke      # 体检 + 端到端烟雾测试（生成 2 秒音频跑完整 pipeline）

SMOKE_MODE="no"
STRICT_MODE="no"
for arg in "$@"; do
  case "$arg" in
    --smoke) SMOKE_MODE="yes" ;;
    --strict) STRICT_MODE="yes" ;;
    -h|--help)
      echo "用法: bash scripts/doctor.sh [--smoke] [--strict]"
      echo "  --smoke   除常规体检外，生成 2 秒测试音频跑一遍完整 pipeline"
      echo "  --strict  核心依赖缺失或 onboarding 未完成时返回非 0"
      exit 0
      ;;
    *) echo "⚠️  忽略未知参数：$arg" ;;
  esac
done

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ok()   { printf '%b\n' "${GREEN}✅${NC} $1"; }
warn() { printf '%b\n' "${YELLOW}⚠️ ${NC} $1"; }
err()  { printf '%b\n' "${RED}❌${NC} $1"; }
info() { printf '%b\n' "${BLUE}ℹ️ ${NC} $1"; }

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
echo "--------------------------------"
echo "核心依赖状态"
echo "--------------------------------"
CORE_OK=1
ONBOARDING_OK=0

# ---------- ffmpeg ----------
if command -v ffmpeg >/dev/null 2>&1; then
  VER=$(ffmpeg -version 2>&1 | head -n1 | awk '{print $3}')
  ok "ffmpeg 已安装（${VER}）"
else
  err "ffmpeg 未安装"
  CORE_OK=0
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
  ok "uv 已安装（${VER}）"
else
  err "uv 未安装"
  CORE_OK=0
  if [[ "$OS" == "Darwin" ]]; then
    echo "    → 安装：brew install uv  （或 curl -LsSf https://astral.sh/uv/install.sh | sh）"
  else
    echo "    → 安装：curl -LsSf https://astral.sh/uv/install.sh | sh"
  fi
fi

# ---------- pandoc ----------
if command -v pandoc >/dev/null 2>&1; then
  VER=$(pandoc --version 2>&1 | head -n1 | awk '{print $2}')
  ok "pandoc 已安装（${VER}）—— md→docx 转换可用"
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
    ok "python3 已安装（${VER}）"
  else
    warn "python3 版本偏低（${VER}），建议 3.9+"
  fi
else
  err "python3 未安装"
  CORE_OK=0
  if [[ "$OS" == "Darwin" ]]; then
    echo "    → macOS 自带 python3；如缺失：brew install python@3.11"
  else
    echo "    → Ubuntu/Debian: sudo apt install python3"
  fi
fi

# ---------- 模型缓存 ----------
MURMUR_MODEL_CACHE="${MURMUR_MODEL_CACHE:-$HOME/.cache/murmur/models}"
if [[ -d "$MURMUR_MODEL_CACHE" ]]; then
  MS_SIZE=$(du -sh "$MURMUR_MODEL_CACHE" 2>/dev/null | awk '{print $1}')
  if find "$MURMUR_MODEL_CACHE" -maxdepth 2 \( -name "weights.safetensors" -o -name "model.bin" \) 2>/dev/null | grep -q .; then
    ok "Murmur / ModelScope 模型缓存已存在（${MS_SIZE}）"
  else
    info "Murmur / ModelScope 缓存目录存在，但暂未发现已验证模型权重"
  fi
else
  info "Murmur / ModelScope 模型缓存尚未建立；大陆环境会优先下载已验证 ModelScope 模型"
fi

HF_CACHE="${HF_HOME:-$HOME/.cache/huggingface}/hub"
if [[ -d "$HF_CACHE" ]]; then
  SIZE=$(du -sh "$HF_CACHE" 2>/dev/null | awk '{print $1}')
  if find "$HF_CACHE" -name "*whisper*large-v3*" 2>/dev/null | grep -q .; then
    ok "HuggingFace 缓存已含 whisper-large-v3 模型（${SIZE}）"
  else
    info "HuggingFace 缓存目录存在但未含 large-v3；无 ModelScope 映射时可能需要从 HuggingFace 下载"
  fi
else
  info "HuggingFace 缓存尚未建立；大陆环境应优先走 ModelScope，而不是先撞 HuggingFace"
  info "国内网络慢优先用：python3 scripts/transcribe.py 录音.m4a --model-source modelscope"
fi

# ---------- Murmur 配置 ----------
echo ""
echo "--------------------------------"
echo "Murmur onboarding 状态"
echo "--------------------------------"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if command -v python3 >/dev/null 2>&1; then
  CONFIG_STATUS=$(PYTHONPATH="$SCRIPT_DIR" python3 - <<'PY'
import config
cfg = config.load()
print(config.config_path())
print(cfg.get('default_format', '?'))
print(cfg.get('default_model', '?'))
print(config.get_cn_mode())
print('done' if not config.needs_onboarding() else 'needs')
PY
)
  CONFIG_FILE=$(printf '%s
' "$CONFIG_STATUS" | sed -n '1p')
  FORMAT=$(printf '%s
' "$CONFIG_STATUS" | sed -n '2p')
  MODEL=$(printf '%s
' "$CONFIG_STATUS" | sed -n '3p')
  CN_MODE=$(printf '%s
' "$CONFIG_STATUS" | sed -n '4p')
  ONBOARD_STATE=$(printf '%s
' "$CONFIG_STATUS" | sed -n '5p')
  if [[ "$ONBOARD_STATE" == "done" ]]; then
    ONBOARDING_OK=1
    ok "Murmur onboarding 已完成（默认格式：${FORMAT}，默认模型：${MODEL}）"
  else
    warn "Murmur onboarding 未完成（配置：${CONFIG_FILE}）"
    info "下一步必须运行：python3 scripts/transcribe.py --onboarding"
    info "Agent：看到 needs_onboarding=true 后必须用候选框询问用户，再运行 --init-defaults"
  fi
  case "$CN_MODE" in
    on) ok "大陆偏好：on（每次转录优先启用 ModelScope 已验证模型；无映射时启用 HF/PyPI 镜像）" ;;
    off) info "大陆模型/镜像偏好：off（每次转录走官方源；国内慢可改：python3 scripts/transcribe.py --set-default-cn on）" ;;
    *) info "大陆模型/镜像偏好：auto（按时区/语言自动判断；强制开：python3 scripts/transcribe.py --set-default-cn on）" ;;
  esac
else
  warn "无法读取 Murmur onboarding 状态：python3 未安装"
fi

echo ""
echo "================================"
if [[ "$CORE_OK" == "1" && "$ONBOARDING_OK" == "1" ]]; then
  ok "核心环境和 onboarding 均就绪，可以开始转录！"
  echo "    试试：python3 scripts/transcribe.py 你的录音.m4a"
elif [[ "$CORE_OK" == "1" ]]; then
  warn "核心环境就绪，但 onboarding 未完成，暂不能开始转录。"
  echo "    下一步必须运行：python3 scripts/transcribe.py --onboarding"
else
  err "缺少核心依赖，请按上方提示安装；或一键跑：bash scripts/install-mac.sh"
  if [[ "$SMOKE_MODE" == "yes" ]]; then
    err "依赖缺失，跳过 --smoke 端到端测试"
    exit 1
  fi
fi
if [[ "$STRICT_MODE" == "yes" && ( "$CORE_OK" != "1" || "$ONBOARDING_OK" != "1" ) ]]; then
  exit 1
fi
echo "================================"
echo ""

# ---------- 烟雾测试（--smoke）----------
if [[ "$SMOKE_MODE" != "yes" ]]; then
  exit 0
fi

echo "================================"
echo "  烟雾测试 (--smoke)"
echo "================================"
echo ""
info "生成 2 秒测试音频 → 跑完整 pipeline → 校验输出"
if [[ "$ENGINE" == "mlx-whisper" ]] && python3 "$SCRIPT_DIR/cn_env.py" --should-mirror >/dev/null 2>&1; then
  SMOKE_MODEL="large-v3-turbo"
  SMOKE_MODEL_SOURCE="modelscope"
  info "大陆 Apple Silicon smoke：用 ModelScope large-v3-turbo 4bit（约 464MB；首次会下载，之后秒级）"
else
  SMOKE_MODEL="tiny"
  SMOKE_MODEL_SOURCE="hf"
  info "用 tiny 模型（约 75MB；首次会下载，之后秒级）"
fi
echo ""

SMOKE_DIR="$(mktemp -d -t murmur-smoke.XXXXXX)"
SMOKE_AUDIO="$SMOKE_DIR/smoke.m4a"
SMOKE_KEEP="no"

cleanup() {
  if [[ "$SMOKE_KEEP" == "yes" ]]; then
    warn "保留调试目录：$SMOKE_DIR"
  else
    rm -rf "$SMOKE_DIR" 2>/dev/null
  fi
}
trap cleanup EXIT

# 1) 生成 2 秒测试音频
info "[1/3] 生成测试音频..."
if [[ "$OS" == "Darwin" ]] && command -v say >/dev/null 2>&1; then
  # macOS: 用 say 合成中文，能同时验证转录质量
  TMP_AIFF="$SMOKE_DIR/smoke.aiff"
  if ! say -v Tingting "Murmur 烟雾测试" -o "$TMP_AIFF" 2>/dev/null; then
    # Tingting 可能没装，退回默认嗓
    say "Murmur smoke test" -o "$TMP_AIFF" 2>/dev/null || {
      err "say 命令失败"
      SMOKE_KEEP="yes"; exit 2
    }
  fi
  ffmpeg -y -i "$TMP_AIFF" -ar 44100 -ac 1 -c:a aac "$SMOKE_AUDIO" >/dev/null 2>&1 || {
    err "ffmpeg 转换 aiff → m4a 失败"
    SMOKE_KEEP="yes"; exit 2
  }
  rm -f "$TMP_AIFF"
else
  # Linux / 无 say：用 ffmpeg 合成 2 秒 440Hz 正弦波
  # 注：sine 在 whisper 上不会出文本，但 pipeline 跑通即 PASS
  ffmpeg -y -f lavfi -i "sine=frequency=440:duration=2" -ar 44100 -ac 1 -c:a aac "$SMOKE_AUDIO" >/dev/null 2>&1 || {
    err "ffmpeg lavfi 生成测试音频失败"
    SMOKE_KEEP="yes"; exit 2
  }
fi
ok "测试音频已生成：$SMOKE_AUDIO ($(du -h "$SMOKE_AUDIO" | awk '{print $1}'))"
echo ""

# 2) 跑 transcribe.py（临时配置，避免污染用户默认配置）
info "[2/3] 跑 transcribe.py（临时配置 --model ${SMOKE_MODEL} --model-source ${SMOKE_MODEL_SOURCE} --format md）..."
SMOKE_CONFIG_HOME="$SMOKE_DIR/config"
if ! XDG_CONFIG_HOME="$SMOKE_CONFIG_HOME" python3 "$SCRIPT_DIR/transcribe.py" \
       --init-defaults --format md --set-default-model "$SMOKE_MODEL" \
       >"$SMOKE_DIR/init.log" 2>&1; then
  err "临时 onboarding 初始化失败。日志："
  cat "$SMOKE_DIR/init.log" | sed 's/^/    /'
  SMOKE_KEEP="yes"; exit 3
fi
START_TS=$(date +%s)
if ! XDG_CONFIG_HOME="$SMOKE_CONFIG_HOME" python3 "$SCRIPT_DIR/transcribe.py" "$SMOKE_AUDIO" \
       --model "$SMOKE_MODEL" --model-source "$SMOKE_MODEL_SOURCE" --format md --output-dir "$SMOKE_DIR" \
       >"$SMOKE_DIR/transcribe.log" 2>&1; then
  err "transcribe.py 失败（exit=$?）。日志末尾："
  tail -20 "$SMOKE_DIR/transcribe.log" | sed 's/^/    /'
  SMOKE_KEEP="yes"; exit 3
fi
END_TS=$(date +%s)
ELAPSED=$((END_TS - START_TS))
ok "转录完成（耗时 ${ELAPSED}s）"
echo ""

# 3) 校验产物
info "[3/3] 校验输出文件..."
TXT="$SMOKE_DIR/转录原稿.txt"
SRT="$SMOKE_DIR/字幕.srt"
FAIL=0
if [[ -f "$TXT" ]]; then
  ok "转录原稿.txt 存在（$(wc -c <"$TXT" | tr -d ' ') bytes）"
  CONTENT=$(head -c 200 "$TXT")
  if [[ -n "$CONTENT" ]]; then
    info "    内容预览：$CONTENT"
  else
    warn "    内容为空（正弦波音频无可识别语音，pipeline 跑通即 PASS）"
  fi
else
  err "转录原稿.txt 不存在！实际产物："
  ls -la "$SMOKE_DIR" 2>&1 | sed 's/^/    /'
  err "transcribe.py 日志末尾："
  tail -30 "$SMOKE_DIR/transcribe.log" 2>&1 | sed 's/^/    /'
  SMOKE_KEEP="yes"
  FAIL=1
fi
if [[ -f "$SRT" ]]; then
  ok "字幕.srt 存在（$(wc -c <"$SRT" | tr -d ' ') bytes）"
else
  err "字幕.srt 不存在！"
  SMOKE_KEEP="yes"
  FAIL=1
fi

# 中间 WAV 应该已被自动清理
if [[ -f "$SMOKE_DIR/audio_16k.wav" ]]; then
  warn "中间文件 audio_16k.wav 未被清理（应该被 transcribe.py 自动删）"
fi

echo ""
echo "================================"
if [[ $FAIL -eq 0 ]]; then
  ok "烟雾测试 PASS — 端到端 pipeline 正常工作"
else
  err "烟雾测试 FAIL — 见上方报错"
  exit 4
fi
echo "================================"
echo ""
