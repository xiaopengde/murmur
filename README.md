# Murmur

本地零成本会议 / 面试录音转录 + AI 智能清洗工作流。告别飞书妙计 / 通义听悟，30 分钟录音直接出 Markdown 或 Word，给 AI agent 一句话就能跑完。

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Platform](https://img.shields.io/badge/platform-macOS%20%7C%20Windows%20%7C%20Linux-blue.svg)](#环境要求)
[![Agent ready](https://img.shields.io/badge/agent--ready-Claude%20Code%20%7C%20Codex%20%7C%20Copilot%20%7C%20Cursor-purple)](#上手在你的-ai-agent-里调用)

中文 · [English](#english-brief)

---

## 这是什么

把任意一段会议 / 面试 / 课堂 / 播客录音在自己电脑上转成可读的 Markdown 或 Word 文档：

- **本地跑**：模型只下一次（约 3GB），之后全程离线，敏感内容不出本机
- **足够快**：M2/M3 上 30 分钟录音约 10-15 分钟跑完；Windows / Intel Mac CPU 也能跑
- **足够准**：基于 OpenAI Whisper large-v3 + 中文常见 ASR 错词修正
- **AI agent 原生**：给 Claude Code / Codex / GitHub Copilot / Cursor 一句话，端到端跑完整流程
- **格式自由**：首次问一次默认要 md 还是 docx，之后随时改

---

## 和飞书妙计 / 通义听悟比

| | 飞书妙计 | 通义听悟 | Murmur |
|---|---|---|---|
| 单次费用 | 约 ¥0.5/分钟 | 约 ¥0.3/分钟 | 0 |
| 数据隐私 | 上传云端 | 上传云端 | 全程本地 |
| 离线可用 | 否 | 否 | 是 |
| 自定义清洗 | 模板固定 | 模板固定 | prompt 完全可改 |
| 输出 docx | 是 | 是 | 是（pandoc）|
| 跨平台 | Web 全平台 | Web 全平台 | macOS / Windows / Linux |

---

## 上手：在你的 AI agent 里调用

Murmur 是一个 **agent skill**。最快的安装方式：**把下面这句话复制到你的 agent 对话框**，它会自己判断该装到哪个目录：

> **请帮我安装这个 skill 到本地：https://github.com/xiaopengde/murmur**

agent 会自动识别你用的是 Claude Code / Copilot / Cursor / Codex，clone 到对应的 skills 目录，然后告诉你"装好了"。之后跟它说"用 Murmur 转一下 xxx.m4a"就行。

### 手动指定安装位置（可选）

如果你想自己控制装到哪：

| Agent | 推荐安装位置 |
|---|---|
| **Claude Code** | `~/.claude/skills/`（全局，所有项目可用）|
| **GitHub Copilot Agent**（VS Code）| `<你的项目>/.github/skills/` |
| **Cursor** | `~/.cursor/skills/` 或 `<项目>/.cursor/skills/` |
| **OpenAI Codex CLI** | `<项目>/.agents/skills/` |
| 任意支持 [agentskills.io](https://agentskills.io) 标准的 agent | `~/.agents/skills/` |

clone 到对应目录，例如以 Claude Code 全局安装为例：

```bash
mkdir -p ~/.claude/skills && cd ~/.claude/skills
git clone https://github.com/xiaopengde/murmur.git
```

VS Code Copilot 用户在自己的工作区里：

```bash
cd <你的工作区>
mkdir -p .github/skills && cd .github/skills
git clone https://github.com/xiaopengde/murmur.git
```

### 装完之后，在 agent 对话框里说一句话

> **"用 Murmur 把 `~/Desktop/会议.m4a` 转成纪要"**

agent 会自动按 [SKILL.md](SKILL.md) 走完整套流程：

1. 跑 `doctor` 体检脚本，看你环境缺什么
2. 缺啥装啥（Mac 跑 `install-mac.sh`，Win 跑 `install-windows.ps1`）
3. **首次**会问你"以后默认 md 还是 docx？"——你回 1 或 2 即可
4. 跑转录（首次会下载约 2.9GB 模型，之后离线）
5. 用 LLM 自动清洗成可读 Markdown（带说话人、修错字、分章节）
6. 默认 docx 时再转 Word

**整个过程只需要一次用户交互**（首次的格式选择），之后无人值守。

### 常用对话清单

| 你想做什么 | 跟 agent 说 |
|---|---|
| 转一段录音 | "用 Murmur 转 `xxx.m4a`" |
| 临时换格式 | "这次输出 md，不改默认" |
| 改默认格式 | "Murmur 改成默认 docx"（或 md）|
| 看当前默认 | "Murmur 现在默认是什么格式" |
| 顺便出复盘 | "用 Murmur 转 `面试.m4a`，再出一份复盘纪要" |

agent 会自己翻译成对应命令跑。

---

## 不用 agent，纯命令行也行

如果你不想用 AI agent，想自己手工跑：

**macOS**：

```bash
git clone https://github.com/xiaopengde/murmur.git && cd murmur
bash scripts/install-mac.sh
python3 scripts/transcribe.py 你的录音.m4a
```

**Windows**（管理员 PowerShell）：

```powershell
git clone https://github.com/xiaopengde/murmur.git ; cd murmur
powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
python scripts\transcribe.py 你的录音.m4a
```

转录完会得到 `转录原稿.txt` + `字幕.srt`。把 [docs/prompts/clean-transcript.md](docs/prompts/clean-transcript.md) 的内容连同 `转录原稿.txt` 一起喂给任意 LLM（ChatGPT / Claude / 国内大模型都行），就能得到清洗后的 Markdown 文档。如果你设了默认 docx，再跑一下 `python scripts/md2docx.py 逐字稿-清洗版.md` 转 Word。

完整命令参考：

```bash
python scripts/transcribe.py 录音.m4a                       # 默认配置
python scripts/transcribe.py 录音.m4a --format md           # 单次覆盖输出格式
python scripts/transcribe.py 录音.m4a --lang en             # 改语言（默认 zh）
python scripts/transcribe.py --set-default md               # 改永久默认格式
python scripts/transcribe.py --set-default docx
python scripts/transcribe.py --show-config                  # 看当前配置
python scripts/md2docx.py 逐字稿-清洗版.md                  # md → Word
```

---

## 仓库结构

```
murmur/
├── README.md                          ← 你现在看的这个
├── SKILL.md                           ← agent 入口（agent 自动读这个）
├── LICENSE                            ← MIT
├── docs/
│   ├── install-mac.md                 ← macOS 详细安装说明
│   ├── install-windows.md             ← Windows / Linux / WSL 详细安装说明
│   ├── troubleshooting.md             ← 故障排查
│   └── prompts/
│       ├── clean-transcript.md        ← 给 LLM 的清洗 prompt
│       └── retrospective.md           ← 给 LLM 的复盘 prompt（可选）
├── scripts/
│   ├── doctor.sh / doctor.ps1         ← 环境体检
│   ├── install-mac.sh                 ← macOS 一键安装
│   ├── install-windows.ps1            ← Windows 一键安装
│   ├── transcribe.py                  ← 主入口（跨平台）
│   ├── md2docx.py                     ← Markdown → Word
│   └── config.py                      ← 默认格式配置管理
└── examples/
    └── sample-clean-output.md         ← 清洗后效果示例
```

---

## 工作原理

```
你的 .m4a / .mp3 / .mp4
        │
        │  ffmpeg
        ▼
16kHz 单声道 WAV（临时）
        │
        │  本地 Whisper large-v3
        │   ├─ Apple Silicon → mlx-whisper（GPU 加速）
        │   └─ Win/Linux/Intel Mac → whisper-ctranslate2（CPU/CUDA）
        ▼
转录原稿.txt + 字幕.srt
        │
        │  你 / agent 用清洗 prompt（docs/prompts/clean-transcript.md）
        ▼
逐字稿-清洗版.md（带说话人 / 修字 / 分段）
        │
        │  默认 docx 时再走一步：pandoc
        ▼
逐字稿-清洗版.docx
```

---

## 环境要求

| | 最低 | 推荐 |
|---|---|---|
| **macOS** | macOS 12+ Apple Silicon | M2/M3/M4 + 16GB RAM |
| **Windows** | Windows 10/11 + 8GB RAM | + NVIDIA GPU（CUDA 加速）|
| **Linux** | 任意发行版 + Python 3.9+ | x86_64 + 16GB RAM |
| **磁盘** | 模型缓存约 3GB | 5GB |
| **网络** | 首次下模型联网一次 | 之后离线 |

---

## 常见问题

**Q：模型有多大？下载慢怎么办？**
A：large-v3 约 2.9GB。**国内用户强烈建议先开镜像加速**（一次设置，永久生效）：

```bash
python scripts/transcribe.py --mirror cn
```

这条命令会同时加速 PyPI 包下载（清华镜像）和 HuggingFace 模型下载（hf-mirror.com）。关闭用 `--mirror off`。

**Q：能转英语 / 日语 / 其他语言吗？**
A：能。`python scripts/transcribe.py 录音.m4a --lang en`，支持 Whisper 全部 99 种语言，默认 zh。

**Q：能识别说话人吗？**
A：mlx-whisper / whisper-ctranslate2 都不带说话人分离。Murmur 的策略是让 LLM 在清洗阶段从上下文推断（面试/对话场景非常准），多人混乱场景标 `**说话人 1/2/3**` 占位即可。如果对 diarization 有硬需求，issue 里讨论。

**Q：录音超过 1 小时会不会出问题？**
A：不会，但建议拆段。本地 Whisper 在长音频上偶发幻觉循环，本工具已默认开了 `--condition-on-previous-text False` 防这个，但更稳妥还是分段。

**Q：可以商用吗？**
A：MIT License，可以。Whisper 模型本身也是 MIT 开源，无商用限制。

完整故障排查见 [docs/troubleshooting.md](docs/troubleshooting.md)。

---

## License

[MIT](LICENSE) © 2026 [xiaopengde](https://github.com/xiaopengde)

底层依赖：
- [openai-whisper](https://github.com/openai/whisper) — MIT
- [mlx-whisper](https://github.com/ml-explore/mlx-examples) — MIT (Apple)
- [whisper-ctranslate2](https://github.com/Softcatala/whisper-ctranslate2) — MIT
- [pandoc](https://pandoc.org) — GPL-2.0+

---

## English (brief)

**Murmur** is a free, fully-local audio → markdown/docx pipeline that replaces SaaS transcription services like Otter.ai or Fireflies.ai. It's built **agent-first** — drop it into your AI coding agent's skills directory (Claude Code / Codex / GitHub Copilot / Cursor) and it runs end-to-end with a single natural-language request.

**Quick start (agent-first):** copy this line into your AI agent:

> *Please install this skill locally for me: https://github.com/xiaopengde/murmur*

The agent will detect whether you're on Claude Code / Copilot / Cursor / Codex and clone Murmur into the right skills directory. Then say *"Use Murmur to transcribe ~/Desktop/meeting.m4a into a doc"* and it'll run env doctor, install missing deps, ask you once for default md vs docx, transcribe with Whisper large-v3 (mlx on Apple Silicon, whisper-ctranslate2 elsewhere), and clean the output via LLM into a readable document.

**Manual usage:** `bash scripts/install-mac.sh` (Mac) / `scripts/install-windows.ps1` (Win) → `python scripts/transcribe.py recording.m4a`.

Full docs in Chinese above. PRs welcome.
