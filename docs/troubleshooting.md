# 故障排查

按"症状 → 原因 → 解法"组织。Ctrl+F 搜你看到的关键词。

---

## 转录质量类

### 症状：输出文本反复出现 "X 点 X 点 X 点……" 或某句话整段重复几十次

**原因**：Whisper 的 `condition-on-previous-text` 默认 True，长音频偶发触发自我循环幻觉，是个臭名昭著的老坑。

**解法**：Murmur 的 `transcribe.py` 已默认关掉这个选项。**如果你看到这个症状**说明你没用本工具的脚本，是直接调的 mlx-whisper / whisper。重跑：

```bash
python scripts/transcribe.py 你的录音.m4a
```

### 症状：全程输出 "谢谢观看" 成段重复

**原因**：音频开头有静音段，Whisper 把 YouTube 训练数据的 token 噪音 hallucinate 出来。

**解法**：Murmur 的 `transcribe.py` 会先用 ffmpeg 把音频转成 16kHz 单声道 WAV，已经规避这个问题。手动跑时记得做这一步。

### 症状：英文术语全部识别错（LLM as Judge → NiM as Judge 等）

**原因**：中英混读时 Whisper 偶发用中文谐音去 hallucinate 英文。

**解法**：

1. 确保 `--lang zh` 没改（中文为主的录音用 zh 最稳，纯英文用 `--lang en`）
2. 在 LLM 清洗阶段主动改错（[docs/prompts/clean-transcript.md](prompts/clean-transcript.md) 里有中文录音常见错词表）

### 症状：说话人混在一起，分不出谁是谁

**原因**：Whisper 不带说话人分离（diarization）功能。

**解法**：

- 清洗阶段让 LLM 从上下文（提问/回答语气、第一/二人称）推断
- 多人混乱场景标 `**说话人 1**` / `**说话人 2**` 占位即可
- 如果对 diarization 有硬需求：[pyannote.audio](https://github.com/pyannote/pyannote-audio) 是社区方案，但配置复杂，不在本工具范围内

### 症状：长音频转录到一半内容突然变烂 / 漏段

**原因**：内存压力 / 长音频累积幻觉。

**解法**：用 ffmpeg 拆分：

```bash
# 拆成 15 分钟一段
ffmpeg -i 长录音.m4a -f segment -segment_time 900 -c copy 片段_%03d.m4a
```

然后逐段转录。

---

## 性能类

### 症状：Mac 上转录速度慢得离谱（30 分钟录音跑 30 分钟以上）

**原因**：

1. 没用 mlx-whisper（用成了 openai-whisper PyPI 版）
2. Intel Mac 走的是 CPU
3. 电池模式被节流

**解法**：

- 看 `bash scripts/doctor.sh` 输出的 "将使用：" 是不是 mlx-whisper
- Apple Silicon 但走的不是 mlx-whisper：可能 brew 是 Rosetta 版，重装到 `/opt/homebrew`
- 插上电源

### 症状：Windows 上速度也慢

**原因**：Windows 没有 mlx，只能用 CPU。

**解法**：

- 有 NVIDIA GPU：装 CUDA Toolkit 12.x，whisper-ctranslate2 自动启用 GPU
- 没 GPU：换小模型（编辑 `transcribe.py`，`large-v3` 改 `medium` 或 `small`，速度 3-5x，准确率小降）
- 或拆分长音频并行跑（开多个 PowerShell 窗口）

### 症状：HuggingFace 模型下载卡死 / 失败

**原因**：国内访问 huggingface.co 不稳定。

**解法**：用镜像

```bash
# Mac/Linux
export HF_ENDPOINT=https://hf-mirror.com

# Windows PowerShell
$env:HF_ENDPOINT = "https://hf-mirror.com"
```

设完重跑。模型只下一次，之后离线可用。

---

## 环境类

### 症状：`bash: command not found: brew`（Mac）

**原因**：没装 Homebrew。

**解法**：

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

### 症状：`无法加载文件 ... 因为在此系统上禁止运行脚本`（Windows）

**原因**：PowerShell 执行策略限制。

**解法**：

```powershell
# 临时（仅本次会话）
Set-ExecutionPolicy -Scope Process Bypass

# 永久
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

或每次加 `-ExecutionPolicy Bypass`：

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
```

### 症状：装完 ffmpeg 但跑 `ffmpeg --version` 还是找不到

**原因**：PATH 没刷新。

**解法**：

- Mac：`source ~/.zshrc` 或重开终端
- Windows：**关掉所有 PowerShell 窗口**重新开（包括 VS Code 内置终端）

### 症状：`uvx: command not found` 但已装 uv

**原因**：uv 安装路径没在 PATH 里。

**解法**：

```bash
# Mac/Linux
export PATH="$HOME/.local/bin:$PATH"
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc

# Windows
# 检查 C:\Users\<你>\.local\bin 是否在 %PATH% 里
# 不在的话去系统设置 → 环境变量 加上
```

---

## VS Code / Agent 类

### 症状：在 VS Code Copilot Agent 里跑 `transcribe.py`，跑到一半被 Ctrl+C 杀掉

**原因**：你在同一个持久 zsh 终端里又发了别的命令（看进度、查文件等）—— `send_to_terminal` 会把当前进程中断。

**解法**：

- **新开一个终端**做查询动作
- 或干脆耐心等转录跑完再发任何命令
- `run_in_terminal` 跑 transcribe 时用 `mode='sync'` + 长 timeout（30 分钟录音建议 timeout=1800000ms）

### 症状：Agent 自作主张选了 md 或 docx，没问我

**原因**：你之前已经设过默认值。

**解法**：

```bash
python scripts/transcribe.py --show-config       # 看当前默认
python scripts/transcribe.py --set-default md    # 改成 md
python scripts/transcribe.py --set-default docx  # 改成 docx
python scripts/transcribe.py 录音.m4a --format md  # 单次覆盖
```

---

## 输出类

### 症状：`md2docx.py` 报 "未检测到 pandoc"

**原因**：没装 pandoc。

**解法**：

- Mac: `brew install pandoc`
- Windows: `winget install JohnMacFarlane.Pandoc`
- Linux: `sudo apt install pandoc`

### 症状：转出来的 docx 里中文乱码 / 字体奇怪

**原因**：pandoc 默认用 Calibri，中文系统没这个字体。

**解法**：用自定义字体模板：

```bash
# 生成默认 docx 模板
pandoc -o reference.docx --print-default-data-file reference.docx

# 用 Word 打开 reference.docx，改成你想要的中文字体（推荐：思源宋体 / 微软雅黑），保存

# 之后转换时引用
pandoc 输入.md -o 输出.docx --reference-doc=reference.docx
```

也可以直接编辑 `scripts/md2docx.py` 加 `--reference-doc` 参数。

---

## 还是不行？

[在 GitHub 提 issue](https://github.com/xiaopengde/murmur/issues/new)，附上：

1. `bash scripts/doctor.sh`（或 `scripts/doctor.ps1`）的完整输出
2. 报错的完整命令和报错信息
3. 系统信息（macOS/Windows 版本，是否 Apple Silicon / 有 GPU）
