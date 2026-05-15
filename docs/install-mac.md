# macOS 详细安装指南

> 一句话：跑 `bash scripts/install-mac.sh` 就完事，下面是出问题时的备份方案。

---

## 0. 你的 Mac 是 Apple Silicon 还是 Intel？

打开终端跑：

```bash
uname -m
```

- 输出 `arm64` → **Apple Silicon**（M1/M2/M3/M4），最佳体验，用 mlx-whisper GPU 加速
- 输出 `x86_64` → **Intel Mac**，仍然能用，走 whisper-ctranslate2 CPU 后端，速度约 1-2x 实时

---

## 1. 装 Homebrew（如果还没装）

Homebrew 是 macOS 的"软件商店"，装一次终身受用。

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

**🇨🇳 大陆用户推荐用 USTC 镜像安装**（避免 `raw.githubusercontent.com` 超时）：

```bash
/bin/bash -c "$(curl -fsSL https://mirrors.ustc.edu.cn/misc/brew-install.sh)"
```

装完后按提示把 brew 加到 PATH（脚本会告诉你贴哪两行进 `~/.zshrc`）。

验证：

```bash
brew --version
```

应该输出类似 `Homebrew 4.x.x`。

---

## 2. 用 Homebrew 装三个核心依赖

```bash
brew install ffmpeg uv pandoc
```

**🇨🇳 大陆用户**：直接跑 `bash scripts/install-mac.sh` 会自动检测时区/语言，命中大陆就**自动启用 USTC 镜像**（`HOMEBREW_API_DOMAIN` / `HOMEBREW_BOTTLE_DOMAIN` / `HOMEBREW_BREW_GIT_REMOTE` / `HOMEBREW_CORE_GIT_REMOTE`），bottle 下载会快很多。也可以手动 `--cn` / `--no-cn` 强制开关：

```bash
bash scripts/install-mac.sh --cn      # 强制启用大陆镜像
bash scripts/install-mac.sh --no-cn   # 强制走官方源
```

如果你想长期让 `brew install` 走 USTC（不只是装 Murmur 时），把下面四行加到 `~/.zshrc`：

```bash
export HOMEBREW_API_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles/api"
export HOMEBREW_BOTTLE_DOMAIN="https://mirrors.ustc.edu.cn/homebrew-bottles"
export HOMEBREW_BREW_GIT_REMOTE="https://mirrors.ustc.edu.cn/brew.git"
export HOMEBREW_CORE_GIT_REMOTE="https://mirrors.ustc.edu.cn/homebrew-core.git"
```

各自的作用：

| 工具 | 作用 | 必需？ |
|---|---|---|
| `ffmpeg` | 把任意音频格式转成 16k 单声道 WAV | ✅ 必需 |
| `uv` | 跑 Python 工具不污染全局环境 | ✅ 必需 |
| `pandoc` | Markdown → Word 转换 | ⚠️ 仅当默认输出 docx 时需要，建议装 |

---

## 3. 验证

```bash
cd /path/to/murmur
bash scripts/doctor.sh
```

全 ✅ 就可以开始转录了。

---

## 4. 常见 macOS 特定问题

### Q：`brew install` 卡在 "Updating Homebrew..."

国内网络问题。换源：

```bash
# 用清华源
git -C "$(brew --repo)" remote set-url origin https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/brew.git
git -C "$(brew --repo homebrew/core)" remote set-url origin https://mirrors.tuna.tsinghua.edu.cn/git/homebrew/homebrew-core.git
brew update
```

### Q：M 系列芯片，但 doctor 显示用 whisper-ctranslate2 而不是 mlx-whisper？

可能你装的是 Rosetta 版的 Homebrew。检查：

```bash
which brew
# Apple Silicon 原生：/opt/homebrew/bin/brew
# Rosetta：           /usr/local/bin/brew
```

如果是后者，建议重装 Homebrew 到 `/opt/homebrew`。

### Q：mlx-whisper 第一次跑很慢？

第一次 `uvx --from mlx-whisper mlx_whisper` 会做两件事：

1. 用 uv 装 mlx-whisper 的 Python 依赖（约 1-2 分钟）
2. 从 HuggingFace 下载 whisper-large-v3 模型（约 2.9GB，国内可能要 5-30 分钟）

之后所有运行都是秒级冷启动。

### Q：HuggingFace 下载慢/失败？

最简单：跑 `transcribe.py` 时加 `--cn`，它会自动给 whisper 子进程注入 `HF_ENDPOINT=https://hf-mirror.com` 和清华 PyPI 镜像（影响 uv 拉 mlx-whisper / whisper-ctranslate2 本身）：

```bash
python scripts/transcribe.py 录音.m4a --cn
```

脚本默认也会按时区/语言自动判断；显式 `--cn` / `--no-cn` 只是用来强制开关。

想让所有命令长期生效（包括手动 `uvx` 调试）：

```bash
export HF_ENDPOINT=https://hf-mirror.com
# 写入 ~/.zshrc（用 grep 防重复）
grep -q '^export HF_ENDPOINT=' ~/.zshrc 2>/dev/null || echo 'export HF_ENDPOINT=https://hf-mirror.com' >> ~/.zshrc
```

设完重跑 `transcribe.py`。

### Q：报错 "Operation not permitted"（macOS 14+）？

把终端给"完全磁盘访问"权限：系统设置 → 隐私与安全 → 完全磁盘访问 → 添加 Terminal/iTerm。

### Q：电池模式下转录变慢？

macOS 在电池模式下会限制 mlx 性能。插上电源跑。

---

## 5. 完全卸载

```bash
# 删模型缓存（约 3GB）
rm -rf ~/.cache/huggingface/hub/models--mlx-community--whisper-large-v3-mlx
rm -rf ~/.cache/huggingface/hub/models--Systran--faster-whisper-large-v3

# 删 Murmur 配置
rm -rf ~/.config/murmur

# 删 uvx 装的 mlx-whisper 缓存
rm -rf ~/.cache/uv

# 工具本身（如果不再用）
brew uninstall ffmpeg uv pandoc
```
