# Murmur 一键安装 — Windows PowerShell
# 装 ffmpeg / uv / pandoc / python（如缺）
# 推荐用管理员模式 PowerShell 运行

$ErrorActionPreference = "Stop"

function Write-Ok    { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warn2 { param($msg) Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host "ℹ️  $msg" -ForegroundColor Cyan }

function Test-Cmd { param($name) $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

Write-Host ""
Write-Host "================================"
Write-Host "  Murmur 一键安装 (Windows)"
Write-Host "================================"
Write-Host ""

# ---------- 检查 winget ----------
if (-not (Test-Cmd winget)) {
    Write-Err "未检测到 winget"
    Write-Host ""
    Write-Host "winget 是 Windows 自带的包管理器（Win10 1809+ / Win11 内置）。"
    Write-Host "如缺失：去 Microsoft Store 搜 'App Installer' 装一下。"
    Write-Host ""
    Write-Host "或者手动装："
    Write-Host "  ffmpeg:   https://www.gyan.dev/ffmpeg/builds/  (下载 release essentials)"
    Write-Host "  uv:       powershell -c `"irm https://astral.sh/uv/install.ps1 | iex`""
    Write-Host "  pandoc:   https://github.com/jgm/pandoc/releases/latest"
    Write-Host "  python:   https://python.org"
    exit 1
}
$wingetVer = (winget --version)
Write-Ok "winget 已安装（$wingetVer）"

# ---------- ffmpeg ----------
if (Test-Cmd ffmpeg) {
    Write-Ok "ffmpeg 已安装，跳过"
} else {
    Write-Info "安装 ffmpeg..."
    winget install -e --id Gyan.FFmpeg --silent --accept-source-agreements --accept-package-agreements
    Write-Ok "ffmpeg 安装完成"
    Write-Warn2 "ffmpeg 装完后需要新开一个 PowerShell 窗口让 PATH 生效"
}

# ---------- uv ----------
if (Test-Cmd uvx) {
    Write-Ok "uv 已安装，跳过"
} else {
    Write-Info "安装 uv..."
    try {
        winget install -e --id astral-sh.uv --silent --accept-source-agreements --accept-package-agreements
    } catch {
        Write-Warn2 "winget 安装 uv 失败，回退到官方脚本..."
        Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
    }
    Write-Ok "uv 安装完成"
}

# ---------- pandoc ----------
if (Test-Cmd pandoc) {
    Write-Ok "pandoc 已安装，跳过"
} else {
    Write-Info "安装 pandoc（用于 md→docx 转换）..."
    winget install -e --id JohnMacFarlane.Pandoc --silent --accept-source-agreements --accept-package-agreements
    Write-Ok "pandoc 安装完成"
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
    Write-Ok "Python 已就绪（$pythonCmd）"
} else {
    Write-Info "安装 Python 3.11..."
    winget install -e --id Python.Python.3.11 --silent --accept-source-agreements --accept-package-agreements
    Write-Ok "Python 安装完成"
    Write-Warn2 "需要新开一个 PowerShell 窗口让 PATH 生效"
}

Write-Host ""
Write-Host "================================"
Write-Ok "Murmur 安装完成！"
Write-Host "================================"
Write-Host ""
Write-Host "下一步："
Write-Host "  1) 关掉当前 PowerShell，新开一个（让 PATH 刷新）"
Write-Host "  2) 跑体检：     powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1"
Write-Host "  3) 第一次转录： python scripts\transcribe.py 你的录音.m4a"
Write-Host ""
Write-Host "首次转录会下载 ~2.9GB 的 Whisper large-v3 模型，喝杯咖啡。"
Write-Host "国内网络慢可在 PowerShell 里设："
Write-Host "  `$env:HF_ENDPOINT=`"https://hf-mirror.com`""
Write-Host ""
