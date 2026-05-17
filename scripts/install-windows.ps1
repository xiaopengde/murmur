# Murmur 一键安装 — Windows PowerShell
# 装 ffmpeg / uv / pandoc / python（如缺）
# 推荐用管理员模式 PowerShell 运行
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1 -CN     # 强制启用大陆镜像/兜底
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1 -NoCN   # 强制禁用

param(
    [switch]$CN,
    [switch]$NoCN
)

$ErrorActionPreference = "Stop"

function Write-Ok    { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warn2 { param($msg) Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host "ℹ️  $msg" -ForegroundColor Cyan }

function Test-Cmd { param($name) $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

# ---------- 自动检测大陆环境 ----------
function Test-CnEnvironment {
    try {
        $culture = (Get-Culture).Name
        if ($culture -like "zh-CN*") { return $true }
    } catch {}
    try {
        $tz = (Get-TimeZone).Id
        if ($tz -like "*China Standard Time*") { return $true }
    } catch {}
    return $false
}

$useCnMirror = $false
$explicitCn = $null  # $true = 用户传 -CN；$false = 用户传 -NoCN；$null = auto-detect
if ($CN) {
    $useCnMirror = $true
    $explicitCn = $true
} elseif ($NoCN) {
    $useCnMirror = $false
    $explicitCn = $false
} elseif (Test-CnEnvironment) {
    $useCnMirror = $true
    Write-Info "检测到中国大陆环境（语言/时区），将启用安装阶段的镜像/兜底（如需关闭：重跑时加 -NoCN）"
}

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
    if ($useCnMirror) {
        Write-Host "🇨🇳 大陆用户兜底方案（任选其一）："
        Write-Host ""
        Write-Host "  方案 A — 用 Scoop（推荐，可走南大镜像）："
        Write-Host "    Set-ExecutionPolicy -Scope CurrentUser RemoteSigned"
        Write-Host "    iwr -useb get.scoop.sh | iex"
        Write-Host "    # 可选：把 Scoop main bucket 换成南大镜像加速"
        Write-Host "    scoop config SCOOP_REPO https://mirror.nju.edu.cn/scoop"
        Write-Host "    scoop install ffmpeg uv pandoc python"
        Write-Host ""
        Write-Host "  方案 B — 用清华 PyPI 镜像装 uv（其它工具走官方下载）："
        Write-Host "    python -m pip install -i https://pypi.tuna.tsinghua.edu.cn/simple uv"
        Write-Host "    # ffmpeg/pandoc/python 用下面的直链"
        Write-Host ""
        Write-Host "  方案 C — 直接下载（最稳）："
    } else {
        Write-Host "或者手动装："
    }
    Write-Host "    ffmpeg:   https://www.gyan.dev/ffmpeg/builds/  (下载 release essentials)"
    Write-Host "    uv:       powershell -c `"irm https://astral.sh/uv/install.ps1 | iex`""
    Write-Host "    pandoc:   https://github.com/jgm/pandoc/releases/latest"
    Write-Host "    python:   https://python.org"
    exit 1
}
$wingetVer = (winget --version)
Write-Ok "winget 已安装（$wingetVer）"

# ---------- ffmpeg ----------
if (Test-Cmd ffmpeg) {
    Write-Ok "ffmpeg 已安装，跳过"
} else {
    Write-Info "安装 ffmpeg..."
    try {
        winget install -e --id Gyan.FFmpeg --silent --accept-source-agreements --accept-package-agreements
        Write-Ok "ffmpeg 安装完成"
    } catch {
        Write-Warn2 "winget 安装 ffmpeg 失败：$_"
        if ($useCnMirror) {
            Write-Host "  🇨🇳 大陆用户兜底：用 Scoop（已配南大镜像）或直接去 https://www.gyan.dev/ffmpeg/builds/ 下载 release essentials，把 bin/ 加到 PATH"
        } else {
            Write-Host "  兜底：https://www.gyan.dev/ffmpeg/builds/ 下载后把 bin/ 加到 PATH"
        }
        throw
    }
    Write-Warn2 "ffmpeg 装完后需要新开一个 PowerShell 窗口让 PATH 生效"
}

# ---------- uv ----------
if (Test-Cmd uvx) {
    Write-Ok "uv 已安装，跳过"
} else {
    Write-Info "安装 uv..."
    $uvInstalled = $false
    try {
        winget install -e --id astral-sh.uv --silent --accept-source-agreements --accept-package-agreements
        $uvInstalled = $true
    } catch {
        Write-Warn2 "winget 安装 uv 失败，回退到官方脚本..."
        try {
            Invoke-RestMethod https://astral.sh/uv/install.ps1 | Invoke-Expression
            $uvInstalled = $true
        } catch {
            Write-Warn2 "官方 install.ps1 也失败：$_"
            if ($useCnMirror) {
                Write-Host "  🇨🇳 大陆用户兜底：用清华 PyPI 镜像装 uv（前提是已有 Python）："
                Write-Host "    python -m pip install -i https://pypi.tuna.tsinghua.edu.cn/simple uv"
            } else {
                Write-Host "  兜底：python -m pip install uv"
            }
            throw
        }
    }
    if ($uvInstalled) { Write-Ok "uv 安装完成" }
}

# ---------- pandoc ----------
if (Test-Cmd pandoc) {
    Write-Ok "pandoc 已安装，跳过"
} else {
    Write-Info "安装 pandoc（用于 md→docx 转换）..."
    try {
        winget install -e --id JohnMacFarlane.Pandoc --silent --accept-source-agreements --accept-package-agreements
        Write-Ok "pandoc 安装完成"
    } catch {
        Write-Warn2 "winget 安装 pandoc 失败：$_"
        Write-Host "  兜底：去 https://github.com/jgm/pandoc/releases/latest 下载 -windows-x86_64.msi 直接装"
        throw
    }
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

# ---------- 持久化大陆镜像偏好（仅当用户显式 -CN / -NoCN 时）----------
# auto-detect 的结果不写入配置——把"自动判断"的决策权留给 transcribe.py 每次跑时再决定
if ($null -ne $explicitCn -and $pythonCmd) {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $transcribePy = Join-Path $scriptDir "transcribe.py"
    if ($explicitCn) {
        & $pythonCmd $transcribePy --set-default-cn on 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "已记住偏好：以后 transcribe.py 默认启用大陆镜像（关闭：python scripts\transcribe.py --set-default-cn off）"
        }
    } else {
        & $pythonCmd $transcribePy --set-default-cn off 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Ok "已记住偏好：以后 transcribe.py 默认走官方源（恢复自动：python scripts\transcribe.py --set-default-cn auto）"
        }
    }
}

Write-Host ""
Write-Host "下一步："
Write-Host "  1) 关掉当前 PowerShell，新开一个（让 PATH 刷新）"
Write-Host "  2) 跑体检：     powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1"
Write-Host "  3) 第一次转录： python scripts\transcribe.py 你的录音.m4a"
Write-Host ""
Write-Host "首次转录会下载 ~2.9GB 的 Whisper large-v3 模型，喝杯咖啡。"
if ($useCnMirror) {
    Write-Host ""
    Write-Host "🇨🇳 大陆用户：模型下载也建议走镜像。把下面这行加到 `$PROFILE 让以后所有终端生效："
    Write-Host "  `$env:HF_ENDPOINT=`"https://hf-mirror.com`""
    Write-Host "（编辑：notepad `$PROFILE）"
} else {
    Write-Host "国内网络慢可在 PowerShell 里设："
    Write-Host "  `$env:HF_ENDPOINT=`"https://hf-mirror.com`""
}
Write-Host ""
