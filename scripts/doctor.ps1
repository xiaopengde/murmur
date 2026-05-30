# Murmur env doctor — Windows PowerShell
# 检查 ffmpeg / uv / pandoc / python / 平台 / HuggingFace 缓存
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1 -Smoke   # 加端到端烟雾测试

param(
    [switch]$Smoke,
    [switch]$Strict
)

$ErrorActionPreference = "Continue"

function Write-Ok    { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warn2 { param($msg) Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host "ℹ️  $msg" -ForegroundColor Cyan }

function Test-Cmd { param($name) $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

Write-Host ""
Write-Host "================================"
Write-Host "  Murmur 环境体检 (Windows)"
Write-Host "================================"
Write-Host ""

# ---------- OS / Arch ----------
$os = "Windows $([System.Environment]::OSVersion.Version.Major)"
$arch = $env:PROCESSOR_ARCHITECTURE
Write-Info "操作系统：$os"
Write-Info "芯片架构：$arch"
Write-Warn2 "Windows → 将使用 whisper-ctranslate2（CPU；如有 NVIDIA GPU 可后续启用 CUDA）"
Write-Host ""
Write-Host "--------------------------------"
Write-Host "核心依赖状态"
Write-Host "--------------------------------"
$coreOk = $true
$onboardingOk = $false

# ---------- ffmpeg ----------
if (Test-Cmd ffmpeg) {
    $ver = (ffmpeg -version 2>&1)[0] -split '\s+' | Select-Object -Index 2
    Write-Ok "ffmpeg 已安装（$ver）"
} else {
    Write-Err "ffmpeg 未安装"
    $coreOk = $false
    Write-Host "    → 安装：winget install Gyan.FFmpeg"
    Write-Host "      或：scoop install ffmpeg"
    Write-Host "      或：choco install ffmpeg"
}

# ---------- uv ----------
if (Test-Cmd uvx) {
    $ver = (uvx --version 2>&1) -split '\s+' | Select-Object -Index 1
    Write-Ok "uv 已安装（$ver）"
} else {
    Write-Err "uv 未安装"
    $coreOk = $false
    Write-Host "    → 安装：winget install astral-sh.uv"
    Write-Host "      或：powershell -c `"irm https://astral.sh/uv/install.ps1 | iex`""
}

# ---------- pandoc ----------
if (Test-Cmd pandoc) {
    $ver = (pandoc --version 2>&1)[0] -split '\s+' | Select-Object -Index 1
    Write-Ok "pandoc 已安装（$ver）—— md→docx 转换可用"
} else {
    Write-Warn2 "pandoc 未安装（仅当默认输出 docx 时需要）"
    Write-Host "    → 安装：winget install JohnMacFarlane.Pandoc"
}

# ---------- python ----------
$pythonCmd = $null
foreach ($candidate in @("python", "python3", "py")) {
    if (Test-Cmd $candidate) {
        $pythonCmd = $candidate
        break
    }
}
if ($pythonCmd) {
    $ver = (& $pythonCmd --version 2>&1) -split '\s+' | Select-Object -Last 1
    Write-Ok "$pythonCmd 已安装（$ver）"
} else {
    Write-Err "Python 未安装"
    $coreOk = $false
    Write-Host "    → 安装：winget install Python.Python.3.11"
    Write-Host "      或从 https://python.org 下载"
}

# ---------- HuggingFace 缓存 ----------
$hfCache = if ($env:HF_HOME) { "$env:HF_HOME\hub" } else { "$env:USERPROFILE\.cache\huggingface\hub" }
if (Test-Path $hfCache) {
    $modelDirs = Get-ChildItem $hfCache -Filter "*whisper*large-v3*" -ErrorAction SilentlyContinue
    if ($modelDirs) {
        $size = "{0:N2} GB" -f ((Get-ChildItem $hfCache -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB)
        Write-Ok "HuggingFace 缓存已含 whisper-large-v3 模型（缓存共 $size）"
    } else {
        Write-Info "HuggingFace 缓存目录存在但未含 large-v3，首次转录会下载约 2.9GB"
    }
} else {
    Write-Info "HuggingFace 缓存尚未建立，首次转录会下载约 2.9GB 模型"
    Write-Info "国内网络慢可设：`$env:HF_ENDPOINT=`"https://hf-mirror.com`""
}

# ---------- Murmur 配置 ----------
Write-Host ""
Write-Host "--------------------------------"
Write-Host "Murmur onboarding 状态"
Write-Host "--------------------------------"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ($pythonCmd) {
    $env:PYTHONPATH = $scriptDir
    $status = & $pythonCmd -c "import config; cfg=config.load(); print(config.config_path()); print(cfg.get('default_format','?')); print(cfg.get('default_model','?')); print(config.get_cn_mode()); print('done' if not config.needs_onboarding() else 'needs')"
    $configFile = $status[0]
    $fmt = $status[1]
    $model = $status[2]
    $cnMode = $status[3]
    $state = $status[4]
    if ($state -eq "done") {
        $onboardingOk = $true
        Write-Ok "Murmur onboarding 已完成（默认格式：$fmt，默认模型：$model）"
    } else {
        Write-Warn2 "Murmur onboarding 未完成（配置：$configFile）"
        Write-Info "下一步必须运行：python scripts\transcribe.py --onboarding"
        Write-Info "Agent：看到 needs_onboarding=true 后必须用候选框询问用户，再运行 --init-defaults"
    }
    switch ($cnMode) {
        "on"  { Write-Ok "大陆镜像偏好：on（每次转录自动启用 HF/PyPI 镜像）" }
        "off" { Write-Info "大陆镜像偏好：off（每次走官方源；国内慢可改：python scripts\transcribe.py --set-default-cn on）" }
        default { Write-Info "大陆镜像偏好：auto（按时区/语言自动判断；强制开：python scripts\transcribe.py --set-default-cn on）" }
    }
} else {
    Write-Warn2 "无法读取 Murmur onboarding 状态：Python 未安装"
}

Write-Host ""
Write-Host "================================"
if ($coreOk -and $onboardingOk) {
    Write-Ok "核心环境和 onboarding 均就绪，可以开始转录！"
    Write-Host "    试试：$pythonCmd scripts\transcribe.py 你的录音.m4a"
} elseif ($coreOk) {
    Write-Warn2 "核心环境就绪，但 onboarding 未完成，暂不能开始转录。"
    Write-Host "    下一步必须运行：python scripts\transcribe.py --onboarding"
} else {
    Write-Err "缺少核心依赖，请按上方提示安装；或一键跑：powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1"
    if ($Smoke) {
        Write-Err "依赖缺失，跳过 -Smoke 端到端测试"
        exit 1
    }
}
if ($Strict -and (-not $coreOk -or -not $onboardingOk)) { exit 1 }
Write-Host "================================"
Write-Host ""

# ---------- 烟雾测试 (-Smoke) ----------
if (-not $Smoke) { exit 0 }

Write-Host "================================"
Write-Host "  烟雾测试 (-Smoke)"
Write-Host "================================"
Write-Host ""
Write-Info "生成 2 秒测试音频 -> 跑完整 pipeline -> 校验输出"
Write-Info "用 tiny 模型（约 75MB；首次会下载，之后秒级）"
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$smokeDir = Join-Path ([System.IO.Path]::GetTempPath()) ("murmur-smoke-" + [System.Guid]::NewGuid().ToString("N").Substring(0,8))
New-Item -ItemType Directory -Path $smokeDir | Out-Null
$smokeAudio = Join-Path $smokeDir "smoke.m4a"
$smokeKeep = $false

try {
    # 1) 生成 2 秒测试音频（Windows 没 say，用 ffmpeg 正弦波）
    Write-Info "[1/3] 生成测试音频..."
    $ffArgs = @("-y", "-f", "lavfi", "-i", "sine=frequency=440:duration=2",
                "-ar", "44100", "-ac", "1", "-c:a", "aac", $smokeAudio)
    $ff = Start-Process -FilePath "ffmpeg" -ArgumentList $ffArgs -NoNewWindow -Wait -PassThru -RedirectStandardError "$smokeDir\ffmpeg.log"
    if ($ff.ExitCode -ne 0) {
        Write-Err "ffmpeg lavfi 生成测试音频失败"
        $smokeKeep = $true
        exit 2
    }
    $size = "{0:N0}" -f (Get-Item $smokeAudio).Length
    Write-Ok "测试音频已生成：$smokeAudio ($size bytes)"
    Write-Host ""

    # 2) 跑 transcribe.py
    Write-Info "[2/3] 跑 transcribe.py（临时配置 --model tiny --format md）..."
    $oldAppData = $env:APPDATA
    $env:APPDATA = Join-Path $smokeDir "config"
    $initLog = Join-Path $smokeDir "init.log"
    $init = Start-Process -FilePath $pythonCmd -ArgumentList @(
        (Join-Path $scriptDir "transcribe.py"),
        "--init-defaults", "--format", "md", "--set-default-model", "tiny"
    ) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $initLog -RedirectStandardError "$initLog.err"
    if ($init.ExitCode -ne 0) {
        Write-Err "临时 onboarding 初始化失败"
        Get-Content $initLog -Tail 20 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
        $smokeKeep = $true
        exit 3
    }
    $start = Get-Date
    $logFile = Join-Path $smokeDir "transcribe.log"
    $py = Start-Process -FilePath $pythonCmd -ArgumentList @(
        (Join-Path $scriptDir "transcribe.py"),
        $smokeAudio,
        "--model", "tiny",
        "--format", "md",
        "--output-dir", $smokeDir
    ) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $logFile -RedirectStandardError "$logFile.err"
    $env:APPDATA = $oldAppData
    $elapsed = [int]((Get-Date) - $start).TotalSeconds
    if ($py.ExitCode -ne 0) {
        Write-Err "transcribe.py 失败（exit=$($py.ExitCode)）。日志末尾："
        Get-Content $logFile -Tail 20 | ForEach-Object { Write-Host "    $_" }
        Get-Content "$logFile.err" -Tail 10 -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "    $_" }
        $smokeKeep = $true
        exit 3
    }
    Write-Ok "转录完成（耗时 ${elapsed}s）"
    Write-Host ""

    # 3) 校验产物
    Write-Info "[3/3] 校验输出文件..."
    $txt = Join-Path $smokeDir "转录原稿.txt"
    $srt = Join-Path $smokeDir "字幕.srt"
    $fail = $false
    if (Test-Path $txt) {
        $bytes = (Get-Item $txt).Length
        Write-Ok "转录原稿.txt 存在（$bytes bytes）"
        $content = (Get-Content $txt -Raw -ErrorAction SilentlyContinue)
        if ($content) {
            Write-Info "    内容预览：$($content.Substring(0, [Math]::Min(60, $content.Length)))"
        } else {
            Write-Warn2 "    内容为空（正弦波音频无可识别语音，pipeline 跑通即 PASS）"
        }
    } else {
        Write-Err "转录原稿.txt 不存在！实际产物："
        Get-ChildItem $smokeDir | ForEach-Object { Write-Host "    $($_.Name)" }
        $smokeKeep = $true
        $fail = $true
    }
    if (Test-Path $srt) {
        $bytes = (Get-Item $srt).Length
        Write-Ok "字幕.srt 存在（$bytes bytes）"
    } else {
        Write-Err "字幕.srt 不存在！"
        $smokeKeep = $true
        $fail = $true
    }

    Write-Host ""
    Write-Host "================================"
    if (-not $fail) {
        Write-Ok "烟雾测试 PASS — 端到端 pipeline 正常工作"
    } else {
        Write-Err "烟雾测试 FAIL — 见上方报错"
        exit 4
    }
    Write-Host "================================"
    Write-Host ""
} finally {
    if ($smokeKeep) {
        Write-Warn2 "保留调试目录：$smokeDir"
    } else {
        Remove-Item -Recurse -Force $smokeDir -ErrorAction SilentlyContinue
    }
}
