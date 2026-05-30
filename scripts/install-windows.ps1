# Murmur 一键安装 — Windows PowerShell
# 装 ffmpeg / uv / pandoc / python（如缺）
# 推荐用管理员模式 PowerShell 运行
#
# 用法：
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1 -CN
#   powershell -ExecutionPolicy Bypass -File scripts\install-windows.ps1 -NoCN

param(
    [switch]$CN,
    [switch]$NoCN
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$ScoopRepoCn = "https://mirrors.nju.edu.cn/git/scoop-installer/Scoop.git"
$ScoopMainCn = "https://mirrors.nju.edu.cn/git/scoop-main.git"
$PypiCn = "https://pypi.tuna.tsinghua.edu.cn/simple"

function Write-Ok    { param($msg) Write-Host "✅ $msg" -ForegroundColor Green }
function Write-Warn2 { param($msg) Write-Host "⚠️  $msg" -ForegroundColor Yellow }
function Write-Err   { param($msg) Write-Host "❌ $msg" -ForegroundColor Red }
function Write-Info  { param($msg) Write-Host "ℹ️  $msg" -ForegroundColor Cyan }

function Test-Cmd { param($name) $null -ne (Get-Command $name -ErrorAction SilentlyContinue) }

function Get-PythonCmd {
    foreach ($candidate in @("python", "python3", "py")) {
        if (Test-Cmd $candidate) { return $candidate }
    }
    return $null
}

function Test-CnEnvironment {
    $pythonCmd = Get-PythonCmd
    if (-not $pythonCmd) { return $false }
    $cnEnvPy = Join-Path $scriptDir "cn_env.py"
    & $pythonCmd $cnEnvPy --detect 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Configure-ScoopCnMirror {
    if (-not (Test-Cmd scoop)) { return }
    scoop config SCOOP_REPO $ScoopRepoCn | Out-Null
    $mainBucket = Join-Path $env:USERPROFILE "scoop\buckets\main"
    if (Test-Path $mainBucket) {
        git -C $mainBucket remote set-url origin $ScoopMainCn 2>$null | Out-Null
    }
}

function Ensure-Scoop {
    if (Test-Cmd scoop) {
        if ($useCnMirror) { Configure-ScoopCnMirror }
        return $true
    }
    Write-Info "安装 Scoop（winget 不可用或安装失败时的兜底）..."
    try {
        Set-ExecutionPolicy -Scope CurrentUser RemoteSigned -Force -ErrorAction SilentlyContinue | Out-Null
        Invoke-RestMethod -Uri "https://get.scoop.sh" -UseBasicParsing | Invoke-Expression
    } catch {
        Write-Warn2 "Scoop 安装失败：$_"
        return $false
    }
    if ($useCnMirror) { Configure-ScoopCnMirror }
    if (Test-Cmd scoop) {
        Write-Ok "Scoop 已安装"
        return $true
    }
    return $false
}

function Install-WingetPackage {
    param([string]$Id)
    if (-not (Test-Cmd winget)) { return $false }
    winget install -e --id $Id --silent --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Install-ScoopPackage {
    param([string]$Name)
    if (-not (Ensure-Scoop)) { return $false }
    scoop install $Name 2>&1 | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Install-PipPackage {
    param(
        [string]$Name,
        [string]$PythonCmd,
        [switch]$UseCnIndex
    )
    if (-not $PythonCmd) { return $false }
    if ($UseCnIndex) {
        & $PythonCmd -m pip install -i $PypiCn $Name 2>&1 | Out-Null
    } else {
        & $PythonCmd -m pip install $Name 2>&1 | Out-Null
    }
    return ($LASTEXITCODE -eq 0)
}

function Install-Tool {
    param(
        [string]$DisplayName,
        [string]$CheckCmd,
        [string]$WingetId,
        [string]$ScoopName,
        [scriptblock]$ExtraFallback
    )
    if (Test-Cmd $CheckCmd) {
        Write-Ok "$DisplayName 已安装，跳过"
        return
    }
    Write-Info "安装 $DisplayName..."
    $installed = $false

    if ($WingetId -and (Install-WingetPackage -Id $WingetId)) {
        $installed = $true
    } elseif ($useCnMirror -and $ScoopName -and (Install-ScoopPackage -Name $ScoopName)) {
        $installed = $true
    } elseif ($ExtraFallback) {
        $installed = [bool](& $ExtraFallback)
    }

    if (-not $installed) {
        Write-Err "$DisplayName 安装失败。winget / Scoop / pip 兜底均未成功，请见 docs/install-windows.md 手动安装。"
    }
    Write-Ok "$DisplayName 安装完成"
}

$useCnMirror = $false
$explicitCn = $null
if ($CN) {
    $useCnMirror = $true
    $explicitCn = $true
} elseif ($NoCN) {
    $useCnMirror = $false
    $explicitCn = $false
} elseif (Test-CnEnvironment) {
    $useCnMirror = $true
    Write-Info "检测到中国大陆环境（语言/时区），将启用 PyPI 镜像 / Scoop 南大镜像兜底（如需关闭：重跑时加 -NoCN）"
}

Write-Host ""
Write-Host "================================"
Write-Host "  Murmur 一键安装 (Windows)"
Write-Host "================================"
Write-Host ""

if (-not (Test-Cmd winget)) {
    Write-Warn2 "未检测到 winget（需要 Microsoft Store 的 App Installer）"
    if (-not $useCnMirror) {
        Write-Err "请先安装 winget，或在大陆环境下重跑以启用 Scoop 兜底"
    } else {
        Write-Info "大陆模式：将尝试用 Scoop + 南大镜像安装依赖"
        if (-not (Ensure-Scoop)) {
            Write-Err "winget 和 Scoop 均不可用。请安装 App Installer 或手动执行 docs/install-windows.md 中的兜底步骤。"
        }
    }
} else {
    Write-Ok "winget 已安装（$(winget --version)）"
}

$pythonCmd = Get-PythonCmd

Install-Tool -DisplayName "ffmpeg" -CheckCmd "ffmpeg" `
    -WingetId "Gyan.FFmpeg" -ScoopName "ffmpeg"

if (-not (Test-Cmd uvx)) {
    $uvOk = $false
    if (Install-WingetPackage -Id "astral-sh.uv") { $uvOk = $true }
    if (-not $uvOk -and $useCnMirror -and (Install-ScoopPackage -Name "uv")) { $uvOk = $true }
    if (-not $uvOk) {
        if (-not $pythonCmd) {
            if ($useCnMirror) {
                Install-ScoopPackage -Name "python" | Out-Null
            } else {
                Install-WingetPackage -Id "Python.Python.3.11" | Out-Null
            }
            $pythonCmd = Get-PythonCmd
        }
        if ($pythonCmd -and (Install-PipPackage -Name "uv" -PythonCmd $pythonCmd -UseCnIndex:$useCnMirror)) {
            $uvOk = $true
        }
    }
    if (-not $uvOk) {
        Write-Err "uv 安装失败。可手动：pip install -i $PypiCn uv"
    }
    Write-Ok "uv 安装完成"
} else {
    Write-Ok "uv 已安装，跳过"
}

Install-Tool -DisplayName "pandoc" -CheckCmd "pandoc" `
    -WingetId "JohnMacFarlane.Pandoc" -ScoopName "pandoc"

$pythonCmd = Get-PythonCmd
if ($pythonCmd) {
    Write-Ok "Python 已就绪（$pythonCmd）"
} else {
    Write-Info "安装 Python 3.11..."
    $pyOk = $false
    if (Install-WingetPackage -Id "Python.Python.3.11") { $pyOk = $true }
    if (-not $pyOk -and $useCnMirror -and (Install-ScoopPackage -Name "python")) { $pyOk = $true }
    if (-not $pyOk) { Write-Err "Python 安装失败" }
    $pythonCmd = Get-PythonCmd
    Write-Ok "Python 安装完成"
    Write-Warn2 "需要新开一个 PowerShell 窗口让 PATH 生效"
}

Write-Host ""
Write-Host "================================"
Write-Ok "Murmur 安装完成！"
Write-Host "================================"
Write-Host ""

$pythonCmd = Get-PythonCmd
if ($useCnMirror -and $pythonCmd) {
    $transcribePy = Join-Path $scriptDir "transcribe.py"
    & $pythonCmd $transcribePy --set-default-cn on 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "已记住偏好：以后 transcribe.py 默认启用大陆镜像（关闭：python scripts\transcribe.py --set-default-cn off）"
    }
} elseif ($explicitCn -eq $false -and $pythonCmd) {
    $transcribePy = Join-Path $scriptDir "transcribe.py"
    & $pythonCmd $transcribePy --set-default-cn off 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) {
        Write-Ok "已记住偏好：以后 transcribe.py 默认走官方源（恢复自动：python scripts\transcribe.py --set-default-cn auto）"
    }
}

Write-Host ""
Write-Host "下一步："
Write-Host "  1) 关掉当前 PowerShell，新开一个（让 PATH 刷新）"
Write-Host "  2) 跑体检：     powershell -ExecutionPolicy Bypass -File scripts\doctor.ps1"
Write-Host "  3) 第一次转录： python scripts\transcribe.py 你的录音.m4a"
Write-Host ""
Write-Host "首次转录会下载 ~1.5GB 的 Whisper large-v3-turbo 模型，喝杯咖啡。"
if ($useCnMirror) {
    Write-Host ""
    Write-Host "🇨🇳 大陆镜像偏好已写入配置；模型下载走 hf-mirror.com，uv 拉包走清华 PyPI。"
} else {
    Write-Host "国内网络慢可加："
    Write-Host "  python scripts\transcribe.py --set-default-cn on"
}
Write-Host ""
