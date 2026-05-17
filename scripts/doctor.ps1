# Murmur env doctor — Windows PowerShell
# 检查 ffmpeg / uv / pandoc / python / 平台 / HuggingFace 缓存

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

# ---------- ffmpeg ----------
if (Test-Cmd ffmpeg) {
    $ver = (ffmpeg -version 2>&1)[0] -split '\s+' | Select-Object -Index 2
    Write-Ok "ffmpeg 已安装（$ver）"
} else {
    Write-Err "ffmpeg 未安装"
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
$configDir = "$env:APPDATA\Murmur"
$configFile = "$configDir\config.json"
if (Test-Path $configFile) {
    try {
        $cfg = Get-Content $configFile -Raw | ConvertFrom-Json
        $fmt = if ($cfg.default_format) { $cfg.default_format } else { "?" }
        Write-Ok "Murmur 配置已存在（默认输出格式：$fmt）"
        $cnMode = if ($cfg.cn_mode) { $cfg.cn_mode } else { "auto" }
        switch ($cnMode) {
            "on"  { Write-Ok "大陆镜像偏好：on（每次转录自动启用 HF/PyPI 镜像）" }
            "off" { Write-Info "大陆镜像偏好：off（每次走官方源；国内慢可改：python scripts\transcribe.py --set-default-cn on）" }
            default { Write-Info "大陆镜像偏好：auto（按时区/语言自动判断；强制开：python scripts\transcribe.py --set-default-cn on）" }
        }
    } catch {
        Write-Warn2 "Murmur 配置文件存在但解析失败：$configFile"
    }
} else {
    Write-Info "Murmur 还未初始化，首次跑 transcribe.py 时会问你 md/docx 默认值"
    Write-Info "国内用户建议先跑：python scripts\transcribe.py --set-default-cn on"
}

Write-Host ""
Write-Host "================================"
if ((Test-Cmd ffmpeg) -and (Test-Cmd uvx) -and $pythonCmd) {
    Write-Ok "核心环境就绪，可以开始转录！"
    Write-Host "    试试：$pythonCmd scripts\transcribe.py 你的录音.m4a"
} else {
    Write-Err "缺少核心依赖，请按上方提示安装；或一键跑：powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1"
}
Write-Host "================================"
Write-Host ""
