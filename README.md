<div align="center">

# 🎙 Murmur

**本地零成本会议 / 面试录音转录 + AI 智能清洗工作流**
**告别飞书妙计 / 通义听悟，30 分钟录音 → Markdown / Word，一行命令搞定**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-blue.svg)](#-环境要求)
[![Made for AI agents](https://img.shields.io/badge/agent--ready-Claude%20Code%20%7C%20Codex%20%7C%20Copilot-purple)](#-给-ai-agent-用的入口skillmd)

中文 · [English](#english)

</div>

---

## ✨ 是什么

把任意一段 **会议 / 面试 / 课堂 / 播客录音** 在自己电脑上转成可读的 **Markdown 或 Word 文档**，过程不联网、不上传、不花钱。

- **本地跑**：模型只下一次（约 3 GB），之后全程离线，敏感内容不出本机
- **足够快**：M2/M3 上 30 分钟录音约 10-15 分钟跑完；Windows / Intel Mac 走 CPU 也能跑
- **足够准**：基于 OpenAI Whisper large-v3 + 中文常见 ASR 错词修正
- **AI agent 友好**：Claude Code / Codex / GitHub Copilot / Cursor 直接读 [SKILL.md](SKILL.md) 就能上手
- **格式自由**：首次使用问一次默认要 `md` 还是 `docx`，之后随时改主意

---

## 🆚 和飞书妙计 / 通义听悟比

| | 飞书妙计 | 通义听悟 | **Murmur** |
|---|---|---|---|
| 单次费用 | 约 ¥0.5/分钟 | 约 ¥0.3/分钟 | **¥0** |
| 数据隐私 | 上传云端 | 上传云端 | **全程本地** |
| 离线可用 | ❌ | ❌ | **✅** |
| 自定义清洗 | 模板固定 | 模板固定 | **prompt 完全可改** |
| 输出 docx | ✅ | ✅ | **✅（pandoc）** |
| 跨平台 | Web 全平台 | Web 全平台 | macOS / Windows / Linux |
| 上手成本 | 注册即用 | 注册即用 | 一次环境配置（5 分钟） |

> 适合谁：**经常开会、做用研、做面试、做内容采访**，需要批量转录又不愿意为云端服务持续付费的同学。

---

## 🚀 三分钟上手

### 1. 下载本仓库

```bash
git clone https://github.com/xiaopengde/murmur.git
cd murmur
```

### 2. 一键安装环境（自动检测系统）

**macOS**：

```bash
bash scripts/install-mac.sh
```

**Windows**（PowerShell 管理员模式）：

```powershell
powershell -ExecutionPolicy Bypass -File scripts/install-windows.ps1
```

**Linux**：参考 [docs/install-windows.md](docs/install-windows.md) 末尾的 Linux 章节，命令几乎一致。

安装会装：`ffmpeg`（音频处理）、`uv`（Python 工具运行）、`pandoc`（md→docx）。

### 3. 检查环境

```bash
# Mac/Linux
bash scripts/doctor.sh

# Windows
powershell -ExecutionPolicy Bypass -File scripts/doctor.ps1
```

全 ✅ 即可。如果有 ❌ 看 [docs/troubleshooting.md](docs/troubleshooting.md)。

### 4. 转录第一段音频

```bash
python scripts/transcribe.py 你的录音.m4a
```

**首次跑会问你**：

```
首次使用 Murmur 👋
以后默认输出格式选哪个？
  [1] markdown (.md)  — 程序员 / VS Code / Notion 友好
  [2] word (.docx)    — 通用，能直接发给同事
请输入 1 或 2：
```

选完之后这个偏好会存到 `~/.config/murmur/config.json`，下次不再问。**任何时候**想改：

```bash
python scripts/transcribe.py --set-default md     # 改默认为 md
python scripts/transcribe.py --set-default docx   # 改默认为 docx
python scripts/transcribe.py 录音.m4a --format md   # 临时只这一次用 md
```

### 5. 让 AI 清洗成可读文档

转录完会得到 `转录原稿.txt` 和 `字幕.srt`。原稿是裸文本，没有段落、说话人、错字也没修。

把 [docs/prompts/clean-transcript.md](docs/prompts/clean-transcript.md) 的内容连同 `转录原稿.txt` 一起喂给任意 LLM（ChatGPT / Claude / 国内大模型 / VS Code Copilot 都行），就能拿到带说话人标签、修过错字、分好章节的可读 Markdown。

如果默认格式是 docx，再跑一下：

```bash
python scripts/md2docx.py 逐字稿-清洗版.md
```

---

## 🤖 给 AI agent 用的入口（SKILL.md）

如果你已经在用 **Claude Code / OpenAI Codex / GitHub Copilot Agent / Cursor**，直接把整个 repo clone 到工作区或 skills 目录，agent 会自动识别 [SKILL.md](SKILL.md)，你只要说一句：

> "用 Murmur 帮我把 `xxx.m4a` 转成可读的会议纪要"

它会自己跑 doctor → 跑 transcribe → 清洗 → 输出 md/docx。整个过程你只需要在它问 "默认格式 md 还是 docx" 时回一个字。

支持的 agent 平台：

- ✅ **GitHub Copilot Agent**（VS Code 内置 + 云端 agent）
- ✅ **Claude Code**（CLI）
- ✅ **OpenAI Codex CLI**
- ✅ **Cursor**
- ✅ 任何遵循 [agentskills.io](https://agentskills.io) 开放标准的 agent

---

## 📂 仓库结构

```
murmur/
├── README.md                          ← 你现在看的这个
├── SKILL.md                           ← AI agent 入口
├── LICENSE                            ← MIT
├── docs/
│   ├── install-mac.md                 ← macOS 详细安装说明
│   ├── install-windows.md             ← Windows 详细安装说明
│   ├── troubleshooting.md             ← 故障排查
│   └── prompts/
│       ├── clean-transcript.md        ← 喂给 LLM 的清洗 prompt
│       └── retrospective.md           ← 喂给 LLM 的复盘 prompt（可选）
├── scripts/
│   ├── doctor.sh / doctor.ps1         ← 环境检查
│   ├── install-mac.sh                 ← macOS 一键安装
│   ├── install-windows.ps1            ← Windows 一键安装
│   ├── transcribe.py                  ← 主入口（跨平台）
│   ├── md2docx.py                     ← Markdown → Word
│   └── config.py                      ← 默认格式配置管理
└── examples/
    └── sample-clean-output.md         ← 清洗后效果示例
```

---

## 🧠 工作原理

```
┌──────────────┐   ffmpeg     ┌──────────────────┐
│ 你的 .m4a /  │ ───────────► │ 16kHz 单声道 WAV │
│ .mp3 / .mp4  │              │ (临时)           │
└──────────────┘              └────────┬─────────┘
                                       │
                                       ▼
                ┌──────────────────────────────────┐
                │  本地 Whisper large-v3           │
                │  • Apple Silicon: mlx-whisper    │
                │  • Win/Linux/x86 Mac:            │
                │    whisper-ctranslate2           │
                └────────┬─────────────────────────┘
                         │
                         ▼
              ┌──────────────────────────┐
              │  转录原稿.txt + 字幕.srt │
              └────────┬─────────────────┘
                       │
                       ▼
              ┌──────────────────────────────────┐
              │  你 / AI agent 用清洗 prompt     │
              │  (docs/prompts/clean-transcript) │
              └────────┬─────────────────────────┘
                       │
                       ▼
              ┌──────────────────────────┐
              │  逐字稿-清洗版.md         │
              │  (含说话人 / 修字 / 分段)│
              └────────┬─────────────────┘
                       │ 默认 docx 时再跑一步
                       ▼
              ┌──────────────────────────┐
              │  逐字稿-清洗版.docx       │
              └──────────────────────────┘
```

---

## 🛠 环境要求

| | 最低 | 推荐 |
|---|---|---|
| **macOS** | macOS 12+ Apple Silicon | M2/M3/M4 + 16GB RAM |
| **Windows** | Windows 10/11 + 8GB RAM | + NVIDIA GPU（CUDA 加速） |
| **Linux** | 任意 + Python 3.9+ | x86_64 + 16GB RAM |
| **磁盘** | 模型缓存约 3GB | 5GB |
| **网络** | 首次下模型联网一次 | 之后离线 |

---

## ❓ 常见问题

**Q：模型有多大？下载慢怎么办？**
A：large-v3 约 2.9GB。国内首次下慢的话，设置 HuggingFace 镜像：

- Mac/Linux: `export HF_ENDPOINT=https://hf-mirror.com`
- Windows: `$env:HF_ENDPOINT="https://hf-mirror.com"`

**Q：能转英语 / 日语 / 其他语言吗？**
A：能。`python scripts/transcribe.py 录音.m4a --lang en`，支持 Whisper 的全部 99 种语言。默认 `zh`。

**Q：能识别说话人吗？**
A：mlx-whisper / whisper-ctranslate2 不带 diarization。Murmur 的策略是**让 LLM 在清洗阶段从上下文推断说话人**（面试场景非常准），多人混乱场景标 `**说话人 1/2/3**` 占位即可。如果对 diarization 有硬需求，issue 里讨论。

**Q：录音超过 1 小时会不会出问题？**
A：不会，但建议拆段。本地 Whisper 在长音频上偶发幻觉循环，本工具已经默认开了 `--condition-on-previous-text False` 来防这个，但更稳妥还是分段。

**Q：可以商用吗？**
A：MIT License，可以。Whisper 模型本身是 MIT 开源，没有商用限制。

完整 FAQ 看 [docs/troubleshooting.md](docs/troubleshooting.md)。

---

## 🌟 喜欢就给个 Star

如果这个工具帮你省下了开会议软件的钱，欢迎：

- ⭐ Star 这个仓库
- 🔄 转发给同样被云转录服务收费心累的朋友
- 🐛 Issue 区报 bug / 提需求

---

## 📜 License

[MIT](LICENSE) © 2026 [Connor Pax](https://github.com/xiaopengde)

底层依赖：
- [openai-whisper](https://github.com/openai/whisper) — MIT
- [mlx-whisper](https://github.com/ml-explore/mlx-examples) — MIT (Apple)
- [whisper-ctranslate2](https://github.com/Softcatala/whisper-ctranslate2) — MIT
- [pandoc](https://pandoc.org) — GPL-2.0+

---

<a name="english"></a>

## English (Brief)

**Murmur** is a free, fully-local audio → markdown/docx pipeline that replaces SaaS transcription services like Otter.ai or Fireflies.ai. It runs Whisper large-v3 on your own Mac/Windows/Linux machine and uses any LLM (online or local) to clean the raw transcript into a readable document with speaker labels.

- **Cross-platform**: macOS (Apple Silicon → mlx-whisper, Intel → whisper-ctranslate2), Windows, Linux
- **AI-agent native**: ships with [SKILL.md](SKILL.md) for Claude Code / OpenAI Codex / GitHub Copilot / Cursor
- **Format choice**: prompts you once for default md vs docx, persisted across runs, switchable anytime
- **Privacy-first**: no audio ever leaves your machine

Quick start: see the Chinese section above, or just clone and run `bash scripts/install-mac.sh` (Mac) / `scripts/install-windows.ps1` (Win) → `python scripts/transcribe.py your-recording.m4a`.
