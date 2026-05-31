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

doctor 脚本会分两块输出：

1. **核心依赖状态**：`ffmpeg` / `uvx` / `pandoc` / `python3` / 平台和芯片 / 模型缓存（ModelScope / HuggingFace）
2. **Murmur onboarding 状态**：默认输出格式、默认离线模型是否已经由用户明确选择

**如果核心依赖有 ❌**，跑对应的 install 脚本：

```bash
# macOS
bash scripts/install-mac.sh

# Windows (需要管理员 PowerShell)
powershell -ExecutionPolicy Bypass -File scripts/install-windows.ps1
```

安装完再跑一次 `doctor`。如果要在自动化里强校验，使用 strict 模式：

```bash
bash scripts/doctor.sh --strict
powershell -ExecutionPolicy Bypass -File scripts/doctor.ps1 -Strict
```

`--strict` / `-Strict` 只有在核心依赖齐全且 onboarding 已完成时才返回 0；依赖缺失或 onboarding 未完成都会返回非 0。**doctor 如果提示 onboarding 未完成，不要说“可以开始转录”，下一步必须跑 `python scripts/transcribe.py --onboarding`。**

**端到端验证**（首次安装强烈推荐，或排查问题时；会使用临时配置，不污染用户默认值）：

```bash
bash scripts/doctor.sh --smoke                                    # macOS / Linux
powershell -ExecutionPolicy Bypass -File scripts/doctor.ps1 -Smoke  # Windows
```

会自动生成 2 秒测试音频跑完整 pipeline。大陆 Apple Silicon 会优先用 ModelScope large-v3-turbo 4bit（首次约 464MB），其他环境用 tiny 模型（首次约 75MB）；通过后说明 ffmpeg → uvx → mlx/whisper → 文件输出全链路工作。失败时会保留临时目录方便排查。

### 步骤 B — 新用户 / 首次 onboarding（硬门禁）

**无论用户是否已经给了音频文件，都必须先跑：**

```bash
python scripts/transcribe.py --onboarding
```

读取 JSON：

- 如果 `needs_onboarding=false`：可以进入步骤 C。
- 如果 `needs_onboarding=true`：agent **必须**使用 AskQuestion / 候选框让用户选择，不能自己决定，不能直接执行 JSON 里的 example。JSON 会明确包含：
  - `must_ask_user: true`
  - `do_not_choose_for_user: true`
  - `do_not_run_example_without_user_choice: true`

必须向用户询问两个候选项：

1. 默认输出格式：`md` 或 `docx`
2. 默认离线模型：`large-v3-turbo` / `large-v3` / `medium` / `small`

用户选完后，运行：

```bash
python scripts/transcribe.py --init-defaults --format <md|docx> --set-default-model <model>
```

只有这个命令成功后，才允许继续转录。`--format` / `--model` 是单次覆盖参数，**不能绕过首次 onboarding**；未完成 onboarding 时，转录主流程会直接退出并要求先完成 onboarding。

如果用户后来想改默认：

```bash
python scripts/transcribe.py --set-default md       # 或 docx
python scripts/transcribe.py --set-default-model medium
```

### 步骤 C — 跑转录并转述进度

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

**Codex / agent 进度转述要求**：转录时必须同步等待终端输出；每约 30 秒 poll 一次终端。看到新的 `📥 模型下载/准备中`、`⏳ 转录推理中`、`✅ 完成` 心跳或阶段变化时，必须用前台消息简短转述给用户（例如“模型仍在下载/准备”“已进入转录推理，已用时 2:00”“转录完成，正在整理输出”），不要让用户长时间面对静默终端。首次没有缓存时，下载/准备完成后才算进入推理阶段。

**🇨🇳 大陆网络**：transcribe.py 会按时区/语言自动判断是否在大陆。命中后默认使用 `--model-source auto`：
- 对已验证映射，优先从 ModelScope 下载模型到 `~/.cache/murmur/models/`，然后把本地目录交给现有 `mlx-whisper` / `whisper-ctranslate2` 推理。
- 对没有 ModelScope 映射的模型，继续给 whisper 子进程注入 `HF_ENDPOINT=https://hf-mirror.com`（HuggingFace 镜像）和 `UV_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple`（uv 拉依赖走清华）。

可手动指定模型源：

```bash
python scripts/transcribe.py 录音.m4a --model-source modelscope  # 强制优先 ModelScope
python scripts/transcribe.py 录音.m4a --model-source hf          # 强制原 HuggingFace/引擎默认源
```

当前已验证映射：
- Apple Silicon / `mlx-whisper`：`large-v3-turbo` → `mlx-community/whisper-large-v3-turbo-4bit`（ModelScope，约 464MB；下载后自动适配 `model.safetensors` → `weights.safetensors`）
- Windows / Linux / Intel Mac / `whisper-ctranslate2`：`large-v3-turbo` → `mobiuslabsgmbh/faster-whisper-large-v3-turbo`（ModelScope，约 1.62GB，CTranslate2 格式；需要按目标平台 smoke test）

