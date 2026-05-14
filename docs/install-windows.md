# Windows 详细安装指南

> 一句话：用管理员模式 PowerShell 跑 `powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1`，下面是手动安装/出问题时的备份方案。

---

## 0. 前置

- **Windows 10 1809+** 或 **Windows 11**（更老的 Win10 没 winget，得手动装）
- 至少 8GB RAM（16GB 更舒服）
- 5GB 空闲磁盘（模型缓存 ~3GB + 临时 WAV 文件）
- 有 NVIDIA GPU 更好（可选，能跑 CUDA 加速），没有也完全 OK

---

## 1. 打开管理员 PowerShell

按 Win 键 → 输入 `powershell` → 右键"以管理员身份运行"。

如果你装了 Windows Terminal（推荐）：右下角下拉菜单选"以管理员身份打开新选项卡"。

---

## 2. 用 winget 装四件套（推荐）

winget 是 Windows 自带的包管理器（Win10 1809+ / Win11 内置）。

先验证 winget 在不在：

```powershell
winget --version
```

如果报"找不到命令"：去 Microsoft Store 搜 **App Installer** 装一下，重启 PowerShell。

然后一次装完：

```powershell
winget install -e --id Gyan.FFmpeg
winget install -e --id astral-sh.uv
winget install -e --id JohnMacFarlane.Pandoc
winget install -e --id Python.Python.3.11
```

各自作用：

| 工具 | 作用 | 必需？ |
|---|---|---|
| `Gyan.FFmpeg` | 音频格式转换 | ✅ 必需 |
| `astral-sh.uv` | Python 工具运行器 | ✅ 必需 |
| `JohnMacFarlane.Pandoc` | Markdown → Word | ⚠️ 仅当默认 docx 时需要，建议装 |
| `Python.Python.3.11` | Python 解释器 | ✅ 必需（除非已装） |

**装完关掉 PowerShell 重新开**，让 PATH 刷新。

---

## 3. 备选方案 A：用 Scoop

如果你已经在用 Scoop：

```powershell
scoop install ffmpeg uv pandoc python
```

---

## 4. 备选方案 B：用 Chocolatey

```powershell
choco install ffmpeg uv pandoc python -y
```

---

## 5. 备选方案 C：完全手动

| 工具 | 下载地址 |
|---|---|
| ffmpeg | https://www.gyan.dev/ffmpeg/builds/ → 下 "release essentials" |
| uv | PowerShell: `irm https://astral.sh/uv/install.ps1 \| iex` |
| pandoc | https://github.com/jgm/pandoc/releases/latest |
| python | https://python.org（**记得勾选"Add Python to PATH"**） |

手动装的话注意把 ffmpeg.exe 所在目录加到系统 PATH（系统设置 → 关于 → 高级系统设置 → 环境变量）。

---

## 6. 验证

```powershell
cd path\to\murmur
powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1
```

全 ✅ 就可以开始转录了。

---

## 7. 常见 Windows 特定问题

### Q：报错 "无法加载文件 ... 因为在此系统上禁止运行脚本"

PowerShell 默认禁止运行未签名脚本。两种解法：

**临时**（当前会话）：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
```

**永久**（推荐用 RemoteSigned 而不是 Bypass）：

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

或每次跑时加 `-ExecutionPolicy Bypass`：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
```

### Q：装完 ffmpeg 但 `ffmpeg --version` 报找不到

PATH 没刷新。**关掉所有 PowerShell 窗口重新开**。如果还不行，手动添加到 PATH：

```powershell
# 假设 ffmpeg 在 C:\ProgramData\chocolatey\bin\ 或 C:\ffmpeg\bin
$env:Path += ";C:\ffmpeg\bin"
# 永久加要去系统设置改
```

### Q：HuggingFace 下载慢/失败

国内镜像，PowerShell 里设：

```powershell
$env:HF_ENDPOINT = "https://hf-mirror.com"
```

想长期生效，加到 PowerShell profile：

```powershell
notepad $PROFILE
# 在打开的文件里加一行：
# $env:HF_ENDPOINT = "https://hf-mirror.com"
```

### Q：转录速度太慢（30 分钟录音要 1 小时+）？

Windows 走 CPU 转录，本来就比 Apple Silicon GPU 慢。提速选项：

1. **NVIDIA 显卡**：whisper-ctranslate2 自动检测 CUDA。装 CUDA Toolkit 12.x 后会自动用 GPU
2. **换小模型**：编辑 `scripts/transcribe.py`，把 `--model large-v3` 改成 `--model medium` 或 `small`，速度 3-5 倍但准确率有降
3. **拆分长音频**：用 ffmpeg 把 1 小时录音拆成 4 段 15 分钟分别跑

### Q：Python 报 UnicodeDecodeError，处理中文文件名出错

PowerShell / cmd 默认代码页可能不是 UTF-8。设一下：

```powershell
$env:PYTHONIOENCODING = "utf-8"
chcp 65001
```

### Q：用 Git Bash 跑 .sh 脚本可以吗？

技术上可以（Git Bash 自带 bash），但 doctor.sh / install-mac.sh 里有 macOS 专属命令（brew、`uname -s` 判断），跑出来不会按预期工作。**Windows 用户请用 PowerShell 版（doctor.ps1 / install-windows.ps1）**。

---

## 8. WSL 用户

如果你在 WSL2 (Ubuntu) 里跑：

```bash
sudo apt update
sudo apt install ffmpeg pandoc python3 python3-pip
curl -LsSf https://astral.sh/uv/install.sh | sh
```

之后流程跟 Linux 完全一致，跑 `bash scripts/doctor.sh` 验证。注意 WSL 里访问 Windows 文件系统会慢，建议把音频文件放到 WSL 的 home 目录里跑。

---

## 9. Linux（Ubuntu/Debian/Fedora/Arch）

```bash
# Ubuntu / Debian
sudo apt update && sudo apt install ffmpeg pandoc python3
curl -LsSf https://astral.sh/uv/install.sh | sh

# Fedora / RHEL
sudo dnf install ffmpeg pandoc python3
curl -LsSf https://astral.sh/uv/install.sh | sh

# Arch
sudo pacman -S ffmpeg pandoc python uv

# 验证
bash scripts/doctor.sh
```

Linux 也是走 whisper-ctranslate2，CUDA GPU 自动启用。

---

## 10. 完全卸载

```powershell
# 删模型缓存
Remove-Item -Recurse -Force "$env:USERPROFILE\.cache\huggingface\hub\models--Systran--faster-whisper-large-v3" -ErrorAction SilentlyContinue

# 删 Murmur 配置
Remove-Item -Recurse -Force "$env:APPDATA\Murmur" -ErrorAction SilentlyContinue

# 删 uvx 缓存
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\uv" -ErrorAction SilentlyContinue

# 卸载工具
winget uninstall Gyan.FFmpeg
winget uninstall astral-sh.uv
winget uninstall JohnMacFarlane.Pandoc
```
