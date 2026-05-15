---
name: murmur
description: 把一段中文（或任意 Whisper 支持语言）的会议/面试录音用本地 Whisper large-v3 转成文本，再清洗成带说话人标签、修过 ASR 错字、分好章节的 markdown 文档（可选再转成 docx）。跨平台（macOS Apple Silicon 用 mlx-whisper，Windows/Linux/Intel Mac 用 whisper-ctranslate2）。零云端、零订阅、隐私不出本机。适用：替代飞书妙计/通义听悟/Otter.ai 这类付费转录服务、需要在 VS Code 或 Word 里直接拿到可读稿、在 AI agent（Claude Code/Copilot/Codex/Cursor）里端到端跑通。不适用：实时转录、强噪声多人重叠会议、需要严格说话人分离的场景。
---

# Murmur — 本地零成本音频转录与清洗工作流

**仓库**：https://github.com/xiaopengde/murmur
**适用 agent**：GitHub Copilot Agent / Claude Code / OpenAI Codex / Cursor / 任意遵循 [agentskills.io](https://agentskills.io) 的 agent

---

## 0. 触发条件

满足以下**任一**触发该 skill：

- 用户说"帮我转录 / 把这段录音转成文字 / 出逐字稿 / 出会议纪要 / 飞书妙计太贵"
- 工作目录里出现 `.m4a` / `.mp3` / `.wav` / `.mp4` / `.webm` / `.flac` / `.ogg` 文件
- 用户明确说"用 Murmur"

---

## 1. 端到端 5 步流程

### 步骤 A — 环境检查（必跑，不要跳）

**假设用户是新机器**，刚装完 Claude Code / Codex / Copilot，没装其他任何东西。所以先检查环境：

```bash
# macOS / Linux
bash scripts/doctor.sh

# Windows (PowerShell)
powershell -ExecutionPolicy Bypass -File scripts/doctor.ps1
```

doctor 脚本会检查：`ffmpeg` / `uv` / `pandoc` / `python3` / 平台和芯片 / HuggingFace 缓存。

**如果有 ❌**，跑对应的 install 脚本：

```bash
# macOS
bash scripts/install-mac.sh

# Windows (需要管理员 PowerShell)
powershell -ExecutionPolicy Bypass -File scripts/install-windows.ps1
```

安装完再跑一次 `doctor`，全 ✅ 才进入下一步。**不要假设用户已经装了 ffmpeg / uv / pandoc**——这是最常见的 onboarding 翻车点。

### 步骤 B — 询问默认输出格式（首次使用时）

`transcribe.py` 自己会处理——首次跑时会停下来问：

```
首次使用 Murmur 👋
以后默认输出格式选哪个？
  [1] markdown (.md)
  [2] word (.docx)
请输入 1 或 2：
```

**作为 agent**：如果是你（agent）在替用户跑，**不要替用户做选择**。把这个交互交给用户回答，或者主动问一句"你以后想默认输出 md 还是 docx？我帮你存好"。

如果用户说"这次先用 docx 试一次，别改默认"，那就：

```bash
python scripts/transcribe.py 录音.m4a --format docx
```

`--format` 是单次覆盖，不动 config。

如果用户后来想改默认：

```bash
python scripts/transcribe.py --set-default md       # 或 docx
```

### 步骤 C — 跑转录

```bash
python scripts/transcribe.py <音频文件> [--lang zh] [--output-dir .] [--model medium] [--cn]
```

脚本内部会：

1. 用 `ffmpeg` 把任意输入转成 16kHz 单声道 WAV（**关键**——直接喂 m4a 会触发 Whisper 幻觉循环）
2. 检测平台：
   - **Apple Silicon Mac** → `uvx --from mlx-whisper mlx_whisper`（GPU 加速，最快）
   - **Windows / Linux / Intel Mac** → `uvx whisper-ctranslate2`（CTranslate2 后端，CPU 也很快）
3. 输出 `转录原稿.txt` + `字幕.srt` 到目标目录
4. 清理临时 WAV

**🇨🇳 大陆网络**：transcribe.py 会按时区/语言自动判断是否在大陆，命中就给 whisper 子进程注入：
- `HF_ENDPOINT=https://hf-mirror.com`（模型下载走 hf-mirror）
- `UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple`（uv 拉 mlx-whisper / whisper-ctranslate2 走清华）

用户已经手动设过的同名环境变量**不会被覆盖**。显式 `--cn` / `--no-cn` 强制开关。

**换更小的模型**（CPU 慢机器常用）：

```bash
python scripts/transcribe.py 录音.m4a --model medium                   # 单次
python scripts/transcribe.py --set-default-model medium                # 永久（写入 config）
python scripts/transcribe.py --set-default-model ""                    # 清空恢复内置默认 large-v3
```

支持 `tiny / base / small / medium / large-v2 / large-v3 / large-v3-turbo` 短名，会按引擎自动映射（mlx-whisper → `mlx-community/whisper-<name>-mlx`，whisper-ctranslate2 → 原样）。也支持透传完整 HF repo 名给高级用户。

**预期耗时**：
- M2/M3：音频时长 × 0.3-0.5
- Windows / Linux CPU：音频时长 × 1-2（首次会更慢，模型加载约 30s）
- 首次跑会下载 ~2.9GB 模型到 `~/.cache/huggingface/hub/`（Win 是 `%USERPROFILE%\.cache\huggingface\hub\`），之后秒级冷启动

**⚠️ 关键约定**：脚本里**已经默认**关掉了 `condition-on-previous-text`，因为这是 No.1 大坑（不关会输出"X 点 X 点 X 点……"或"谢谢观看"成段重复）。**不要**修改这个默认值。

### 步骤 D — LLM 清洗成可读 Markdown

读 `转录原稿.txt`，按 [docs/prompts/clean-transcript.md](docs/prompts/clean-transcript.md) 里的 prompt **整段照做**。

**核心原则（必须遵守）**：

1. **忠实优先**——逐字稿不是会议纪要，不要润色、不要扩写、不要"提升表达"
2. **修水词**——删掉无意义的"嗯/啊/那个/然后那个"等口头禅；同一个词重复 3 次以上压成 1 次
3. **修 ASR 专有名词错误**——主动改并在文件头部列修正清单让用户能核对（清洗 prompt 里有常见错词表）
4. **加 speaker 标签**——从上下文（提问 vs 回答的语气、第一/二人称）推断；面试场景标 `**面试官**：` / `**我**：`，会议场景标 `**A**：` / `**B**：`，**不确定的就不标**
5. **加章节结构**——按话题切，标题是一句话概括内容，不要 "第一部分" 这种空标题
6. **保留中英混写**——LLM as Judge / Rubric / prompt 等英文术语保留原样
7. **不要编造**——原文没说的内容、推测的意图、补充的解释，**一个字都不要加**

输出文件命名：`逐字稿-清洗版.md`，放在和音频同目录。

### 步骤 E — 如果默认是 docx，转 docx

```bash
python scripts/md2docx.py 逐字稿-清洗版.md
```

会在同目录输出 `逐字稿-清洗版.docx`，用 pandoc 实现，跨平台一致。

如果用户配置了默认 docx，**不要**问"要不要转 docx"，直接转就完事——这是设默认的意义。

### 步骤 F（可选）— 复盘纪要

仅当用户明确说"复盘 / 纪要 / 总结 / retro"时做。读 [docs/prompts/retrospective.md](docs/prompts/retrospective.md)，按里面的模板生成 `复盘纪要.md`。

**默认只交付步骤 D 的清洗稿**，不要主动给复盘——大多数人只要可读逐字稿。

---

## 2. 目录约定

一次会议/面试 = 一个子目录：

```
<场景名-YYYY-MM-DD>/
├── 录音.m4a                ← 用户的原始音频
├── 字幕.srt                ← transcribe.py 输出，保留
├── 转录原稿.txt            ← transcribe.py 输出，保留（清洗依据）
├── 逐字稿-清洗版.md        ← LLM 清洗产物，主要交付物
├── 逐字稿-清洗版.docx      ← 默认 docx 时附加产物
└── 复盘纪要.md             ← 可选
```

如果用户音频文件本来就在某个目录里，就在那个目录就地输出；不要无中生有创建子目录除非用户要求。

---

## 3. 各 agent 平台的小差异

### GitHub Copilot Agent (VS Code)

- `run_in_terminal` 跑 `transcribe.py` 时用 `mode='sync'` + 长 timeout（30 分钟录音建议 timeout 30min）
- **不要**在转录跑着的时候 `send_to_terminal` 任何"看进度"的命令到同一个持久 zsh——会 Ctrl+C 掉进程
- 真要看进度，新开终端

### Claude Code

- 用 `Bash` tool 直接跑命令；它有自动的 timeout 处理
- 如果用户在 macOS 且首次安装，可能需要 sudo 提示

### OpenAI Codex CLI

- 默认权限可能不够；安装步骤需要用户手动 sudo
- 转录命令本身不需要特权

### Cursor

- 跟 VS Code Copilot 行为一致

---

## 4. 故障排查速查

| 症状 | 原因 | 解法 |
|---|---|---|
| 转录文本反复 "X 点 X 点 X 点…" 或某句话整段重复 | `condition-on-previous-text` 未关 | 用本仓库的 transcribe.py 不会有这个问题；如果手动改过命令，加回 `--condition-on-previous-text False` |
| 全程 "谢谢观看" 成段重复 | 音频开头有静音 + 没做 ffmpeg 预处理 | 用本仓库的 transcribe.py 自动处理；手动跑时记得先 `ffmpeg -ar 16000 -ac 1` |
| 速度极慢 | 用成了 openai-whisper PyPI 版（纯 CPU + Python） | 确认走的是 mlx-whisper（Mac AS）或 whisper-ctranslate2（其他） |
| 模型下载卡住 | HuggingFace 网络问题 | 加 `--cn` 让 transcribe.py 自动注入 `HF_ENDPOINT=https://hf-mirror.com`（默认按时区/语言自动判断，可不传） |
| uvx 首次拉 mlx-whisper / whisper-ctranslate2 卡住 | PyPI 访问慢 | 同样加 `--cn`，会同时注入 `UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple` |
| CPU 机器转录慢、显存不够 | 模型太大 | 换小模型：`--model medium` 单次，或 `--set-default-model medium` 永久 |
| `brew install` / `winget install` 卡在下载 | 国内访问 Homebrew bottle / GitHub Releases 慢 | 重跑安装脚本时加 CN flag：<br>Mac: `bash scripts/install-mac.sh --cn`（启用 USTC 镜像）<br>Win: `powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1 -CN`（启用 Scoop/PyPI 兜底）<br>脚本默认会按时区/语言自动判断，加 flag 是强制启用 |
| Mac 上 install-mac.sh 报 "command not found: brew" | Homebrew 没装 | 让用户先装 Homebrew（脚本会给提示） |
| Windows 上 install-windows.ps1 报权限错误 | PowerShell 没用管理员模式 | 右键 PowerShell → 以管理员身份运行 |
| Windows 上 winget 找不到 | 旧版 Windows 10 没装 winget | 让用户从 Microsoft Store 装 "App Installer" |
| 英文术语全错 | 多语言混读触发了语言切换 | transcribe.py 默认 `--language zh`，对中文为主的录音最稳；纯英文用 `--lang en` |
| 说话人混在一起 | Whisper 不带 diarization | 清洗阶段靠上下文推断；多人混乱场景用 `**说话人 1/2/3**` 占位 |
| 转录到一半进程被杀 | 同一持久终端被 send_to_terminal 干扰 / 电脑休眠 | 见 §3 "GitHub Copilot Agent" 注意事项 |

完整故障排查见 [docs/troubleshooting.md](docs/troubleshooting.md)。

---

## 5. 一次完整跑通的最简命令序列

假设用户给你一个 `面试.m4a`，目标默认 docx：

```bash
# 1) 环境检查（macOS）
bash scripts/doctor.sh

# 2) 缺啥装啥
bash scripts/install-mac.sh

# 3) 转录（首次会问 md/docx，让用户回答）
python scripts/transcribe.py 面试.m4a

# 4) agent 你来读 转录原稿.txt，按 docs/prompts/clean-transcript.md
#    清洗输出 逐字稿-清洗版.md（这一步是 LLM 自己做，不调脚本）

# 5) 默认 docx → 转
python scripts/md2docx.py 逐字稿-清洗版.md

# 6) 用户说要复盘？再来一步
#    读 docs/prompts/retrospective.md，输出 复盘纪要.md
```

整个过程**只有一次**用户交互（首次的 md/docx 选择），之后都是无人值守。

---

## 6. 这个 skill 的设计哲学

写给后续维护者 / fork 这个 skill 的 agent：

1. **新机器零假设**——doctor 和 install 脚本必须能在刚装完 OS 的 Mac/Win 上跑通
2. **不替用户做关键选择**——格式默认值这种长期影响的设置必须问，但只问一次
3. **LLM 清洗 prompt 和代码解耦**——prompts 在 `docs/prompts/`，agent 直接读，方便用户改
4. **跨平台分支必须显式**——不要假设 Apple Silicon 和 Windows 走同一条命令；transcribe.py 里的平台判断是核心逻辑
5. **错误恢复优先**——任何关键命令失败都要给可执行的下一步建议，不要只报错