用户已经手动设过的同名环境变量**不会被覆盖**。显式 `--cn` / `--no-cn` 强制单次开关。

**持久化偏好**（避免每次都加 `--cn`）：

```bash
python scripts/transcribe.py --set-default-cn on    # 以后每次自动启用
python scripts/transcribe.py --set-default-cn off   # 以后每次走官方源
python scripts/transcribe.py --set-default-cn auto  # 恢复按时区/语言自动判断（默认）
```

也可以直接 `bash scripts/install-mac.sh --cn`（或 `-CN` for Windows），安装脚本会在结束时把偏好写进配置。

**换更小的模型**（CPU 慢机器常用）：

```bash
python scripts/transcribe.py 录音.m4a --model medium                   # 单次
python scripts/transcribe.py --set-default-model medium                # 永久（写入 config）
python scripts/transcribe.py --set-default-model ""                    # 清空恢复内置默认 large-v3-turbo
```

支持 `tiny / base / small / medium / large-v2 / large-v3 / large-v3-turbo` 短名，会按引擎自动映射：

- Apple Silicon / `mlx-whisper` 使用显式 HuggingFace repo 映射（例如 `large-v3-turbo` → `mlx-community/whisper-large-v3-turbo`，不是 `...-turbo-mlx`）
- `whisper-ctranslate2` 透传短名（如 `large-v3-turbo` / `medium`）

也支持透传完整 HF repo 名给高级用户。转录失败时，脚本会打印 resolved model，并尽量区分网络问题与 repo 不存在 / 私有 / 映射错误。

**预期耗时**：
- M2/M3：音频时长 × 0.3-0.5
- Windows / Linux CPU：音频时长 × 1-2（首次会更慢，模型加载约 30s）
- 首次跑会先下载模型到 `~/.cache/murmur/models/`（ModelScope 路线）或 `~/.cache/huggingface/hub/`（原 HuggingFace 路线；Win 是 `%USERPROFILE%\.cache\huggingface\hub\`），日志显示 `📥 模型下载/准备中`；缓存就绪后才显示 `⏳ 转录推理中`，之后秒级冷启动

**⚠️ 关键约定**：脚本里**已经默认**关掉了 `condition-on-previous-text`，因为这是 No.1 大坑（不关会输出"X 点 X 点 X 点……"或"谢谢观看"成段重复）。**不要**修改这个默认值。

### 步骤 D — LLM 清洗成可读 Markdown

读 `转录原稿.txt`，按以下步骤执行（**不要跳过任何一步**）：

**1. 组装 prompt**（两种方式选一）

- **自动（推荐）**：
  ```bash
  python scripts/clean.py 转录原稿.txt [--scene interview|meeting|podcast]
  # 输出组装好的 prompt，复制到 LLM 对话框即可
  ```
- **手动**：打开 `docs/prompts/clean-transcript.md`，把 `## === PROMPT 开始 ===` 到 `## === PROMPT 结束 ===` 之间的内容**原封不动**复制出来（不要总结、不要省略、不要用下面的简化版代替）。然后在末尾的占位符处贴入 `转录原稿.txt` 的全部内容。

**2. 补场景描述**（如已知，加在 prompt 最前面）

- 面试录音：`这是一段中文面试录音，面试官代称"面试官"，应试者代称"我"。`
- 会议录音：`这是一段工作会议录音，已知参与者：[姓名/代号]。`
- 不确定则不加（LLM 会从上下文推断）

**3. 发给 LLM 执行**（GPT-4o / Claude / Gemini / 国内大模型均可）

- 原稿超过 **1.5 万字**：先让 LLM 列出章节结构，再逐章节批次清洗，最后拼成一个文件
- 说话人 ≥ 3 人且混乱：先听前 30 秒录音，告诉 LLM 每个人的角色/声音特征

**4. 对照「输出前自检清单」核查**

拿到 LLM 输出后，过一遍 `docs/prompts/clean-transcript.md` 末尾的「输出前自检清单」（7 项）。有不合格项让 LLM 补改后再保存。

**5. 保存为 `逐字稿-清洗版.md`**，放在和音频同目录。

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
| 模型下载卡住 | HuggingFace 网络问题 | 优先加 `--model-source modelscope` 或 `--cn` 走 ModelScope 已验证模型；常用国内的话直接 `--set-default-cn on` |
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

整个过程**只有一次**用户交互（首次 onboarding 的格式 + 模型选择），之后都是无人值守。

---

## 6. 这个 skill 的设计哲学

写给后续维护者 / fork 这个 skill 的 agent：

1. **新机器零假设**——doctor 和 install 脚本必须能在刚装完 OS 的 Mac/Win 上跑通
2. **不替用户做关键选择**——格式默认值这种长期影响的设置必须问，但只问一次
3. **LLM 清洗 prompt 和代码解耦**——prompts 在 `docs/prompts/`，agent 直接读，方便用户改
4. **跨平台分支必须显式**——不要假设 Apple Silicon 和 Windows 走同一条命令；transcribe.py 里的平台判断是核心逻辑
5. **错误恢复优先**——任何关键命令失败都要给可执行的下一步建议，不要只报错
